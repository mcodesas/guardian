#!/usr/bin/env python3
"""Guardian Windows interactive agent: evaluation build, not a security-certified product.

Requires the owner's explicit consent, enrolled face samples and an interactive
Windows desktop. Facial models are NOT included; review model licensing.
Liveness/anti-spoofing is NOT implemented. Do not deploy strict mode to real
users without multi-device QA and a reliable recovery process.
"""
from __future__ import annotations

import argparse
import base64
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import getpass
import io
import json
import logging
import os
from pathlib import Path
import secrets
import sys
import time
from urllib.parse import urlparse

import cv2
import numpy as np
import requests
import win32crypt
from guardian_policy import (
    is_valid_trust_window, should_flag_unknown, should_lock_on_away,
    should_request_remote_approval,
)

LOG = logging.getLogger("guardian")
DATA_DIR = Path(os.environ.get("APPDATA", ".")) / "Guardian" / "agent"
CONFIG = DATA_DIR / "config.dat"
BIOMETRICS = DATA_DIR / "biometrics.dat"
SPOOL = DATA_DIR / "outbox.dat"
EVIDENCE_DIR = DATA_DIR / "evidence"
CURRENT_VERSION = "0.2.0-evaluation"


def protect(plaintext: bytes) -> bytes:
    return win32crypt.CryptProtectData(plaintext, "Guardian local private data", None, None, None, 0)


def unprotect(ciphertext: bytes) -> bytes:
    return win32crypt.CryptUnprotectData(ciphertext, None, None, None, 0)[1]


def save_private(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_bytes(protect(json.dumps(data).encode("utf-8")))
    os.replace(temporary, path)


def load_private(path: Path) -> dict:
    return json.loads(unprotect(path.read_bytes()).decode("utf-8"))


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def as_timestamp(value: str) -> float:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


class LASTINPUTINFO(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.UINT), ("dwTime", wintypes.DWORD)]


def seconds_idle() -> float:
    info = LASTINPUTINFO()
    info.cbSize = ctypes.sizeof(info)
    if not ctypes.windll.user32.GetLastInputInfo(ctypes.byref(info)):
        return 0.0
    current = ctypes.windll.kernel32.GetTickCount() & 0xFFFFFFFF
    return ((current - info.dwTime) & 0xFFFFFFFF) / 1000.0


def request_windows_lock() -> bool:
    # A successful return means the OS accepted an asynchronous lock request,
    # NOT proof that the display has been locked.
    return bool(ctypes.windll.user32.LockWorkStation())


def validate_server(value: str) -> str:
    u = urlparse(value)
    if not u.hostname:
        raise ValueError("La URL del servidor está vacía")
    if u.scheme != "https" and not (
        u.scheme == "http" and u.hostname in ("127.0.0.1", "localhost")
    ):
        raise ValueError("Se requiere HTTPS fuera de localhost")
    return value.rstrip("/")


class AgentApi:
    def __init__(self, config: dict):
        self.root = validate_server(config["server"])
        self.device = config["deviceId"]
        self.headers = {
            "X-Guardian-Agent-Key": config["agentKey"],
            "Content-Type": "application/json",
        }
        self.session = requests.Session()

    def call(self, method: str, endpoint: str, body: dict | None = None) -> dict:
        url = self.root + "/api/v1/agent/" + self.device + endpoint
        response = self.session.request(method, url, headers=self.headers, json=body, timeout=5)
        response.raise_for_status()
        return response.json()

    def activate(self) -> dict:
        return self.call("POST", "/activate")

    def policy(self) -> dict:
        return self.call("GET", "/policy")

    def event(self, kind: str, reason: str) -> dict:
        return self.call("POST", "/events", {"type": kind, "reason": reason})

    def challenge(self) -> dict:
        return self.call("POST", "/challenges")

    def challenge_status(self, challenge_id: str) -> dict:
        return self.call("GET", "/challenges/" + challenge_id)


def emit_event(api: AgentApi, kind: str, reason: str) -> None:
    try:
        api.event(kind, reason)
        return
    except requests.RequestException:
        LOG.warning("Sin red, evento añadido a cola local")
    try:
        pending = load_private(SPOOL).get("events", []) if SPOOL.exists() else []
        pending.append({"type": kind, "reason": reason})
        save_private(SPOOL, {"events": pending[-100:]})
    except Exception:
        LOG.exception("No se pudo persistir la cola local")


def flush_outbox(api: AgentApi) -> None:
    if not SPOOL.exists():
        return
    queued = load_private(SPOOL).get("events", [])
    remaining = []
    for index, event in enumerate(queued):
        try:
            api.event(event["type"], event["reason"])
        except requests.RequestException:
            remaining = queued[index:]
            break
    if remaining:
        save_private(SPOOL, {"events": remaining})
    else:
        SPOOL.unlink(missing_ok=True)


