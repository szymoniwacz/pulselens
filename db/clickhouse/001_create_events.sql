CREATE TABLE IF NOT EXISTS events
(
    application_id UUID,
    event_id UUID,
    name String,
    user_id String,
    occurred_at DateTime64(3, 'UTC'),
    received_at DateTime64(3, 'UTC'),
    platform LowCardinality(String),
    country LowCardinality(String),
    properties String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (application_id, occurred_at, name, event_id)
