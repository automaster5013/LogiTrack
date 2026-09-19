CREATE TABLE delivery_daily_kpis (
  metric_date DATE PRIMARY KEY,
  total_deliveries BIGINT NOT NULL CHECK (total_deliveries >= 0),
  active_deliveries BIGINT NOT NULL CHECK (active_deliveries >= 0),
  delivered_deliveries BIGINT NOT NULL CHECK (delivered_deliveries >= 0),
  delayed_deliveries BIGINT NOT NULL CHECK (delayed_deliveries >= 0),
  average_progress_percent DOUBLE PRECISION NOT NULL CHECK (average_progress_percent BETWEEN 0 AND 100),
  average_cycle_minutes DOUBLE PRECISION NOT NULL CHECK (average_cycle_minutes >= 0),
  on_time_rate_percent DOUBLE PRECISION NOT NULL CHECK (on_time_rate_percent BETWEEN 0 AND 100),
  projected_at TIMESTAMPTZ NOT NULL
);

