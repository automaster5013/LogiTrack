CREATE TABLE deliveries (
  id UUID PRIMARY KEY,
  order_number VARCHAR(80) NOT NULL,
  vehicle_id VARCHAR(80) NOT NULL,
  status VARCHAR(32) NOT NULL,
  origin_name VARCHAR(160) NOT NULL,
  origin_lat DOUBLE PRECISION NOT NULL,
  origin_lon DOUBLE PRECISION NOT NULL,
  destination_name VARCHAR(160) NOT NULL,
  destination_lat DOUBLE PRECISION NOT NULL,
  destination_lon DOUBLE PRECISION NOT NULL,
  current_lat DOUBLE PRECISION,
  current_lon DOUBLE PRECISION,
  progress DOUBLE PRECISION NOT NULL DEFAULT 0,
  eta TIMESTAMPTZ,
  idempotency_key VARCHAR(160) NOT NULL UNIQUE,
  version BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_deliveries_vehicle ON deliveries(vehicle_id);
CREATE INDEX idx_deliveries_status ON deliveries(status);

CREATE TABLE processed_events (
  event_id UUID PRIMARY KEY,
  consumer_name VARCHAR(120) NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL
);

