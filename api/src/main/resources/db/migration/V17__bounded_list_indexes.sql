CREATE INDEX idx_deliveries_created_desc ON deliveries(created_at DESC);
CREATE INDEX idx_orders_created_desc ON orders(created_at DESC);
CREATE INDEX idx_route_snapshots_generated_desc ON route_snapshots(generated_at DESC);
