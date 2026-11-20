-- A new mobile approval key requires fresh verification through the
-- already-confirmed account email. A password/access token is not enough.
CREATE TABLE mobile_enrollment_challenge (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guardian_account_id UUID NOT NULL REFERENCES guardian_account(id),
    requested_by_session UUID NOT NULL REFERENCES auth_session(id),
    code_hash VARCHAR(255) NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    attempts SMALLINT NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
    consumed_at TIMESTAMPTZ,
    CHECK (expires_at > requested_at)
);
CREATE INDEX idx_mobile_enrollment_recent
    ON mobile_enrollment_challenge(guardian_account_id, requested_at DESC);
