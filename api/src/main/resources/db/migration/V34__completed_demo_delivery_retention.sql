ALTER TABLE route_snapshots DROP CONSTRAINT route_snapshots_delivery_id_fkey;
ALTER TABLE route_snapshots ADD CONSTRAINT route_snapshots_delivery_id_fkey
  FOREIGN KEY (delivery_id) REFERENCES deliveries(id) ON DELETE CASCADE;

ALTER TABLE delivery_alerts DROP CONSTRAINT delivery_alerts_delivery_id_fkey;
ALTER TABLE delivery_alerts ADD CONSTRAINT delivery_alerts_delivery_id_fkey
  FOREIGN KEY (delivery_id) REFERENCES deliveries(id) ON DELETE CASCADE;

ALTER TABLE telemetry_points DROP CONSTRAINT telemetry_points_delivery_id_fkey;
ALTER TABLE telemetry_points ADD CONSTRAINT telemetry_points_delivery_id_fkey
  FOREIGN KEY (delivery_id) REFERENCES deliveries(id) ON DELETE CASCADE;

CREATE INDEX idx_deliveries_completed_demo_retention
  ON deliveries(updated_at, id)
  WHERE status = 'DELIVERED' AND vehicle_id LIKE 'TRUCK-DEMO-%';
