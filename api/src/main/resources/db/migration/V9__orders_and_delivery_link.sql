CREATE TABLE orders (
  id UUID PRIMARY KEY,
  order_number VARCHAR(80) NOT NULL UNIQUE,
  status VARCHAR(24) NOT NULL CHECK (status IN ('READY', 'DISPATCHED', 'FULFILLED')),
  origin_name VARCHAR(160) NOT NULL,
  origin_lat DOUBLE PRECISION NOT NULL,
  origin_lon DOUBLE PRECISION NOT NULL,
  destination_name VARCHAR(160) NOT NULL,
  destination_lat DOUBLE PRECISION NOT NULL,
  destination_lon DOUBLE PRECISION NOT NULL,
  idempotency_key VARCHAR(160) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE deliveries ADD COLUMN order_id UUID REFERENCES orders(id);
CREATE UNIQUE INDEX uq_deliveries_order_id ON deliveries(order_id) WHERE order_id IS NOT NULL;
CREATE INDEX idx_orders_status_created ON orders(status, created_at DESC);
