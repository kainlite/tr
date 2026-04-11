%{
  title: "DevOps from Zero to Hero: Database Migrations and Zero-Downtime Deployments",
  author: "Gabriel Garrido",
  description: "We will explore why database changes are the riskiest part of deployments, learn safe migration patterns with Prisma, and implement zero-downtime deployments in Kubernetes with rolling updates, health checks, and rollback strategies...",
  tags: ~w(devops kubernetes databases deployments beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article seventeen of the DevOps from Zero to Hero series. In the previous articles we
built a complete CI/CD pipeline, set up observability, and deployed our TypeScript API to Kubernetes.
Everything works, the pipeline is green, and deploys are smooth. But there is one topic we have been
quietly avoiding: the database.

<br />

Deploying new application code is relatively straightforward. You build a new image, roll it out, and
if something goes wrong, you roll back. But database changes are different. They are stateful. You
cannot just "undo" a column drop. They affect every instance of your application simultaneously. And
if you get the ordering wrong, you can take down your entire service.

<br />

In this article we will cover what database migrations are and how they work, how to write safe
migrations using Prisma, the expand-contract pattern for making backwards-compatible schema changes,
zero-downtime deployment strategies in Kubernetes, health checks and readiness probes, and rollback
strategies for when things go wrong. By the end, you will know how to ship database changes
confidently, even under production traffic.

<br />

Let's get into it.

<br />

##### **Why database changes are the riskiest part of deployments**
Application code is stateless. If you deploy a bad version, you roll back to the previous container
image and the problem is gone. The old code runs exactly as it did before. But databases are
stateful. Once you drop a column, that data is gone. Once you rename a table, every query that
references the old name breaks instantly.

<br />

Here is what makes database changes so dangerous:

<br />

> * **They are shared state**: Every pod, every instance, every replica reads from the same database. A schema change affects all of them at once. You cannot do a gradual rollout of a database change the way you can with application code.
> * **They are hard to reverse**: Adding a column is easy to undo (just drop it). But dropping a column, changing a column type, or deleting data? Those operations are destructive. You cannot "undelete" a column and get the data back.
> * **Ordering matters**: If your application code expects a column that does not exist yet, it crashes. If your migration removes a column that old application code still references, it crashes. The sequencing between code deploys and schema changes is critical.
> * **They hold locks**: Many schema changes (especially on large tables) acquire locks that block reads or writes. A migration that takes 30 seconds to run on your dev database might take 30 minutes on a production table with millions of rows, locking out all traffic.

<br />

The core challenge is this: during a deployment, you will have old code and new code running at the
same time. Your database schema must be compatible with both versions simultaneously. This constraint
drives every decision we will make in this article.

<br />

##### **Migration fundamentals**
A database migration is a versioned, incremental change to your database schema. Instead of manually
running SQL statements against your database, you write migration files that describe the change, and
a migration tool applies them in order.

<br />

Every migration has two parts:

<br />

> * **Up**: The forward change. Create a table, add a column, create an index. This is what runs when you apply the migration.
> * **Down**: The reverse change. Drop the table, remove the column, remove the index. This is what runs when you roll back the migration.

<br />

Migration files are typically named with a timestamp or sequence number so the tool knows what order
to run them in:

<br />

```bash
migrations/
  20260601120000_create_users_table/
    migration.sql
  20260602090000_add_email_to_orders/
    migration.sql
  20260603140000_create_audit_log/
    migration.sql
```

<br />

The migration tool keeps track of which migrations have been applied in a special table (usually
called `_prisma_migrations` or `schema_migrations`). When you run `migrate`, it checks which
migrations are pending and applies them in order. This gives you a complete, auditable history of
every schema change, the ability to reproduce your database schema from scratch, and a mechanism
to roll back changes when needed.

<br />

##### **Setting up migrations with Prisma**
We will use Prisma as our TypeScript ORM and migration tool. Prisma takes a different approach from
traditional migration tools: you define your schema in a declarative file, and Prisma generates the
SQL migrations for you.

<br />

First, install Prisma in your project:

<br />

```bash
npm install prisma --save-dev
npm install @prisma/client

# Initialize Prisma with PostgreSQL
npx prisma init --datasource-provider postgresql
```

<br />

This creates a `prisma/schema.prisma` file. Let's define our first model:

<br />

```typescript
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  name      String
  email     String   @unique
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  orders    Order[]
}

model Order {
  id        Int      @id @default(autoincrement())
  amount    Float
  status    String   @default("pending")
  userId    Int
  user      User     @relation(fields: [userId], references: [id])
  createdAt DateTime @default(now())
}
```

<br />

Now generate the first migration:

<br />

```bash
npx prisma migrate dev --name create_users_and_orders
```

<br />

Prisma compares your schema file to the current database state, generates the SQL, and applies it.
The generated migration looks like this:

<br />

```sql
-- CreateTable
CREATE TABLE "User" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Order" (
    "id" SERIAL NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "userId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Order_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- AddForeignKey
ALTER TABLE "Order" ADD CONSTRAINT "Order_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
```

<br />

Now let's add a column. Say we need a `phone` field on the `User` model:

<br />

```typescript
model User {
  id        Int      @id @default(autoincrement())
  name      String
  email     String   @unique
  phone     String?  // nullable, so existing rows are fine
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  orders    Order[]
}
```

<br />

```bash
npx prisma migrate dev --name add_phone_to_users
```

<br />

The generated SQL:

<br />

```sql
-- AlterTable
ALTER TABLE "User" ADD COLUMN "phone" TEXT;
```

<br />

Notice that the column is nullable (`TEXT` without `NOT NULL`). This is important. If we made it
required, the migration would fail because existing rows would not have a value for the new column.
Making new columns nullable (or giving them a default value) is one of the most basic safe migration
patterns.

<br />

Now let's rename a column. Say we want to rename `name` to `fullName`. In Prisma, you use the
`@map` attribute to rename the database column without changing the Prisma field name:

<br />

```typescript
model User {
  id        Int      @id @default(autoincrement())
  fullName  String   @map("full_name")
  email     String   @unique
  phone     String?
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  orders    Order[]

  @@map("users")
}
```

<br />

But hold on. If we just rename the column directly, any application code that still queries the old
column name will break. This is exactly the kind of dangerous operation we need to handle with the
expand-contract pattern, which we will cover next.

<br />

##### **Safe migration patterns**
The golden rule of safe migrations is: never make a breaking change in a single deploy. Instead,
break it into multiple steps where each step is backwards-compatible.

<br />

Here are the patterns you should follow:

<br />

**Adding a column (safe)**

<br />

Adding a nullable column or a column with a default value is always safe. Old code ignores the new
column. New code can use it.

<br />

```sql
-- Safe: nullable column, old code ignores it
ALTER TABLE "User" ADD COLUMN "phone" TEXT;

-- Safe: column with default, old code ignores it
ALTER TABLE "Order" ADD COLUMN "currency" TEXT NOT NULL DEFAULT 'USD';
```

<br />

**Adding an index (safe, but watch lock time)**

<br />

Creating an index is safe from a compatibility standpoint, but on large tables it can lock the table
for a long time. Use `CONCURRENTLY` in PostgreSQL to avoid blocking writes:

<br />

```sql
-- This locks the table until the index is built (dangerous on large tables)
CREATE INDEX idx_orders_user_id ON "Order" ("userId");

-- This builds the index without locking (safe for production)
CREATE INDEX CONCURRENTLY idx_orders_user_id ON "Order" ("userId");
```

<br />

**Creating a new table (safe)**

<br />

New tables do not affect existing code at all. Always safe.

<br />

**Dropping a column (dangerous if done wrong)**

<br />

If you drop a column that old application code still reads from, those queries will fail. Never drop
a column in the same deploy that still references it.

<br />

**Renaming a column (dangerous if done in one step)**

<br />

A column rename is essentially a drop-and-add from the application's perspective. Old code queries
the old name. New code queries the new name. During a rolling update, both versions run
simultaneously, and one of them will always be broken.

<br />

##### **The expand-contract pattern**
The expand-contract pattern is the standard way to make breaking schema changes safely. It works in
three phases:

<br />

**Phase 1: Expand (add the new thing)**

<br />

Add the new column alongside the old one. Update your application code to write to both columns.
Deploy this change.

<br />

```sql
-- Migration 1: Add the new column
ALTER TABLE "users" ADD COLUMN "full_name" TEXT;
```

<br />

```typescript
// Application code writes to both columns
async function updateUser(id: number, name: string) {
  await prisma.user.update({
    where: { id },
    data: {
      name: name,      // old column (for old code still reading it)
      fullName: name,  // new column (for new code)
    },
  });
}
```

<br />

**Phase 2: Migrate data**

<br />

Backfill the new column with data from the old column. This can be a migration script or a
background job.

<br />

```sql
-- Migration 2: Backfill existing data
UPDATE "users" SET "full_name" = "name" WHERE "full_name" IS NULL;
```

<br />

At this point, both columns have the same data. Old code reads from `name`, new code reads from
`full_name`, and everything works.

<br />

**Phase 3: Contract (remove the old thing)**

<br />

Once all application code has been updated to use the new column, and you have verified that no
queries reference the old column, you can drop it.

<br />

```sql
-- Migration 3: Drop the old column (only after all code uses full_name)
ALTER TABLE "users" DROP COLUMN "name";
```

<br />

This three-phase approach means that at every point during the rollout, the database schema is
compatible with both the old and new versions of your code. No downtime, no errors, no data loss.

<br />

Here is the timeline:

<br />

```bash
# Expand-contract timeline
#
# Deploy 1: Add "full_name" column, write to both columns
#   Old code: reads "name"       -> works (column still exists)
#   New code: reads "full_name"  -> works (column was just added)
#
# Deploy 2: Backfill "full_name" from "name"
#   All rows now have both columns populated
#
# Deploy 3: Remove all reads from "name", drop column
#   Old code: gone (fully rolled out)
#   New code: reads "full_name"  -> works (only column left)
```

<br />

Yes, this takes three deploys instead of one. That is the trade-off. Safety costs velocity, but it
saves you from 3am incidents.

<br />

##### **Dangerous patterns to avoid**
Here are the schema changes that cause the most outages, and how to handle them instead:

<br />

> * **Renaming a column in a single deploy**: This is a drop plus add. Use expand-contract instead. Add the new column, backfill, update code, then drop the old column.
> * **Changing a column type in place**: Changing `VARCHAR(50)` to `TEXT` might seem harmless, but changing `TEXT` to `INTEGER` will fail if any rows contain non-numeric data. Add a new column with the new type, backfill with type conversion, switch code, then drop the old column.
> * **Adding a NOT NULL constraint without a default**: If you add `NOT NULL` to an existing column that has null values, the migration will fail. First backfill all nulls, then add the constraint.
> * **Dropping a table that is still referenced**: Foreign key constraints will block the drop, but application code will crash. Remove all code references first, then drop.
> * **Running large data migrations in the main transaction**: Updating millions of rows in a single transaction locks the table and can cause timeouts. Batch your updates (1000-5000 rows at a time) with small pauses between batches.

<br />

A useful rule of thumb: if a migration cannot be reversed with a simple "undo" migration, it is
dangerous and needs the expand-contract treatment.

<br />

##### **Zero-downtime deployments in Kubernetes**
Now that we know how to handle database changes safely, let's look at the other half of the puzzle:
deploying application code without dropping requests. Kubernetes gives you several mechanisms for
this.

<br />

**Rolling updates**

<br />

The default Kubernetes deployment strategy is `RollingUpdate`. It gradually replaces old pods with
new pods, ensuring that some pods are always available to serve traffic.

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # At most 1 extra pod during rollout
      maxUnavailable: 0   # Never have fewer than 3 healthy pods
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: myapp:v2
          ports:
            - containerPort: 3000
```

<br />

With `maxSurge: 1` and `maxUnavailable: 0`, Kubernetes will:

<br />

> * **Step 1**: Create 1 new pod (v2). Now you have 3 old + 1 new = 4 pods total.
> * **Step 2**: Wait until the new pod passes its readiness probe.
> * **Step 3**: Terminate 1 old pod (v1). Now you have 2 old + 1 new = 3 pods.
> * **Step 4**: Create another new pod (v2). Now you have 2 old + 2 new = 4 pods.
> * **Repeat** until all pods are running v2.

<br />

During this process, both v1 and v2 pods are serving traffic. This is exactly why your database
schema must be compatible with both versions.

<br />

**The Recreate strategy**

<br />

The `Recreate` strategy kills all old pods before creating new ones. This means downtime, so you
should only use it when your application cannot run two versions simultaneously (for example, if it
holds an exclusive lock on a resource).

<br />

```yaml
strategy:
  type: Recreate
```

<br />

For almost all web applications, `RollingUpdate` is what you want.

<br />

##### **Health checks: liveness, readiness, and startup probes**
Probes are how Kubernetes knows if your pod is healthy. There are three types, and each one serves a
different purpose:

<br />

> * **Readiness probe**: "Is this pod ready to receive traffic?" Kubernetes only sends traffic to pods that pass their readiness probe. During a deployment, new pods will not receive traffic until they are ready. This is the most important probe for zero-downtime deployments.
> * **Liveness probe**: "Is this pod still alive?" If a pod fails its liveness probe, Kubernetes restarts it. Use this to recover from deadlocks or stuck processes. Be careful: if your liveness probe is too aggressive, Kubernetes will restart pods that are just slow, creating a crash loop.
> * **Startup probe**: "Has this pod finished starting up?" This is for applications with a slow startup (loading large caches, running migrations). The startup probe runs first, and liveness/readiness probes do not start until it passes.

<br />

Here is how to configure all three:

<br />

```yaml
containers:
  - name: myapp
    image: myapp:v2
    ports:
      - containerPort: 3000
    readinessProbe:
      httpGet:
        path: /health/ready
        port: 3000
      initialDelaySeconds: 5
      periodSeconds: 10
      failureThreshold: 3
    livenessProbe:
      httpGet:
        path: /health/live
        port: 3000
      initialDelaySeconds: 15
      periodSeconds: 20
      failureThreshold: 3
    startupProbe:
      httpGet:
        path: /health/started
        port: 3000
      failureThreshold: 30
      periodSeconds: 10
```

<br />

And here is what the health check endpoints look like in your TypeScript API:

<br />

```typescript
// Health check endpoints
app.get("/health/live", (req, res) => {
  // Liveness: is the process running?
  // Keep this simple. If this endpoint responds, the process is alive.
  res.status(200).json({ status: "alive" });
});

app.get("/health/ready", async (req, res) => {
  // Readiness: can this pod serve traffic?
  // Check that all dependencies are reachable.
  try {
    await prisma.$queryRaw`SELECT 1`;  // database is reachable
    res.status(200).json({ status: "ready" });
  } catch (error) {
    res.status(503).json({ status: "not ready", error: "database unreachable" });
  }
});

app.get("/health/started", (req, res) => {
  // Startup: has the app finished initializing?
  if (appIsInitialized) {
    res.status(200).json({ status: "started" });
  } else {
    res.status(503).json({ status: "starting" });
  }
});
```

<br />

A common mistake is making the liveness probe too strict. If your liveness probe checks the
database, and the database has a brief network hiccup, Kubernetes will restart all your pods at
once, making the situation much worse. Keep liveness probes simple (just "is the process running?")
and use readiness probes for dependency checks.

<br />

##### **Graceful shutdown: preStop hooks and connection draining**
When Kubernetes terminates a pod during a rolling update, it sends a `SIGTERM` signal. Your
application should catch this signal and stop accepting new requests while finishing in-flight
requests. But there is a race condition: Kubernetes removes the pod from the service endpoints at
the same time it sends `SIGTERM`, and the endpoint removal takes a moment to propagate. During that
window, traffic can still be routed to a pod that is shutting down.

<br />

The fix is a `preStop` hook that adds a small delay:

<br />

```yaml
containers:
  - name: myapp
    image: myapp:v2
    lifecycle:
      preStop:
        exec:
          command: ["sh", "-c", "sleep 10"]
```

<br />

This tells Kubernetes to wait 10 seconds before sending `SIGTERM`. During those 10 seconds, the pod
is removed from the service endpoints, so no new traffic is routed to it. After the sleep, `SIGTERM`
is sent and the application can shut down gracefully.

<br />

In your TypeScript application, handle the shutdown signal:

<br />

```typescript
// Graceful shutdown handler
process.on("SIGTERM", () => {
  console.log("SIGTERM received. Starting graceful shutdown...");

  // Stop accepting new connections
  server.close(() => {
    console.log("HTTP server closed. Cleaning up...");

    // Close database connections
    prisma.$disconnect().then(() => {
      console.log("Database disconnected. Exiting.");
      process.exit(0);
    });
  });

  // Force exit after 30 seconds if graceful shutdown hangs
  setTimeout(() => {
    console.error("Graceful shutdown timed out. Forcing exit.");
    process.exit(1);
  }, 30000);
});
```

<br />

Also, set `terminationGracePeriodSeconds` on the pod spec to give your application enough time to
drain. The default is 30 seconds, but adjust it based on how long your longest requests take:

<br />

```yaml
spec:
  terminationGracePeriodSeconds: 60
  containers:
    - name: myapp
      # ...
```

<br />

##### **PodDisruptionBudgets**
A PodDisruptionBudget (PDB) tells Kubernetes how many pods must remain available during voluntary
disruptions like node drains, cluster upgrades, or autoscaler scale-downs. Without a PDB, Kubernetes
could drain all your nodes at once during a cluster upgrade, taking down every pod simultaneously.

<br />

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
spec:
  minAvailable: 2    # At least 2 pods must always be running
  selector:
    matchLabels:
      app: myapp
```

<br />

You can also use `maxUnavailable` instead of `minAvailable`:

<br />

```yaml
spec:
  maxUnavailable: 1   # At most 1 pod can be down at a time
```

<br />

For a deployment with 3 replicas, `minAvailable: 2` and `maxUnavailable: 1` are equivalent. Use
whichever reads more clearly for your team.

<br />

##### **Blue-green deployments**
Blue-green deployments take a different approach from rolling updates. Instead of gradually replacing
pods, you run two complete environments simultaneously: the "blue" environment (current production)
and the "green" environment (new version). Once the green environment is validated, you switch
traffic from blue to green in one step.

<br />

Here is how to implement blue-green with Kubernetes services:

<br />

```yaml
# Blue deployment (current production, running v1)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue
    spec:
      containers:
        - name: myapp
          image: myapp:v1
---
# Green deployment (new version, running v2)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
        - name: myapp
          image: myapp:v2
---
# Service (points to blue initially)
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
    version: blue    # Change to "green" to switch traffic
  ports:
    - port: 80
      targetPort: 3000
```

<br />

To switch traffic, you update the service selector from `version: blue` to `version: green`. All
traffic moves at once. If something is wrong, you switch back to blue.

<br />

> * **When to use blue-green**: When you need instant rollback (one label change), when you want to validate the new version with real traffic patterns before committing, or when your application cannot tolerate mixed versions.
> * **When to stick with rolling updates**: For most standard deployments. Blue-green requires double the resources (both environments run simultaneously) and adds operational complexity.

<br />

##### **Rollback strategies**
No matter how careful you are, things will go wrong. Having a rollback plan is not optional. Here
are the three main strategies:

<br />

**Kubernetes rollback**

<br />

Kubernetes keeps a history of your deployments. You can roll back to a previous version with a
single command:

<br />

```bash
# See rollout history
kubectl rollout history deployment/myapp

# Roll back to the previous version
kubectl rollout undo deployment/myapp

# Roll back to a specific revision
kubectl rollout undo deployment/myapp --to-revision=3

# Watch the rollback progress
kubectl rollout status deployment/myapp
```

<br />

This only rolls back the application code (the container image). It does not roll back database
migrations. If your migration was additive (adding a column), the old code simply ignores the new
column, and there is nothing to roll back. If your migration was destructive (dropping a column),
you need a database rollback.

<br />

**Database rollback**

<br />

Prisma does not have a built-in "undo last migration" command for production. In production, you
write a new migration that reverses the change:

<br />

```bash
# In development, you can reset (destroys all data)
npx prisma migrate reset

# In production, create a new "undo" migration
npx prisma migrate dev --name undo_add_phone_to_users
```

<br />

The "undo" migration is just another migration that reverses the previous change:

<br />

```sql
-- Undo migration: remove the phone column
ALTER TABLE "User" DROP COLUMN "phone";
```

<br />

This is another reason to prefer additive migrations. Adding a column is easy to undo (drop it).
Dropping a column is impossible to undo (the data is gone). If you follow the expand-contract
pattern, your "undo" is always just "drop the column you added."

<br />

**Feature flags as an alternative to rollbacks**

<br />

Instead of rolling back code or database changes, you can use feature flags to disable the new
functionality without changing the deployed code:

<br />

```typescript
// Feature flag check
app.get("/api/orders", async (req, res) => {
  const orders = await prisma.order.findMany({
    include: {
      user: true,
    },
  });

  if (featureFlags.isEnabled("show-order-currency")) {
    // New behavior: include currency field
    return res.json(orders.map(o => ({
      ...o,
      currency: o.currency ?? "USD",
    })));
  }

  // Old behavior: no currency field
  return res.json(orders);
});
```

<br />

Feature flags let you decouple deployment from release. You deploy the code (including the
migration), but the new feature is behind a flag. If something goes wrong, you flip the flag off.
No rollback needed, no redeployment, no database undo.

<br />

##### **Practical example: adding a column under production traffic**
Let's put it all together with a real scenario. We need to add a `currency` column to the `Order`
table. The API is serving traffic, and we cannot afford any downtime.

<br />

**Step 1: Write the migration**

<br />

Update the Prisma schema:

<br />

```typescript
model Order {
  id        Int      @id @default(autoincrement())
  amount    Float
  status    String   @default("pending")
  currency  String   @default("USD")   // new column with a default
  userId    Int
  user      User     @relation(fields: [userId], references: [id])
  createdAt DateTime @default(now())
}
```

<br />

Generate and review the migration:

<br />

```bash
npx prisma migrate dev --name add_currency_to_orders
```

<br />

Generated SQL:

<br />

```sql
ALTER TABLE "Order" ADD COLUMN "currency" TEXT NOT NULL DEFAULT 'USD';
```

<br />

This is safe because the column has a default value, so existing rows get `'USD'` automatically,
and old application code that does not know about the column will simply ignore it.

<br />

**Step 2: Update the application code**

<br />

Update the API to use the new column:

<br />

```typescript
// Updated order creation endpoint
app.post("/api/orders", async (req, res) => {
  const { amount, userId, currency } = req.body;

  const order = await prisma.order.create({
    data: {
      amount,
      userId,
      currency: currency ?? "USD",   // use provided currency or default
    },
  });

  res.status(201).json(order);
});
```

<br />

**Step 3: Run the migration in CI/CD**

<br />

Add a migration step to your CI/CD pipeline that runs before the application deployment:

<br />

```yaml
# In your GitHub Actions workflow
jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Install dependencies
        run: npm ci

      - name: Run database migrations
        run: npx prisma migrate deploy
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}

  deploy:
    needs: migrate    # Deploy only after migrations succeed
    runs-on: ubuntu-latest
    steps:
      - name: Update deployment image
        run: |
          kubectl set image deployment/myapp \
            myapp=myapp:${{ github.sha }}

      - name: Wait for rollout
        run: kubectl rollout status deployment/myapp --timeout=300s
```

<br />

**Step 4: Verify**

<br />

After the deploy, verify everything is working:

<br />

```bash
# Check the migration was applied
npx prisma migrate status

# Test the API
curl -X POST https://api.example.com/api/orders \
  -H "Content-Type: application/json" \
  -d '{"amount": 29.99, "userId": 1, "currency": "EUR"}'

# Verify the response includes the currency
curl https://api.example.com/api/orders/1
```

<br />

Because we used an additive change with a default value, the entire process was zero-downtime. Old
pods that do not know about the `currency` column kept serving traffic while new pods rolled out.
No conflicts, no errors, no interruption.

<br />

##### **Migration checklist**
Before running any migration in production, go through this checklist:

<br />

> * **Is the migration additive?** Adding columns (nullable or with defaults), adding tables, and adding indexes are safe. Everything else needs extra care.
> * **Can old code work with the new schema?** During a rolling update, old and new code run simultaneously. Make sure the old code will not break.
> * **Can new code work with the old schema?** If the migration fails or is delayed, can the new code still function?
> * **Have you tested the migration on a copy of production data?** Your dev database has 100 rows. Production has 10 million. What takes 1 second in dev might take 10 minutes in production.
> * **Do you have a rollback plan?** What SQL would you run to undo this migration? Write it down before you deploy.
> * **Are you using `CONCURRENTLY` for index creation?** On large tables, index creation locks the table. Use `CREATE INDEX CONCURRENTLY` in PostgreSQL.
> * **Are you batching large data migrations?** Do not update millions of rows in a single transaction. Batch them.

<br />

##### **What comes next**
We now know how to make database changes safely, deploy application code without downtime, and roll
back when things go wrong. In the next article, we will explore security in the CI/CD pipeline:
scanning for vulnerabilities, managing secrets, and hardening your deployment process.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps from Zero to Hero: Migraciones de Base de Datos y Deployments Sin Downtime",
  author: "Gabriel Garrido",
  description: "Vamos a explorar por que los cambios en la base de datos son la parte mas riesgosa de los deployments, aprender patrones seguros de migracion con Prisma, e implementar deployments sin downtime en Kubernetes con rolling updates, health checks, y estrategias de rollback...",
  tags: ~w(devops kubernetes databases deployments beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo diecisiete de la serie DevOps from Zero to Hero. En los articulos anteriores
construimos un pipeline completo de CI/CD, configuramos observabilidad, y desplegamos nuestra API de
TypeScript en Kubernetes. Todo funciona, el pipeline esta verde, y los deploys salen bien. Pero hay
un tema que estuvimos esquivando en silencio: la base de datos.

<br />

Desplegar codigo nuevo de la aplicacion es relativamente sencillo. Construis una imagen nueva, la
desplegás, y si algo sale mal, haces rollback. Pero los cambios en la base de datos son diferentes.
Son stateful. No podes simplemente "deshacer" un drop de columna. Afectan a todas las instancias de
tu aplicacion simultaneamente. Y si te equivocas en el orden, podes tirar abajo todo tu servicio.

<br />

En este articulo vamos a cubrir que son las migraciones de base de datos y como funcionan, como
escribir migraciones seguras usando Prisma, el patron expand-contract para hacer cambios de esquema
retrocompatibles, estrategias de deployment sin downtime en Kubernetes, health checks y readiness
probes, y estrategias de rollback para cuando las cosas salen mal. Al final, vas a saber como
enviar cambios de base de datos con confianza, incluso bajo trafico de produccion.

<br />

Vamos a meternos de lleno.

<br />

##### **Por que los cambios en la base de datos son la parte mas riesgosa de los deployments**
El codigo de la aplicacion es stateless. Si desplegás una version mala, haces rollback a la imagen
anterior del contenedor y el problema desaparece. El codigo viejo corre exactamente como antes. Pero
las bases de datos son stateful. Una vez que dropeas una columna, esos datos se perdieron. Una vez
que renombras una tabla, cada query que referencia el nombre viejo se rompe al instante.

<br />

Esto es lo que hace que los cambios de base de datos sean tan peligrosos:

<br />

> * **Son estado compartido**: Cada pod, cada instancia, cada replica lee de la misma base de datos. Un cambio de esquema los afecta a todos de una vez. No podes hacer un rollout gradual de un cambio de base de datos como lo haces con codigo de aplicacion.
> * **Son dificiles de revertir**: Agregar una columna es facil de deshacer (la dropeas). Pero dropear una columna, cambiar un tipo de columna, o borrar datos? Esas operaciones son destructivas. No podes "desborrar" una columna y recuperar los datos.
> * **El orden importa**: Si tu codigo espera una columna que todavia no existe, se rompe. Si tu migracion remueve una columna que el codigo viejo todavia referencia, se rompe. La secuencia entre deploys de codigo y cambios de esquema es critica.
> * **Toman locks**: Muchos cambios de esquema (especialmente en tablas grandes) adquieren locks que bloquean lecturas o escrituras. Una migracion que tarda 30 segundos en tu base de datos de desarrollo puede tardar 30 minutos en una tabla de produccion con millones de filas, bloqueando todo el trafico.

<br />

El desafio central es este: durante un deployment, vas a tener codigo viejo y codigo nuevo corriendo
al mismo tiempo. Tu esquema de base de datos debe ser compatible con ambas versiones simultaneamente.
Esta restriccion guia cada decision que vamos a tomar en este articulo.

<br />

##### **Fundamentos de migraciones**
Una migracion de base de datos es un cambio versionado e incremental a tu esquema de base de datos.
En lugar de ejecutar sentencias SQL manualmente contra tu base de datos, escribis archivos de
migracion que describen el cambio, y una herramienta de migracion los aplica en orden.

<br />

Cada migracion tiene dos partes:

<br />

> * **Up**: El cambio hacia adelante. Crear una tabla, agregar una columna, crear un indice. Esto es lo que se ejecuta cuando aplicas la migracion.
> * **Down**: El cambio inverso. Dropear la tabla, remover la columna, remover el indice. Esto es lo que se ejecuta cuando haces rollback de la migracion.

<br />

Los archivos de migracion tipicamente se nombran con un timestamp o numero de secuencia para que la
herramienta sepa en que orden ejecutarlos:

<br />

```bash
migrations/
  20260601120000_create_users_table/
    migration.sql
  20260602090000_add_email_to_orders/
    migration.sql
  20260603140000_create_audit_log/
    migration.sql
```

<br />

La herramienta de migracion lleva registro de cuales migraciones fueron aplicadas en una tabla
especial (generalmente llamada `_prisma_migrations` o `schema_migrations`). Cuando ejecutas
`migrate`, chequea cuales migraciones estan pendientes y las aplica en orden. Esto te da un
historial completo y auditable de cada cambio de esquema, la capacidad de reproducir tu esquema
de base de datos desde cero, y un mecanismo para revertir cambios cuando sea necesario.

<br />

##### **Configurando migraciones con Prisma**
Vamos a usar Prisma como nuestro ORM y herramienta de migracion de TypeScript. Prisma tiene un
enfoque diferente al de las herramientas de migracion tradicionales: vos definis tu esquema en un
archivo declarativo, y Prisma genera las migraciones SQL por vos.

<br />

Primero, instala Prisma en tu proyecto:

<br />

```bash
npm install prisma --save-dev
npm install @prisma/client

# Inicializar Prisma con PostgreSQL
npx prisma init --datasource-provider postgresql
```

<br />

Esto crea un archivo `prisma/schema.prisma`. Definamos nuestro primer modelo:

<br />

```typescript
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  name      String
  email     String   @unique
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  orders    Order[]
}

model Order {
  id        Int      @id @default(autoincrement())
  amount    Float
  status    String   @default("pending")
  userId    Int
  user      User     @relation(fields: [userId], references: [id])
  createdAt DateTime @default(now())
}
```

<br />

Ahora genera la primera migracion:

<br />

```bash
npx prisma migrate dev --name create_users_and_orders
```

<br />

Prisma compara tu archivo de esquema con el estado actual de la base de datos, genera el SQL, y lo
aplica. La migracion generada se ve asi:

<br />

```sql
-- CreateTable
CREATE TABLE "User" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Order" (
    "id" SERIAL NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "userId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Order_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- AddForeignKey
ALTER TABLE "Order" ADD CONSTRAINT "Order_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
```

<br />

Ahora agreguemos una columna. Supongamos que necesitamos un campo `phone` en el modelo `User`:

<br />

```typescript
model User {
  id        Int      @id @default(autoincrement())
  name      String
  email     String   @unique
  phone     String?  // nullable, asi las filas existentes estan bien
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  orders    Order[]
}
```

<br />

```bash
npx prisma migrate dev --name add_phone_to_users
```

<br />

El SQL generado:

<br />

```sql
-- AlterTable
ALTER TABLE "User" ADD COLUMN "phone" TEXT;
```

<br />

Fijate que la columna es nullable (`TEXT` sin `NOT NULL`). Esto es importante. Si la hicieramos
obligatoria, la migracion fallaria porque las filas existentes no tendrian un valor para la nueva
columna. Hacer las columnas nuevas nullables (o darles un valor por defecto) es uno de los patrones
mas basicos de migraciones seguras.

<br />

Ahora renombremos una columna. Supongamos que queremos renombrar `name` a `fullName`. En Prisma,
usas el atributo `@map` para renombrar la columna de la base de datos sin cambiar el nombre del
campo en Prisma:

<br />

```typescript
model User {
  id        Int      @id @default(autoincrement())
  fullName  String   @map("full_name")
  email     String   @unique
  phone     String?
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  orders    Order[]

  @@map("users")
}
```

<br />

Pero pará. Si simplemente renombramos la columna directamente, cualquier codigo de la aplicacion
que todavia consulte el nombre viejo de la columna se va a romper. Este es exactamente el tipo de
operacion peligrosa que necesitamos manejar con el patron expand-contract, que vamos a cubrir a
continuacion.

<br />

##### **Patrones de migracion seguros**
La regla de oro de las migraciones seguras es: nunca hagas un cambio que rompa cosas en un solo
deploy. En cambio, dividilo en multiples pasos donde cada paso es retrocompatible.

<br />

Estos son los patrones que deberias seguir:

<br />

**Agregar una columna (seguro)**

<br />

Agregar una columna nullable o una columna con valor por defecto siempre es seguro. El codigo viejo
ignora la nueva columna. El codigo nuevo puede usarla.

<br />

```sql
-- Seguro: columna nullable, el codigo viejo la ignora
ALTER TABLE "User" ADD COLUMN "phone" TEXT;

-- Seguro: columna con default, el codigo viejo la ignora
ALTER TABLE "Order" ADD COLUMN "currency" TEXT NOT NULL DEFAULT 'USD';
```

<br />

**Agregar un indice (seguro, pero cuidado con el tiempo de lock)**

<br />

Crear un indice es seguro desde el punto de vista de compatibilidad, pero en tablas grandes puede
lockear la tabla por mucho tiempo. Usa `CONCURRENTLY` en PostgreSQL para evitar bloquear escrituras:

<br />

```sql
-- Esto lockea la tabla hasta que el indice se construye (peligroso en tablas grandes)
CREATE INDEX idx_orders_user_id ON "Order" ("userId");

-- Esto construye el indice sin lockear (seguro para produccion)
CREATE INDEX CONCURRENTLY idx_orders_user_id ON "Order" ("userId");
```

<br />

**Crear una tabla nueva (seguro)**

<br />

Las tablas nuevas no afectan al codigo existente para nada. Siempre seguro.

<br />

**Dropear una columna (peligroso si se hace mal)**

<br />

Si dropeas una columna que el codigo viejo todavia lee, esas queries van a fallar. Nunca dropees
una columna en el mismo deploy que todavia la referencia.

<br />

**Renombrar una columna (peligroso si se hace en un solo paso)**

<br />

Un rename de columna es esencialmente un drop mas un add desde la perspectiva de la aplicacion. El
codigo viejo consulta el nombre viejo. El codigo nuevo consulta el nombre nuevo. Durante un rolling
update, ambas versiones corren simultaneamente, y una de ellas siempre va a estar rota.

<br />

##### **El patron expand-contract**
El patron expand-contract es la forma estandar de hacer cambios de esquema que rompen cosas de
manera segura. Funciona en tres fases:

<br />

**Fase 1: Expand (agregar lo nuevo)**

<br />

Agrega la nueva columna al lado de la vieja. Actualiza tu codigo para escribir en ambas columnas.
Desplegá este cambio.

<br />

```sql
-- Migracion 1: Agregar la nueva columna
ALTER TABLE "users" ADD COLUMN "full_name" TEXT;
```

<br />

```typescript
// El codigo de la aplicacion escribe en ambas columnas
async function updateUser(id: number, name: string) {
  await prisma.user.update({
    where: { id },
    data: {
      name: name,      // columna vieja (para codigo viejo que todavia la lee)
      fullName: name,  // columna nueva (para codigo nuevo)
    },
  });
}
```

<br />

**Fase 2: Migrar datos**

<br />

Backfillá la nueva columna con datos de la columna vieja. Esto puede ser un script de migracion o
un job en background.

<br />

```sql
-- Migracion 2: Backfill de datos existentes
UPDATE "users" SET "full_name" = "name" WHERE "full_name" IS NULL;
```

<br />

En este punto, ambas columnas tienen los mismos datos. El codigo viejo lee de `name`, el codigo
nuevo lee de `full_name`, y todo funciona.

<br />

**Fase 3: Contract (remover lo viejo)**

<br />

Una vez que todo el codigo de la aplicacion fue actualizado para usar la nueva columna, y
verificaste que ninguna query referencia la columna vieja, podes dropearla.

<br />

```sql
-- Migracion 3: Dropear la columna vieja (solo despues de que todo el codigo use full_name)
ALTER TABLE "users" DROP COLUMN "name";
```

<br />

Este enfoque de tres fases significa que en cada punto durante el rollout, el esquema de la base de
datos es compatible con ambas versiones (vieja y nueva) de tu codigo. Sin downtime, sin errores,
sin perdida de datos.

<br />

Aca está la linea de tiempo:

<br />

```bash
# Linea de tiempo expand-contract
#
# Deploy 1: Agregar columna "full_name", escribir en ambas columnas
#   Codigo viejo: lee "name"       -> funciona (la columna todavia existe)
#   Codigo nuevo: lee "full_name"  -> funciona (la columna recien se agrego)
#
# Deploy 2: Backfill "full_name" desde "name"
#   Todas las filas ahora tienen ambas columnas pobladas
#
# Deploy 3: Remover todas las lecturas de "name", dropear columna
#   Codigo viejo: ya no existe (rollout completo)
#   Codigo nuevo: lee "full_name"  -> funciona (unica columna restante)
```

<br />

Si, esto toma tres deploys en lugar de uno. Ese es el trade-off. La seguridad cuesta velocidad,
pero te salva de incidentes a las 3 de la mañana.

<br />

##### **Patrones peligrosos a evitar**
Estos son los cambios de esquema que causan la mayor cantidad de caidas, y como manejarlos en
su lugar:

<br />

> * **Renombrar una columna en un solo deploy**: Es un drop mas un add. Usa expand-contract en su lugar. Agrega la nueva columna, backfillá, actualizá el codigo, y despues dropeá la columna vieja.
> * **Cambiar un tipo de columna in-place**: Cambiar `VARCHAR(50)` a `TEXT` puede parecer inofensivo, pero cambiar `TEXT` a `INTEGER` va a fallar si alguna fila contiene datos no numericos. Agrega una nueva columna con el tipo nuevo, backfillá con conversion de tipo, cambiá el codigo, y despues dropeá la columna vieja.
> * **Agregar una restriccion NOT NULL sin default**: Si le agregas `NOT NULL` a una columna existente que tiene valores null, la migracion va a fallar. Primero backfillá todos los nulls, despues agrega la restriccion.
> * **Dropear una tabla que todavia es referenciada**: Las restricciones de foreign key van a bloquear el drop, pero el codigo de la aplicacion se va a romper. Primero removélas del codigo, despues dropeá.
> * **Ejecutar migraciones de datos grandes en la transaccion principal**: Actualizar millones de filas en una sola transaccion lockea la tabla y puede causar timeouts. Procesá tus updates en lotes (1000-5000 filas por vez) con pausas pequeñas entre lotes.

<br />

Una regla util: si una migracion no se puede revertir con un simple "undo" de migracion, es
peligrosa y necesita el tratamiento expand-contract.

<br />

##### **Deployments sin downtime en Kubernetes**
Ahora que sabemos como manejar cambios de base de datos de forma segura, veamos la otra mitad del
rompecabezas: desplegar codigo de la aplicacion sin tirar requests. Kubernetes te da varios
mecanismos para esto.

<br />

**Rolling updates**

<br />

La estrategia de deployment por defecto en Kubernetes es `RollingUpdate`. Reemplaza gradualmente
pods viejos con pods nuevos, asegurandose de que siempre haya algunos pods disponibles para
servir trafico.

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # Como maximo 1 pod extra durante el rollout
      maxUnavailable: 0   # Nunca tener menos de 3 pods sanos
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: myapp:v2
          ports:
            - containerPort: 3000
```

<br />

Con `maxSurge: 1` y `maxUnavailable: 0`, Kubernetes va a:

<br />

> * **Paso 1**: Crear 1 pod nuevo (v2). Ahora tenes 3 viejos + 1 nuevo = 4 pods en total.
> * **Paso 2**: Esperar hasta que el pod nuevo pase su readiness probe.
> * **Paso 3**: Terminar 1 pod viejo (v1). Ahora tenes 2 viejos + 1 nuevo = 3 pods.
> * **Paso 4**: Crear otro pod nuevo (v2). Ahora tenes 2 viejos + 2 nuevos = 4 pods.
> * **Repetir** hasta que todos los pods esten corriendo v2.

<br />

Durante este proceso, tanto los pods v1 como v2 estan sirviendo trafico. Esta es exactamente la
razon por la que tu esquema de base de datos debe ser compatible con ambas versiones.

<br />

**La estrategia Recreate**

<br />

La estrategia `Recreate` mata todos los pods viejos antes de crear los nuevos. Esto implica
downtime, asi que solo deberias usarla cuando tu aplicacion no puede correr dos versiones
simultaneamente (por ejemplo, si mantiene un lock exclusivo sobre un recurso).

<br />

```yaml
strategy:
  type: Recreate
```

<br />

Para casi todas las aplicaciones web, `RollingUpdate` es lo que queres.

<br />

##### **Health checks: liveness, readiness, y startup probes**
Los probes son la forma en que Kubernetes sabe si tu pod esta sano. Hay tres tipos, y cada uno
sirve para un proposito diferente:

<br />

> * **Readiness probe**: "Este pod esta listo para recibir trafico?" Kubernetes solo envia trafico a pods que pasan su readiness probe. Durante un deployment, los pods nuevos no van a recibir trafico hasta que esten listos. Este es el probe mas importante para deployments sin downtime.
> * **Liveness probe**: "Este pod sigue vivo?" Si un pod falla su liveness probe, Kubernetes lo reinicia. Usalo para recuperarte de deadlocks o procesos trabados. Cuidado: si tu liveness probe es muy agresivo, Kubernetes va a reiniciar pods que simplemente estan lentos, creando un crash loop.
> * **Startup probe**: "Este pod termino de arrancar?" Esto es para aplicaciones con un arranque lento (cargando caches grandes, corriendo migraciones). El startup probe corre primero, y los liveness/readiness probes no arrancan hasta que pase.

<br />

Asi se configuran los tres:

<br />

```yaml
containers:
  - name: myapp
    image: myapp:v2
    ports:
      - containerPort: 3000
    readinessProbe:
      httpGet:
        path: /health/ready
        port: 3000
      initialDelaySeconds: 5
      periodSeconds: 10
      failureThreshold: 3
    livenessProbe:
      httpGet:
        path: /health/live
        port: 3000
      initialDelaySeconds: 15
      periodSeconds: 20
      failureThreshold: 3
    startupProbe:
      httpGet:
        path: /health/started
        port: 3000
      failureThreshold: 30
      periodSeconds: 10
```

<br />

Y asi se ven los endpoints de health check en tu API de TypeScript:

<br />

```typescript
// Endpoints de health check
app.get("/health/live", (req, res) => {
  // Liveness: el proceso esta corriendo?
  // Mantenelo simple. Si este endpoint responde, el proceso esta vivo.
  res.status(200).json({ status: "alive" });
});

app.get("/health/ready", async (req, res) => {
  // Readiness: este pod puede servir trafico?
  // Chequear que todas las dependencias sean alcanzables.
  try {
    await prisma.$queryRaw`SELECT 1`;  // la base de datos es alcanzable
    res.status(200).json({ status: "ready" });
  } catch (error) {
    res.status(503).json({ status: "not ready", error: "database unreachable" });
  }
});

app.get("/health/started", (req, res) => {
  // Startup: la app termino de inicializar?
  if (appIsInitialized) {
    res.status(200).json({ status: "started" });
  } else {
    res.status(503).json({ status: "starting" });
  }
});
```

<br />

Un error comun es hacer el liveness probe demasiado estricto. Si tu liveness probe chequea la base
de datos, y la base de datos tiene un breve problema de red, Kubernetes va a reiniciar todos tus
pods de una, empeorando mucho la situacion. Mantene los liveness probes simples (solo "el proceso
esta corriendo?") y usa readiness probes para chequeos de dependencias.

<br />

##### **Shutdown graceful: preStop hooks y connection draining**
Cuando Kubernetes termina un pod durante un rolling update, envia una señal `SIGTERM`. Tu
aplicacion deberia capturar esta señal y dejar de aceptar requests nuevos mientras termina los
requests en curso. Pero hay una race condition: Kubernetes remueve el pod de los endpoints del
servicio al mismo tiempo que envia `SIGTERM`, y la remocion del endpoint tarda un momento en
propagarse. Durante esa ventana, el trafico puede seguir siendo ruteado a un pod que se esta
apagando.

<br />

La solucion es un hook `preStop` que agrega una pequeña demora:

<br />

```yaml
containers:
  - name: myapp
    image: myapp:v2
    lifecycle:
      preStop:
        exec:
          command: ["sh", "-c", "sleep 10"]
```

<br />

Esto le dice a Kubernetes que espere 10 segundos antes de enviar `SIGTERM`. Durante esos 10
segundos, el pod es removido de los endpoints del servicio, asi que no se rutea trafico nuevo hacia
el. Despues del sleep, se envia `SIGTERM` y la aplicacion puede apagarse de forma graceful.

<br />

En tu aplicacion TypeScript, manejá la señal de shutdown:

<br />

```typescript
// Handler de shutdown graceful
process.on("SIGTERM", () => {
  console.log("SIGTERM recibido. Iniciando shutdown graceful...");

  // Dejar de aceptar conexiones nuevas
  server.close(() => {
    console.log("Servidor HTTP cerrado. Limpiando...");

    // Cerrar conexiones de base de datos
    prisma.$disconnect().then(() => {
      console.log("Base de datos desconectada. Saliendo.");
      process.exit(0);
    });
  });

  // Forzar salida despues de 30 segundos si el shutdown graceful se traba
  setTimeout(() => {
    console.error("Shutdown graceful excedio el timeout. Forzando salida.");
    process.exit(1);
  }, 30000);
});
```

<br />

Tambien, configura `terminationGracePeriodSeconds` en el spec del pod para darle a tu aplicacion
suficiente tiempo para drenar. El default son 30 segundos, pero ajustalo segun cuanto tardan tus
requests mas largos:

<br />

```yaml
spec:
  terminationGracePeriodSeconds: 60
  containers:
    - name: myapp
      # ...
```

<br />

##### **PodDisruptionBudgets**
Un PodDisruptionBudget (PDB) le dice a Kubernetes cuantos pods deben permanecer disponibles durante
disrupciones voluntarias como drains de nodos, upgrades de cluster, o scale-downs del autoscaler.
Sin un PDB, Kubernetes podria drenar todos tus nodos de una durante un upgrade de cluster,
tirando abajo todos los pods simultaneamente.

<br />

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
spec:
  minAvailable: 2    # Al menos 2 pods deben estar corriendo siempre
  selector:
    matchLabels:
      app: myapp
```

<br />

Tambien podes usar `maxUnavailable` en lugar de `minAvailable`:

<br />

```yaml
spec:
  maxUnavailable: 1   # Como maximo 1 pod puede estar caido a la vez
```

<br />

Para un deployment con 3 replicas, `minAvailable: 2` y `maxUnavailable: 1` son equivalentes. Usa
el que se lea mas claro para tu equipo.

<br />

##### **Deployments blue-green**
Los deployments blue-green toman un enfoque diferente a los rolling updates. En lugar de reemplazar
pods gradualmente, corres dos entornos completos simultaneamente: el entorno "blue" (produccion
actual) y el entorno "green" (version nueva). Una vez que el entorno green esta validado, cambias
el trafico de blue a green en un solo paso.

<br />

Asi se implementa blue-green con servicios de Kubernetes:

<br />

```yaml
# Deployment Blue (produccion actual, corriendo v1)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue
    spec:
      containers:
        - name: myapp
          image: myapp:v1
---
# Deployment Green (version nueva, corriendo v2)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
        - name: myapp
          image: myapp:v2
---
# Service (apunta a blue inicialmente)
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
    version: blue    # Cambialo a "green" para switchear el trafico
  ports:
    - port: 80
      targetPort: 3000
```

<br />

Para switchear el trafico, actualizas el selector del servicio de `version: blue` a
`version: green`. Todo el trafico se mueve de una. Si algo esta mal, switcheas de vuelta a blue.

<br />

> * **Cuando usar blue-green**: Cuando necesitas rollback instantaneo (un cambio de label), cuando queres validar la version nueva con patrones de trafico real antes de commitear, o cuando tu aplicacion no tolera versiones mezcladas.
> * **Cuando quedarse con rolling updates**: Para la mayoria de los deployments estandar. Blue-green requiere el doble de recursos (ambos entornos corren simultaneamente) y agrega complejidad operacional.

<br />

##### **Estrategias de rollback**
Sin importar lo cuidadoso que seas, las cosas van a salir mal. Tener un plan de rollback no es
opcional. Estas son las tres estrategias principales:

<br />

**Rollback de Kubernetes**

<br />

Kubernetes mantiene un historial de tus deployments. Podes hacer rollback a una version anterior
con un solo comando:

<br />

```bash
# Ver historial de rollout
kubectl rollout history deployment/myapp

# Rollback a la version anterior
kubectl rollout undo deployment/myapp

# Rollback a una revision especifica
kubectl rollout undo deployment/myapp --to-revision=3

# Ver el progreso del rollback
kubectl rollout status deployment/myapp
```

<br />

Esto solo hace rollback del codigo de la aplicacion (la imagen del contenedor). No hace rollback
de las migraciones de base de datos. Si tu migracion fue aditiva (agregar una columna), el codigo
viejo simplemente ignora la nueva columna, y no hay nada que revertir. Si tu migracion fue
destructiva (dropear una columna), necesitas un rollback de base de datos.

<br />

**Rollback de base de datos**

<br />

Prisma no tiene un comando built-in de "deshacer ultima migracion" para produccion. En produccion,
escribis una nueva migracion que revierte el cambio:

<br />

```bash
# En desarrollo, podes resetear (destruye todos los datos)
npx prisma migrate reset

# En produccion, crea una nueva migracion de "undo"
npx prisma migrate dev --name undo_add_phone_to_users
```

<br />

La migracion de "undo" es simplemente otra migracion que revierte el cambio anterior:

<br />

```sql
-- Migracion de undo: remover la columna phone
ALTER TABLE "User" DROP COLUMN "phone";
```

<br />

Esta es otra razon para preferir migraciones aditivas. Agregar una columna es facil de deshacer
(la dropeas). Dropear una columna es imposible de deshacer (los datos se perdieron). Si seguis el
patron expand-contract, tu "undo" siempre es simplemente "dropear la columna que agregaste."

<br />

**Feature flags como alternativa a los rollbacks**

<br />

En lugar de hacer rollback de codigo o cambios de base de datos, podes usar feature flags para
deshabilitar la funcionalidad nueva sin cambiar el codigo desplegado:

<br />

```typescript
// Chequeo de feature flag
app.get("/api/orders", async (req, res) => {
  const orders = await prisma.order.findMany({
    include: {
      user: true,
    },
  });

  if (featureFlags.isEnabled("show-order-currency")) {
    // Comportamiento nuevo: incluir campo currency
    return res.json(orders.map(o => ({
      ...o,
      currency: o.currency ?? "USD",
    })));
  }

  // Comportamiento viejo: sin campo currency
  return res.json(orders);
});
```

<br />

Los feature flags te permiten desacoplar el deployment del release. Desplegás el codigo (incluyendo
la migracion), pero la funcionalidad nueva esta detras de un flag. Si algo sale mal, apagás el flag.
No necesitas rollback, ni redesplegar, ni deshacer nada en la base de datos.

<br />

##### **Ejemplo practico: agregar una columna bajo trafico de produccion**
Juntemos todo con un escenario real. Necesitamos agregar una columna `currency` a la tabla `Order`.
La API esta sirviendo trafico, y no podemos permitirnos ningun downtime.

<br />

**Paso 1: Escribir la migracion**

<br />

Actualiza el esquema de Prisma:

<br />

```typescript
model Order {
  id        Int      @id @default(autoincrement())
  amount    Float
  status    String   @default("pending")
  currency  String   @default("USD")   // nueva columna con default
  userId    Int
  user      User     @relation(fields: [userId], references: [id])
  createdAt DateTime @default(now())
}
```

<br />

Genera y revisa la migracion:

<br />

```bash
npx prisma migrate dev --name add_currency_to_orders
```

<br />

SQL generado:

<br />

```sql
ALTER TABLE "Order" ADD COLUMN "currency" TEXT NOT NULL DEFAULT 'USD';
```

<br />

Esto es seguro porque la columna tiene un valor por defecto, asi que las filas existentes reciben
`'USD'` automaticamente, y el codigo viejo que no conoce la columna simplemente la ignora.

<br />

**Paso 2: Actualizar el codigo de la aplicacion**

<br />

Actualiza la API para usar la nueva columna:

<br />

```typescript
// Endpoint de creacion de ordenes actualizado
app.post("/api/orders", async (req, res) => {
  const { amount, userId, currency } = req.body;

  const order = await prisma.order.create({
    data: {
      amount,
      userId,
      currency: currency ?? "USD",   // usar currency provista o default
    },
  });

  res.status(201).json(order);
});
```

<br />

**Paso 3: Correr la migracion en CI/CD**

<br />

Agrega un paso de migracion a tu pipeline de CI/CD que corra antes del deployment de la aplicacion:

<br />

```yaml
# En tu workflow de GitHub Actions
jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Install dependencies
        run: npm ci

      - name: Run database migrations
        run: npx prisma migrate deploy
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}

  deploy:
    needs: migrate    # Desplegar solo despues de que las migraciones pasen
    runs-on: ubuntu-latest
    steps:
      - name: Update deployment image
        run: |
          kubectl set image deployment/myapp \
            myapp=myapp:${{ github.sha }}

      - name: Wait for rollout
        run: kubectl rollout status deployment/myapp --timeout=300s
```

<br />

**Paso 4: Verificar**

<br />

Despues del deploy, verifica que todo este funcionando:

<br />

```bash
# Chequear que la migracion fue aplicada
npx prisma migrate status

# Testear la API
curl -X POST https://api.example.com/api/orders \
  -H "Content-Type: application/json" \
  -d '{"amount": 29.99, "userId": 1, "currency": "EUR"}'

# Verificar que la respuesta incluya el currency
curl https://api.example.com/api/orders/1
```

<br />

Como usamos un cambio aditivo con valor por defecto, todo el proceso fue sin downtime. Los pods
viejos que no conocen la columna `currency` siguieron sirviendo trafico mientras los pods nuevos
se desplegaban. Sin conflictos, sin errores, sin interrupcion.

<br />

##### **Checklist de migraciones**
Antes de correr cualquier migracion en produccion, pasa por este checklist:

<br />

> * **La migracion es aditiva?** Agregar columnas (nullables o con defaults), agregar tablas, y agregar indices son seguros. Todo lo demas necesita cuidado extra.
> * **El codigo viejo puede funcionar con el nuevo esquema?** Durante un rolling update, codigo viejo y nuevo corren simultaneamente. Asegurate de que el codigo viejo no se rompa.
> * **El codigo nuevo puede funcionar con el esquema viejo?** Si la migracion falla o se atrasa, el codigo nuevo puede seguir funcionando?
> * **Probaste la migracion en una copia de datos de produccion?** Tu base de datos de desarrollo tiene 100 filas. Produccion tiene 10 millones. Lo que tarda 1 segundo en dev puede tardar 10 minutos en produccion.
> * **Tenes un plan de rollback?** Que SQL ejecutarias para deshacer esta migracion? Escribilo antes de desplegar.
> * **Estas usando `CONCURRENTLY` para crear indices?** En tablas grandes, la creacion de indices lockea la tabla. Usa `CREATE INDEX CONCURRENTLY` en PostgreSQL.
> * **Estas procesando migraciones de datos grandes en lotes?** No actualices millones de filas en una sola transaccion. Hacelo en lotes.

<br />

##### **Que viene despues**
Ahora sabemos como hacer cambios de base de datos de forma segura, desplegar codigo de la
aplicacion sin downtime, y hacer rollback cuando las cosas salen mal. En el proximo articulo, vamos
a explorar la seguridad en el pipeline de CI/CD: escaneo de vulnerabilidades, gestion de secretos,
y hardening de tu proceso de deployment.

<br />

Espero que te haya resultado util y que lo hayas disfrutado, hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que lo
pueda corregir.

Tambien, podes ver el codigo fuente y los cambios en los [fuentes aca](https://github.com/kainlite/tr)

<br />
