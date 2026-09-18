CREATE TABLE route_snapshots (
  id UUID PRIMARY KEY,
  delivery_id UUID NOT NULL REFERENCES deliveries(id),
  provider VARCHAR(80) NOT NULL,
  algorithm_version VARCHAR(40) NOT NULL,
  geometry JSONB NOT NULL,
  geometry_hash VARCHAR(64) NOT NULL,
  distance_meters BIGINT NOT NULL CHECK (distance_meters > 0),
  duration_seconds BIGINT NOT NULL CHECK (duration_seconds > 0),
  planned_eta TIMESTAMPTZ NOT NULL,
  generated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_route_snapshots_delivery_generated ON route_snapshots(delivery_id, generated_at DESC);
CREATE INDEX idx_route_snapshots_geometry_hash ON route_snapshots(geometry_hash);

