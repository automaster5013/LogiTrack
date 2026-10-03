ALTER TABLE orders ADD COLUMN dispatch_request_key VARCHAR(160);
CREATE UNIQUE INDEX uq_orders_dispatch_request ON orders(dispatch_request_key) WHERE dispatch_request_key IS NOT NULL;
