#!/usr/bin/env python3
"""Guardian integration smoke: PostgreSQL + SMTP + auth + device + approvals.

Only execute against an isolated disposable Docker Compose CI environment,
never a user's production account or database.
"""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
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

    # New profile and account-session management endpoints.
    account = api("/account", token=access)
    assert account["email"] == email
    assert api("/account", "PATCH", {"name":"QA Owner Updated","phone":"+573001112233"},
               token=access)["name"] == "QA Owner Updated"
    active_sessions = api("/account/sessions",token=access)
    assert len(active_sessions) == 1 and active_sessions[0]["current"]
    assert isinstance(api("/account/members",token=access),list)
    assert isinstance(api("/workspaces",token=access),list)

    # Email change must verify a fresh code and revoke previous sessions.
    updated_email = f"updated-{uuid.uuid4().hex[:12]}@example.test"
    api("/account/email/change-request", "POST", {
        "email":updated_email, "currentPassword":password,
    }, token=access)
    change_code = mailbox_code("Verificar nuevo correo")
    api("/account/email/confirm","POST",{"code":change_code},token=access)
    api("/auth/me",token=access,expected=401)
    email=updated_email
    access=api("/auth/login","POST",{
        "email":email,"password":password,"clientLabel":"after-email-change",
    })["accessToken"]

    # Invitation expiry is a PostgreSQL timestamp, and invite can be revoked.
    invited=f"guardian-invited-{uuid.uuid4().hex[:12]}@example.test"
    api("/account/invitations","POST",{"email":invited,"role":"VIEWER"},
        token=access,expected=201)
    invitations=api("/account/invitations",token=access)
    own_invite=next(i for i in invitations if i["email"]==invited)
    assert own_invite["status"]=="PENDING"
    api(f"/account/invitations/{own_invite['id']}","DELETE",token=access)
    invitations=api("/account/invitations",token=access)
    assert next(i for i in invitations if i["id"]==own_invite["id"])["status"]=="REVOKED"

    api("/account", expected=401)


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

    # Only the paired agent can send location/failure reports. Data is
    # encrypted at rest, never available on public API endpoints.
    observation_id = str(uuid.uuid4())
    observed_at = datetime.now(timezone.utc).isoformat()
    payload = {
        "eventId": observation_id, "eventType":"FAILED_UNLOCK",
        "occurredAt": observed_at,
        "latitude":4.60971, "longitude":-74.08175,
        "accuracyMeters":45.0, "locationSource":"WINDOWS_GEO",
        "locationObservedAt":observed_at,
        "photoStatus":"UNAVAILABLE",
    }
    api(f"/agent/{device_id}/security-observations", "POST", payload,
        agent_key="invalid-agent-key", expected=401)
    reported = api(f"/agent/{device_id}/security-observations", "POST",payload,agent_key=key)
    assert reported["accepted"] is True and reported["duplicate"] is False
    repeated = api(f"/agent/{device_id}/security-observations", "POST",payload,agent_key=key)
    assert repeated["duplicate"] is True
    location = api(f"/devices/{device_id}/last-location",token=access)
    assert abs(location["latitude"]-4.60971)<0.0001
    assert location["type"] == "FAILED_UNLOCK"
    observations = api(f"/devices/{device_id}/security-observations",token=access)
    assert len(observations)==1 and observations[0]["id"]==observation_id
    api(f"/devices/{device_id}/security-observations",expected=401)
    api(f"/devices/{device_id}/security-observations/{observation_id}/photo",
        token=access,expected=404)


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
          "password recovery, profile editing, sessions, encrypted location events, "
          "idempotent alerts, token rotation and logout")


if __name__ == "__main__":
    main()
