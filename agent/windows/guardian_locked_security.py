"""Guardian: opt-in Windows locked-session location and failed-unlock alerts.

This monitor does NOT bypass Windows sign-in, session isolation, camera privacy or
location consent. It may be unable to photograph a locked workstation; in that
case the alert is sent without a photo. Windows audit policies and sufficient
Security Event Log read permissions are mandatory for attempted-unlock detection.

Run in the owner's authorized session, with explicit opt-in flags. Offline events
are stored via Windows DPAPI using Guardian's pre-existing save_private helper.
"""
from __future__ import annotations

import argparse
import asyncio
import base64
from datetime import datetime, timezone
import logging
import math
import sys
import time
import uuid
import xml.etree.ElementTree as ET

LOG = logging.getLogger("guardian.locked")
EVENT_NS = {"e": "http://schemas.microsoft.com/win/2004/08/events/event"}
MAX_PHOTO_BYTES = 550_000


def parse_windows_event(xml: str) -> dict | None:
    """Extract only audit event code/type/time/record; never collect passwords."""
    root = ET.fromstring(xml)
    system = root.find("e:System", EVENT_NS)
    if system is None:
        return None
    code_node = system.find("e:EventID", EVENT_NS)
    record_node = system.find("e:EventRecordID", EVENT_NS)
    time_node = system.find("e:TimeCreated", EVENT_NS)
    if code_node is None or record_node is None:
        return None
    event_id = int(code_node.text or "0")
    if event_id not in (4625, 4800, 4801):
        return None
    fields = {}
    for item in root.findall("e:EventData/e:Data", EVENT_NS):
        if item.get("Name") and item.text is not None:
            fields[item.get("Name")] = item.text
    return {
        "eventId": event_id,
        "recordId": int(record_node.text or "0"),
        "occurredAt": time_node.get("SystemTime") if time_node is not None else None,
        "logonType": fields.get("LogonType"),
    }


def relevant_failed_unlock(event: dict, locked: bool) -> bool:
    """A 4625 type 7 is an unlock failure; type 2 needs lock context."""
    return event.get("eventId") == 4625 and (
        event.get("logonType") == "7" or (event.get("logonType") == "2" and locked)
    )


def valid_location(position: dict | None) -> bool:
    if not position:
        return False
    try:
        lat, lon = float(position["latitude"]), float(position["longitude"])
        accuracy = float(position["accuracyMeters"])
    except (TypeError, ValueError, KeyError):
        return False
    return (all(math.isfinite(v) for v in (lat, lon, accuracy))
            and -90 <= lat <= 90 and -180 <= lon <= 180 and 0 <= accuracy <= 100000)


class WindowsEventReader:
    """Read the latest audited logon events without backfilling old events."""

    def __init__(self):
        self.latest_record = None
        self.locked = False
        self.primed = False

    def _read(self) -> list[dict]:
        import win32evtlog  # Only installed/used on Windows.
        xpath = "*[System[(EventID=4625 or EventID=4800 or EventID=4801)]]"
        handle = win32evtlog.EvtQuery("Security", win32evtlog.EvtQueryReverseDirection, xpath)
        found = []
        try:
            try:
                handles = win32evtlog.EvtNext(handle, 128)
            except Exception as exc:
                if getattr(exc, "winerror", None) == 259:
                    handles = []
                else:
                    raise
            for event in handles:
                try:
                    parsed = parse_windows_event(
                        win32evtlog.EvtRender(event, win32evtlog.EvtRenderEventXml))
                    if parsed:
                        found.append(parsed)
                finally:
                    win32evtlog.EvtClose(event)
        finally:
            win32evtlog.EvtClose(handle)
        return sorted(found, key=lambda event: event["recordId"])

    def poll(self) -> list[dict]:
        entries = self._read()
        if not self.primed:
            # Establish current lock state from recent records, without firing
            # old failed-attempt alerts from before the Guardian process started.
            for event in entries:
                if event["eventId"] == 4800:
                    self.locked = True
                elif event["eventId"] == 4801:
                    self.locked = False
            self.latest_record = max((e["recordId"] for e in entries), default=0)
            self.primed = True
            return []
        unseen = [e for e in entries if e["recordId"] > (self.latest_record or 0)]
        self.latest_record = max([self.latest_record or 0] + [e["recordId"] for e in entries])
        alerts = []
        for event in unseen:
            if event["eventId"] == 4800:
                self.locked = True
            elif event["eventId"] == 4801:
                self.locked = False
            elif relevant_failed_unlock(event, self.locked):
                alerts.append(event)
        return alerts