def evidence(frame: np.ndarray) -> str:
    ok, jpeg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 78])
    if not ok:
        return ""
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    filename = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + secrets.token_hex(4) + ".enc"
    # Encrypted to current Windows user with DPAPI. No plaintext JPEG on disk.
    (EVIDENCE_DIR / filename).write_bytes(protect(jpeg.tobytes()))
    # Keep only the latest 100 images and a maximum seven-day retention.
    # Never create plaintext JPEG files.
    all_evidence = sorted(EVIDENCE_DIR.glob("*.enc"), key=lambda p: p.stat().st_mtime,
                          reverse=True)
    for index, item in enumerate(all_evidence):
        try:
            if index >= 100 or time.time() - item.stat().st_mtime > 7 * 24 * 3600:
                item.unlink()
        except OSError:
            LOG.warning("No se pudo aplicar la retención a una evidencia")
    return filename


class Recognition:
    def __init__(self, detector_file: str, recognition_file: str):
        if not (Path(detector_file).is_file() and Path(recognition_file).is_file()):
            raise RuntimeError("Se requieren archivos ONNX con licencia verificada (YuNet/SFace u otros compatibles)")
        self.detector = cv2.FaceDetectorYN.create(detector_file, "", (640, 480))
        self.recognizer = cv2.FaceRecognizerSF.create(recognition_file, "")

    def face_feature(self, frame: np.ndarray) -> np.ndarray | None:
        height, width = frame.shape[:2]
        self.detector.setInputSize((width, height))
        _, faces = self.detector.detect(frame)
        if faces is None or len(faces) != 1:
            return None
        face = faces[0]
        if face[2] < 75 or face[3] < 75:
            return None
        aligned = self.recognizer.alignCrop(frame, face)
        return self.recognizer.feature(aligned)

    def similarity(self, first: np.ndarray, second: np.ndarray) -> float:
        return float(self.recognizer.match(first, second, cv2.FaceRecognizerSF_FR_COSINE))


def open_camera(device: int) -> cv2.VideoCapture:
    camera = cv2.VideoCapture(device, cv2.CAP_DSHOW)
    if not camera.isOpened():
        raise RuntimeError("No se pudo abrir la cámara. Revisa sus permisos u orientación.")
    return camera


def setup(args: argparse.Namespace) -> None:
    server = validate_server(input("Servidor Guardian HTTPS: ").strip())
    device_id = input("ID del dispositivo registrado en Flutter: ").strip()
    try:
        import uuid
        uuid.UUID(device_id)
    except Exception as exc:
        raise ValueError("ID de dispositivo inválido") from exc
    key = getpass.getpass("Clave de agente (no visible): ").strip()
    if len(key) < 40:
        raise ValueError("Clave de agente incompleta")
    config = {
        "server": server, "deviceId": device_id,
        "agentKey": key, "cameraIndex": int(args.camera),
    }
    AgentApi(config).activate()
    save_private(CONFIG, config)
    print("Agente vinculado; configuración cifrada en el perfil Windows.")
    print("Siguiente paso: enroll --detector MODELO_YUNET --recognizer MODELO_SFACE")


def enroll(args: argparse.Namespace) -> None:
    if not CONFIG.exists():
        raise RuntimeError("Primero ejecuta setup")
    recognizer = Recognition(args.detector, args.recognizer)
    config = load_private(CONFIG)
    camera = open_camera(config.get("cameraIndex", 0))
    features = []
    last_sample = 0.0
    print("Registro visible y voluntario. Mueve la cabeza ligeramente.")
    try:
        while len(features) < 12:
            ok, frame = camera.read()
            if not ok:
                raise RuntimeError("La cámara dejó de entregar imágenes")
            face = recognizer.face_feature(frame)
            if face is not None and time.monotonic() - last_sample >= 0.6:
                features.append(face.reshape(-1).tolist())
                last_sample = time.monotonic()
            caption = "Guardian | muestras: " + str(len(features)) + "/12 | Q: cancelar"
            cv2.putText(frame, caption, (14, 27), cv2.FONT_HERSHEY_SIMPLEX,
                        0.58, (0, 245, 205), 2)
            cv2.imshow("Guardian - Registro con consentimiento", frame)
            if cv2.waitKey(50) & 0xFF == ord("q"):
                raise KeyboardInterrupt()
        save_private(BIOMETRICS, {"features": features, "enrolledAt": utcnow().isoformat()})
        print("Plantillas faciales cifradas con DPAPI. Registro terminado.")
    finally:
        camera.release()
        cv2.destroyAllWindows()


