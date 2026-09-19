ALTER TABLE outbox_events
  ADD CONSTRAINT outbox_status_values CHECK (status IN ('PENDING','PUBLISHED','FAILED')),
  ADD CONSTRAINT outbox_attempts_nonnegative CHECK (attempts >= 0),
  ADD CONSTRAINT outbox_publication_state CHECK ((status = 'PUBLISHED') = (published_at IS NOT NULL));

ALTER TABLE warehouse_tasks
  ADD CONSTRAINT warehouse_task_type_values CHECK (task_type IN ('INBOUND','OUTBOUND')),
  ADD CONSTRAINT warehouse_task_status_values CHECK (status IN ('RECEIVED','PICKED','DISPATCHED')),
  ADD CONSTRAINT warehouse_task_type_status CHECK ((task_type = 'INBOUND' AND status = 'RECEIVED') OR (task_type = 'OUTBOUND' AND status IN ('PICKED','DISPATCHED')));

ALTER TABLE inventory_ledger
  ADD CONSTRAINT inventory_transaction_type_values CHECK (transaction_type IN ('RECEIPT','PICK','DISPATCH')),
  ADD CONSTRAINT inventory_after_values CHECK (on_hand_after >= 0 AND reserved_after >= 0 AND reserved_after <= on_hand_after),
  ADD CONSTRAINT inventory_delta_shape CHECK (
    (transaction_type = 'RECEIPT' AND on_hand_delta > 0 AND reserved_delta = 0) OR
    (transaction_type = 'PICK' AND on_hand_delta = 0 AND reserved_delta > 0) OR
    (transaction_type = 'DISPATCH' AND on_hand_delta < 0 AND reserved_delta = on_hand_delta)
  );

ALTER TABLE delivery_alerts
  ADD CONSTRAINT delivery_alert_type_values CHECK (alert_type IN ('DELAY','ROUTE_DEVIATION')),
  ADD CONSTRAINT delivery_alert_severity_values CHECK (severity IN ('WARNING','CRITICAL')),
  ADD CONSTRAINT delivery_alert_status_values CHECK (status IN ('ACTIVE','RESOLVED')),
  ADD CONSTRAINT delivery_alert_occurrences_positive CHECK (occurrence_count > 0),
  ADD CONSTRAINT delivery_alert_resolution_state CHECK ((status = 'RESOLVED') = (resolved_at IS NOT NULL));

ALTER TABLE dead_letter_events
  ADD CONSTRAINT dead_letter_status_values CHECK (status IN ('PENDING','REPLAYED')),
  ADD CONSTRAINT dead_letter_position_nonnegative CHECK (dlq_partition >= 0 AND dlq_offset >= 0),
  ADD CONSTRAINT dead_letter_replay_state CHECK (
    (status = 'PENDING' AND replayed_at IS NULL AND replayed_by IS NULL) OR
    (status = 'REPLAYED' AND replayed_at IS NOT NULL AND replayed_by IS NOT NULL)
  );

ALTER TABLE replay_audits ADD CONSTRAINT replay_audit_action_values CHECK (action = 'REPLAY');

ALTER TABLE replay_plans
  ADD CONSTRAINT replay_plan_status_values CHECK (status IN ('PREPARED','EXECUTED','PARTIAL','EXPIRED')),
  ADD CONSTRAINT replay_plan_counts_nonnegative CHECK (succeeded_count >= 0 AND failed_count >= 0),
  ADD CONSTRAINT replay_plan_event_ids_array CHECK (jsonb_typeof(event_ids) = 'array' AND jsonb_array_length(event_ids) > 0),
  ADD CONSTRAINT replay_plan_execution_state CHECK (
    (status IN ('PREPARED','EXPIRED') AND executed_at IS NULL) OR
    (status IN ('EXECUTED','PARTIAL') AND executed_at IS NOT NULL)
  );
