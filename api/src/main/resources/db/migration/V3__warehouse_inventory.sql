CREATE TABLE warehouse_stock (
  id UUID PRIMARY KEY,
  warehouse_id VARCHAR(80) NOT NULL,
  sku VARCHAR(100) NOT NULL,
  on_hand INTEGER NOT NULL DEFAULT 0 CHECK (on_hand >= 0),
  reserved INTEGER NOT NULL DEFAULT 0 CHECK (reserved >= 0 AND reserved <= on_hand),
  version BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (warehouse_id, sku)
);

CREATE TABLE warehouse_tasks (
  id UUID PRIMARY KEY,
  task_type VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL,
  reference_number VARCHAR(100) NOT NULL,
  warehouse_id VARCHAR(80) NOT NULL,
  sku VARCHAR(100) NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  idempotency_key VARCHAR(160) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE inventory_ledger (
  id UUID PRIMARY KEY,
  task_id UUID NOT NULL REFERENCES warehouse_tasks(id),
  warehouse_id VARCHAR(80) NOT NULL,
  sku VARCHAR(100) NOT NULL,
  transaction_type VARCHAR(30) NOT NULL,
  on_hand_delta INTEGER NOT NULL,
  reserved_delta INTEGER NOT NULL,
  on_hand_after INTEGER NOT NULL,
  reserved_after INTEGER NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_warehouse_tasks_status ON warehouse_tasks(warehouse_id, status);
CREATE INDEX idx_inventory_ledger_sku ON inventory_ledger(warehouse_id, sku, occurred_at);

