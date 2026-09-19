ALTER TABLE outbox_retry_audits
  DROP CONSTRAINT outbox_retry_audits_outbox_event_id_fkey,
  ADD CONSTRAINT outbox_retry_audits_outbox_event_id_fkey
    FOREIGN KEY (outbox_event_id) REFERENCES outbox_events(id) ON DELETE CASCADE;
