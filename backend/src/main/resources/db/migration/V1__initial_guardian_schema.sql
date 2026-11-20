-- Guardian: modelado inicial. Todavia no se exponen endpoints de escritura.
CREATE TABLE guardian_account (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(320) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE protected_device (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guardian_account_id UUID NOT NULL REFERENCES guardian_account(id),
    display_name VARCHAR(160) NOT NULL,
    platform VARCHAR(24) NOT NULL CHECK (platform IN ('WINDOWS','MACOS','LINUX','ANDROID','IOS')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);
CREATE INDEX idx_protected_device_owner ON protected_device(guardian_account_id);

CREATE TABLE mobile_credential (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guardian_account_id UUID NOT NULL REFERENCES guardian_account(id),
    credential_id VARCHAR(255) NOT NULL UNIQUE,
    public_key TEXT NOT NULL,
    platform VARCHAR(16) NOT NULL CHECK (platform IN ('ANDROID','IOS')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);
CREATE INDEX idx_mobile_credential_owner ON mobile_credential(guardian_account_id);

CREATE TABLE security_incident (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    protected_device_id UUID NOT NULL REFERENCES protected_device(id),
    incident_type VARCHAR(40) NOT NULL CHECK (incident_type IN
        ('UNKNOWN_PERSON','NOT_VERIFIABLE','OWNER_ABSENT','CAMERA_UNAVAILABLE','LOCK_FAILURE')),
    occurred_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    evidence_object_key VARCHAR(512),
    details JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX idx_security_incident_device_time
    ON security_incident(protected_device_id, occurred_at DESC);

CREATE TABLE approval_challenge (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    protected_device_id UUID NOT NULL REFERENCES protected_device(id),
    nonce_hash VARCHAR(128) NOT NULL UNIQUE,
    state VARCHAR(16) NOT NULL DEFAULT 'PENDING'
        CHECK (state IN ('PENDING','APPROVED','REJECTED','EXPIRED','CANCELLED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    decided_at TIMESTAMPTZ,
    decided_by_credential_id UUID REFERENCES mobile_credential(id),
    trust_until TIMESTAMPTZ,
    CHECK (expires_at > created_at),
    CHECK (trust_until IS NULL OR trust_until > created_at)
);
CREATE INDEX idx_approval_challenge_device_time
    ON approval_challenge(protected_device_id, created_at DESC);
CREATE INDEX idx_approval_challenge_pending
    ON approval_challenge(expires_at) WHERE state = 'PENDING';
