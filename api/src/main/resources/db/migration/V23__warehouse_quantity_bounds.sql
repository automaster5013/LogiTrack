ALTER TABLE warehouse_tasks
    ADD CONSTRAINT warehouse_tasks_quantity_range
    CHECK (quantity BETWEEN 1 AND 1000000);
