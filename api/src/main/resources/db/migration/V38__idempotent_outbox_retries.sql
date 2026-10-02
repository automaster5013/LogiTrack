ALTER TABLE outbox_retry_audits ADD COLUMN request_key VARCHAR(160);
UPDATE outbox_retry_audits SET request_key = 'legacy:' || id::text;
CREATE UNIQUE INDEX uq_outbox_retry_request ON outbox_retry_audits(request_key);
ALTER TABLE outbox_retry_audits ALTER COLUMN request_key SET NOT NULL;
