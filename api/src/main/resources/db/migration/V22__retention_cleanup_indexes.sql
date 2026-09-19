CREATE INDEX idx_processed_events_processed_at
  ON processed_events(processed_at);

CREATE INDEX idx_outbox_published_retention
  ON outbox_events(published_at)
  WHERE status = 'PUBLISHED';

CREATE INDEX idx_telemetry_points_occurred_at
  ON telemetry_points(occurred_at);