async def _get_geolocation() -> dict | None:
    """Use Windows Geolocator only if location was previously authorized."""
    from winrt.windows.devices.geolocation import Geolocator
    locator = Geolocator()
    position = await asyncio.wait_for(locator.get_geoposition_async(), timeout=8)
    coordinate = position.coordinate
    point = getattr(coordinate, "point", None)
    basic = getattr(point, "position", None) if point is not None else None
    lat = getattr(basic, "latitude", getattr(coordinate, "latitude", None))
    lon = getattr(basic, "longitude", getattr(coordinate, "longitude", None))
    result = {
        "latitude": float(lat), "longitude": float(lon),
        "accuracyMeters": float(coordinate.accuracy),
        "locationObservedAt": datetime.now(timezone.utc).isoformat(),
        "locationSource": "WINDOWS_GEO",
    }
    return result if valid_location(result) else None


class LocationProvider:
    def __init__(self):
        self.last_good: dict | None = None
        self.last_attempt = 0.0

    def acquire(self, enabled: bool) -> dict:
        if not enabled:
            return {"locationSource": "UNAVAILABLE"}
        now = time.monotonic()
        if now - self.last_attempt >= 30:
            self.last_attempt = now
            try:
                position = asyncio.run(_get_geolocation())
                if position is not None:
                    self.last_good = position
                    return position
            except Exception as ex:
                LOG.debug("Ubicación de Windows no disponible (%s)", type(ex).__name__)
        if self.last_good is not None:
            return {**self.last_good, "locationSource": "CACHED"}
        return {"locationSource": "UNAVAILABLE"}


def take_photo(camera_index: int, enabled: bool) -> tuple[str, str | None]:
    """Best effort only; OS camera permission is never overridden."""
    if not enabled:
        return "DISABLED", None
    try:
        import cv2
        camera = cv2.VideoCapture(camera_index, cv2.CAP_DSHOW)
        try:
            if not camera.isOpened():
                return "UNAVAILABLE", None
            # Grab fresh frame after the failure notification is observed.
            ok, frame = camera.read()
            if not ok or frame is None:
                return "UNAVAILABLE", None
            height, width = frame.shape[:2]
            if width > 960:
                frame = cv2.resize(frame, (960, max(1, int(height * 960 / width))))
            ok, encoded = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 68])
            if not ok:
                return "FAILED", None
            jpeg = encoded.tobytes()
            if len(jpeg) > MAX_PHOTO_BYTES:
                return "FAILED", None
            return "CAPTURED", base64.b64encode(jpeg).decode("ascii")
        finally:
            camera.release()
    except Exception as ex:
        LOG.warning("La cámara no pudo capturar el intento (%s)", type(ex).__name__)
        return "UNAVAILABLE", None


