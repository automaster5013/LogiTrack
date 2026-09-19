CREATE TABLE delivery_alerts (
  id UUID PRIMARY KEY,
  delivery_id UUID NOT NULL REFERENCES deliveries(id),
  alert_type VARCHAR(40) NOT NULL,
  severity VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL,
  message VARCHAR(300) NOT NULL,
  observed_value DOUBLE PRECISION NOT NULL,
  threshold_value DOUBLE PRECISION NOT NULL,
  occurrence_count INTEGER NOT NULL,
  first_observed_at TIMESTAMPTZ NOT NULL,
  last_observed_at TIMESTAMPTZ NOT NULL,
  resolved_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX uq_delivery_alert_active
  ON delivery_alerts(delivery_id, alert_type) WHERE status = 'ACTIVE';
CREATE INDEX idx_delivery_alert_status_observed
  ON delivery_alerts(status, last_observed_at DESC);

