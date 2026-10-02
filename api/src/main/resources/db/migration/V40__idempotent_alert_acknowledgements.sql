ALTER TABLE delivery_alerts ADD COLUMN acknowledgement_request_key VARCHAR(160);
CREATE UNIQUE INDEX uq_delivery_alert_acknowledgement_request ON delivery_alerts(acknowledgement_request_key) WHERE acknowledgement_request_key IS NOT NULL;
