ALTER TABLE alert_policy_audits ADD COLUMN request_key VARCHAR(160);
ALTER TABLE alert_policy_audits ADD COLUMN policy_updated_at TIMESTAMPTZ;

ALTER TABLE alert_policy_audits ADD CONSTRAINT alert_policy_upsert_request_key
  CHECK (action = 'UPSERT' OR request_key IS NULL);

CREATE UNIQUE INDEX uq_alert_policy_upsert_request
  ON alert_policy_audits(request_key)
  WHERE request_key IS NOT NULL;
