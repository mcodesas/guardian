ALTER TABLE guardian_account
    ADD COLUMN display_name VARCHAR(120) NOT NULL DEFAULT '',
    ADD COLUMN password_hash VARCHAR(255),
    ADD COLUMN email_verified BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN verification_code_hash VARCHAR(255),
    ADD COLUMN verification_expires_at TIMESTAMPTZ,
    ADD COLUMN verification_attempts SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN verification_sent_at TIMESTAMPTZ,
    ADD COLUMN failed_login_attempts SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN locked_until TIMESTAMPTZ;
-- Registered accounts must include a password. Existing data is empty on initial setup.
ALTER TABLE guardian_account ALTER COLUMN password_hash SET NOT NULL;

CREATE TABLE auth_session (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guardian_account_id UUID NOT NULL REFERENCES guardian_account(id),
    access_token_hash CHAR(64) NOT NULL UNIQUE,
    refresh_token_hash CHAR(64) NOT NULL UNIQUE,
    access_expires_at TIMESTAMPTZ NOT NULL,
    refresh_expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ,
    client_label VARCHAR(120) NOT NULL DEFAULT ''
);
CREATE INDEX idx_auth_session_owner ON auth_session(guardian_account_id);

ALTER TABLE protected_device
    ADD COLUMN registration_state VARCHAR(20) NOT NULL DEFAULT 'UNPAIRED'
        CHECK (registration_state IN ('UNPAIRED','PAIRED','REVOKED')),
    ADD COLUMN lock_on_away BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN away_timeout_seconds INTEGER NOT NULL DEFAULT 15
        CHECK (away_timeout_seconds BETWEEN 5 AND 300),
    ADD COLUMN allow_remote_approval BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN last_seen_at TIMESTAMPTZ;

CREATE TABLE agent_credential (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    protected_device_id UUID NOT NULL UNIQUE REFERENCES protected_device(id),
    secret_hash CHAR(64) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);

ALTER TABLE approval_challenge ADD COLUMN challenge_nonce VARCHAR(64) UNIQUE;

CREATE TABLE push_registration (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guardian_account_id UUID NOT NULL REFERENCES guardian_account(id),
    mobile_credential_id UUID REFERENCES mobile_credential(id),
    token_hash CHAR(64) NOT NULL UNIQUE,
    token_ciphertext TEXT,
    platform VARCHAR(16) NOT NULL CHECK (platform IN ('ANDROID','IOS')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);

CREATE TABLE notification_event (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guardian_account_id UUID NOT NULL REFERENCES guardian_account(id),
    protected_device_id UUID REFERENCES protected_device(id),
    approval_challenge_id UUID REFERENCES approval_challenge(id),
    security_incident_id UUID REFERENCES security_incident(id),
    type VARCHAR(32) NOT NULL CHECK (type IN
      ('APPROVAL_REQUIRED','INTRUSION','OWNER_ABSENT','DEVICE_ATTENTION','APPROVAL_DECIDED')),
    title VARCHAR(180) NOT NULL,
    body VARCHAR(600) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ
);
CREATE INDEX idx_notification_owner_created
    ON notification_event(guardian_account_id, created_at DESC);
