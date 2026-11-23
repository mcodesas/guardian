-- Guardian Account Management. PostgreSQL 17; run after V1-V4.
ALTER TABLE guardian_account
    ADD COLUMN phone_number VARCHAR(32),
    ADD COLUMN disabled_at TIMESTAMPTZ,
    ADD COLUMN email_change_to VARCHAR(320),
    ADD COLUMN email_change_code_hash VARCHAR(255),
    ADD COLUMN email_change_expires_at TIMESTAMPTZ,
    ADD COLUMN email_change_attempts SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN email_change_sent_at TIMESTAMPTZ,
    ADD COLUMN reactivation_code_hash VARCHAR(255),
    ADD COLUMN reactivation_expires_at TIMESTAMPTZ,
    ADD COLUMN reactivation_attempts SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN reactivation_sent_at TIMESTAMPTZ,
    ADD COLUMN deletion_code_hash VARCHAR(255),
    ADD COLUMN deletion_expires_at TIMESTAMPTZ,
    ADD COLUMN deletion_attempts SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN deletion_sent_at TIMESTAMPTZ;

CREATE TABLE guardian_membership (
    owner_account_id UUID NOT NULL REFERENCES guardian_account(id) ON DELETE CASCADE,
    member_account_id UUID NOT NULL REFERENCES guardian_account(id) ON DELETE CASCADE,
    role VARCHAR(16) NOT NULL CHECK (role IN ('ADMIN', 'AUTHORIZED', 'VIEWER')),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_guardian_membership PRIMARY KEY (owner_account_id, member_account_id),
    CONSTRAINT chk_guardian_membership_not_self CHECK (owner_account_id <> member_account_id)
);
CREATE INDEX idx_guardian_membership_member ON guardian_membership(member_account_id)
    WHERE enabled = TRUE;

CREATE TABLE guardian_invitation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_account_id UUID NOT NULL REFERENCES guardian_account(id) ON DELETE CASCADE,
    invited_by_account_id UUID NOT NULL REFERENCES guardian_account(id) ON DELETE CASCADE,
    email VARCHAR(320) NOT NULL,
    role VARCHAR(16) NOT NULL CHECK (role IN ('ADMIN', 'AUTHORIZED', 'VIEWER')),
    token_hash CHAR(64) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    CONSTRAINT chk_guardian_invitation_dates CHECK (expires_at > created_at)
);
CREATE INDEX idx_guardian_invitation_owner ON guardian_invitation(owner_account_id, created_at DESC);
CREATE INDEX idx_guardian_invitation_email ON guardian_invitation(lower(email));

-- Auditable, bounded account activity. Entries are deleted on full account erasure.
CREATE TABLE guardian_account_audit (
    id BIGSERIAL PRIMARY KEY,
    owner_account_id UUID NOT NULL REFERENCES guardian_account(id) ON DELETE CASCADE,
    actor_account_id UUID REFERENCES guardian_account(id) ON DELETE SET NULL,
    action VARCHAR(48) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX idx_guardian_account_audit_owner ON guardian_account_audit(owner_account_id, created_at DESC);
