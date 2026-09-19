ALTER TABLE deliveries ADD COLUMN last_telemetry_at TIMESTAMPTZ;

UPDATE deliveries d
SET last_telemetry_at = latest.occurred_at
FROM (
  SELECT delivery_id, MAX(occurred_at) AS occurred_at
  FROM telemetry_points
  GROUP BY delivery_id
) latest
WHERE latest.delivery_id = d.id;
