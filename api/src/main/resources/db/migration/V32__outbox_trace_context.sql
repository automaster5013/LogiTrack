ALTER TABLE outbox_events
  ADD COLUMN origin_trace_id VARCHAR(32),
  ADD COLUMN origin_span_id VARCHAR(16),
  ADD COLUMN origin_trace_sampled BOOLEAN;

ALTER TABLE outbox_events ADD CONSTRAINT outbox_origin_trace_context_complete CHECK (
  (origin_trace_id IS NULL AND origin_span_id IS NULL AND origin_trace_sampled IS NULL) OR
  (origin_trace_id ~ '^[0-9a-f]{32}$' AND origin_span_id ~ '^[0-9a-f]{16}$' AND origin_trace_sampled IS NOT NULL)
);
