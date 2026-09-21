DROP INDEX IF EXISTS idx_telemetry_points_delivery_occurred;
CREATE INDEX idx_telemetry_points_delivery_occurred
  ON telemetry_points(delivery_id, occurred_at DESC, event_id DESC);

DROP INDEX IF EXISTS idx_telemetry_points_occurred_at;
CREATE INDEX idx_telemetry_points_occurred_at
  ON telemetry_points(occurred_at DESC, event_id DESC);
