ALTER TABLE deliveries
  ADD CONSTRAINT deliveries_status_values CHECK (status IN ('CREATED','IN_TRANSIT','DELAYED','DELIVERED')),
  ADD CONSTRAINT deliveries_completion_state CHECK ((status = 'DELIVERED') = (progress = 1));
