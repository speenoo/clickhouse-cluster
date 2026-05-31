# ClickHouse Two-Node Bootstrap

This repo is configured to bring up the first production cluster on two existing OVH nodes:

- Node 2: `40.160.32.78`
- Node 3: `15.204.208.204`

The starting topology is:

- 1 ClickHouse shard
- 2 ClickHouse replicas
- 2 ClickHouse Keeper nodes
- shared OVH S3-backed storage policy named `ovh_main`
- optional HAProxy service on Node 2

This is intentionally not the final 3-shard layout. It is the smallest setup that lets Node 2 and Node 3 coordinate as replicas and lets either node load data.

## Service Layout

Run these services:

| Node | Service | Dockerfile | Role |
| --- | --- | --- | --- |
| Node 2 | `keeper-01` | `clickhouse_keeper/Dockerfile` | Keeper server 1 |
| Node 2 | `clickhouse-01-01` | `clickhouse/Dockerfile` | shard 01, replica 01 |
| Node 2 | `proxy` | `proxy/Dockerfile` | optional client entrypoint |
| Node 3 | `keeper-02` | `clickhouse_keeper/Dockerfile` | Keeper server 2 |
| Node 3 | `clickhouse-01-02` | `clickhouse/Dockerfile` | shard 01, replica 02 |

Use internal/private hostnames or private IPs if Coolify gives them to you. The public IPs below are filled in so the shape is clear.

## Required Ports

Node 2 and Node 3 must be able to reach each other on:

```text
2181  Keeper client port
9234  Keeper raft port
8123  ClickHouse HTTP
9000  ClickHouse native TCP
9009  ClickHouse interserver replication
```

If the proxy runs on the same machine as ClickHouse, avoid binding both proxy `9000` and ClickHouse `9000` to the same host port. Prefer internal networking between containers and expose only the proxy externally.

## Node 2: Keeper Env

Use this for the `keeper-01` service on Node 2:

```sh
KEEPER_ID=1
KEEPER_01_HOST=40.160.32.78
KEEPER_02_HOST=15.204.208.204
```

## Node 2: ClickHouse Env

Use this for the `clickhouse-01-01` service on Node 2:

```sh
KEEPER_01_HOST=40.160.32.78
KEEPER_02_HOST=15.204.208.204

CLICKHOUSE_01_01_HOST=40.160.32.78
CLICKHOUSE_01_02_HOST=15.204.208.204

CLICKHOUSE_HOSTNAME=40.160.32.78
CH_SHARD=01
CH_REPLICA=01

CH_USER=default
CH_PASSWORD=replace-me

OVH_S3_ENDPOINT=https://your-bucket.s3.region.example/
OVH_S3_ACCESS_KEY_ID=replace-me
OVH_S3_SECRET_ACCESS_KEY=replace-me
```

## Node 2: Proxy Env

Use this for the optional `proxy` service on Node 2:

```sh
CLICKHOUSE_01_01_HOST=40.160.32.78
CLICKHOUSE_01_02_HOST=15.204.208.204

RAILWAY_SERVICE_ID=clickhouse
HA_PROXY_STATS_USERNAME=admin
HA_PROXY_STATS_PASSWORD=replace-me
```

The proxy listens inside its container on:

```text
8080  HTTP
9000  native TCP
```

## Node 3: Keeper Env

Use this for the `keeper-02` service on Node 3:

```sh
KEEPER_ID=2
KEEPER_01_HOST=40.160.32.78
KEEPER_02_HOST=15.204.208.204
```

## Node 3: ClickHouse Env

Use this for the `clickhouse-01-02` service on Node 3:

```sh
KEEPER_01_HOST=40.160.32.78
KEEPER_02_HOST=15.204.208.204

CLICKHOUSE_01_01_HOST=40.160.32.78
CLICKHOUSE_01_02_HOST=15.204.208.204

CLICKHOUSE_HOSTNAME=15.204.208.204
CH_SHARD=01
CH_REPLICA=02

CH_USER=default
CH_PASSWORD=replace-me

OVH_S3_ENDPOINT=https://your-bucket.s3.region.example/
OVH_S3_ACCESS_KEY_ID=replace-me
OVH_S3_SECRET_ACCESS_KEY=replace-me
```

## Persistent Mounts

Each ClickHouse service needs persistent storage for:

```text
/var/lib/clickhouse
/var/lib/clickhouse-disks/d1
/var/lib/clickhouse-disks/d2
```

Each Keeper service needs persistent storage for:

```text
/var/lib/clickhouse/coordination
```

The S3 cache lives at:

```text
/var/lib/clickhouse-disks/d1/s3_cache/
```

The configured cache size is `3000Gi`, so Node 2 and Node 3 need enough local disk under `d1`.

## Boot Order

1. Start `keeper-01` on Node 2.
2. Start `keeper-02` on Node 3.
3. Start `clickhouse-01-01` on Node 2.
4. Start `clickhouse-01-02` on Node 3.
5. Start `proxy` on Node 2 after both ClickHouse services are healthy.

This is a two-node Keeper cluster. Both Keeper nodes must be live for Keeper writes to continue. That is acceptable for this bootstrap, but a later production hardening pass should add a third Keeper node.

## Table Pattern

Create replicated local tables on the cluster:

```sql
CREATE DATABASE IF NOT EXISTS db ON CLUSTER local_cluster;

CREATE TABLE db.events_local ON CLUSTER local_cluster
(
    event_date Date,
    id UInt64
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{installation}/{cluster}/{shard}/db/events_local',
    '{replica}'
)
PARTITION BY event_date
ORDER BY id
SETTINGS storage_policy = 'ovh_main';
```

Create a distributed table in front of it:

```sql
CREATE TABLE db.events ON CLUSTER local_cluster AS db.events_local
ENGINE = Distributed(local_cluster, db, events_local, rand());
```

## Loading Data

Normal loading path:

```sql
INSERT INTO db.events SELECT ...
```

That lets ClickHouse route through the `Distributed` table. Because there is one shard and two replicas, ClickHouse writes to one healthy replica and replication catches the other one up.

Node 3 targeted loading path:

1. Connect directly to Node 3.
2. Insert into the local replicated table:

```sql
INSERT INTO db.events_local SELECT ...
```

3. Node 2 catches up through ReplicatedMergeTree replication.

Do not point two unrelated, non-replicated tables at the same S3 object path. S3 is shared storage here, but ClickHouse safety comes from the replicated table path, Keeper metadata, and unique `{replica}` values.

## Smoke Checks

From either ClickHouse node:

```sql
SELECT * FROM system.clusters WHERE cluster = 'local_cluster';
SELECT * FROM system.zookeeper WHERE path = '/';
SELECT database, table, is_leader, is_readonly, queue_size FROM system.replicas;
```

Expected basics:

- `system.clusters` shows two replicas for `local_cluster`.
- `system.zookeeper` returns rows.
- `system.replicas.is_readonly` should be `0` for healthy replicated tables.
