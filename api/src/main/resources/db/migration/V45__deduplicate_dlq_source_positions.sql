ALTER TABLE dead_letter_events
  ADD COLUMN original_partition INTEGER,
  ADD COLUMN original_offset BIGINT,
  ADD CONSTRAINT dead_letter_original_position_complete CHECK (
    (original_partition IS NULL AND original_offset IS NULL) OR
    (original_partition IS NOT NULL AND original_offset IS NOT NULL AND
     original_partition >= 0 AND original_offset >= 0)
  );

CREATE UNIQUE INDEX uq_dead_letter_original_position
  ON dead_letter_events(original_topic, original_partition, original_offset)
  WHERE original_partition IS NOT NULL AND original_offset IS NOT NULL;
