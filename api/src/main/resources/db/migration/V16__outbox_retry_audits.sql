CREATE TABLE outbox_retry_audits (
  id UUID PRIMARY KEY,
  outbox_event_id UUID NOT NULL REFERENCES outbox_events(id),
  actor VARCHAR(120) NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_outbox_retry_audits_occurred ON outbox_retry_audits(occurred_at DESC);
