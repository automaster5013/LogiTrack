CREATE TABLE telemetry_points (
  event_id UUID PRIMARY KEY,
  delivery_id UUID NOT NULL REFERENCES deliveries(id),
  vehicle_id VARCHAR(120) NOT NULL,
  latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  progress DOUBLE PRECISION NOT NULL CHECK (progress BETWEEN 0 AND 1),
  occurred_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_telemetry_points_delivery_occurred
  ON telemetry_points(delivery_id, occurred_at);
