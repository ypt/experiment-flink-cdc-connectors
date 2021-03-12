CREATE TABLE users_favorite_color (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGSERIAL,
  favorite_color VARCHAR
);

-- NOTE: REPLICA IDENDITY needs to be set to FULL
-- https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/connectors/formats/debezium.html#consuming-data-
-- https://debezium.io/documentation/reference/1.2/connectors/postgresql.html#postgresql-replica-identity
ALTER TABLE users_favorite_color REPLICA IDENTITY FULL;
