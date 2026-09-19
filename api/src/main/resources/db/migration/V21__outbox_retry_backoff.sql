ALTER TABLE outbox_events ADD COLUMN next_attempt_at TIMESTAMPTZ;
UPDATE outbox_events SET next_attempt_at = COALESCE(published_at, created_at);
ALTER TABLE outbox_events ALTER COLUMN next_attempt_at SET NOT NULL;

DROP INDEX idx_outbox_pending;
CREATE INDEX idx_outbox_pending_due ON outbox_events(next_attempt_at, created_at)
  WHERE status = 'PENDING';
