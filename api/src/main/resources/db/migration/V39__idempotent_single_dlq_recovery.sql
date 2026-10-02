ALTER TABLE replay_audits ADD COLUMN request_key VARCHAR(160);
CREATE UNIQUE INDEX uq_replay_audit_request ON replay_audits(request_key) WHERE request_key IS NOT NULL;