class LockedSecurityReporter:
    """Windows-only runner. Offline queue is encrypted by Windows DPAPI."""

    def __init__(self, api, save_private, load_private, spool_path,
                 enable_location: bool, enable_photo: bool, camera_index: int):
        self.api = api
        self.save_private = save_private
        self.load_private = load_private
        self.spool_path = spool_path
        self.enable_location = enable_location
        self.enable_photo = enable_photo
        self.camera_index = camera_index
        self.events = WindowsEventReader()
        self.locations = LocationProvider()
        self.last_heartbeat = 0.0
        self.last_event_check = 0.0
        self.last_flush = 0.0
        self.last_warning = 0.0
        self.last_location_warmup = 0.0

    def _send(self, record: dict):
        return self.api.call("POST", "/security-observations", record)

    def _queue(self, record: dict):
        pending = self.load_private(self.spool_path).get("observations", []) \
            if self.spool_path.exists() else []
        pending.append(record)
        # Prevent unlimited storage consumption; oldest records are discarded.
        self.save_private(self.spool_path, {"observations": pending[-30:]})

    def _submit(self, record: dict):
        import requests
        try:
            self._send(record)
        except requests.RequestException:
            self._queue(record)
            LOG.warning("Sin conexión: alerta guardada cifrada para reintento")

    def _flush(self):
        import requests
        if not self.spool_path.exists():
            return
        pending = self.load_private(self.spool_path).get("observations", [])
        retained = []
        for i, record in enumerate(pending):
            try:
                self._send(record)
            except requests.RequestException:
                retained = pending[i:]
                break
        if retained:
            self.save_private(self.spool_path, {"observations": retained})
        else:
            self.spool_path.unlink(missing_ok=True)

    def _report(self, kind: str, occurred_at: str | None):
        photo_status, jpeg = take_photo(self.camera_index,
                                        kind == "FAILED_UNLOCK" and self.enable_photo)
        location = self.locations.acquire(self.enable_location)
        record = {
            "eventId": str(uuid.uuid4()),
            "eventType": kind,
            "occurredAt": occurred_at or datetime.now(timezone.utc).isoformat(),
            "photoStatus": photo_status if kind == "FAILED_UNLOCK" else "NOT_REQUESTED",
            "photoJpegBase64": jpeg,
            **location,
        }
        self._submit(record)

    def tick(self):
        now = time.monotonic()
        if now - self.last_event_check >= 7:
            self.last_event_check = now
            try:
                alerts = self.events.poll()
            except Exception as exc:
                if now - self.last_warning > 120:
                    LOG.warning("No es posible leer auditoría Windows. Revisa permisos y política: %s",
                                type(exc).__name__)
                    self.last_warning = now
                alerts = []
            for event in alerts:
                self._report("FAILED_UNLOCK", event["occurredAt"])
        # Ask location permission while the owner is still signed in, not
        # for the first time on the Windows secure lock screen.
        if self.enable_location and not self.events.locked and now - self.last_location_warmup > 600:
            self.last_location_warmup = now
            self.locations.acquire(True)
        if self.enable_location and self.events.locked and now - self.last_heartbeat > 300:
            self.last_heartbeat = now
            self._report("LOCKED_LOCATION", None)
        if now - self.last_flush >= 45:
            self.last_flush = now
            self._flush()


def main():
    parser = argparse.ArgumentParser(description="Guardian monitor de ubicación e intentos fallidos de desbloqueo")
    parser.add_argument("--monitor", action="store_true", required=True)
    parser.add_argument("--track-location", action="store_true", help="Permiso explícito: registrar ubicación aun bloqueado")
    parser.add_argument("--capture-failed-unlock", action="store_true", help="Permiso explícito: intentar foto después de 4625")
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--interval", type=float, default=2.0)
    options = parser.parse_args()
    if sys.platform != "win32":
        parser.error("Este monitor necesita Windows")
    if not options.track_location and not options.capture_failed_unlock:
        parser.error("Selecciona al menos una función con consentimiento")
    from pathlib import Path
    from guardian_agent import AgentApi, CONFIG, DATA_DIR, load_private, save_private
    if not CONFIG.exists():
        parser.error("Primero vincula Guardian ejecutando guardian_agent.py setup")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    config = load_private(CONFIG)
    spool = DATA_DIR / "locked_security_spool.dat"
    reporter = LockedSecurityReporter(AgentApi(config), save_private, load_private,
                                      spool, options.track_location,
                                      options.capture_failed_unlock, options.camera)
    LOG.warning("Monitoreo explícito activado. Para detenerlo, Ctrl+C. "
                "Un evento de Windows no garantiza disponibilidad de foto o GPS.")
    try:
        while True:
            reporter.tick()
            time.sleep(max(1.0, options.interval))
    except KeyboardInterrupt:
        LOG.info("Guardian: monitor detenido por el propietario")


if __name__ == "__main__":
    main()
