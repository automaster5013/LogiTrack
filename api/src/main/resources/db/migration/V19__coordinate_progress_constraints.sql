ALTER TABLE deliveries
  ADD CONSTRAINT deliveries_origin_lat_range CHECK (origin_lat BETWEEN -90 AND 90),
  ADD CONSTRAINT deliveries_origin_lon_range CHECK (origin_lon BETWEEN -180 AND 180),
  ADD CONSTRAINT deliveries_destination_lat_range CHECK (destination_lat BETWEEN -90 AND 90),
  ADD CONSTRAINT deliveries_destination_lon_range CHECK (destination_lon BETWEEN -180 AND 180),
  ADD CONSTRAINT deliveries_current_lat_range CHECK (current_lat IS NULL OR current_lat BETWEEN -90 AND 90),
  ADD CONSTRAINT deliveries_current_lon_range CHECK (current_lon IS NULL OR current_lon BETWEEN -180 AND 180),
  ADD CONSTRAINT deliveries_progress_range CHECK (progress BETWEEN 0 AND 1);

ALTER TABLE telemetry_points
  ADD CONSTRAINT telemetry_points_latitude_range CHECK (latitude BETWEEN -90 AND 90),
  ADD CONSTRAINT telemetry_points_longitude_range CHECK (longitude BETWEEN -180 AND 180),
  ADD CONSTRAINT telemetry_points_progress_range CHECK (progress BETWEEN 0 AND 1);
