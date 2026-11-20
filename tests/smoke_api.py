#!/usr/bin/env python3
"""Guardian integration smoke: PostgreSQL + SMTP + auth + device + approvals.

Only execute against an isolated disposable Docker Compose CI environment,
never a user's production account or database.
"""
from __future__ import annotations

import json
import re
import secrets
import time
import urllib.error
import urllib.request
import uuid


BASE = "http://127.0.0.1:18083"
MAIL = "http://127.0.0.1:18025"


def http(url: str, method: str = "GET", data: dict | None = None,
         token: str | None = None, agent_key: str | None = None,
         expected: int = 200) -> dict:
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    if agent_key:
        headers["X-Guardian-Agent-Key"] = agent_key
    request = urllib.request.Request(
        url, method=method, headers=headers,
        data=json.dumps(data).encode("utf-8") if data is not None else None,
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            status = response.status
            response_body = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        status = error.code
        response_body = error.read().decode("utf-8")
    if status != expected:
        raise AssertionError(
            f"{method} {url.split('?')[0]} expected HTTP {expected}, "
            f"received {status}: {response_body[:400]}"
        )
    return json.loads(response_body) if response_body else {}


def api(endpoint: str, method: str = "GET", data: dict | None = None,
        token: str | None = None, agent_key: str | None = None,
        expected: int = 200) -> dict:
    return http(BASE + "/api/v1" + endpoint, method, data, token, agent_key, expected)


def mailbox_code(subject_contains: str) -> str:
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        mailbox = http(MAIL + "/api/v1/messages")
        for item in mailbox.get("messages", []):
            if subject_contains not in item.get("Subject", ""):
                continue
            message = http(MAIL + "/api/v1/message/" + item["ID"])
            content = message.get("Text", "")
            matches = re.findall(r"(?<!\d)\d{6}(?!\d)", content)
            if matches:
                return matches[0]
        time.sleep(1)
    raise AssertionError(f"Mailpit did not receive OTP for {subject_contains}")


def main() -> None:
    health = http(BASE + "/actuator/health")
    assert health["status"] == "UP"

    api("/devices", expected=401)
    email = f"qa-guardian-{uuid.uuid4().hex[:12]}@example.test"
    password = "CI-Guardian-" + secrets.token_hex(16)
    name = "QA Guardian"

    api("/auth/register", "POST",
        {"name": name, "email": email, "password": password}, expected=201)
    code = mailbox_code("Verifica tu cuenta")
    api("/auth/verify", "POST", {"email": email, "code": code})

    tokens = api("/auth/login", "POST",
        {"email": email, "password": password, "clientLabel": "guardian-ci"})
    access = tokens["accessToken"]
    assert len(access) >= 32 and len(tokens["refreshToken"]) >= 32
    # Refresh tokens rotate. The old pair must become invalid.
    rotated = api("/auth/refresh", "POST",
                  {"refreshToken": tokens["refreshToken"]})
    api("/auth/me", token=access, expected=401)
    api("/auth/refresh", "POST",
        {"refreshToken": tokens["refreshToken"]}, expected=401)
    access = rotated["accessToken"]

    owner = api("/auth/me", token=access)
    assert owner["email"] == email
    assert owner["verified"] is True

    device = api("/devices", "POST",
        {"name": "Equipo QA", "platform": "WINDOWS"},
        token=access, expected=201)
    device_id, key = device["id"], device["agentKey"]
    assert device["state"] == "UNPAIRED"

    api(f"/agent/{device_id}/activate", "POST",
        agent_key="not-the-agent-secret", expected=401)
    assert api(f"/agent/{device_id}/activate", "POST", agent_key=key)["paired"]
    policy = api(f"/agent/{device_id}/policy", agent_key=key)
    assert policy["lockOnAway"] is True
    assert policy["allowRemoteApproval"] is True

    api(f"/agent/{device_id}/events", "POST",
        {"type": "NOT_VERIFIABLE", "reason": "Prueba en CI sin rostro"},
        agent_key=key)
    incidents = api("/incidents", token=access)
    assert any(v["type"] == "NOT_VERIFIABLE" for v in incidents)

    challenge = api(f"/agent/{device_id}/challenges", "POST", agent_key=key)
    assert challenge["challengeId"]
    status = api(f"/agent/{device_id}/challenges/{challenge['challengeId']}",
                 agent_key=key)
    assert status["state"] == "PENDING"

    approvals = api("/approvals", token=access)
    assert any(v["id"] == challenge["challengeId"] for v in approvals)
    notifications = api("/notifications", token=access)
    assert any(v["type"] == "APPROVAL_REQUIRED" for v in notifications)

    # A forged decision without a registered mobile signing key is forbidden.
    api(f"/approvals/{challenge['challengeId']}/decision", "POST", {
        "credentialId": str(uuid.uuid4()),
        "decision": "APPROVED",
        "trustMinutes": 5,
        "signature": "not-a-valid-signature",
    }, token=access, expected=403)

    # Account recovery revokes every previous session and requires a new password.
    api("/auth/request-reset", "POST", {"email": email})
    reset_code = mailbox_code("Recuperar acceso")
    new_password = "CI-Renewed-" + secrets.token_hex(16)
    api("/auth/reset", "POST", {
        "email": email, "code": reset_code, "newPassword": new_password,
    })
    api("/auth/me", token=access, expected=401)
    api("/auth/login", "POST", {
        "email": email, "password": password, "clientLabel": "old-credentials",
    }, expected=401)
    new_session = api("/auth/login", "POST", {
        "email": email, "password": new_password, "clientLabel": "recovered-ci",
    })
    access = new_session["accessToken"]

    api("/auth/logout", "POST", token=access)
    api("/auth/me", token=access, expected=401)
    print("PASS: health, registration, SMTP OTP, login, bearer auth, devices, "
          "agent, security incident, approval challenge, signed-decision denial, "
          "password recovery, token rotation and logout")


if __name__ == "__main__":
    main()
