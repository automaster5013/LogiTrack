CREATE TABLE dead_letter_events (
  id UUID PRIMARY KEY,
  original_topic VARCHAR(160) NOT NULL,
  message_key VARCHAR(240),
  payload TEXT NOT NULL,
  trace_id VARCHAR(160),
  exception_message VARCHAR(1000),
  dlq_topic VARCHAR(160) NOT NULL,
  dlq_partition INTEGER NOT NULL,
  dlq_offset BIGINT NOT NULL,
  status VARCHAR(24) NOT NULL,
  failed_at TIMESTAMPTZ NOT NULL,
  replayed_at TIMESTAMPTZ,
  replayed_by VARCHAR(120),
  UNIQUE (dlq_topic, dlq_partition, dlq_offset)
);
CREATE INDEX idx_dead_letter_status_failed ON dead_letter_events(status, failed_at DESC);

CREATE TABLE replay_audits (
  id UUID PRIMARY KEY,
  dead_letter_event_id UUID NOT NULL REFERENCES dead_letter_events(id),
  action VARCHAR(32) NOT NULL,
  actor VARCHAR(120) NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_replay_audits_event ON replay_audits(dead_letter_event_id, occurred_at DESC);

