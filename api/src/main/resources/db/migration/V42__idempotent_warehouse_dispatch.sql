ALTER TABLE warehouse_tasks ADD COLUMN dispatch_request_key VARCHAR(160);
CREATE UNIQUE INDEX uq_warehouse_dispatch_request ON warehouse_tasks(dispatch_request_key) WHERE dispatch_request_key IS NOT NULL;
