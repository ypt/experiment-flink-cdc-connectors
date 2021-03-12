# experiment-flink-cdc
An exploration of [Flink](https://flink.apache.org/) and change-data-capture
(CDC). We will try to examine what it's like to have Flink directly manage CDC,
omitting messaging middleware (Kafka, Pulsar, etc.). For comparison, here's
another exploration of that does include an event log middleware ([Apache
Pulsar](https://pulsar.apache.org/)) in the system:
[experiment-flink-pulsar-debezium](https://github.com/ypt/experiment-flink-pulsar-debezium).

Here, this exploration primariy leverages:

- Flink's [Debezium](https://debezium.io/) embedding
  [flink-cdc-connectors](https://github.com/ververica/flink-cdc-connectors)
- [Flink Table
  API](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/tableApi.html)
- [Flink SQL
  Client](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/sqlClient.html)

It is based and adapted from [these resources](#resources).

If you're impatient and would like to jump directly to the [takeaways from this
exploration](#takeaways).

Otherwise, continue reading below for a hands on example that you can run on
your own.

Here's the system we'll experiment with

![System diagram](/docs/system-diagram.svg?raw=true&sanitize=true "System
diagram")

## Why?
The general theme of "I want to get state from Point-A to Point-B, maybe
transform it along the way, and continue to keep it updated, in near real-time"
is a fairly common story that can take a variety of forms.
1. data integration amongst microservices
1. analytic datastore loading and updating
1. cache maintenance
1. search index syncing

Given these use cases, some interesting questions to explore are:
1. Fundamentally, how well does a stream processing paradigm speak to these use
   cases? (I believe it does quite well.
   [[1](https://www.confluent.io/blog/using-logs-to-build-a-solid-data-infrastructure-or-why-dual-writes-are-a-bad-idea/),
   [2](https://www.confluent.io/blog/turning-the-database-inside-out-with-apache-samza/),
   [3](https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying)])
1. How about Flink and its ecosystem?
1. From a technological lens: how's performance, scalability, and fault
   tolerence?
1. From a usability lens: what types of personas might be successful using
   various types of solutions? For example, how easy to use and powerful are
   Flink's [Table
   API](https://ci.apache.org/projects/flink/flink-docs-release-1.12/dev/table/)
   and [SQL
   Client](https://ci.apache.org/projects/flink/flink-docs-release-1.12/dev/table/sqlClient.html),
   vs its more expressive [lower level
   API's](https://ci.apache.org/projects/flink/flink-docs-release-1.12/dev/datastream_api.html).
   And what types of personas might be good fits for each?

## Setup
Build and bring up the system
```sh
docker-compose build
docker-compose up
```

For some visibility into the Flink system, Flink provides a web UI. To check it
out, visit: http://localhost:8081/#/overview

Log into `source-db1` psql shell
```sh
docker-compose exec source-db1 psql experiment experiment
```

Start Flink SQL client
```sh
docker-compose exec sql-client ./sql-client.sh
```

## Set up a connector to a Postgres source

Define a [Dynamic
Table](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/streaming/dynamic_tables.html)
using the `source-db1` database `users` table. See more connector configuration
options
[here](https://github.com/ververica/flink-cdc-connectors/blob/master/flink-connector-postgres-cdc/src/main/java/com/alibaba/ververica/cdc/connectors/postgres/table/PostgreSQLTableFactory.java#L38).
```sql
-- Flink SQL Client

CREATE TABLE source_db1_users (
  id BIGINT NOT NULL,
  full_name STRING
) WITH (
  'connector' = 'postgres-cdc',
  'decoding.plugin.name' = 'pgoutput',
  'hostname' = 'source-db1',
  'port' = '5432',
  'username' = 'experiment',
  'password' = 'experiment',
  'database-name' = 'experiment',
  'schema-name' = 'public',
  'table-name' = 'users'
);
```

In `source-db1` psql, examine the [replication
slots](https://www.postgresql.org/docs/10/logical-replication.html)
```sql
-- source-db1 psql

SELECT * FROM pg_replication_slots;

--  slot_name | plugin | slot_type | datoid | database | temporary | active | active_pid | xmin | catalog_xmin | restart_lsn | confirmed_flush_lsn
-- -----------+--------+-----------+--------+----------+-----------+--------+------------+------+--------------+-------------+---------------------
-- (0 rows)
```

Notice that there are no replication slots, yet.

Now start a [Continuous
Query](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/streaming/dynamic_tables.html#continuous-queries)
via the Flink SQL CLI that connects to `source-db1`.
```sql
-- Flink SQL Client

SELECT * FROM source_db1_users;
```

In `source-db1` psql, examine the replication slots again
```sql
-- source-db1 psql

SELECT * FROM pg_replication_slots;

--  slot_name |  plugin  | slot_type | datoid |  database  | temporary | active | active_pid | xmin | catalog_xmin | restart_lsn | confirmed_flush_lsn
-- -----------+----------+-----------+--------+------------+-----------+--------+------------+------+--------------+-------------+---------------------
--  flink     | pgoutput | logical   |  16384 | experiment | f         | f      |            |      |          560 | 0/1660A30   | 0/1660A68
-- (1 row)
```

Notice that a replication slot named `flink` was created.

And insert a row into the `users` table
```sql
-- source-db1 psql

INSERT INTO users (full_name) VALUES ('susan smith');
```

Notice that the query in the Flink SQL client window now shows this new row!

Update the row
```sql
-- source-db1 psql

UPDATE users SET full_name = 'susanna smith' WHERE id = 1;
```

Notice that the query in the Flink SQL client window now shows the updated
value!

## Set up another source, and join data across sources

Set up another Dynamic Table, via a connector to another Postgres database,
`source-db2`
```sql
-- Flink SQL Client

CREATE TABLE source_db2_users_favorite_color (
  id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  favorite_color STRING
) WITH (
  'connector' = 'postgres-cdc',
  'decoding.plugin.name' = 'pgoutput',
  'hostname' = 'source-db2',
  'port' = '5432',
  'username' = 'experiment',
  'password' = 'experiment',
  'database-name' = 'experiment',
  'schema-name' = 'public',
  'table-name' = 'users_favorite_color'
);
```

Try a query that joins data from the two source tables
```sql
-- Flink SQL Client

SELECT * FROM source_db1_users AS u
  LEFT JOIN source_db2_users_favorite_color AS ufc
  ON u.id = ufc.user_id;

-- id        full_name           id0         user_id      favorite_color
--  1    susanna smith        (NULL)          (NULL)              (NULL)
```

## Sending data to a sink

Now let's create a [JDBC
sink](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/connectors/jdbc.html)
that connects to the `sink-db1` database's `users_full_name_and_favorite_color`
table.

```sql
-- Flink SQL Client

CREATE TABLE sink_db1_users_full_name_and_favorite_color (
  id BIGINT NOT NULL,
  full_name STRING,
  favorite_color STRING,
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'jdbc',
  'url' = 'jdbc:postgresql://sink-db1:5432/experiment',
  'username' = 'experiment',
  'password' = 'experiment',
  'table-name' = 'users_full_name_and_favorite_color'
);
```

Let's examine what's at the sink table.

```sql
-- sink-db1 psql, docker-compose exec sink-db1 psql experiment experiment

SELECT * FROM users_full_name_and_favorite_color;

--  id | full_name | favorite_color
-- ----+-----------+----------------
-- (0 rows)
```

There's nothing there yet, because we have not written anything there yet.

Now let's write to the sink using data joined from `source-db1` and
`source-db2`. We can do this via a [Continuous
Query](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/streaming/dynamic_tables.html#continuous-queries)
performing an `INSERT` into the sink.
```sql
-- Flink SQL Client

INSERT INTO sink_db1_users_full_name_and_favorite_color (id, full_name, favorite_color)
SELECT
  u.id,
  u.full_name,
  ufc.favorite_color
FROM source_db1_users AS u
  LEFT JOIN source_db2_users_favorite_color AS ufc
  ON u.id = ufc.user_id;
```

Check the results at `sink-db1`
```sql
-- sink-db1 psql

SELECT * FROM users_full_name_and_favorite_color;

--  id |   full_name   | favorite_color
-- ----+---------------+----------------
--   1 | susanna smith |
-- (1 row)
```

Insert some new data into `source-db2`
```sql
-- source-db2 psql, docker-compose exec source-db2 psql experiment experiment

INSERT INTO users_favorite_color (user_id, favorite_color) VALUES (1, 'blue');
```

Check out the results at `sink-db1` again
```sql
-- sink-db1 psql

SELECT * FROM users_full_name_and_favorite_color;

--  id |  full_name  | favorite_color
-- ----+-------------+----------------
--   1 | susan smith | blue
-- (1 row)
```

Try out a few updates at the source databases

```sql
-- source-db1 psql

UPDATE users SET full_name = 'sue smith' WHERE id = 1;
INSERT INTO users (full_name) VALUES ('bob smith');
```

```sql
-- source-db2 psql

INSERT INTO users_favorite_color (user_id, favorite_color) VALUES (2, 'red');
```

And refresh the sink...
```sql
-- sink-db1 psql

SELECT * FROM users_full_name_and_favorite_color;

--  id | full_name | favorite_color
-- ----+-----------+----------------
--   1 | sue smith | blue
--   2 | bob smith | red
-- (2 rows)
```

## Can a Postgres replication slot be shared?
In another **concurrent** Flink SQL client session, trying to add a concurrent
stream to `source-db1`.

Bring up another Flink SQL client session
```sh
docker-compose exec sql-client ./sql-client.sh
```

Set up another source connection
```sql
-- Flink SQL Client

CREATE TABLE source_db1_test (
  id BIGINT NOT NULL,
  hello STRING
) WITH (
  'connector' = 'postgres-cdc',
  'decoding.plugin.name' = 'pgoutput',
  'hostname' = 'source-db1',
  'port' = '5432',
  'username' = 'experiment',
  'password' = 'experiment',
  'database-name' = 'experiment',
  'schema-name' = 'public',
  'table-name' = 'test'
);

SELECT * FROM source_db1_test;

-- [ERROR] Could not execute SQL statement. Reason:
-- org.postgresql.util.PSQLException: FATAL: number of requested standby connections exceeds max_wal_senders (currently 1)
```

Set Postgres `max_wal_senders=10` at the source databases (in
`docker-compose.yaml`), restart the system, and try again

```sql
-- Flink SQL Client

CREATE TABLE source_db1_test (
  id BIGINT NOT NULL,
  hello STRING
) WITH (
  'connector' = 'postgres-cdc',
  'decoding.plugin.name' = 'pgoutput',
  'hostname' = 'source-db1',
  'port' = '5432',
  'username' = 'experiment',
  'password' = 'experiment',
  'database-name' = 'experiment',
  'schema-name' = 'public',
  'table-name' = 'test'
);

SELECT * FROM source_db1_test;

-- [ERROR] Could not execute SQL statement. Reason:
-- org.postgresql.util.PSQLException: ERROR: replication slot "flink" is active for PID 34
```

**Takeaway**: A _single_ Postgres replication slot cannot be shared
_concurrently_.

Ok then - let's try setting up _another_ replication slot.

Set Postgres `max_replication_slots=10` at the source databases (in
`docker-compose.yaml`), restart the system, and try again

```sql
CREATE TABLE source_db1_test (
  id BIGINT NOT NULL,
  hello STRING
) WITH (
  'connector' = 'postgres-cdc',
  'decoding.plugin.name' = 'pgoutput',
  'slot.name' = 'flink2', -- ADDED THIS
  'hostname' = 'source-db1',
  'port' = '5432',
  'username' = 'experiment',
  'password' = 'experiment',
  'database-name' = 'experiment',
  'schema-name' = 'public',
  'table-name' = 'test'
);

select * from source_db1_test;

-- [ERROR] Could not execute SQL statement. Reason:
-- org.apache.flink.table.api.ValidationException: Unsupported options found for connector 'postgres-cdc'.

-- Unsupported options:

-- slot.name

-- Supported options:

-- connector
-- database-name
-- decoding.plugin.name
-- hostname
-- password
-- port
-- property-version
-- schema-name
-- table-name
-- username
```

**Takeaway**: Bad news, we need to provide a unique slot name, but are not yet
able to as of `v1.2.0` of `flink-cdc-connectors`. However, the good news is that
[slot.name
config](https://github.com/ververica/flink-cdc-connectors/blob/master/flink-connector-postgres-cdc/src/main/java/com/alibaba/ververica/cdc/connectors/postgres/table/PostgreSQLTableFactory.java#L96)
is in the `master` branch though.

## Accessing the Postgres sink via Postgres' catalog also works
Instead of setting up each JDBC sink table individually, the Flink JDBC
connector can be [set up to access and use Postgres'
catalog](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/connectors/jdbc.html#postgres-database-as-a-catalog).


First, if it's still running, stop the old `INSERT` job via Flink's web
interface (http://localhost:8081/#/job/running)

Now set up a new connection via Postgres' catalog.

```sql
-- Flink SQL Client

-- Drop the old sink table in Flink's catalog
DROP TABLE sink_db1_users_full_name_and_favorite_color

-- Connect to Postgres catalog in Flink
CREATE CATALOG sink_db1 WITH (
    'type'='jdbc',
    'property-version'='1',
    'base-url'='jdbc:postgresql://sink-db1:5432/',
    'default-database'='experiment',
    'username'='experiment',
    'password'='experiment'
);

-- Access sink-db1 via Flink's connection to Postgres
SELECT * FROM sink_db1.experiment.users_full_name_and_favorite_color;

-- Create a new INSERT job
INSERT INTO sink_db1.experiment.users_full_name_and_favorite_color (id, full_name, favorite_color)
SELECT
  u.id,
  u.full_name,
  ufc.favorite_color
FROM source_db1_users AS u
  LEFT JOIN source_db2_users_favorite_color AS ufc
  ON u.id = ufc.user_id;
```

Take a look at the data at the sink
```sql
-- sink-db1 psql

SELECT * FROM users_full_name_and_favorite_color;

--  id | full_name | favorite_color
-- ----+-----------+----------------
--   2 | bob smith | red
--   1 | sue smith | blue
-- (2 rows)
```

Insert new data to a source
```sql
-- source-db1 psql

INSERT INTO users (full_name) VALUES ('anne smith');
```

Take a look at the data at the sink again
```sql
-- sink-db1 psql

SELECT * FROM users_full_name_and_favorite_color;

--  id | full_name | favorite_color
-- ----+-----------+----------------
--   2 | bob smith | red
--   1 | sue smith | blue
--   3 | ann smith |
-- (3 rows)
```

The new entry should appear.

The Postgres catalog can also be used for table schema metadata when creating
tables in Flink's catalog, via `CREATE TABLE...LIKE`

```sql
-- FLINK SQL Client
CREATE TABLE sink_db1_users_full_name_and_favorite_color
LIKE sink_db1.experiment.users_full_name_and_favorite_color (INCLUDING OPTIONS);

SELECT * FROM sink_db1_users_full_name_and_favorite_color;
```

## What happens if an underlying _source_ table's schema changes?

Start a Flink Continuous Query
```sql
-- Flink SQL Client

SELECT * FROM source_db1_users;
```

Now, let's try adding a new column
```sql
-- source-db1 psql

ALTER TABLE users
ADD new_column VARCHAR;
```

The Flink query is still running and ok...

Let's insert some data
```sql
-- source-db1 psql

INSERT INTO users (full_name, new_column) VALUES ('fred smith', 'value for new column');
```

The Flink query is still running and ok...

Now let's try dropping a column that our Flink query was using.

```sql
-- source-db1 psql

ALTER TABLE users
DROP COLUMN full_name;
```

The Flink query is _still_ running and ok...

Now insert some new data at the source.
```sql
-- source-db1 psql

INSERT INTO users (new_column) VALUES ('another value for new column');
```

_Now_ the Flink query errors

```
[ERROR] Could not execute SQL statement. Reason:
org.apache.kafka.connect.errors.DataException: full_name is not a valid field name
```

## What happens if underlying _sink_ table schema changes?

First, let's try adding a new column
```sql
-- sink-db1 psql

ALTER TABLE users_full_name_and_favorite_color
ADD COLUMN new_column VARCHAR;
```

Insert some data
```sql
-- source-db1 psql

INSERT INTO users (full_name) VALUES ('sally');
```

Try a Flink query
```sql
-- Flink SQL CLI

SELECT * FROM sink_db1_users_full_name_and_favorite_color;
```

The new row is there, everything still works


Now try removing a column.
```sql
-- sink-db1 psql

ALTER TABLE users_full_name_and_favorite_color
DROP COLUMN full_name;
```

And insert some new data at a source
```sql
-- source-db1 psql

INSERT INTO users (full_name) VALUES ('bob');
```

Check out the Flink web ui (http://localhost:8081). The Flink job performing the
`INSERT` keeps running, and the task manager logs show errors.

```
org.apache.flink.connector.jdbc.internal.JdbcBatchingOutputFormat [] - JDBC executeBatch error, retry times = 0
java.sql.BatchUpdateException: Batch entry 0 INSERT INTO users_full_name_and_favorite_color(id, full_name, favorite_color) VALUES (4, 'sally', NULL) ON CONFLICT (id) DO UPDATE SET id=EXCLUDED.id, full_name=EXCLUDED.full_name, favorite_color=EXCLUDED.favorite_color was aborted: ERROR: column "full_name" of relation "users_full_name_and_favorite_color" does not exist
```

## Takeaways
The `flink-cdc-connector` approach to setting up CDC offers a nice, easy way to
set up CDC. It conveniently does not require additional event log infrastructure
(Kafka, Pulsar, etc.) in the system. That said, with the removal of that
additional layer of indirection, some **care and discipline is recommended when
managing such a system**. Some potentially dangerous things to carefully manage
include:

1. The Flink connector is able to create replication slots at the sources
1. Replication slots that stagnate will result in the accumulation of WAL files
   at the sources

Alternatively, in circumstances where better decoupling and independence between
source owners and sink owners - another form of CDC connection that is more
tightly controlled, and output that is more curated, will be safer and more
manageable. In other words, a more carefully curated "public API" and better
shielded internal implementation details.

For example:

Source owners are responsible for:

```
Source
→ CDC
→ Message bus, raw CDC feed
→ Some process cleanses and prepares the stream for consumers
→ Message bus, cleansed stream, stream is set up to be compacted w/ indefinite
  retention for active keys, tombstoned keys are removed
```

And changelog consumers usage will look like:

```
Message bus, cleansed stream
→ Consumer apps (Flink, Plain old Kafka or Pulsar client, etc.), read and
  leverage cleansed stream somehow
→ Sink
```

The message bus approach is explored more in
[experiment-flink-pulsar-debezium](https://github.com/ypt/experiment-flink-pulsar-debezium).

### A sidenote on GPDR

One challenge with a message bus middleware based approach will be harmonizing
bootstrapping/backfilling ("I need enough changelog data to rebuild state") with
GPDR data deletion requirements ("There is some state that I want to remove
everywhere").

Aside from the "encrypt and throw away key" approach (which has its tradeoffs),
there is another approach - based on compaction + tombstones. While [Kafka's
approach to compaction](https://kafka.apache.org/documentation/#compaction) (the
most recent message per non-deleted key is retained forever, and tombstoned keys
are deleted everywhere) should work for this purpose, [Pulsar's approach to
compaction](https://pulsar.apache.org/docs/en/concepts-topic-compaction/) (a
separate compacted topic is maintained in parallel with the original
non-compacted topic) is problematic until the ability to configure lifecycle
(i.e. retention policy) of both compacted and original topic independently is
implemented. As of Pulsar `2.7.0`, this capability is not yet available.

## Resources
CDC Source
- https://github.com/ververica/flink-cdc-connectors
- https://github.com/morsapaes/flink-sql-CDC
- https://flink.apache.org/2020/07/28/flink-sql-demo-building-e2e-streaming-application.html

JDBC Sink
- https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/connectors/jdbc.html

## Future explorations
- How might we consolidate/merge multiple (logically same, but physically
  independent) source tables from distinct Postgres nodes and schemas into one
  logical dynamic table? For example: With a Postgres + schema per tenant
  database structure. Also, an analogous demuxing at a sink.
- Given a spectrum of personas ranging in technical proficiency - how might we
  potentially productize and platform(ize) solutions for less technical
  personas? For example, the range of those that don't want to think about:
  Java/Scala, deployment, operations, ... to even SQL?
- Performance?
- Fault tolerance? What if a source goes down? What if a sink goes down? What if
  Flink goes down?
- State management best practices? State migrations?
- What is the impact of continuous joins on the size of Flink state?
- Governance, access mgt of source, sink?
- Elasticsearch sink
- Temporal joins, lookup cache -
  https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/connectors/jdbc.html#lookup-cache
- Deployment
