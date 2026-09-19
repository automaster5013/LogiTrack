CREATE INDEX idx_delivery_alert_observed_desc ON delivery_alerts(last_observed_at DESC);
CREATE INDEX idx_warehouse_tasks_created_desc ON warehouse_tasks(created_at DESC);
