ALTER TABLE replay_plans ADD COLUMN execution_request_key VARCHAR(160);
CREATE UNIQUE INDEX ux_replay_plans_execution_request_key ON replay_plans(execution_request_key) WHERE execution_request_key IS NOT NULL;

ALTER TABLE discard_plans ADD COLUMN execution_request_key VARCHAR(160);
CREATE UNIQUE INDEX ux_discard_plans_execution_request_key ON discard_plans(execution_request_key) WHERE execution_request_key IS NOT NULL;
