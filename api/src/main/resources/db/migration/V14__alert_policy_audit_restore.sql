ALTER TABLE alert_policy_audits DROP CONSTRAINT alert_policy_audit_action;
ALTER TABLE alert_policy_audits ADD CONSTRAINT alert_policy_audit_action CHECK (action IN ('UPSERT','RESET','RESTORE'));