def approval(api: AgentApi) -> float | None:
    """Returns temporary trust-until timestamp, or None (deny, error, offline)."""
    try:
        result = api.challenge()
        request_id = result["challengeId"]
        expiration = as_timestamp(result["expiresAt"])
    except requests.RequestException:
        return None
    LOG.warning("Rostro no verificable. Solicitud enviada al teléfono.")
    while time.time() < expiration:
        try:
            response = api.challenge_status(request_id)
            if response["state"] == "APPROVED":
                until = response.get("trustUntil")
                return as_timestamp(until) if until else None
            if response["state"] in ("REJECTED", "CANCELLED", "EXPIRED"):
                return None
        except requests.RequestException:
            pass
        time.sleep(3)
    return None


def request_lock_and_report(api: AgentApi, kind: str, reason: str,
                            frame: np.ndarray | None = None) -> None:
    photo = evidence(frame) if frame is not None else ""
    note = reason + (". Evidencia cifrada local: " + photo if photo else "")
    accepted = request_windows_lock()
    if not accepted:
        emit_event(api, "LOCK_FAILURE", "Windows rechazó el intento de bloqueo: " + reason)
    else:
        emit_event(api, kind, note)
        LOG.warning("Bloqueo solicitado al sistema Windows (no comprobado automáticamente)")


def monitor(args: argparse.Namespace) -> None:
    if not (CONFIG.exists() and BIOMETRICS.exists()):
        raise RuntimeError("Debes ejecutar setup y enroll antes de monitor")
    config = load_private(CONFIG)
    embeddings = [
        np.array(feature, dtype=np.float32).reshape(1, -1)
        for feature in load_private(BIOMETRICS)["features"]
    ]
    recognizer = Recognition(args.detector, args.recognizer)
    api = AgentApi(config)
    api.activate()
    camera = open_camera(config.get("cameraIndex", 0))
    policy = {"lockOnAway": True, "awayTimeoutSeconds": 15,
              "allowRemoteApproval": True}
    last_policy = 0.0
    last_flush = 0.0
    missing_since: float | None = None
    unknown_streak = 0
    failed_frames = 0
    camera_failure_reported = False
    trust_until = 0.0
    locked_cooldown = 0.0
    LOG.warning("Guardian modo %s. La cámara y el estado de protección están visibles.",
                args.mode)
    if args.mode == "protect":
        LOG.warning("Modo experimental: sin detección de presencia real anti-suplantación.")

    try:
        while True:
            now = time.time()
            if now - last_policy > 60:
                try:
                    policy = api.policy()
                except requests.RequestException:
                    LOG.warning("Sin conexión: continúa la última política")
                finally:
                    last_policy = now
            if now - last_flush > 30:
                flush_outbox(api)
                last_flush = now

            ok, frame = camera.read()
            failed_frames = 0 if ok else failed_frames + 1
            if failed_frames >= 10 and not camera_failure_reported:
                emit_event(api, "CAMERA_UNAVAILABLE",
                           "La cámara dejó de entregar imágenes; verifica conexión o permisos")
                camera_failure_reported = True
                if args.mode == "protect" and now > locked_cooldown:
                    request_lock_and_report(api, "CAMERA_UNAVAILABLE",
                                            "La cámara no está disponible")
                    locked_cooldown = now + 90
            if ok:
                camera_failure_reported = False

            feature = recognizer.face_feature(frame) if ok else None
            idle = seconds_idle()
            timeout = int(policy.get("awayTimeoutSeconds", 15))
            trusted = is_valid_trust_window(until=trust_until, now=now)

            # Even during temporary approval, an explicitly unknown FACE
            # must still be evaluated; otherwise anyone could exploit the
            # approved 5/15/30 minute window. Approval only suppresses
            # prompts when the face cannot be verified.
            if feature is not None:
                missing_since = None
                scores = [recognizer.similarity(feature, sample) for sample in embeddings]
                if scores and max(scores) >= float(args.threshold):
                    state = "Propietario reconocido"
                    unknown_streak = 0
                else:
                    unknown_streak += 1
                    state = "Rostro diferente al propietario (sin prueba de vida)"
                    if should_flag_unknown(consecutive=unknown_streak, idle_seconds=idle,
                                           now=now, cooldown_until=locked_cooldown):
                        trust_until = 0.0
                        if args.mode == "protect":
                            request_lock_and_report(api, "UNKNOWN_PERSON",
                                "Rostro diferente observado repetidamente; revisar incidente",
                                frame)
                        else:
                            emit_event(api, "UNKNOWN_PERSON",
                                "Rostro diferente observado; modo observación")
                        locked_cooldown = now + 90
                        unknown_streak = 0
            else:
                unknown_streak = 0
                state = "Identidad no verificable (no implica intrusión)"
                if missing_since is None:
                    missing_since = now
                if now - missing_since >= timeout and now > locked_cooldown:
                    if should_lock_on_away(absence_seconds=now-missing_since,
                            idle_seconds=idle, timeout_seconds=timeout,
                            enabled=bool(policy.get("lockOnAway", True)),
                            now=now, cooldown_until=locked_cooldown):
                        # The owner may be away even if a previous mobile
                        # approval was granted. Never suppress away-lock.
                        trust_until = 0.0
                        if args.mode == "protect":
                            request_lock_and_report(api, "OWNER_ABSENT",
                                "Ausencia persistente; bloqueo solicitado")
                        else:
                            emit_event(api, "OWNER_ABSENT",
                                "Ausencia persistente; modo observación")
                        locked_cooldown = now + 90
                    elif should_request_remote_approval(absence_seconds=now-missing_since,
                            idle_seconds=idle, timeout_seconds=timeout,
                            trust_until=trust_until, now=now,
                            cooldown_until=locked_cooldown):
                        # Fail safe: a person operating an unverifiable
                        # session must not get 45 seconds of free access
                        # while the phone authorization is pending.
                        if args.mode == "protect":
                            request_lock_and_report(api, "NOT_VERIFIABLE",
                                "Actividad sin rostro verificable; requiere autorización")
                        else:
                            emit_event(api, "NOT_VERIFIABLE",
                                "Actividad sin rostro verificable; modo observación")
                        if policy.get("allowRemoteApproval", True):
                            until = approval(api)
                            if until:
                                trust_until = until
                                state = "Autorización móvil válida, desbloqueo manual"
                            else:
                                state = "Sin aprobación; conserva bloqueo local"
                        locked_cooldown = time.time() + 90
                    missing_since = time.time()
            if ok:
                display = frame.copy()
                cv2.rectangle(display, (0, 0), (display.shape[1], 52), (15, 25, 33), -1)
                cv2.putText(display, "GUARDIAN ACTIVO", (12, 20), cv2.FONT_HERSHEY_SIMPLEX,
                            .57, (90, 234, 211), 2)
                cv2.putText(display, state[:62], (12, 42), cv2.FONT_HERSHEY_SIMPLEX,
                            .45, (255, 255, 255), 1)
                cv2.imshow("Guardian - Proteccion activa (Q para salir)", display)
            if cv2.waitKey(250) & 0xFF == ord("q"):
                LOG.warning("Protección local detenida voluntariamente")
                break
    finally:
        camera.release()
        cv2.destroyAllWindows()


