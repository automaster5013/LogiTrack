ALTER TABLE dead_letter_events
  ADD COLUMN discarded_at TIMESTAMPTZ,
  ADD COLUMN discarded_by VARCHAR(120),
  ADD COLUMN discard_reason VARCHAR(500),
  DROP CONSTRAINT dead_letter_status_values,
  DROP CONSTRAINT dead_letter_replay_state,
  ADD CONSTRAINT dead_letter_status_values CHECK (status IN ('PENDING','REPLAYED','DISCARDED')),
  ADD CONSTRAINT dead_letter_terminal_state CHECK (
    (status = 'PENDING' AND replayed_at IS NULL AND replayed_by IS NULL AND discarded_at IS NULL AND discarded_by IS NULL AND discard_reason IS NULL) OR
    (status = 'REPLAYED' AND replayed_at IS NOT NULL AND replayed_by IS NOT NULL AND discarded_at IS NULL AND discarded_by IS NULL AND discard_reason IS NULL) OR
    (status = 'DISCARDED' AND replayed_at IS NULL AND replayed_by IS NULL AND discarded_at IS NOT NULL AND discarded_by IS NOT NULL AND discard_reason IS NOT NULL)
  );

ALTER TABLE replay_audits
  ADD COLUMN reason VARCHAR(500),
  DROP CONSTRAINT replay_audit_action_values,
  ADD CONSTRAINT replay_audit_action_values CHECK (action IN ('REPLAY','DISCARD')),
  ADD CONSTRAINT replay_audit_reason_state CHECK ((action = 'REPLAY' AND reason IS NULL) OR (action = 'DISCARD' AND reason IS NOT NULL));

DROP INDEX idx_dead_letter_replayed_retention;
CREATE INDEX idx_dead_letter_terminal_retention ON dead_letter_events(COALESCE(replayed_at, discarded_at))
  WHERE status IN ('REPLAYED','DISCARDED');
