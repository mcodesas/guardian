-- Guardian: alerts with device location and optional encrypted incident photo.
-- Apply after V5__account_administration.sql.
CREATE TABLE device_security_observation (
    id UUID PRIMARY KEY,
    protected_device_id UUID NOT NULL REFERENCES protected_device(id),
    event_type VARCHAR(32) NOT NULL CHECK (event_type IN ('FAILED_UNLOCK', 'LOCKED_LOCATION')),
    occurred_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Coordinates and accuracy encrypted together with the evidence key.
    encrypted_location BYTEA,
    location_source VARCHAR(24) NOT NULL CHECK (location_source IN ('WINDOWS_GEO', 'CACHED', 'UNAVAILABLE')),
    location_observed_at TIMESTAMPTZ,
    photo_status VARCHAR(24) NOT NULL CHECK (photo_status IN ('CAPTURED', 'UNAVAILABLE', 'DISABLED', 'FAILED', 'NOT_REQUESTED')),
    -- AES-256-GCM: first 12 bytes random nonce + ciphertext and auth tag. Never plaintext.
    encrypted_photo BYTEA,
    photo_mime VARCHAR(24),
    CONSTRAINT location_complete CHECK (
        (encrypted_location IS NULL AND location_source = 'UNAVAILABLE') OR
        (encrypted_location IS NOT NULL AND location_source IN ('WINDOWS_GEO','CACHED'))
    ),
    CONSTRAINT photo_valid CHECK (
        (encrypted_photo IS NULL AND photo_mime IS NULL) OR
        (encrypted_photo IS NOT NULL AND photo_mime = 'image/jpeg' AND photo_status = 'CAPTURED')
    )
);
CREATE INDEX idx_guardian_observation_recent ON device_security_observation(protected_device_id, occurred_at DESC);
CREATE INDEX idx_guardian_observation_photo_cleanup ON device_security_observation(received_at)
    WHERE encrypted_photo IS NOT NULL;
