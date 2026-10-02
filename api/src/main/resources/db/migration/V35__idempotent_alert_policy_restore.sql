ALTER TABLE alert_policy_audits ADD COLUMN restored_from_audit_id UUID;

ALTER TABLE alert_policy_audits ADD CONSTRAINT alert_policy_restore_source
  CHECK (action = 'RESTORE' OR restored_from_audit_id IS NULL);

CREATE UNIQUE INDEX uq_alert_policy_restore_request
  ON alert_policy_audits(restored_from_audit_id, actor)
  WHERE restored_from_audit_id IS NOT NULL;
