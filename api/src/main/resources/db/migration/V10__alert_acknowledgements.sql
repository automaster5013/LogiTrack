ALTER TABLE delivery_alerts
  ADD COLUMN acknowledged_at TIMESTAMPTZ,
  ADD COLUMN acknowledged_by VARCHAR(120);

ALTER TABLE delivery_alerts
  ADD CONSTRAINT ck_delivery_alert_ack_pair CHECK (
    (acknowledged_at IS NULL AND acknowledged_by IS NULL)
    OR (acknowledged_at IS NOT NULL AND acknowledged_by IS NOT NULL)
  );

CREATE INDEX idx_delivery_alert_unacknowledged
  ON delivery_alerts(last_observed_at DESC)
  WHERE status = 'ACTIVE' AND acknowledged_at IS NULL;