def view_evidence(args: argparse.Namespace) -> None:
    # View decrypted evidence in memory only, without creating a plaintext JPEG.
    path = EVIDENCE_DIR / args.filename
    if not path.is_file() or path.suffix != ".enc":
        raise ValueError("No existe esa evidencia cifrada")
    content = unprotect(path.read_bytes())
    frame = cv2.imdecode(np.frombuffer(content, np.uint8), cv2.IMREAD_COLOR)
    if frame is None:
        raise ValueError("No se pudo abrir la imagen")
    cv2.imshow("Guardian - Evidencia local", frame)
    cv2.waitKey(0)
    cv2.destroyAllWindows()


def main() -> int:
    if sys.platform != "win32":
        print("Este agente solo puede ejecutarse en Windows.", file=sys.stderr)
        return 2
    parser = argparse.ArgumentParser(description="Guardian Windows Agent")
    parser.add_argument("--verbose", action="store_true")
    actions = parser.add_subparsers(dest="action", required=True)
    p_setup = actions.add_parser("setup", help="Vincular agente al dispositivo")
    p_setup.add_argument("--camera", type=int, default=0)
    for name in ("enroll", "monitor"):
        p = actions.add_parser(name)
        p.add_argument("--detector", required=True, help="Ruta de modelo YuNet ONNX")
        p.add_argument("--recognizer", required=True, help="Ruta de modelo SFace ONNX")
        if name == "monitor":
            p.add_argument("--threshold", type=float, default=0.42)
            p.add_argument("--mode", choices=("observe", "protect"), default="observe",
                           help="observe: no bloquea; protect: solicita bloqueos Windows")
    p_evidence = actions.add_parser("view-evidence")
    p_evidence.add_argument("filename")
    args = parser.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    try:
        if args.action == "setup":
            setup(args)
        elif args.action == "enroll":
            enroll(args)
        elif args.action == "monitor":
            if not 0.36 <= args.threshold <= 0.65:
                raise ValueError("El umbral debe estar entre 0.36 y 0.65")
            monitor(args)
        else:
            view_evidence(args)
        return 0
    except KeyboardInterrupt:
        LOG.warning("Operación cancelada por el propietario")
        return 1
    except Exception as error:
        LOG.error("Guardian no pudo continuar: %s", error)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
