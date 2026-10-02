ALTER TABLE replay_plans ADD COLUMN request_key VARCHAR(160);
ALTER TABLE discard_plans ADD COLUMN request_key VARCHAR(160);

UPDATE replay_plans SET request_key = 'legacy:' || id::text;
UPDATE discard_plans SET request_key = 'legacy:' || id::text;

CREATE UNIQUE INDEX uq_replay_plan_request ON replay_plans(request_key) WHERE request_key IS NOT NULL;
CREATE UNIQUE INDEX uq_discard_plan_request ON discard_plans(request_key) WHERE request_key IS NOT NULL;

ALTER TABLE replay_plans ALTER COLUMN request_key SET NOT NULL;
ALTER TABLE discard_plans ALTER COLUMN request_key SET NOT NULL;
