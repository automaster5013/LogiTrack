CREATE TABLE replay_plans (
  id UUID PRIMARY KEY,
  actor VARCHAR(120) NOT NULL,
  event_ids JSONB NOT NULL,
  status VARCHAR(24) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  executed_at TIMESTAMPTZ,
  succeeded_count INTEGER NOT NULL DEFAULT 0,
  failed_count INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_replay_plans_status_expires ON replay_plans(status, expires_at);

