ALTER TABLE guardian_account
  ADD COLUMN reset_code_hash VARCHAR(255),
  ADD COLUMN reset_code_expires_at TIMESTAMPTZ,
  ADD COLUMN reset_code_attempts SMALLINT NOT NULL DEFAULT 0,
  ADD COLUMN reset_code_sent_at TIMESTAMPTZ;
