ALTER TABLE alert_policies ADD COLUMN active BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE alert_policy_audits ADD COLUMN action VARCHAR(20) NOT NULL DEFAULT 'UPSERT';
ALTER TABLE alert_policy_audits ADD CONSTRAINT alert_policy_audit_action CHECK (action IN ('UPSERT','RESET'));

CREATE INDEX idx_alert_policies_active_vehicle ON alert_policies(active, vehicle_id);
