%{
  title: "SRE: Database Reliability",
  author: "Gabriel Garrido",
  description: "We will explore database reliability patterns for PostgreSQL in Kubernetes, from connection pooling and backup strategies to zero-downtime migrations, CloudNativePG operator, and failover automation...",
  tags: ~w(sre database postgresql kubernetes reliability),
  published: true,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In the previous articles we covered [SLIs and SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[incident management](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observability](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[capacity planning](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[secrets management](/blog/sre-secrets-management-in-kubernetes),
[cost optimization](/blog/sre-cost-optimization-in-the-cloud), and
[dependency management](/blog/sre-dependency-management-and-graceful-degradation). We have covered a lot
of ground, but there is one critical piece we have not yet tackled: the database.

<br />

Your database is probably the hardest single point of failure in your entire stack. You can scale stateless
services horizontally, you can restart crashed pods, you can even lose a whole node and recover in seconds.
But if your database goes down, everything stops. If you lose data, it might be gone forever. And if your
migrations lock a table for five minutes during peak traffic, your users will notice.

<br />

In this article we will walk through the patterns and tools that make PostgreSQL reliable in Kubernetes.
We will cover connection pooling, read replicas, backup strategies, zero-downtime migrations, monitoring,
the CloudNativePG operator, and failover automation. These are the building blocks that let you sleep at
night even when your app handles real traffic and real data.

<br />

Let's get into it.

<br />

##### **Connection pooling with PgBouncer**
PostgreSQL creates a new process for every connection. That works fine when you have 10 connections, but
in Kubernetes where you might have dozens of pods each running multiple processes, you can easily exhaust
the server's connection limit. The default `max_connections` in PostgreSQL is 100, and each connection
consumes around 5-10MB of RAM.

<br />

PgBouncer sits between your application and PostgreSQL, multiplexing many client connections onto a smaller
number of server connections. It is lightweight (a single PgBouncer process can handle thousands of client
connections) and battle-tested in production at massive scale.

<br />

Here is a basic PgBouncer configuration:

<br />

```bash
# pgbouncer.ini
[databases]
myapp = host=postgresql-primary port=5432 dbname=myapp_production

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Pool mode: transaction is the most common for web apps
pool_mode = transaction

# Pool sizing
default_pool_size = 20
min_pool_size = 5
max_client_conn = 1000
max_db_connections = 50

# Timeouts
server_idle_timeout = 300
client_idle_timeout = 0
query_timeout = 30

# Logging
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60
```

<br />

The `pool_mode` setting is crucial:

<br />

> * **transaction** mode releases the server connection back to the pool after each transaction completes. This is what you want for most web applications because it maximizes connection reuse. However, it does not support session-level features like prepared statements, advisory locks, or LISTEN/NOTIFY.
> * **session** mode keeps the server connection assigned for the entire client session. This supports all PostgreSQL features but provides less connection multiplexing. Use this if your app relies on session-level features.
> * **statement** mode releases the connection after each statement. This provides the best multiplexing but only works for simple read-only queries with no multi-statement transactions.

<br />

For Ecto (the database layer in Phoenix/Elixir), transaction mode works perfectly because Ecto wraps
each request in an explicit transaction or uses simple queries.

<br />

**Running PgBouncer as a sidecar in Kubernetes**

<br />

The sidecar pattern puts a PgBouncer container in the same pod as your application. This means each
application pod gets its own PgBouncer instance, and the connection to PgBouncer is over localhost
(zero network latency). Here is the pod spec:

<br />

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tr-web
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: tr-web
  template:
    metadata:
      labels:
        app: tr-web
    spec:
      containers:
        - name: app
          image: kainlite/tr:latest
          ports:
            - containerPort: 4000
          env:
            # Point the app at PgBouncer on localhost instead of directly at PostgreSQL
            - name: DATABASE_URL
              value: "ecto://myapp:password@localhost:6432/myapp_production"
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"

        - name: pgbouncer
          image: bitnami/pgbouncer:latest
          ports:
            - containerPort: 6432
          env:
            - name: POSTGRESQL_HOST
              value: "postgresql-primary.database.svc.cluster.local"
            - name: POSTGRESQL_PORT
              value: "5432"
            - name: PGBOUNCER_DATABASE
              value: "myapp_production"
            - name: PGBOUNCER_POOL_MODE
              value: "transaction"
            - name: PGBOUNCER_DEFAULT_POOL_SIZE
              value: "20"
            - name: PGBOUNCER_MAX_CLIENT_CONN
              value: "500"
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
```

<br />

**How to size your connection pool**

<br />

A common mistake is setting the pool too large. More connections does not mean better performance. In
fact, too many connections cause contention on locks and shared buffers, which hurts throughput.

<br />

A good starting formula:

<br />

```bash
# Total server connections = number of CPU cores on the DB server * 2 + effective_spindle_count
# For a 4-core server with SSD:
# max_useful_connections = 4 * 2 + 1 = 9 (but round up to ~20 for headroom)

# Then distribute across your application pods:
# per_pod_pool_size = total_server_connections / number_of_pods
# For 3 pods with 50 max DB connections:
# per_pod_pool_size = 50 / 3 ≈ 16

# In your Ecto repo config:
config :myapp, MyApp.Repo,
  pool_size: 16,
  queue_target: 500,    # Target queue time in ms
  queue_interval: 1000  # How often to check queue health
```

<br />

Monitor the actual connection usage with `SHOW POOLS;` in PgBouncer or with PostgreSQL's
`pg_stat_activity` view. Adjust based on real data, not guesses.

<br />

##### **Read replicas and load balancing**
For read-heavy workloads (which most web applications are), you can offload read queries to replicas
while keeping writes on the primary. PostgreSQL's streaming replication makes this straightforward.

<br />

**Setting up streaming replication**

<br />

On the primary, enable replication in `postgresql.conf`:

<br />

```bash
# postgresql.conf on primary
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on

# Archive WAL for PITR (more on this in the backup section)
archive_mode = on
archive_command = 'pgbackrest --stanza=myapp archive-push %p'
```

<br />

On the replica, set up the recovery configuration:

<br />

```bash
# postgresql.conf on replica
primary_conninfo = 'host=postgresql-primary port=5432 user=replicator password=secret'
primary_slot_name = 'replica_1'
hot_standby = on
hot_standby_feedback = on
```

<br />

**Read/write splitting in Ecto**

<br />

Ecto supports multiple repositories, so you can define a read-only repo that points to replicas:

<br />

```yaml
# lib/myapp/repo.ex
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :myapp,
    adapter: Ecto.Adapters.Postgres
end

# lib/myapp/read_repo.ex
defmodule MyApp.ReadRepo do
  use Ecto.Repo,
    otp_app: :myapp,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
```

<br />

```yaml
# config/runtime.exs
config :myapp, MyApp.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: 16

config :myapp, MyApp.ReadRepo,
  url: System.get_env("DATABASE_REPLICA_URL"),
  pool_size: 20  # Replicas can handle more connections since they only serve reads
```

<br />

Then in your application code, use the appropriate repo:

<br />

```hcl
# Write operations go to the primary
MyApp.Repo.insert(%User{name: "Gabriel"})
MyApp.Repo.update(changeset)
MyApp.Repo.delete(user)

# Read operations go to replicas
MyApp.ReadRepo.all(User)
MyApp.ReadRepo.get(User, 1)

# For operations that need to read their own writes (e.g., after an insert),
# use the primary repo to avoid replication lag issues
def create_and_return_user(attrs) do
  {:ok, user} = MyApp.Repo.insert(%User{} |> User.changeset(attrs))
  # Read from primary, not replica, to avoid stale data
  MyApp.Repo.get!(User, user.id)
end
```

<br />

**Load balancing across replicas with pgpool-II**

<br />

If you have multiple replicas, pgpool-II can distribute read queries across them:

<br />

```bash
# pgpool.conf
backend_hostname0 = 'postgresql-primary'
backend_port0 = 5432
backend_weight0 = 0
backend_flag0 = 'ALWAYS_PRIMARY'

backend_hostname1 = 'postgresql-replica-1'
backend_port1 = 5432
backend_weight1 = 1

backend_hostname2 = 'postgresql-replica-2'
backend_port2 = 5432
backend_weight2 = 1

# Load balancing
load_balance_mode = on
statement_level_load_balance = on

# Health check
health_check_period = 10
health_check_timeout = 5
health_check_max_retries = 3
```

<br />

With this setup, pgpool-II sends all writes to the primary and distributes reads across the two replicas
with equal weight. The health check ensures that unhealthy replicas are removed from the pool automatically.

<br />

##### **Backup strategies**
There are three main types of PostgreSQL backups, and a solid strategy uses at least two of them:

<br />

> * **Logical backups (pg_dump)**: Export the database as SQL statements. Great for portability, selective restoration, and small to medium databases. Slow for large databases.
> * **WAL archiving (PITR)**: Continuously archive Write-Ahead Log files. Allows Point-in-Time Recovery to any moment in time. Essential for production databases.
> * **Physical backups (pgBackRest/pg_basebackup)**: Copy the raw data files. Fast for large databases, supports incremental backups, and works with WAL archiving for PITR.

<br />

**Logical backups with pg_dump**

<br />

The simplest backup approach. Good for small databases or when you need to migrate between PostgreSQL
versions:

<br />

```bash
# Full database dump in custom format (compressed, supports parallel restore)
pg_dump -h postgresql-primary -U myapp -Fc -f /backups/myapp_$(date +%Y%m%d_%H%M%S).dump myapp_production

# Restore from a dump
pg_restore -h postgresql-primary -U myapp -d myapp_production --clean --if-exists /backups/myapp_20260318_030000.dump

# For very large databases, use parallel dump/restore
pg_dump -h postgresql-primary -U myapp -Fd -j 4 -f /backups/myapp_parallel/ myapp_production
pg_restore -h postgresql-primary -U myapp -d myapp_production -j 4 /backups/myapp_parallel/
```

<br />

**WAL archiving for Point-in-Time Recovery**

<br />

WAL archiving captures every change made to the database. Combined with a base backup, you can restore
to any point in time. This is how you recover from "oops, someone ran DELETE without a WHERE clause":

<br />

```bash
# postgresql.conf
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /wal_archive/%f && cp %p /wal_archive/%f'

# For S3-based archiving (recommended for production):
archive_command = 'aws s3 cp %p s3://my-wal-archive/%f --sse AES256'
```

<br />

To restore to a specific point in time:

<br />

```bash
# recovery.conf (or postgresql.conf in PG12+)
restore_command = 'aws s3 cp s3://my-wal-archive/%f %p'
recovery_target_time = '2026-03-18 14:30:00 UTC'
recovery_target_action = 'promote'
```

<br />

**Physical backups with pgBackRest**

<br />

pgBackRest is the gold standard for PostgreSQL physical backups. It supports full, incremental, and
differential backups, parallel backup and restore, compression, encryption, and S3-compatible storage:

<br />

```bash
# /etc/pgbackrest/pgbackrest.conf
[global]
repo1-type=s3
repo1-s3-endpoint=s3.amazonaws.com
repo1-s3-bucket=myapp-pg-backups
repo1-s3-region=us-east-1
repo1-s3-key=AKIAIOSFODNN7EXAMPLE
repo1-s3-key-secret=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
repo1-retention-full=4
repo1-retention-diff=14
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=your-encryption-passphrase

process-max=4
compress-type=zst
compress-level=6

[myapp]
pg1-path=/var/lib/postgresql/16/main
pg1-port=5432
```

<br />

```bash
# Create the stanza (one-time setup)
pgbackrest --stanza=myapp stanza-create

# Full backup
pgbackrest --stanza=myapp --type=full backup

# Incremental backup (only changes since last full or incremental)
pgbackrest --stanza=myapp --type=incr backup

# Differential backup (only changes since last full)
pgbackrest --stanza=myapp --type=diff backup

# List backups
pgbackrest --stanza=myapp info

# Restore to latest
pgbackrest --stanza=myapp --delta restore

# Restore to a specific point in time
pgbackrest --stanza=myapp --delta --type=time --target="2026-03-18 14:30:00" restore
```

<br />

**Scheduling backups with Kubernetes CronJobs**

<br />

```yaml
# backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pg-backup-full
  namespace: database
spec:
  schedule: "0 2 * * 0"  # Full backup every Sunday at 2am
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          containers:
            - name: backup
              image: pgbackrest/pgbackrest:latest
              command:
                - /bin/sh
                - -c
                - |
                  pgbackrest --stanza=myapp --type=full backup
                  RESULT=$?
                  if [ $RESULT -ne 0 ]; then
                    echo "Backup failed with exit code $RESULT"
                    # Send alert to Slack or PagerDuty
                    curl -X POST "$SLACK_WEBHOOK" \
                      -H 'Content-type: application/json' \
                      -d '{"text":"ALERT: PostgreSQL full backup failed!"}'
                  fi
                  exit $RESULT
              envFrom:
                - secretRef:
                    name: pgbackrest-credentials
                - secretRef:
                    name: slack-webhook
              volumeMounts:
                - name: pgbackrest-config
                  mountPath: /etc/pgbackrest
          volumes:
            - name: pgbackrest-config
              configMap:
                name: pgbackrest-config
          restartPolicy: Never
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pg-backup-incremental
  namespace: database
spec:
  schedule: "0 2 * * 1-6"  # Incremental backup every other day at 2am
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          containers:
            - name: backup
              image: pgbackrest/pgbackrest:latest
              command:
                - /bin/sh
                - -c
                - |
                  pgbackrest --stanza=myapp --type=incr backup
                  RESULT=$?
                  if [ $RESULT -ne 0 ]; then
                    curl -X POST "$SLACK_WEBHOOK" \
                      -H 'Content-type: application/json' \
                      -d '{"text":"ALERT: PostgreSQL incremental backup failed!"}'
                  fi
                  exit $RESULT
              envFrom:
                - secretRef:
                    name: pgbackrest-credentials
                - secretRef:
                    name: slack-webhook
              volumeMounts:
                - name: pgbackrest-config
                  mountPath: /etc/pgbackrest
          volumes:
            - name: pgbackrest-config
              configMap:
                name: pgbackrest-config
          restartPolicy: Never
```

<br />

##### **Backup validation and restore testing**
Here is a hard truth: a backup that has never been tested is not a backup. It is a hope. And hope is
not a strategy.

<br />

You need to regularly restore your backups to a temporary database and verify that the data is intact.
This should be automated, not something you do manually once a year when someone remembers.

<br />

**Automated restore testing with a CronJob**

<br />

```hcl
# restore-test-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pg-restore-test
  namespace: database
spec:
  schedule: "0 6 * * 3"  # Every Wednesday at 6am
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 3600  # Timeout after 1 hour
      template:
        spec:
          containers:
            - name: restore-test
              image: pgbackrest/pgbackrest:latest
              command:
                - /bin/sh
                - -c
                - |
                  set -e
                  echo "Starting restore test at $(date)"

                  # Initialize a temporary PostgreSQL data directory
                  export PGDATA=/tmp/pg_restore_test
                  mkdir -p $PGDATA

                  # Restore the latest backup to the temp directory
                  pgbackrest --stanza=myapp --delta \
                    --pg1-path=$PGDATA \
                    --target-action=promote \
                    restore

                  # Start PostgreSQL on a non-standard port
                  pg_ctl -D $PGDATA -o "-p 5433" -w start

                  # Run validation queries
                  USERS_COUNT=$(psql -p 5433 -d myapp_production -tAc "SELECT count(*) FROM users;")
                  POSTS_COUNT=$(psql -p 5433 -d myapp_production -tAc "SELECT count(*) FROM posts;")
                  LATEST_RECORD=$(psql -p 5433 -d myapp_production -tAc \
                    "SELECT max(inserted_at) FROM users;")

                  echo "Validation results:"
                  echo "  Users count: $USERS_COUNT"
                  echo "  Posts count: $POSTS_COUNT"
                  echo "  Latest record: $LATEST_RECORD"

                  # Verify data is recent (not older than 48 hours)
                  IS_RECENT=$(psql -p 5433 -d myapp_production -tAc \
                    "SELECT max(inserted_at) > now() - interval '48 hours' FROM users;")

                  # Stop the temp PostgreSQL
                  pg_ctl -D $PGDATA -w stop

                  # Clean up
                  rm -rf $PGDATA

                  if [ "$IS_RECENT" = "t" ]; then
                    echo "RESTORE TEST PASSED: Data is recent and valid"
                    curl -X POST "$SLACK_WEBHOOK" \
                      -H 'Content-type: application/json' \
                      -d "{\"text\":\"Restore test PASSED. Users: $USERS_COUNT, Posts: $POSTS_COUNT, Latest: $LATEST_RECORD\"}"
                  else
                    echo "RESTORE TEST FAILED: Data is stale or missing"
                    curl -X POST "$SLACK_WEBHOOK" \
                      -H 'Content-type: application/json' \
                      -d '{"text":"ALERT: Restore test FAILED. Data is stale or missing!"}'
                    exit 1
                  fi
              envFrom:
                - secretRef:
                    name: pgbackrest-credentials
                - secretRef:
                    name: slack-webhook
              resources:
                requests:
                  memory: "1Gi"
                  cpu: "500m"
                limits:
                  memory: "2Gi"
          restartPolicy: Never
```

<br />

The key things this restore test validates:

<br />

> * **The backup is restorable**: If pgBackRest cannot restore, you know immediately
> * **The data is recent**: If the latest record is older than 48 hours, something is wrong with your backup pipeline
> * **Core tables exist and have data**: A basic sanity check that the schema and data are intact
> * **Notification on success and failure**: You want to know both when it works and when it does not

<br />

You should also track restore test results as a metric and set up an SLO for it. Something like
"99% of weekly restore tests should succeed" is a good starting point.

<br />

##### **Zero-downtime migrations**
Database migrations are one of the most common causes of downtime. A migration that locks a table can
block all queries to that table, which means your application hangs until the migration completes.
In PostgreSQL, even seemingly innocent operations like adding a column with a default value used to
lock the entire table (though this was fixed in PostgreSQL 11).

<br />

Here are the safe migration patterns for Ecto:

<br />

**Safe: Adding a nullable column without a default**

<br />

```elixir
# This is always safe. It takes a brief ACCESS EXCLUSIVE lock but completes almost instantly.
defmodule MyApp.Repo.Migrations.AddAvatarToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :avatar_url, :string
    end
  end
end
```

<br />

**Safe: Adding a column with a default (PostgreSQL 11+)**

<br />

```elixir
# In PostgreSQL 11+, this is safe because the default is stored in the catalog,
# not written to every row. The lock is brief.
defmodule MyApp.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, default: "user"
    end
  end
end
```

<br />

**Dangerous: Adding an index on a large table**

<br />

A regular `CREATE INDEX` locks the table for writes. On a table with millions of rows, this can take
minutes. Use `CREATE INDEX CONCURRENTLY` instead:

<br />

```elixir
# WRONG: This locks the table for writes
defmodule MyApp.Repo.Migrations.AddIndexToPostsTitle do
  use Ecto.Migration

  def change do
    create index(:posts, [:title])
  end
end

# RIGHT: Use concurrently to avoid locking
defmodule MyApp.Repo.Migrations.AddIndexToPostsTitle do
  use Ecto.Migration

  # disable_ddl_transaction is required for concurrent index creation
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:posts, [:title], concurrently: true)
  end
end
```

<br />

**Safe pattern: Backfilling data in batches**

<br />

Never backfill data in a migration that runs inside a transaction. Instead, write a separate
migration or task that processes rows in batches:

<br />

```elixir
# Step 1: Add the new column (fast, safe)
defmodule MyApp.Repo.Migrations.AddSlugToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :slug, :string
    end
  end
end

# Step 2: Backfill in batches (separate migration or mix task)
defmodule MyApp.Repo.Migrations.BackfillPostSlugs do
  use Ecto.Migration

  import Ecto.Query

  @disable_ddl_transaction true
  @disable_migration_lock true
  @batch_size 1000

  def up do
    backfill_batch(0)
  end

  defp backfill_batch(last_id) do
    {count, _} =
      repo().query!("""
        UPDATE posts
        SET slug = lower(replace(title, ' ', '-'))
        WHERE id > $1
          AND id <= $1 + $2
          AND slug IS NULL
      """, [last_id, @batch_size])

    if count > 0 do
      # Small sleep to avoid overwhelming the database
      Process.sleep(100)
      backfill_batch(last_id + @batch_size)
    end
  end

  def down do
    # Nothing to undo, the column drop will handle cleanup
    :ok
  end
end

# Step 3: Add the NOT NULL constraint and index (after backfill is complete)
defmodule MyApp.Repo.Migrations.MakePostSlugRequired do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Add a check constraint first (non-blocking in PG12+)
    execute "ALTER TABLE posts ADD CONSTRAINT posts_slug_not_null CHECK (slug IS NOT NULL) NOT VALID"
    # Then validate it (takes a brief lock but does not block writes for long)
    execute "ALTER TABLE posts VALIDATE CONSTRAINT posts_slug_not_null"
    # Create unique index concurrently
    create unique_index(:posts, [:slug], concurrently: true)
  end

  def down do
    drop_if_exists index(:posts, [:slug])
    execute "ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_slug_not_null"
  end
end
```

<br />

**Migration safety checklist**

<br />

Before running any migration in production:

<br />

> * **Check the lock type**: Will the migration take an ACCESS EXCLUSIVE lock? For how long?
> * **Test on a copy of production data**: Never test migrations on an empty database. A migration that runs instantly on 100 rows might lock the table for minutes on 10 million rows.
> * **Use statement_timeout**: Set a statement timeout so that if a migration takes too long, it fails instead of locking the table indefinitely.
> * **Run during low traffic**: Even "safe" migrations are safer during off-peak hours.
> * **Have a rollback plan**: Know how to undo the migration before you run it.

<br />

```yaml
# Set a statement timeout for migrations to prevent long locks
# config/runtime.exs
config :myapp, MyApp.Repo,
  migration_lock: nil,
  migration_default_prefix: "public",
  after_connect: {Postgrex, :query!, ["SET statement_timeout TO '5s'", []]}
```

<br />

##### **Database monitoring**
You cannot fix what you cannot see. PostgreSQL comes with excellent built-in monitoring views, and
combining them with Prometheus gives you a comprehensive picture of your database health.

<br />

**pg_stat_statements: finding slow queries**

<br />

`pg_stat_statements` is the most important PostgreSQL extension for performance monitoring. It tracks
execution statistics for every query that runs on the server:

<br />

```dockerfile
# Enable the extension (once)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

# Top 10 queries by total execution time
SELECT
  queryid,
  calls,
  round(total_exec_time::numeric, 2) AS total_time_ms,
  round(mean_exec_time::numeric, 2) AS mean_time_ms,
  round(max_exec_time::numeric, 2) AS max_time_ms,
  rows,
  round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS percent_total,
  left(query, 100) AS query_preview
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

# Top 10 queries by average execution time (slow queries)
SELECT
  queryid,
  calls,
  round(mean_exec_time::numeric, 2) AS mean_time_ms,
  round(max_exec_time::numeric, 2) AS max_time_ms,
  rows / NULLIF(calls, 0) AS avg_rows,
  left(query, 100) AS query_preview
FROM pg_stat_statements
WHERE calls > 10  -- Filter out rarely executed queries
ORDER BY mean_exec_time DESC
LIMIT 10;

# Queries with the most I/O
SELECT
  queryid,
  calls,
  shared_blks_read + shared_blks_written AS total_blocks,
  round(mean_exec_time::numeric, 2) AS mean_time_ms,
  left(query, 100) AS query_preview
FROM pg_stat_statements
ORDER BY (shared_blks_read + shared_blks_written) DESC
LIMIT 10;
```

<br />

**Connection monitoring**

<br />

Knowing how your connections are being used is critical for sizing your pool correctly and detecting
connection leaks:

<br />

```dockerfile
# Current connection count by state
SELECT
  state,
  count(*) AS connections,
  max(now() - state_change) AS longest_in_state
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY state
ORDER BY connections DESC;

# Connections by application name (useful for identifying which service uses the most)
SELECT
  application_name,
  state,
  count(*) AS connections
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY application_name, state
ORDER BY connections DESC;

# Find long-running queries (potential problems)
SELECT
  pid,
  now() - query_start AS duration,
  state,
  left(query, 80) AS query_preview,
  wait_event_type,
  wait_event
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '30 seconds'
ORDER BY duration DESC;

# Find blocked queries (waiting for locks)
SELECT
  blocked_locks.pid AS blocked_pid,
  blocked_activity.usename AS blocked_user,
  blocking_locks.pid AS blocking_pid,
  blocking_activity.usename AS blocking_user,
  left(blocked_activity.query, 60) AS blocked_query,
  left(blocking_activity.query, 60) AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity
  ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
  AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
  AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
  AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
  AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity
  ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

<br />

**Replication lag monitoring**

<br />

If you are using read replicas, monitoring replication lag is essential. A replica that is too far
behind can serve stale data:

<br />

```sql
# On the primary: check replication status
SELECT
  client_addr,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
  pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replay_lag_pretty
FROM pg_stat_replication;

# On the replica: check how far behind it is
SELECT
  now() - pg_last_xact_replay_timestamp() AS replication_delay,
  pg_is_in_recovery() AS is_replica,
  pg_last_wal_receive_lsn() AS last_received,
  pg_last_wal_replay_lsn() AS last_replayed;
```

<br />

**Prometheus exporter for PostgreSQL**

<br />

The `postgres_exporter` from Prometheus Community exposes all these metrics in Prometheus format.
Deploy it alongside your PostgreSQL instances:

<br />

```dockerfile
# postgres-exporter.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-exporter
  template:
    metadata:
      labels:
        app: postgres-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9187"
    spec:
      containers:
        - name: exporter
          image: prometheuscommunity/postgres-exporter:latest
          ports:
            - containerPort: 9187
          env:
            - name: DATA_SOURCE_URI
              value: "postgresql-primary.database.svc:5432/myapp_production?sslmode=disable"
            - name: DATA_SOURCE_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-exporter-credentials
                  key: username
            - name: DATA_SOURCE_PASS
              valueFrom:
                secretKeyRef:
                  name: postgres-exporter-credentials
                  key: password
            - name: PG_EXPORTER_EXTEND_QUERY_PATH
              value: /etc/postgres-exporter/queries.yaml
          volumeMounts:
            - name: custom-queries
              mountPath: /etc/postgres-exporter
      volumes:
        - name: custom-queries
          configMap:
            name: postgres-exporter-queries
---
# Custom queries for the exporter
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-exporter-queries
  namespace: database
data:
  queries.yaml: |
    pg_slow_queries:
      query: |
        SELECT count(*) AS count
        FROM pg_stat_activity
        WHERE state = 'active'
          AND now() - query_start > interval '30 seconds'
      metrics:
        - count:
            usage: "GAUGE"
            description: "Number of queries running longer than 30 seconds"

    pg_connection_count:
      query: |
        SELECT state, count(*) AS count
        FROM pg_stat_activity
        GROUP BY state
      metrics:
        - count:
            usage: "GAUGE"
            description: "Number of connections by state"
      master: true

    pg_database_size:
      query: |
        SELECT pg_database.datname,
               pg_database_size(pg_database.datname) AS size_bytes
        FROM pg_database
        WHERE datistemplate = false
      metrics:
        - datname:
            usage: "LABEL"
            description: "Database name"
        - size_bytes:
            usage: "GAUGE"
            description: "Database size in bytes"
```

<br />

With this setup, you can create Prometheus alerts for:

<br />

> * **High replication lag**: Alert when a replica is more than 30 seconds behind
> * **Connection exhaustion**: Alert when connections are above 80% of `max_connections`
> * **Slow queries**: Alert when there are queries running longer than 60 seconds
> * **Database size growth**: Alert when the database is growing faster than expected

<br />

##### **CloudNativePG operator**
CloudNativePG (CNPG) is a Kubernetes operator that manages the full lifecycle of PostgreSQL clusters.
It handles provisioning, scaling, failover, backups, and monitoring. If you are running PostgreSQL in
Kubernetes, this is the operator you should be using.

<br />

**Installation**

<br />

```bash
# Install with Helm
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

helm install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system \
  --create-namespace
```

<br />

**Creating a PostgreSQL cluster**

<br />

Here is a production-ready Cluster CRD:

<br />

```yaml
# postgresql-cluster.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: myapp-db
  namespace: database
spec:
  instances: 3  # 1 primary + 2 replicas
  imageName: ghcr.io/cloudnative-pg/postgresql:16.2

  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "512MB"
      effective_cache_size: "1536MB"
      maintenance_work_mem: "128MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
      random_page_cost: "1.1"  # SSD optimized
      effective_io_concurrency: "200"
      work_mem: "4MB"
      min_wal_size: "1GB"
      max_wal_size: "4GB"
      max_worker_processes: "4"
      max_parallel_workers_per_gather: "2"
      max_parallel_workers: "4"
      max_parallel_maintenance_workers: "2"
      # Enable pg_stat_statements
      shared_preload_libraries: "pg_stat_statements"
      pg_stat_statements.track: "all"
      pg_stat_statements.max: "10000"
    pg_hba:
      - "host all all 10.0.0.0/8 scram-sha-256"
      - "host replication streaming_replica 10.0.0.0/8 scram-sha-256"

  bootstrap:
    initdb:
      database: myapp_production
      owner: myapp
      secret:
        name: myapp-db-credentials

  storage:
    size: 50Gi
    storageClass: longhorn  # Or your preferred storage class

  resources:
    requests:
      memory: "2Gi"
      cpu: "1"
    limits:
      memory: "4Gi"

  # Enable monitoring
  monitoring:
    enablePodMonitor: true
    customQueriesConfigMap:
      - name: cnpg-default-monitoring
        key: queries

  # Anti-affinity to spread instances across nodes
  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname

  # Backup configuration to S3
  backup:
    barmanObjectStore:
      destinationPath: "s3://myapp-pg-backups/cnpg/"
      s3Credentials:
        accessKeyId:
          name: aws-s3-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: aws-s3-credentials
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
        maxParallel: 4
      data:
        compression: gzip
        immediateCheckpoint: true
    retentionPolicy: "30d"
```

<br />

This creates a 3-instance PostgreSQL cluster with:

<br />

> * **Automatic replication**: CNPG handles streaming replication between primary and replicas
> * **Tuned parameters**: Optimized PostgreSQL configuration for a typical web workload
> * **Pod anti-affinity**: Instances are spread across different Kubernetes nodes for resilience
> * **Monitoring**: Pod monitors for Prometheus integration
> * **WAL archiving to S3**: Continuous backup of WAL files for PITR

<br />

**Scheduled backups**

<br />

```yaml
# scheduled-backup.yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: myapp-db-daily-backup
  namespace: database
spec:
  schedule: "0 2 * * *"  # Every day at 2am
  backupOwnerReference: self
  cluster:
    name: myapp-db
  immediate: false
  target: prefer-standby  # Take backup from a replica to avoid impacting the primary
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: myapp-db-weekly-full
  namespace: database
spec:
  schedule: "0 3 * * 0"  # Every Sunday at 3am
  backupOwnerReference: self
  cluster:
    name: myapp-db
  immediate: false
  target: prefer-standby
```

<br />

**Connecting your application**

<br />

CNPG creates Kubernetes services for read-write and read-only access:

<br />

```yaml
# The operator creates these services automatically:
# myapp-db-rw   -> points to the primary (read-write)
# myapp-db-ro   -> points to replicas (read-only, load balanced)
# myapp-db-r    -> points to any instance (for reads that can tolerate lag)

# In your Ecto configuration:
config :myapp, MyApp.Repo,
  hostname: "myapp-db-rw.database.svc.cluster.local",
  database: "myapp_production",
  username: "myapp",
  password: System.get_env("DB_PASSWORD"),
  pool_size: 16

config :myapp, MyApp.ReadRepo,
  hostname: "myapp-db-ro.database.svc.cluster.local",
  database: "myapp_production",
  username: "myapp",
  password: System.get_env("DB_PASSWORD"),
  pool_size: 20
```

<br />

**Monitoring the CNPG cluster**

<br />

CNPG exposes a rich set of metrics. Here are some useful PromQL queries:

<br />

```bash
# Replication lag in seconds
cnpg_pg_replication_lag{cluster="myapp-db"}

# Number of connections by state
cnpg_pg_stat_activity_count{cluster="myapp-db"}

# Transaction rate
rate(cnpg_pg_stat_database_xact_commit{cluster="myapp-db"}[5m])
  + rate(cnpg_pg_stat_database_xact_rollback{cluster="myapp-db"}[5m])

# Cache hit ratio (should be > 99%)
cnpg_pg_stat_database_blks_hit{cluster="myapp-db"}
  / (cnpg_pg_stat_database_blks_hit{cluster="myapp-db"}
     + cnpg_pg_stat_database_blks_read{cluster="myapp-db"}) * 100

# WAL generation rate
rate(cnpg_pg_stat_archiver_archived_count{cluster="myapp-db"}[5m])

# Database size
cnpg_pg_database_size_bytes{cluster="myapp-db", datname="myapp_production"}
```

<br />

##### **Failover and high availability**
The whole point of running multiple instances is that when the primary fails, a replica takes over
automatically. This is where CloudNativePG really shines.

<br />

**Automatic failover with CloudNativePG**

<br />

CNPG monitors the health of all instances continuously. When it detects that the primary is
unhealthy, it:

<br />

> 1. **Detects the failure**: The operator checks instance health via health probes and replication status
> 2. **Selects the best replica**: Chooses the replica with the least replication lag
> 3. **Promotes the replica**: Runs `pg_promote()` to make the replica the new primary
> 4. **Updates the services**: The `myapp-db-rw` service now points to the new primary
> 5. **Reconfigures remaining replicas**: They start replicating from the new primary
> 6. **Fences the old primary**: Prevents the old primary from accepting writes (split-brain prevention)

<br />

This entire process typically completes in 10-30 seconds. Your application might see a brief
connection error during the switchover, so make sure your Ecto configuration has proper retry logic:

<br />

```yaml
# config/runtime.exs
config :myapp, MyApp.Repo,
  hostname: "myapp-db-rw.database.svc.cluster.local",
  database: "myapp_production",
  pool_size: 16,
  # Ecto/DBConnection will retry failed checkouts
  queue_target: 5000,
  queue_interval: 5000,
  # Configure the socket options for faster failure detection
  socket_options: [
    keepalive: true,
    # Send keepalive probes after 10 seconds of idle
    # (platform-dependent, works on Linux)
  ],
  parameters: [
    application_name: "tr-web"
  ]
```

<br />

**Testing failover**

<br />

You should regularly test that failover works. With CNPG, you can trigger a controlled switchover:

<br />

```bash
# Trigger a switchover (controlled failover)
kubectl cnpg promote myapp-db myapp-db-2 --namespace database

# Or use the plugin to trigger a restart of the primary (simulates a crash)
kubectl cnpg restart myapp-db myapp-db-1 --namespace database

# Check the cluster status during and after failover
kubectl cnpg status myapp-db --namespace database
```

<br />

The output shows you which instance is the primary, replication lag, and the overall cluster health:

<br />

```hcl
# Example output of kubectl cnpg status myapp-db
Cluster Summary
  Name:               myapp-db
  Namespace:          database
  PostgreSQL Image:   ghcr.io/cloudnative-pg/postgresql:16.2
  Primary instance:   myapp-db-2    # This was promoted
  Status:             Cluster in healthy state
  Instances:          3

Certificates Status
  ...

Instances Status
  Name        Role       Status  Node          Timeline  LSN
  ----        ----       ------  ----          --------  ---
  myapp-db-1  Replica    OK      worker-01     2         0/5000060
  myapp-db-2  Primary    OK      worker-02     2         0/5000060
  myapp-db-3  Replica    OK      worker-03     2         0/5000060
```

<br />

**Patroni as an alternative**

<br />

If you are not using CloudNativePG (maybe you are running PostgreSQL on VMs or using a different
Kubernetes approach), Patroni is the go-to solution for PostgreSQL high availability. It uses a
distributed consensus store (etcd, Consul, or ZooKeeper) to manage leader election and failover:

<br />

```yaml
# patroni.yml
scope: myapp-cluster
name: postgresql-node-1

restapi:
  listen: 0.0.0.0:8008
  connect_address: postgresql-node-1:8008

etcd:
  hosts: etcd-1:2379,etcd-2:2379,etcd-3:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576  # 1MB
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 200
        shared_buffers: 512MB
        wal_level: replica
        hot_standby: on
        max_wal_senders: 10
        max_replication_slots: 10

  initdb:
    - encoding: UTF8
    - data-checksums

postgresql:
  listen: 0.0.0.0:5432
  connect_address: postgresql-node-1:5432
  data_dir: /var/lib/postgresql/16/main
  authentication:
    superuser:
      username: postgres
      password: secret
    replication:
      username: replicator
      password: secret
```

<br />

The key difference is that CNPG is Kubernetes-native (it uses the Kubernetes API for coordination)
while Patroni requires a separate consensus store. If you are already running in Kubernetes, CNPG is
the simpler choice.

<br />

**Split-brain prevention**

<br />

Split-brain is the worst thing that can happen in a database cluster: two instances both think they
are the primary and accept writes independently. When they reconnect, the data is inconsistent and
potentially unrecoverable.

<br />

Both CNPG and Patroni have built-in split-brain prevention:

<br />

> * **CNPG** uses fencing. When a failover happens, the old primary is fenced (its data directory is marked as invalid) so even if it comes back, it cannot serve writes. It must be reinitialized as a replica.
> * **Patroni** uses the consensus store (etcd) as the source of truth. Only the node that holds the leader key in etcd can be the primary. If a node loses contact with etcd, it demotes itself.

<br />

Additional safeguards you should have:

<br />

> * **Network policies**: Ensure that only the operator or Patroni can modify the service endpoints
> * **Monitoring**: Alert on any instance that reports itself as primary when it should not be
> * **pg_rewind**: Enable `pg_rewind` so that a former primary can be quickly resynchronized as a replica without a full base backup

<br />

```yaml
# PrometheusRule for split-brain detection
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: pg-split-brain-alert
  namespace: database
spec:
  groups:
    - name: postgresql.split-brain
      rules:
        - alert: PostgreSQLSplitBrain
          expr: |
            count(cnpg_pg_replication_is_replica{cluster="myapp-db"} == 0) > 1
          for: 30s
          labels:
            severity: critical
          annotations:
            summary: "CRITICAL: Multiple primary instances detected in myapp-db cluster"
            description: "There are {{ $value }} instances reporting as primary. This is a split-brain situation that requires immediate attention."
```

<br />

##### **Closing notes**
Database reliability is not a single thing you set up and forget. It is a combination of patterns
that work together: connection pooling keeps your connections healthy, replicas distribute the read
load, backups protect your data, safe migrations prevent self-inflicted outages, monitoring tells you
when something is wrong, and automated failover keeps things running when hardware fails.

<br />

The good news is that tools like CloudNativePG make most of this much easier than it used to be.
Instead of hand-configuring replication, failover scripts, and backup cron jobs, you declare your
desired state in a Kubernetes manifest and the operator handles the rest. That is a massive
improvement over the "artisanal PostgreSQL" approach many of us grew up with.

<br />

Start with the basics: get PgBouncer in front of your database, set up automated backups with restore
testing, and add pg_stat_statements for query monitoring. Then when you are ready, move to CloudNativePG
for a fully managed cluster with automated failover. Each layer builds on the previous one.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Confiabilidad de Bases de Datos",
  author: "Gabriel Garrido",
  description: "Vamos a explorar patrones de confiabilidad de bases de datos para PostgreSQL en Kubernetes, desde connection pooling y estrategias de backup hasta migraciones sin downtime, el operador CloudNativePG, y automatización de failover...",
  tags: ~w(sre database postgresql kubernetes reliability),
  published: true,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En los artículos anteriores cubrimos [SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[gestión de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observabilidad](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[planificación de capacidad](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[gestión de secretos](/blog/sre-secrets-management-in-kubernetes),
[optimización de costos](/blog/sre-cost-optimization-in-the-cloud), y
[gestión de dependencias](/blog/sre-dependency-management-and-graceful-degradation). Cubrimos un montón
de terreno, pero hay una pieza crítica que todavía no tocamos: la base de datos.

<br />

Tu base de datos es probablemente el punto de falla único más difícil de manejar en todo tu stack.
Podés escalar servicios stateless horizontalmente, podés reiniciar pods crasheados, incluso podés
perder un nodo entero y recuperarte en segundos. Pero si tu base de datos se cae, todo se detiene.
Si perdés datos, pueden estar perdidos para siempre. Y si tus migraciones lockean una tabla durante
cinco minutos en hora pico, tus usuarios se van a dar cuenta.

<br />

En este artículo vamos a recorrer los patrones y herramientas que hacen que PostgreSQL sea confiable
en Kubernetes. Vamos a cubrir connection pooling, read replicas, estrategias de backup, migraciones
sin downtime, monitoreo, el operador CloudNativePG, y automatización de failover. Estos son los
bloques fundamentales que te permiten dormir tranquilo incluso cuando tu app maneja tráfico y datos
reales.

<br />

Vamos al tema.

<br />

##### **Connection pooling con PgBouncer**
PostgreSQL crea un nuevo proceso por cada conexión. Eso funciona bien cuando tenés 10 conexiones,
pero en Kubernetes donde podrías tener decenas de pods, cada uno corriendo múltiples procesos, podés
agotar fácilmente el límite de conexiones del servidor. El `max_connections` por defecto en PostgreSQL
es 100, y cada conexión consume alrededor de 5-10MB de RAM.

<br />

PgBouncer se sienta entre tu aplicación y PostgreSQL, multiplexando muchas conexiones de clientes en
un número menor de conexiones al servidor. Es liviano (un solo proceso de PgBouncer puede manejar
miles de conexiones de clientes) y está probado en producción a escala masiva.

<br />

Acá hay una configuración básica de PgBouncer:

<br />

```bash
# pgbouncer.ini
[databases]
myapp = host=postgresql-primary port=5432 dbname=myapp_production

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Modo de pool: transaction es el más común para apps web
pool_mode = transaction

# Tamaño del pool
default_pool_size = 20
min_pool_size = 5
max_client_conn = 1000
max_db_connections = 50

# Timeouts
server_idle_timeout = 300
client_idle_timeout = 0
query_timeout = 30

# Logging
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60
```

<br />

El setting `pool_mode` es crucial:

<br />

> * **transaction** libera la conexión al servidor de vuelta al pool después de que cada transacción se completa. Esto es lo que querés para la mayoría de las aplicaciones web porque maximiza la reutilización de conexiones. Sin embargo, no soporta features a nivel de sesión como prepared statements, advisory locks, o LISTEN/NOTIFY.
> * **session** mantiene la conexión al servidor asignada durante toda la sesión del cliente. Esto soporta todas las features de PostgreSQL pero provee menos multiplexación de conexiones. Usá esto si tu app depende de features a nivel de sesión.
> * **statement** libera la conexión después de cada statement. Provee la mejor multiplexación pero solo funciona para queries simples de solo lectura sin transacciones de múltiples statements.

<br />

Para Ecto (la capa de base de datos en Phoenix/Elixir), el modo transaction funciona perfectamente
porque Ecto envuelve cada request en una transacción explícita o usa queries simples.

<br />

**Corriendo PgBouncer como sidecar en Kubernetes**

<br />

El patrón sidecar pone un contenedor de PgBouncer en el mismo pod que tu aplicación. Esto significa
que cada pod de la aplicación tiene su propia instancia de PgBouncer, y la conexión a PgBouncer es
por localhost (cero latencia de red). Acá está el spec del pod:

<br />

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tr-web
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: tr-web
  template:
    metadata:
      labels:
        app: tr-web
    spec:
      containers:
        - name: app
          image: kainlite/tr:latest
          ports:
            - containerPort: 4000
          env:
            # Apuntar la app a PgBouncer en localhost en vez de directamente a PostgreSQL
            - name: DATABASE_URL
              value: "ecto://myapp:password@localhost:6432/myapp_production"
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"

        - name: pgbouncer
          image: bitnami/pgbouncer:latest
          ports:
            - containerPort: 6432
          env:
            - name: POSTGRESQL_HOST
              value: "postgresql-primary.database.svc.cluster.local"
            - name: POSTGRESQL_PORT
              value: "5432"
            - name: PGBOUNCER_DATABASE
              value: "myapp_production"
            - name: PGBOUNCER_POOL_MODE
              value: "transaction"
            - name: PGBOUNCER_DEFAULT_POOL_SIZE
              value: "20"
            - name: PGBOUNCER_MAX_CLIENT_CONN
              value: "500"
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
```

<br />

**Cómo dimensionar tu pool de conexiones**

<br />

Un error común es poner el pool demasiado grande. Más conexiones no significa mejor rendimiento.
De hecho, demasiadas conexiones causan contención en locks y shared buffers, lo que perjudica el
throughput.

<br />

Una buena fórmula inicial:

<br />

```bash
# Total de conexiones al servidor = cantidad de cores de CPU del servidor de DB * 2 + effective_spindle_count
# Para un servidor de 4 cores con SSD:
# max_useful_connections = 4 * 2 + 1 = 9 (pero redondeá a ~20 para tener margen)

# Después distribuí entre tus pods de aplicación:
# per_pod_pool_size = total_server_connections / number_of_pods
# Para 3 pods con 50 conexiones máximas a la DB:
# per_pod_pool_size = 50 / 3 ≈ 16

# En tu config de repo de Ecto:
config :myapp, MyApp.Repo,
  pool_size: 16,
  queue_target: 500,    # Tiempo objetivo de cola en ms
  queue_interval: 1000  # Cada cuánto verificar la salud de la cola
```

<br />

Monitoreá el uso real de conexiones con `SHOW POOLS;` en PgBouncer o con la vista `pg_stat_activity`
de PostgreSQL. Ajustá basándote en datos reales, no en suposiciones.

<br />

##### **Read replicas y balanceo de carga**
Para workloads pesados en lectura (que es lo que son la mayoría de las aplicaciones web), podés
descargar queries de lectura a réplicas mientras mantenés las escrituras en el primario. La
replicación por streaming de PostgreSQL hace que esto sea bastante directo.

<br />

**Configurando replicación por streaming**

<br />

En el primario, habilitá la replicación en `postgresql.conf`:

<br />

```bash
# postgresql.conf en el primario
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on

# Archivar WAL para PITR (más sobre esto en la sección de backups)
archive_mode = on
archive_command = 'pgbackrest --stanza=myapp archive-push %p'
```

<br />

En la réplica, configurá la recuperación:

<br />

```bash
# postgresql.conf en la réplica
primary_conninfo = 'host=postgresql-primary port=5432 user=replicator password=secret'
primary_slot_name = 'replica_1'
hot_standby = on
hot_standby_feedback = on
```

<br />

**Read/write splitting en Ecto**

<br />

Ecto soporta múltiples repositorios, así que podés definir un repo de solo lectura que apunte a
las réplicas:

<br />

```yaml
# lib/myapp/repo.ex
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :myapp,
    adapter: Ecto.Adapters.Postgres
end

# lib/myapp/read_repo.ex
defmodule MyApp.ReadRepo do
  use Ecto.Repo,
    otp_app: :myapp,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
```

<br />

```yaml
# config/runtime.exs
config :myapp, MyApp.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: 16

config :myapp, MyApp.ReadRepo,
  url: System.get_env("DATABASE_REPLICA_URL"),
  pool_size: 20  # Las réplicas pueden manejar más conexiones ya que solo sirven lecturas
```

<br />

Después en el código de tu aplicación, usá el repo apropiado:

<br />

```yaml
# Operaciones de escritura van al primario
MyApp.Repo.insert(%User{name: "Gabriel"})
MyApp.Repo.update(changeset)
MyApp.Repo.delete(user)

# Operaciones de lectura van a las réplicas
MyApp.ReadRepo.all(User)
MyApp.ReadRepo.get(User, 1)

# Para operaciones que necesitan leer sus propias escrituras (ej: después de un insert),
# usá el repo primario para evitar problemas de replication lag
def create_and_return_user(attrs) do
  {:ok, user} = MyApp.Repo.insert(%User{} |> User.changeset(attrs))
  # Leer del primario, no de la réplica, para evitar datos obsoletos
  MyApp.Repo.get!(User, user.id)
end
```

<br />

**Balanceo de carga entre réplicas con pgpool-II**

<br />

Si tenés múltiples réplicas, pgpool-II puede distribuir queries de lectura entre ellas:

<br />

```bash
# pgpool.conf
backend_hostname0 = 'postgresql-primary'
backend_port0 = 5432
backend_weight0 = 0
backend_flag0 = 'ALWAYS_PRIMARY'

backend_hostname1 = 'postgresql-replica-1'
backend_port1 = 5432
backend_weight1 = 1

backend_hostname2 = 'postgresql-replica-2'
backend_port2 = 5432
backend_weight2 = 1

# Balanceo de carga
load_balance_mode = on
statement_level_load_balance = on

# Health check
health_check_period = 10
health_check_timeout = 5
health_check_max_retries = 3
```

<br />

Con este setup, pgpool-II envía todas las escrituras al primario y distribuye las lecturas entre las
dos réplicas con peso igual. El health check asegura que las réplicas no saludables se remuevan del
pool automáticamente.

<br />

##### **Estrategias de backup**
Hay tres tipos principales de backups de PostgreSQL, y una estrategia sólida usa al menos dos de ellos:

<br />

> * **Backups lógicos (pg_dump)**: Exportan la base de datos como statements SQL. Geniales para portabilidad, restauración selectiva, y bases de datos chicas a medianas. Lentos para bases de datos grandes.
> * **Archivado de WAL (PITR)**: Archiva continuamente archivos de Write-Ahead Log. Permite Point-in-Time Recovery a cualquier momento en el tiempo. Esencial para bases de datos de producción.
> * **Backups físicos (pgBackRest/pg_basebackup)**: Copian los archivos de datos crudos. Rápidos para bases de datos grandes, soportan backups incrementales, y funcionan con archivado de WAL para PITR.

<br />

**Backups lógicos con pg_dump**

<br />

El enfoque de backup más simple. Bueno para bases de datos chicas o cuando necesitás migrar entre
versiones de PostgreSQL:

<br />

```bash
# Dump completo de la base en formato custom (comprimido, soporta restore paralelo)
pg_dump -h postgresql-primary -U myapp -Fc -f /backups/myapp_$(date +%Y%m%d_%H%M%S).dump myapp_production

# Restaurar desde un dump
pg_restore -h postgresql-primary -U myapp -d myapp_production --clean --if-exists /backups/myapp_20260318_030000.dump

# Para bases de datos muy grandes, usá dump/restore paralelo
pg_dump -h postgresql-primary -U myapp -Fd -j 4 -f /backups/myapp_parallel/ myapp_production
pg_restore -h postgresql-primary -U myapp -d myapp_production -j 4 /backups/myapp_parallel/
```

<br />

**Archivado de WAL para Point-in-Time Recovery**

<br />

El archivado de WAL captura cada cambio hecho a la base de datos. Combinado con un backup base,
podés restaurar a cualquier punto en el tiempo. Así es como te recuperás de "ups, alguien ejecutó
DELETE sin WHERE":

<br />

```bash
# postgresql.conf
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /wal_archive/%f && cp %p /wal_archive/%f'

# Para archivado basado en S3 (recomendado para producción):
archive_command = 'aws s3 cp %p s3://my-wal-archive/%f --sse AES256'
```

<br />

Para restaurar a un punto específico en el tiempo:

<br />

```bash
# recovery.conf (o postgresql.conf en PG12+)
restore_command = 'aws s3 cp s3://my-wal-archive/%f %p'
recovery_target_time = '2026-03-18 14:30:00 UTC'
recovery_target_action = 'promote'
```

<br />

**Backups físicos con pgBackRest**

<br />

pgBackRest es el estándar de oro para backups físicos de PostgreSQL. Soporta backups completos,
incrementales y diferenciales, backup y restore paralelos, compresión, encriptación, y
almacenamiento compatible con S3:

<br />

```bash
# /etc/pgbackrest/pgbackrest.conf
[global]
repo1-type=s3
repo1-s3-endpoint=s3.amazonaws.com
repo1-s3-bucket=myapp-pg-backups
repo1-s3-region=us-east-1
repo1-s3-key=AKIAIOSFODNN7EXAMPLE
repo1-s3-key-secret=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
repo1-retention-full=4
repo1-retention-diff=14
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=your-encryption-passphrase

process-max=4
compress-type=zst
compress-level=6

[myapp]
pg1-path=/var/lib/postgresql/16/main
pg1-port=5432
```

<br />

```bash
# Crear el stanza (setup inicial, una sola vez)
pgbackrest --stanza=myapp stanza-create

# Backup completo
pgbackrest --stanza=myapp --type=full backup

# Backup incremental (solo cambios desde el último full o incremental)
pgbackrest --stanza=myapp --type=incr backup

# Backup diferencial (solo cambios desde el último full)
pgbackrest --stanza=myapp --type=diff backup

# Listar backups
pgbackrest --stanza=myapp info

# Restaurar al último
pgbackrest --stanza=myapp --delta restore

# Restaurar a un punto específico en el tiempo
pgbackrest --stanza=myapp --delta --type=time --target="2026-03-18 14:30:00" restore
```

<br />

**Programando backups con Kubernetes CronJobs**

<br />

```yaml
# backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pg-backup-full
  namespace: database
spec:
  schedule: "0 2 * * 0"  # Backup completo todos los domingos a las 2am
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          containers:
            - name: backup
              image: pgbackrest/pgbackrest:latest
              command:
                - /bin/sh
                - -c
                - |
                  pgbackrest --stanza=myapp --type=full backup
                  RESULT=$?
                  if [ $RESULT -ne 0 ]; then
                    echo "Backup falló con código de salida $RESULT"
                    # Enviar alerta a Slack o PagerDuty
                    curl -X POST "$SLACK_WEBHOOK" \
                      -H 'Content-type: application/json' \
                      -d '{"text":"ALERTA: ¡Backup completo de PostgreSQL falló!"}'
                  fi
                  exit $RESULT
              envFrom:
                - secretRef:
                    name: pgbackrest-credentials
                - secretRef:
                    name: slack-webhook
              volumeMounts:
                - name: pgbackrest-config
                  mountPath: /etc/pgbackrest
          volumes:
            - name: pgbackrest-config
              configMap:
                name: pgbackrest-config
          restartPolicy: Never
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pg-backup-incremental
  namespace: database
spec:
  schedule: "0 2 * * 1-6"  # Backup incremental todos los demás días a las 2am
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          containers:
            - name: backup
              image: pgbackrest/pgbackrest:latest
              command:
                - /bin/sh
                - -c
                - |
                  pgbackrest --stanza=myapp --type=incr backup
                  RESULT=$?
                  if [ $RESULT -ne 0 ]; then
                    curl -X POST "$SLACK_WEBHOOK" \
                      -H 'Content-type: application/json' \
                      -d '{"text":"ALERTA: ¡Backup incremental de PostgreSQL falló!"}'
                  fi
                  exit $RESULT
              envFrom:
                - secretRef:
                    name: pgbackrest-credentials
                - secretRef:
                    name: slack-webhook
              volumeMounts:
                - name: pgbackrest-config
                  mountPath: /etc/pgbackrest
          volumes:
            - name: pgbackrest-config
              configMap:
                name: pgbackrest-config
          restartPolicy: Never
```

<br />

##### **Validación de backups y pruebas de restauración**
Acá va una verdad dura: un backup que nunca fue probado no es un backup. Es una esperanza. Y la
esperanza no es una estrategia.

<br />

Necesitás restaurar tus backups regularmente a una base de datos temporal y verificar que los datos
estén intactos. Esto debería estar automatizado, no ser algo que hacés manualmente una vez al año
cuando alguien se acuerda.

<br />

**Pruebas automatizadas de restauración con un CronJob**

<br />

```yaml
# restore-test-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pg-restore-test
  namespace: database
spec:
  schedule: "0 6 * * 3"  # Cada miércoles a las 6am
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 3600  # Timeout después de 1 hora
      template:
        spec:
          containers:
            - name: restore-test
              image: pgbackrest/pgbackrest:latest
              command:
                - /bin/sh
                - -c
                - |
                  set -e
                  echo "Iniciando prueba de restauración a $(date)"

                  # Inicializar un directorio temporal de datos de PostgreSQL
                  export PGDATA=/tmp/pg_restore_test
                  mkdir -p $PGDATA

                  # Restaurar el último backup al directorio temporal
                  pgbackrest --stanza=myapp --delta \
                    --pg1-path=$PGDATA \
                    --target-action=promote \
                    restore

                  # Arrancar PostgreSQL en un puerto no estándar
                  pg_ctl -D $PGDATA -o "-p 5433" -w start

                  # Ejecutar queries de validación
                  USERS_COUNT=$(psql -p 5433 -d myapp_production -tAc "SELECT count(*) FROM users;")
                  POSTS_COUNT=$(psql -p 5433 -d myapp_production -tAc "SELECT count(*) FROM posts;")
                  LATEST_RECORD=$(psql -p 5433 -d myapp_production -tAc \
                    "SELECT max(inserted_at) FROM users;")

                  echo "Resultados de validación:"
                  echo "  Cantidad de usuarios: $USERS_COUNT"
                  echo "  Cantidad de posts: $POSTS_COUNT"
                  echo "  Último registro: $LATEST_RECORD"

                  # Verificar que los datos son recientes (no más viejos que 48 horas)
                  IS_RECENT=$(psql -p 5433 -d myapp_production -tAc \
                    "SELECT max(inserted_at) > now() - interval '48 hours' FROM users;")

                  # Parar el PostgreSQL temporal
                  pg_ctl -D $PGDATA -w stop

                  # Limpiar
                  rm -rf $PGDATA

                  if [ "$IS_RECENT" = "t" ]; then
                    echo "PRUEBA DE RESTAURACIÓN PASÓ: Los datos son recientes y válidos"
                    curl -X POST "$SLACK_WEBHOOK" \
                      -H 'Content-type: application/json' \
                      -d "{\"text\":\"Prueba de restauración PASÓ. Usuarios: $USERS_COUNT, Posts: $POSTS_COUNT, Último: $LATEST_RECORD\"}"
                  else
                    echo "PRUEBA DE RESTAURACIÓN FALLÓ: Los datos son obsoletos o faltan"
                    curl -X POST "$SLACK_WEBHOOK" \
                      -H 'Content-type: application/json' \
                      -d '{"text":"ALERTA: ¡Prueba de restauración FALLÓ! Los datos son obsoletos o faltan."}'
                    exit 1
                  fi
              envFrom:
                - secretRef:
                    name: pgbackrest-credentials
                - secretRef:
                    name: slack-webhook
              resources:
                requests:
                  memory: "1Gi"
                  cpu: "500m"
                limits:
                  memory: "2Gi"
          restartPolicy: Never
```

<br />

Las cosas clave que esta prueba de restauración valida:

<br />

> * **El backup es restaurable**: Si pgBackRest no puede restaurar, te enterás inmediatamente
> * **Los datos son recientes**: Si el último registro tiene más de 48 horas, algo anda mal con tu pipeline de backup
> * **Las tablas principales existen y tienen datos**: Un chequeo básico de que el schema y los datos están intactos
> * **Notificación en éxito y falla**: Querés saber tanto cuando funciona como cuando no

<br />

También deberías rastrear los resultados de las pruebas de restauración como una métrica y configurar
un SLO para eso. Algo como "99% de las pruebas de restauración semanales deberían pasar" es un buen
punto de partida.

<br />

##### **Migraciones sin downtime**
Las migraciones de base de datos son una de las causas más comunes de downtime. Una migración que
lockea una tabla puede bloquear todas las queries a esa tabla, lo que significa que tu aplicación se
cuelga hasta que la migración se completa. En PostgreSQL, incluso operaciones aparentemente inocentes
como agregar una columna con un valor por defecto solían lockear toda la tabla (aunque esto se arregló
en PostgreSQL 11).

<br />

Acá están los patrones de migración seguros para Ecto:

<br />

**Seguro: Agregar una columna nullable sin default**

<br />

```elixir
# Esto siempre es seguro. Toma un lock ACCESS EXCLUSIVE breve pero se completa casi al instante.
defmodule MyApp.Repo.Migrations.AddAvatarToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :avatar_url, :string
    end
  end
end
```

<br />

**Seguro: Agregar una columna con default (PostgreSQL 11+)**

<br />

```elixir
# En PostgreSQL 11+, esto es seguro porque el default se almacena en el catálogo,
# no se escribe en cada fila. El lock es breve.
defmodule MyApp.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, default: "user"
    end
  end
end
```

<br />

**Peligroso: Agregar un índice en una tabla grande**

<br />

Un `CREATE INDEX` regular lockea la tabla para escrituras. En una tabla con millones de filas, esto
puede tomar minutos. Usá `CREATE INDEX CONCURRENTLY` en su lugar:

<br />

```elixir
# MAL: Esto lockea la tabla para escrituras
defmodule MyApp.Repo.Migrations.AddIndexToPostsTitle do
  use Ecto.Migration

  def change do
    create index(:posts, [:title])
  end
end

# BIEN: Usá concurrently para evitar el lock
defmodule MyApp.Repo.Migrations.AddIndexToPostsTitle do
  use Ecto.Migration

  # disable_ddl_transaction es requerido para creación de índices concurrent
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:posts, [:title], concurrently: true)
  end
end
```

<br />

**Patrón seguro: Backfilling de datos en lotes**

<br />

Nunca hagas backfill de datos en una migración que corre dentro de una transacción. En su lugar,
escribí una migración o tarea separada que procese filas en lotes:

<br />

```elixir
# Paso 1: Agregar la nueva columna (rápido, seguro)
defmodule MyApp.Repo.Migrations.AddSlugToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :slug, :string
    end
  end
end

# Paso 2: Backfill en lotes (migración separada o tarea mix)
defmodule MyApp.Repo.Migrations.BackfillPostSlugs do
  use Ecto.Migration

  import Ecto.Query

  @disable_ddl_transaction true
  @disable_migration_lock true
  @batch_size 1000

  def up do
    backfill_batch(0)
  end

  defp backfill_batch(last_id) do
    {count, _} =
      repo().query!("""
        UPDATE posts
        SET slug = lower(replace(title, ' ', '-'))
        WHERE id > $1
          AND id <= $1 + $2
          AND slug IS NULL
      """, [last_id, @batch_size])

    if count > 0 do
      # Pequeña pausa para no sobrecargar la base de datos
      Process.sleep(100)
      backfill_batch(last_id + @batch_size)
    end
  end

  def down do
    # Nada que deshacer, el drop de la columna va a limpiar
    :ok
  end
end

# Paso 3: Agregar la constraint NOT NULL y el índice (después de que el backfill esté completo)
defmodule MyApp.Repo.Migrations.MakePostSlugRequired do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Agregar una check constraint primero (no bloqueante en PG12+)
    execute "ALTER TABLE posts ADD CONSTRAINT posts_slug_not_null CHECK (slug IS NOT NULL) NOT VALID"
    # Después validarla (toma un lock breve pero no bloquea escrituras por mucho)
    execute "ALTER TABLE posts VALIDATE CONSTRAINT posts_slug_not_null"
    # Crear índice único de forma concurrent
    create unique_index(:posts, [:slug], concurrently: true)
  end

  def down do
    drop_if_exists index(:posts, [:slug])
    execute "ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_slug_not_null"
  end
end
```

<br />

**Checklist de seguridad para migraciones**

<br />

Antes de correr cualquier migración en producción:

<br />

> * **Chequeá el tipo de lock**: ¿La migración va a tomar un lock ACCESS EXCLUSIVE? ¿Por cuánto tiempo?
> * **Probá en una copia de datos de producción**: Nunca pruebes migraciones en una base de datos vacía. Una migración que corre instantáneamente en 100 filas puede lockear la tabla por minutos en 10 millones de filas.
> * **Usá statement_timeout**: Configurá un statement timeout para que si una migración toma demasiado, falle en vez de lockear la tabla indefinidamente.
> * **Correla durante bajo tráfico**: Incluso migraciones "seguras" son más seguras durante horas de poco tráfico.
> * **Tené un plan de rollback**: Sabé cómo deshacer la migración antes de correrla.

<br />

```yaml
# Configurar un statement timeout para migraciones para prevenir locks largos
# config/runtime.exs
config :myapp, MyApp.Repo,
  migration_lock: nil,
  migration_default_prefix: "public",
  after_connect: {Postgrex, :query!, ["SET statement_timeout TO '5s'", []]}
```

<br />

##### **Monitoreo de base de datos**
No podés arreglar lo que no podés ver. PostgreSQL viene con excelentes vistas de monitoreo
incorporadas, y combinarlas con Prometheus te da una imagen completa de la salud de tu base de datos.

<br />

**pg_stat_statements: encontrando queries lentas**

<br />

`pg_stat_statements` es la extensión más importante de PostgreSQL para monitoreo de performance.
Rastrea estadísticas de ejecución para cada query que corre en el servidor:

<br />

```dockerfile
# Habilitar la extensión (una vez)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

# Top 10 queries por tiempo total de ejecución
SELECT
  queryid,
  calls,
  round(total_exec_time::numeric, 2) AS total_time_ms,
  round(mean_exec_time::numeric, 2) AS mean_time_ms,
  round(max_exec_time::numeric, 2) AS max_time_ms,
  rows,
  round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS percent_total,
  left(query, 100) AS query_preview
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

# Top 10 queries por tiempo promedio de ejecución (queries lentas)
SELECT
  queryid,
  calls,
  round(mean_exec_time::numeric, 2) AS mean_time_ms,
  round(max_exec_time::numeric, 2) AS max_time_ms,
  rows / NULLIF(calls, 0) AS avg_rows,
  left(query, 100) AS query_preview
FROM pg_stat_statements
WHERE calls > 10  -- Filtrar queries ejecutadas raramente
ORDER BY mean_exec_time DESC
LIMIT 10;

# Queries con más I/O
SELECT
  queryid,
  calls,
  shared_blks_read + shared_blks_written AS total_blocks,
  round(mean_exec_time::numeric, 2) AS mean_time_ms,
  left(query, 100) AS query_preview
FROM pg_stat_statements
ORDER BY (shared_blks_read + shared_blks_written) DESC
LIMIT 10;
```

<br />

**Monitoreo de conexiones**

<br />

Saber cómo se están usando tus conexiones es crítico para dimensionar tu pool correctamente y
detectar fugas de conexiones:

<br />

```dockerfile
# Cantidad actual de conexiones por estado
SELECT
  state,
  count(*) AS connections,
  max(now() - state_change) AS longest_in_state
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY state
ORDER BY connections DESC;

# Conexiones por nombre de aplicación (útil para identificar qué servicio usa más)
SELECT
  application_name,
  state,
  count(*) AS connections
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY application_name, state
ORDER BY connections DESC;

# Encontrar queries de larga duración (problemas potenciales)
SELECT
  pid,
  now() - query_start AS duration,
  state,
  left(query, 80) AS query_preview,
  wait_event_type,
  wait_event
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '30 seconds'
ORDER BY duration DESC;

# Encontrar queries bloqueadas (esperando locks)
SELECT
  blocked_locks.pid AS blocked_pid,
  blocked_activity.usename AS blocked_user,
  blocking_locks.pid AS blocking_pid,
  blocking_activity.usename AS blocking_user,
  left(blocked_activity.query, 60) AS blocked_query,
  left(blocking_activity.query, 60) AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity
  ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
  AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
  AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
  AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
  AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity
  ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

<br />

**Monitoreo de replication lag**

<br />

Si estás usando read replicas, monitorear el replication lag es esencial. Una réplica que está muy
atrasada puede servir datos obsoletos:

<br />

```sql
# En el primario: verificar estado de replicación
SELECT
  client_addr,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
  pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replay_lag_pretty
FROM pg_stat_replication;

# En la réplica: verificar cuánto atrás está
SELECT
  now() - pg_last_xact_replay_timestamp() AS replication_delay,
  pg_is_in_recovery() AS is_replica,
  pg_last_wal_receive_lsn() AS last_received,
  pg_last_wal_replay_lsn() AS last_replayed;
```

<br />

**Prometheus exporter para PostgreSQL**

<br />

El `postgres_exporter` de Prometheus Community expone todas estas métricas en formato Prometheus.
Deployealo junto a tus instancias de PostgreSQL:

<br />

```dockerfile
# postgres-exporter.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-exporter
  template:
    metadata:
      labels:
        app: postgres-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9187"
    spec:
      containers:
        - name: exporter
          image: prometheuscommunity/postgres-exporter:latest
          ports:
            - containerPort: 9187
          env:
            - name: DATA_SOURCE_URI
              value: "postgresql-primary.database.svc:5432/myapp_production?sslmode=disable"
            - name: DATA_SOURCE_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-exporter-credentials
                  key: username
            - name: DATA_SOURCE_PASS
              valueFrom:
                secretKeyRef:
                  name: postgres-exporter-credentials
                  key: password
            - name: PG_EXPORTER_EXTEND_QUERY_PATH
              value: /etc/postgres-exporter/queries.yaml
          volumeMounts:
            - name: custom-queries
              mountPath: /etc/postgres-exporter
      volumes:
        - name: custom-queries
          configMap:
            name: postgres-exporter-queries
---
# Queries custom para el exporter
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-exporter-queries
  namespace: database
data:
  queries.yaml: |
    pg_slow_queries:
      query: |
        SELECT count(*) AS count
        FROM pg_stat_activity
        WHERE state = 'active'
          AND now() - query_start > interval '30 seconds'
      metrics:
        - count:
            usage: "GAUGE"
            description: "Cantidad de queries corriendo más de 30 segundos"

    pg_connection_count:
      query: |
        SELECT state, count(*) AS count
        FROM pg_stat_activity
        GROUP BY state
      metrics:
        - count:
            usage: "GAUGE"
            description: "Cantidad de conexiones por estado"
      master: true

    pg_database_size:
      query: |
        SELECT pg_database.datname,
               pg_database_size(pg_database.datname) AS size_bytes
        FROM pg_database
        WHERE datistemplate = false
      metrics:
        - datname:
            usage: "LABEL"
            description: "Nombre de la base de datos"
        - size_bytes:
            usage: "GAUGE"
            description: "Tamaño de la base de datos en bytes"
```

<br />

Con este setup, podés crear alertas de Prometheus para:

<br />

> * **Alto replication lag**: Alertar cuando una réplica está más de 30 segundos atrasada
> * **Agotamiento de conexiones**: Alertar cuando las conexiones están por encima del 80% de `max_connections`
> * **Queries lentas**: Alertar cuando hay queries corriendo más de 60 segundos
> * **Crecimiento del tamaño de la base**: Alertar cuando la base de datos está creciendo más rápido de lo esperado

<br />

##### **Operador CloudNativePG**
CloudNativePG (CNPG) es un operador de Kubernetes que gestiona el ciclo de vida completo de clusters
de PostgreSQL. Maneja provisionamiento, escalado, failover, backups, y monitoreo. Si estás corriendo
PostgreSQL en Kubernetes, este es el operador que deberías estar usando.

<br />

**Instalación**

<br />

```bash
# Instalar con Helm
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

helm install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system \
  --create-namespace
```

<br />

**Creando un cluster de PostgreSQL**

<br />

Acá hay un CRD de Cluster listo para producción:

<br />

```yaml
# postgresql-cluster.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: myapp-db
  namespace: database
spec:
  instances: 3  # 1 primario + 2 réplicas
  imageName: ghcr.io/cloudnative-pg/postgresql:16.2

  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "512MB"
      effective_cache_size: "1536MB"
      maintenance_work_mem: "128MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
      random_page_cost: "1.1"  # Optimizado para SSD
      effective_io_concurrency: "200"
      work_mem: "4MB"
      min_wal_size: "1GB"
      max_wal_size: "4GB"
      max_worker_processes: "4"
      max_parallel_workers_per_gather: "2"
      max_parallel_workers: "4"
      max_parallel_maintenance_workers: "2"
      # Habilitar pg_stat_statements
      shared_preload_libraries: "pg_stat_statements"
      pg_stat_statements.track: "all"
      pg_stat_statements.max: "10000"
    pg_hba:
      - "host all all 10.0.0.0/8 scram-sha-256"
      - "host replication streaming_replica 10.0.0.0/8 scram-sha-256"

  bootstrap:
    initdb:
      database: myapp_production
      owner: myapp
      secret:
        name: myapp-db-credentials

  storage:
    size: 50Gi
    storageClass: longhorn  # O tu storage class preferida

  resources:
    requests:
      memory: "2Gi"
      cpu: "1"
    limits:
      memory: "4Gi"

  # Habilitar monitoreo
  monitoring:
    enablePodMonitor: true
    customQueriesConfigMap:
      - name: cnpg-default-monitoring
        key: queries

  # Anti-afinidad para distribuir instancias entre nodos
  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname

  # Configuración de backup a S3
  backup:
    barmanObjectStore:
      destinationPath: "s3://myapp-pg-backups/cnpg/"
      s3Credentials:
        accessKeyId:
          name: aws-s3-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: aws-s3-credentials
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
        maxParallel: 4
      data:
        compression: gzip
        immediateCheckpoint: true
    retentionPolicy: "30d"
```

<br />

Esto crea un cluster de PostgreSQL de 3 instancias con:

<br />

> * **Replicación automática**: CNPG maneja la replicación por streaming entre primario y réplicas
> * **Parámetros tuneados**: Configuración de PostgreSQL optimizada para un workload web típico
> * **Anti-afinidad de pods**: Las instancias se distribuyen entre diferentes nodos de Kubernetes para resiliencia
> * **Monitoreo**: Pod monitors para integración con Prometheus
> * **Archivado de WAL a S3**: Backup continuo de archivos WAL para PITR

<br />

**Backups programados**

<br />

```yaml
# scheduled-backup.yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: myapp-db-daily-backup
  namespace: database
spec:
  schedule: "0 2 * * *"  # Todos los días a las 2am
  backupOwnerReference: self
  cluster:
    name: myapp-db
  immediate: false
  target: prefer-standby  # Tomar backup desde una réplica para no impactar al primario
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: myapp-db-weekly-full
  namespace: database
spec:
  schedule: "0 3 * * 0"  # Todos los domingos a las 3am
  backupOwnerReference: self
  cluster:
    name: myapp-db
  immediate: false
  target: prefer-standby
```

<br />

**Conectando tu aplicación**

<br />

CNPG crea servicios de Kubernetes para acceso de lectura-escritura y solo lectura:

<br />

```yaml
# El operador crea estos servicios automáticamente:
# myapp-db-rw   -> apunta al primario (lectura-escritura)
# myapp-db-ro   -> apunta a las réplicas (solo lectura, balanceado)
# myapp-db-r    -> apunta a cualquier instancia (para lecturas que toleran lag)

# En tu configuración de Ecto:
config :myapp, MyApp.Repo,
  hostname: "myapp-db-rw.database.svc.cluster.local",
  database: "myapp_production",
  username: "myapp",
  password: System.get_env("DB_PASSWORD"),
  pool_size: 16

config :myapp, MyApp.ReadRepo,
  hostname: "myapp-db-ro.database.svc.cluster.local",
  database: "myapp_production",
  username: "myapp",
  password: System.get_env("DB_PASSWORD"),
  pool_size: 20
```

<br />

**Monitoreando el cluster de CNPG**

<br />

CNPG expone un set rico de métricas. Acá hay algunas consultas PromQL útiles:

<br />

```bash
# Replication lag en segundos
cnpg_pg_replication_lag{cluster="myapp-db"}

# Cantidad de conexiones por estado
cnpg_pg_stat_activity_count{cluster="myapp-db"}

# Tasa de transacciones
rate(cnpg_pg_stat_database_xact_commit{cluster="myapp-db"}[5m])
  + rate(cnpg_pg_stat_database_xact_rollback{cluster="myapp-db"}[5m])

# Cache hit ratio (debería ser > 99%)
cnpg_pg_stat_database_blks_hit{cluster="myapp-db"}
  / (cnpg_pg_stat_database_blks_hit{cluster="myapp-db"}
     + cnpg_pg_stat_database_blks_read{cluster="myapp-db"}) * 100

# Tasa de generación de WAL
rate(cnpg_pg_stat_archiver_archived_count{cluster="myapp-db"}[5m])

# Tamaño de la base de datos
cnpg_pg_database_size_bytes{cluster="myapp-db", datname="myapp_production"}
```

<br />

##### **Failover y alta disponibilidad**
El punto principal de correr múltiples instancias es que cuando el primario falla, una réplica toma
el control automáticamente. Acá es donde CloudNativePG realmente brilla.

<br />

**Failover automático con CloudNativePG**

<br />

CNPG monitorea la salud de todas las instancias continuamente. Cuando detecta que el primario no
está saludable:

<br />

> 1. **Detecta la falla**: El operador verifica la salud de las instancias via health probes y estado de replicación
> 2. **Selecciona la mejor réplica**: Elige la réplica con menos replication lag
> 3. **Promueve la réplica**: Ejecuta `pg_promote()` para hacer que la réplica sea el nuevo primario
> 4. **Actualiza los servicios**: El servicio `myapp-db-rw` ahora apunta al nuevo primario
> 5. **Reconfigura las réplicas restantes**: Empiezan a replicar desde el nuevo primario
> 6. **Cerca al viejo primario**: Previene que el viejo primario acepte escrituras (prevención de split-brain)

<br />

Todo este proceso típicamente se completa en 10-30 segundos. Tu aplicación podría ver un breve error
de conexión durante el switchover, así que asegurate de que tu configuración de Ecto tenga lógica de
reintentos apropiada:

<br />

```yaml
# config/runtime.exs
config :myapp, MyApp.Repo,
  hostname: "myapp-db-rw.database.svc.cluster.local",
  database: "myapp_production",
  pool_size: 16,
  # Ecto/DBConnection va a reintentar checkouts fallidos
  queue_target: 5000,
  queue_interval: 5000,
  # Configurar las opciones de socket para detección más rápida de fallas
  socket_options: [
    keepalive: true,
    # Enviar sondas keepalive después de 10 segundos de inactividad
    # (depende de la plataforma, funciona en Linux)
  ],
  parameters: [
    application_name: "tr-web"
  ]
```

<br />

**Probando el failover**

<br />

Deberías probar regularmente que el failover funciona. Con CNPG, podés disparar un switchover
controlado:

<br />

```bash
# Disparar un switchover (failover controlado)
kubectl cnpg promote myapp-db myapp-db-2 --namespace database

# O usá el plugin para disparar un restart del primario (simula un crash)
kubectl cnpg restart myapp-db myapp-db-1 --namespace database

# Verificar el estado del cluster durante y después del failover
kubectl cnpg status myapp-db --namespace database
```

<br />

La salida te muestra qué instancia es el primario, el replication lag, y la salud general del cluster:

<br />

```yaml
# Ejemplo de salida de kubectl cnpg status myapp-db
Cluster Summary
  Name:               myapp-db
  Namespace:          database
  PostgreSQL Image:   ghcr.io/cloudnative-pg/postgresql:16.2
  Primary instance:   myapp-db-2    # Este fue promovido
  Status:             Cluster in healthy state
  Instances:          3

Certificates Status
  ...

Instances Status
  Name        Role       Status  Node          Timeline  LSN
  ----        ----       ------  ----          --------  ---
  myapp-db-1  Replica    OK      worker-01     2         0/5000060
  myapp-db-2  Primary    OK      worker-02     2         0/5000060
  myapp-db-3  Replica    OK      worker-03     2         0/5000060
```

<br />

**Patroni como alternativa**

<br />

Si no estás usando CloudNativePG (tal vez estás corriendo PostgreSQL en VMs o usando un enfoque
diferente para Kubernetes), Patroni es la solución de referencia para alta disponibilidad de
PostgreSQL. Usa un store de consenso distribuido (etcd, Consul, o ZooKeeper) para manejar elección
de líder y failover:

<br />

```yaml
# patroni.yml
scope: myapp-cluster
name: postgresql-node-1

restapi:
  listen: 0.0.0.0:8008
  connect_address: postgresql-node-1:8008

etcd:
  hosts: etcd-1:2379,etcd-2:2379,etcd-3:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576  # 1MB
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 200
        shared_buffers: 512MB
        wal_level: replica
        hot_standby: on
        max_wal_senders: 10
        max_replication_slots: 10

  initdb:
    - encoding: UTF8
    - data-checksums

postgresql:
  listen: 0.0.0.0:5432
  connect_address: postgresql-node-1:5432
  data_dir: /var/lib/postgresql/16/main
  authentication:
    superuser:
      username: postgres
      password: secret
    replication:
      username: replicator
      password: secret
```

<br />

La diferencia clave es que CNPG es nativo de Kubernetes (usa la API de Kubernetes para coordinación)
mientras que Patroni requiere un store de consenso separado. Si ya estás corriendo en Kubernetes,
CNPG es la opción más simple.

<br />

**Prevención de split-brain**

<br />

El split-brain es lo peor que puede pasar en un cluster de base de datos: dos instancias creen que
son el primario y aceptan escrituras de forma independiente. Cuando se reconectan, los datos son
inconsistentes y potencialmente irrecuperables.

<br />

Tanto CNPG como Patroni tienen prevención de split-brain incorporada:

<br />

> * **CNPG** usa fencing. Cuando ocurre un failover, el viejo primario es cercado (su directorio de datos se marca como inválido) así que incluso si vuelve, no puede servir escrituras. Tiene que ser reinicializado como réplica.
> * **Patroni** usa el store de consenso (etcd) como fuente de verdad. Solo el nodo que tiene la key de líder en etcd puede ser el primario. Si un nodo pierde contacto con etcd, se demota a sí mismo.

<br />

Salvaguardas adicionales que deberías tener:

<br />

> * **Network policies**: Asegurate de que solo el operador o Patroni pueda modificar los endpoints de los servicios
> * **Monitoreo**: Alertá sobre cualquier instancia que se reporte como primario cuando no debería serlo
> * **pg_rewind**: Habilitá `pg_rewind` para que un ex-primario pueda ser resincronizado rápidamente como réplica sin un backup base completo

<br />

```yaml
# PrometheusRule para detección de split-brain
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: pg-split-brain-alert
  namespace: database
spec:
  groups:
    - name: postgresql.split-brain
      rules:
        - alert: PostgreSQLSplitBrain
          expr: |
            count(cnpg_pg_replication_is_replica{cluster="myapp-db"} == 0) > 1
          for: 30s
          labels:
            severity: critical
          annotations:
            summary: "CRITICO: Múltiples instancias primarias detectadas en el cluster myapp-db"
            description: "Hay {{ $value }} instancias reportándose como primario. Esta es una situación de split-brain que requiere atención inmediata."
```

<br />

##### **Notas finales**
La confiabilidad de la base de datos no es una sola cosa que configurás y te olvidás. Es una
combinación de patrones que trabajan juntos: connection pooling mantiene tus conexiones saludables,
las réplicas distribuyen la carga de lectura, los backups protegen tus datos, las migraciones seguras
previenen outages autoinfligidos, el monitoreo te dice cuando algo anda mal, y el failover
automatizado mantiene todo funcionando cuando el hardware falla.

<br />

La buena noticia es que herramientas como CloudNativePG hacen que la mayor parte de esto sea mucho
más fácil de lo que solía ser. En vez de configurar manualmente la replicación, scripts de failover,
y cron jobs de backup, declarás tu estado deseado en un manifiesto de Kubernetes y el operador se
encarga del resto. Eso es una mejora enorme comparado con el enfoque de "PostgreSQL artesanal" con
el que muchos de nosotros crecimos.

<br />

Empezá con lo básico: poné PgBouncer delante de tu base de datos, configurá backups automatizados
con pruebas de restauración, y agregá pg_stat_statements para monitoreo de queries. Después, cuando
estés listo, pasate a CloudNativePG para un cluster completamente gestionado con failover automático.
Cada capa se construye sobre la anterior.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
