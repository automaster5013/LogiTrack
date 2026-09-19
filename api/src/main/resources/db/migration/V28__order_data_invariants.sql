ALTER TABLE orders
  ADD CONSTRAINT orders_origin_lat_range CHECK (origin_lat BETWEEN -90 AND 90),
  ADD CONSTRAINT orders_origin_lon_range CHECK (origin_lon BETWEEN -180 AND 180),
  ADD CONSTRAINT orders_destination_lat_range CHECK (destination_lat BETWEEN -90 AND 90),
  ADD CONSTRAINT orders_destination_lon_range CHECK (destination_lon BETWEEN -180 AND 180),
  ADD CONSTRAINT orders_required_text_nonblank CHECK (
    btrim(order_number) <> '' AND
    btrim(origin_name) <> '' AND
    btrim(destination_name) <> '' AND
    btrim(idempotency_key) <> ''
  ),
  ADD CONSTRAINT orders_timestamp_order CHECK (updated_at >= created_at);
