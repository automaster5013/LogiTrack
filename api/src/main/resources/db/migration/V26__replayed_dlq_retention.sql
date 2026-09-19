ALTER TABLE replay_audits
  DROP CONSTRAINT replay_audits_dead_letter_event_id_fkey,
  ADD CONSTRAINT replay_audits_dead_letter_event_id_fkey
    FOREIGN KEY (dead_letter_event_id) REFERENCES dead_letter_events(id) ON DELETE CASCADE;

CREATE INDEX idx_dead_letter_replayed_retention ON dead_letter_events(replayed_at)
  WHERE status = 'REPLAYED';
