CREATE TABLE alert_policies (
    id UUID PRIMARY KEY,
    vehicle_id VARCHAR(120) NOT NULL UNIQUE,
    deviation_open_meters DOUBLE PRECISION NOT NULL,
    deviation_close_meters DOUBLE PRECISION NOT NULL,
    critical_deviation_meters DOUBLE PRECISION NOT NULL,
    delay_open_seconds BIGINT NOT NULL,
    delay_close_seconds BIGINT NOT NULL,
    critical_delay_seconds BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    updated_by VARCHAR(120) NOT NULL,
    CONSTRAINT alert_policy_deviation_order CHECK (
        deviation_close_meters >= 0 AND deviation_close_meters < deviation_open_meters
        AND deviation_open_meters <= critical_deviation_meters
    ),
    CONSTRAINT alert_policy_delay_order CHECK (
        delay_close_seconds >= 0 AND delay_close_seconds < delay_open_seconds
        AND delay_open_seconds <= critical_delay_seconds
    )
);

CREATE TABLE alert_policy_audits (
    id UUID PRIMARY KEY,
    policy_id UUID NOT NULL REFERENCES alert_policies(id),
    vehicle_id VARCHAR(120) NOT NULL,
    deviation_open_meters DOUBLE PRECISION NOT NULL,
    deviation_close_meters DOUBLE PRECISION NOT NULL,
    critical_deviation_meters DOUBLE PRECISION NOT NULL,
    delay_open_seconds BIGINT NOT NULL,
    delay_close_seconds BIGINT NOT NULL,
    critical_delay_seconds BIGINT NOT NULL,
    actor VARCHAR(120) NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_alert_policy_audits_occurred_at ON alert_policy_audits(occurred_at DESC);

INSERT INTO alert_policies (
    id, vehicle_id, deviation_open_meters, deviation_close_meters, critical_deviation_meters,
    delay_open_seconds, delay_close_seconds, critical_delay_seconds, updated_at, updated_by
) VALUES (
    '00000000-0000-0000-0000-000000000011', '*', 500, 300, 1500,
    600, 300, 1800, CURRENT_TIMESTAMP, 'system'
);
