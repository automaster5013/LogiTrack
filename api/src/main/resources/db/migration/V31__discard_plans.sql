CREATE TABLE discard_plans (
  id UUID PRIMARY KEY,
  actor VARCHAR(120) NOT NULL,
  reason VARCHAR(500) NOT NULL,
  event_ids JSONB NOT NULL,
  status VARCHAR(24) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  executed_at TIMESTAMPTZ,
  succeeded_count INTEGER NOT NULL DEFAULT 0,
  failed_count INTEGER NOT NULL DEFAULT 0,
  CONSTRAINT discard_plan_status_values CHECK (status IN ('PREPARED','EXECUTED','PARTIAL','EXPIRED')),
  CONSTRAINT discard_plan_counts_nonnegative CHECK (succeeded_count >= 0 AND failed_count >= 0),
  CONSTRAINT discard_plan_event_ids_array CHECK (jsonb_typeof(event_ids) = 'array' AND jsonb_array_length(event_ids) > 0),
  CONSTRAINT discard_plan_execution_state CHECK (
    (status IN ('PREPARED','EXPIRED') AND executed_at IS NULL) OR
    (status IN ('EXECUTED','PARTIAL') AND executed_at IS NOT NULL)
  )
);
CREATE INDEX idx_discard_plans_status_expires ON discard_plans(status,expires_at);
