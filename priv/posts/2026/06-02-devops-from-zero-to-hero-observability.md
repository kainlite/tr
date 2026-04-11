%{
  title: "DevOps from Zero to Hero: Observability in Kubernetes",
  author: "Gabriel Garrido",
  description: "We will explore the three pillars of observability: logs, metrics, and traces. Learn structured logging, Prometheus and Grafana setup on EKS, basic PromQL, distributed tracing with OpenTelemetry, and how to instrument a TypeScript API...",
  tags: ~w(devops kubernetes observability prometheus grafana beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article fifteen of the DevOps from Zero to Hero series. In the previous articles we
deployed our TypeScript API to Kubernetes and packaged it with Helm. Everything is running, the pods
are green, and life is good. But then someone asks: "Is the API actually healthy? How do we know if
response times are getting worse? What happened at 3am when users started complaining?"

<br />

Without observability, you are flying blind. You deployed your app, but you have no idea what is
happening inside it. Observability gives you the ability to understand the internal state of your
system by examining the data it produces. It is the difference between "something is broken" and
"the /orders endpoint is returning 500 errors because the database connection pool is exhausted."

<br />

In this article we will cover the three pillars of observability (logs, metrics, and traces), set up
Prometheus and Grafana on EKS using Helm, build a basic dashboard, instrument our TypeScript API with
structured logging and a metrics endpoint, configure a simple alert, and walk through the observability
workflow you will use during real incidents. This is a beginner-friendly introduction. If you want to
go deeper into topics like SLO-based alerting, Loki for log aggregation, or advanced OpenTelemetry
patterns, check out the
[SRE Observability Deep Dive](/blog/sre-observability-deep-dive-traces-logs-and-metrics) from the
SRE series.

<br />

Let's get into it.

<br />

##### **The three pillars of observability**
Observability is built on three types of telemetry data. Each one answers a different question, and
you need all three to debug production issues effectively.

<br />

> * **Logs**: Discrete events that tell you what happened. "Request abc123 failed with a 500 error at 14:32:05." Logs give you the richest context because they can include arbitrary details like request bodies, stack traces, and user IDs.
> * **Metrics**: Numerical measurements over time. "The API handled 150 requests per second with a p99 latency of 200ms." Metrics are cheap to store, fast to query, and perfect for dashboards and alerts.
> * **Traces**: The path a request takes through your system. "This request hit the API gateway, then the orders service, then the database, and the slow part was the database query." Traces are essential when you have multiple services talking to each other.

<br />

Think of it this way: metrics tell you something is wrong, traces tell you where in the system it is
wrong, and logs tell you why it is wrong. Here is the flow:

<br />

```bash
# The observability workflow during an incident:
#
# 1. ALERT (from metrics): "Error rate > 5% for the last 5 minutes"
#    -> You know SOMETHING is wrong
#
# 2. DASHBOARD (metrics): Check Grafana, see /orders endpoint has high error rate
#    -> You know WHAT is wrong
#
# 3. TRACES: Find failing requests, see they all fail at the database call
#    -> You know WHERE it is wrong
#
# 4. LOGS: Check the database service logs: "ERROR: too many connections"
#    -> You know WHY it is wrong
```

<br />

We will cover each pillar in detail, starting with logs because they are the most familiar.

<br />

##### **Logs: structured logging**
If you have ever used `console.log("something broke")` in production, you know the problem. When you
have thousands of log lines flowing through your system, finding the relevant one is like searching
for a needle in a haystack. Unstructured logs (plain text strings) are hard to search, hard to filter,
and hard to aggregate.

<br />

Structured logging solves this by writing logs as JSON objects with consistent fields. Instead of:

<br />

```plaintext
[2026-06-02 14:32:05] ERROR: Failed to process order 12345 for user john@example.com
```

<br />

You write:

<br />

```json
{
  "timestamp": "2026-06-02T14:32:05.123Z",
  "level": "error",
  "message": "Failed to process order",
  "orderId": "12345",
  "userId": "john@example.com",
  "service": "orders-api",
  "traceId": "abc123def456",
  "duration_ms": 1523
}
```

<br />

Now you can search for all errors related to a specific user, a specific order, or a specific trace.
You can count how many errors happened per service. You can correlate logs with traces using the
traceId field. This is the power of structured logging.

<br />

**Log levels** define the severity of a log entry. Use them consistently:

<br />

> * **error**: Something failed and needs attention. A request returned a 500, a database query timed out, an external API is unreachable.
> * **warn**: Something unexpected happened but the system handled it. A retry succeeded, a cache miss occurred, a deprecated endpoint was called.
> * **info**: Normal operations worth recording. A request was processed successfully, a user logged in, a background job completed.
> * **debug**: Detailed information useful during development. Request payloads, SQL queries, internal state. Disable this in production unless you are actively debugging.

<br />

Let's add structured logging to our TypeScript API using `pino`, which is the fastest JSON logger
for Node.js:

<br />

```bash
# Install pino and the pretty-printer for local development
npm install pino pino-http
npm install -D pino-pretty
```

<br />

```typescript
// src/logger.ts
import pino from "pino";

const logger = pino({
  level: process.env.LOG_LEVEL || "info",
  // In production, output raw JSON. Locally, use pino-pretty for readability.
  transport:
    process.env.NODE_ENV !== "production"
      ? { target: "pino-pretty", options: { colorize: true } }
      : undefined,
  // Add default fields to every log entry
  base: {
    service: "task-api",
    version: process.env.APP_VERSION || "unknown",
  },
});

export default logger;
```

<br />

```typescript
// src/app.ts
import express from "express";
import pinoHttp from "pino-http";
import logger from "./logger";

const app = express();

// Automatically log every HTTP request with method, URL, status, and duration
app.use(pinoHttp({ logger }));

app.get("/tasks", async (req, res) => {
  try {
    const tasks = await db.query("SELECT * FROM tasks");
    // Info-level log with structured context
    logger.info({ taskCount: tasks.length }, "Tasks retrieved successfully");
    res.json(tasks);
  } catch (error) {
    // Error-level log with the error object and request context
    logger.error(
      { err: error, path: req.path, method: req.method },
      "Failed to retrieve tasks"
    );
    res.status(500).json({ error: "Internal server error" });
  }
});
```

<br />

With `pino-http`, every request automatically gets a log entry like this:

<br />

```json
{
  "level": 30,
  "time": 1748870525123,
  "service": "task-api",
  "req": { "method": "GET", "url": "/tasks" },
  "res": { "statusCode": 200 },
  "responseTime": 45,
  "msg": "request completed"
}
```

<br />

This is exactly the kind of data you can search and filter in a log aggregation system like Loki,
Elasticsearch, or CloudWatch Logs. You can query things like "show me all requests where
responseTime > 1000" or "show me all error-level logs from the task-api service in the last hour."

<br />

##### **Metrics: counting what matters**
While logs tell you about individual events, metrics tell you about the overall behavior of your
system over time. Metrics are numerical measurements collected at regular intervals.

<br />

There are three core metric types you need to know:

<br />

> * **Counter**: A value that only goes up. Examples: total number of HTTP requests, total number of errors, total bytes transferred. You usually care about the rate of change (requests per second) rather than the raw value.
> * **Gauge**: A value that can go up and down. Examples: current CPU usage, memory usage, number of active connections, queue depth. Gauges represent the current state of something.
> * **Histogram**: Measures the distribution of values. Examples: request duration, response size. Histograms let you answer questions like "what is the 99th percentile latency?" which is far more useful than the average.

<br />

**Prometheus** is the standard metrics system in the Kubernetes ecosystem. It works with a pull
model: instead of your application pushing metrics to a server, Prometheus scrapes your application's
metrics endpoint at regular intervals (usually every 15 or 30 seconds).

<br />

Here is how the flow works:

<br />

```plaintext
Your App (/metrics endpoint)
  |
  v
Prometheus (scrapes every 15s, stores time-series data)
  |
  v
Grafana (queries Prometheus, renders dashboards)
  |
  v
Alertmanager (receives alerts from Prometheus, sends notifications)
```

<br />

Let's add a `/metrics` endpoint to our TypeScript API using the `prom-client` library:

<br />

```bash
npm install prom-client
```

<br />

```typescript
// src/metrics.ts
import client from "prom-client";

// Create a registry to hold all metrics
const register = new client.Registry();

// Add default Node.js metrics (CPU, memory, event loop lag, etc.)
client.collectDefaultMetrics({ register });

// Custom counter: total HTTP requests, labeled by method, path, and status
export const httpRequestsTotal = new client.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "path", "status"] as const,
  registers: [register],
});

// Custom histogram: request duration in seconds
export const httpRequestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Duration of HTTP requests in seconds",
  labelNames: ["method", "path", "status"] as const,
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  registers: [register],
});

// Custom gauge: number of active database connections
export const dbActiveConnections = new client.Gauge({
  name: "db_active_connections",
  help: "Number of active database connections",
  registers: [register],
});

export { register };
```

<br />

```typescript
// src/middleware/metrics.ts
import { Request, Response, NextFunction } from "express";
import { httpRequestsTotal, httpRequestDuration } from "../metrics";

export function metricsMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
) {
  const start = Date.now();

  res.on("finish", () => {
    const duration = (Date.now() - start) / 1000;
    const path = req.route?.path || req.path;
    const labels = {
      method: req.method,
      path: path,
      status: res.statusCode.toString(),
    };

    httpRequestsTotal.inc(labels);
    httpRequestDuration.observe(labels, duration);
  });

  next();
}
```

<br />

```typescript
// src/app.ts - add the metrics endpoint and middleware
import { register } from "./metrics";
import { metricsMiddleware } from "./middleware/metrics";

// Apply metrics middleware to all routes
app.use(metricsMiddleware);

// Expose metrics for Prometheus to scrape
app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});
```

<br />

When Prometheus scrapes `/metrics`, it gets output like this:

<br />

```promql
# HELP http_requests_total Total number of HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/tasks",status="200"} 1523
http_requests_total{method="POST",path="/tasks",status="201"} 47
http_requests_total{method="GET",path="/tasks",status="500"} 3

# HELP http_request_duration_seconds Duration of HTTP requests in seconds
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",path="/tasks",status="200",le="0.05"} 1200
http_request_duration_seconds_bucket{method="GET",path="/tasks",status="200",le="0.1"} 1450
http_request_duration_seconds_bucket{method="GET",path="/tasks",status="200",le="0.25"} 1510
http_request_duration_seconds_bucket{method="GET",path="/tasks",status="200",le="+Inf"} 1523
```

<br />

For Prometheus to discover this endpoint in Kubernetes, you add annotations to your pod or service:

<br />

```yaml
# In your Helm chart's deployment template or values
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "3000"
    prometheus.io/path: "/metrics"
```

<br />

##### **Installing Prometheus and Grafana on EKS**
The easiest way to get Prometheus and Grafana running on Kubernetes is the `kube-prometheus-stack`
Helm chart. This single chart installs Prometheus, Grafana, Alertmanager, node-exporter (for host
metrics), kube-state-metrics (for Kubernetes object metrics), and a bunch of pre-configured
dashboards and alerting rules.

<br />

```bash
# Add the Prometheus community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create a namespace for monitoring
kubectl create namespace monitoring

# Install the kube-prometheus-stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=your-secure-password \
  --set prometheus.prometheusSpec.retention=7d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi
```

<br />

That is it. A single Helm command and you have a full monitoring stack. Let's verify everything is
running:

<br />

```bash
# Check all pods in the monitoring namespace
kubectl get pods -n monitoring

# Expected output:
# NAME                                                     READY   STATUS    RESTARTS   AGE
# alertmanager-monitoring-kube-prometheus-alertmanager-0    2/2     Running   0          2m
# monitoring-grafana-6c4f8d5b7-x2k4f                      3/3     Running   0          2m
# monitoring-kube-prometheus-operator-7d9f5b8c9-abc12      1/1     Running   0          2m
# monitoring-kube-state-metrics-5f8d9b7c6-def34            1/1     Running   0          2m
# monitoring-prometheus-node-exporter-ghij5                1/1     Running   0          2m
# prometheus-monitoring-kube-prometheus-prometheus-0        2/2     Running   0          2m
```

<br />

To access Grafana locally, use port-forwarding:

<br />

```bash
# Forward Grafana to localhost:3001
kubectl port-forward svc/monitoring-grafana 3001:80 -n monitoring

# Open http://localhost:3001 in your browser
# Login: admin / your-secure-password
```

<br />

For production, you would expose Grafana through an Ingress with TLS. Here is a quick values file
for a production-like setup:

<br />

```yaml
# monitoring-values.yaml
grafana:
  adminPassword: "${GRAFANA_ADMIN_PASSWORD}"
  ingress:
    enabled: true
    ingressClassName: alb
    hosts:
      - grafana.yourdomain.com
    tls:
      - secretName: grafana-tls
        hosts:
          - grafana.yourdomain.com

prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources:
            requests:
              storage: 50Gi
    # Tell Prometheus to scrape pods with the standard annotations
    podMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources:
            requests:
              storage: 5Gi
```

<br />

```bash
# Install with the production values
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f monitoring-values.yaml
```

<br />

##### **PromQL basics: querying your metrics**
PromQL is the query language for Prometheus. It looks strange at first, but you only need to learn a
handful of patterns to cover most use cases.

<br />

**Instant vector** - select the current value of a metric:

<br />

```promql
# All HTTP requests from the task-api
http_requests_total{service="task-api"}

# Only 500 errors
http_requests_total{service="task-api", status="500"}
```

<br />

**Rate** - the most important function. Calculates the per-second rate of increase for counters
over a time window:

<br />

```promql
# Requests per second over the last 5 minutes
rate(http_requests_total[5m])

# Error rate (500s only) per second
rate(http_requests_total{status="500"}[5m])
```

<br />

**Aggregation** - combine multiple time series:

<br />

```promql
# Total requests per second across all instances
sum(rate(http_requests_total[5m]))

# Requests per second grouped by status code
sum by (status) (rate(http_requests_total[5m]))

# Error percentage
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
* 100
```

<br />

**Histogram quantiles** - calculate percentiles:

<br />

```promql
# p99 latency (99th percentile)
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# p50 latency (median)
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))

# p99 latency per endpoint
histogram_quantile(0.99, sum by (path, le) (rate(http_request_duration_seconds_bucket[5m])))
```

<br />

Here are some queries you will use all the time:

<br />

```promql
# CPU usage by pod (percentage)
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="task-api"}[5m])) * 100

# Memory usage by pod (megabytes)
sum by (pod) (container_memory_working_set_bytes{namespace="task-api"}) / 1024 / 1024

# Pod restarts (a restart usually means something crashed)
increase(kube_pod_container_status_restarts_total{namespace="task-api"}[1h])

# Available replicas vs desired replicas (are all pods healthy?)
kube_deployment_status_replicas_available{namespace="task-api"}
/
kube_deployment_spec_replicas{namespace="task-api"}
```

<br />

##### **Building a Grafana dashboard**
Grafana comes with hundreds of pre-built dashboards you can import. For Kubernetes, the
kube-prometheus-stack already includes dashboards for node metrics, pod metrics, and cluster overview.
But you will also want a custom dashboard for your application.

<br />

**Importing a community dashboard:**

<br />

1. Open Grafana and go to Dashboards > Import.
2. Enter a dashboard ID from [grafana.com/dashboards](https://grafana.com/grafana/dashboards/). For
   example, dashboard `315` is a popular Kubernetes cluster monitoring dashboard.
3. Select your Prometheus data source and click Import.

<br />

That gives you a ready-made dashboard in seconds. Now let's build a custom one for our API.

<br />

**Creating a custom dashboard:**

<br />

1. Go to Dashboards > New Dashboard > Add visualization.
2. Select your Prometheus data source.
3. For the first panel, enter this PromQL query:

<br />

```promql
sum by (status) (rate(http_requests_total{service="task-api"}[5m]))
```

<br />

4. Set the panel title to "Request Rate by Status Code".
5. Choose the "Time series" visualization type.
6. Under Legend, set it to `{{status}}` so each line is labeled with its status code.

<br />

Add more panels for the metrics that matter most:

<br />

> * **Request rate**: `sum(rate(http_requests_total{service="task-api"}[5m]))` as a stat panel showing total RPS.
> * **Error rate percentage**: The error percentage query from earlier, displayed as a gauge with thresholds (green < 1%, yellow < 5%, red >= 5%).
> * **p99 latency**: `histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{service="task-api"}[5m])))` as a time series chart.
> * **Active database connections**: `db_active_connections{service="task-api"}` as a gauge.
> * **Pod CPU and memory**: The container queries from the previous section.

<br />

A good dashboard follows the USE method (Utilization, Saturation, Errors) or the RED method (Rate,
Errors, Duration). For an API, the RED method is the most practical:

<br />

```plaintext
RED Dashboard Layout:
+---------------------+-------------------+--------------------+
| Request Rate (RPS)  | Error Rate (%)    | p99 Latency (ms)   |
| [stat panel]        | [gauge panel]     | [stat panel]       |
+---------------------+-------------------+--------------------+
| Request Rate by Status Code (time series)                    |
+--------------------------------------------------------------+
| Latency Distribution: p50, p90, p99 (time series)            |
+--------------------------------------------------------------+
| Error Log Stream (if using Loki)                             |
+--------------------------------------------------------------+
```

<br />

Once you are happy with the dashboard, save it and note the JSON model. You can export it and store
it in your Git repository so it can be provisioned automatically. The kube-prometheus-stack supports
dashboard provisioning through ConfigMaps:

<br />

```yaml
# grafana-dashboard-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: task-api-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  task-api.json: |
    {
      "dashboard": {
        "title": "Task API",
        "panels": [ ... ]
      }
    }
```

<br />

##### **Traces: following a request across services**
Logs tell you what happened in a single service. Traces tell you what happened across multiple
services for a single request. Every trace is made up of **spans**, and each span represents a
unit of work: an HTTP handler, a database query, an external API call.

<br />

Here is what a trace looks like:

<br />

```plaintext
Trace ID: abc123def456
|
|-- Span: API Gateway (15ms)
|   |-- Span: Authentication middleware (2ms)
|   |-- Span: Orders Service HTTP call (180ms)
|       |-- Span: Database query: SELECT * FROM orders (150ms)  <-- the bottleneck!
|       |-- Span: Cache write (3ms)
|
Total duration: 200ms
```

<br />

Without tracing, you would see that the API Gateway took 200ms but you would have no idea that the
bottleneck was a slow database query inside the Orders Service. With tracing, you can see the exact
breakdown.

<br />

**OpenTelemetry** (OTel) is the standard for instrumenting applications with traces (and metrics and
logs). It provides SDKs for every major language and a vendor-neutral way to export telemetry data.
Let's add basic tracing to our TypeScript API:

<br />

```bash
# Install OpenTelemetry packages
npm install @opentelemetry/api \
  @opentelemetry/sdk-node \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-http
```

<br />

```typescript
// src/tracing.ts - must be imported before anything else
import { NodeSDK } from "@opentelemetry/sdk-node";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { Resource } from "@opentelemetry/resources";
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
} from "@opentelemetry/semantic-conventions";

const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: "task-api",
    [ATTR_SERVICE_VERSION]: process.env.APP_VERSION || "0.1.0",
  }),
  traceExporter: new OTLPTraceExporter({
    // Send traces to an OTel Collector or Jaeger
    url:
      process.env.OTEL_EXPORTER_OTLP_ENDPOINT ||
      "http://otel-collector:4318/v1/traces",
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      // Auto-instrument Express, HTTP, and database clients
      "@opentelemetry/instrumentation-express": { enabled: true },
      "@opentelemetry/instrumentation-http": { enabled: true },
      "@opentelemetry/instrumentation-pg": { enabled: true },
    }),
  ],
});

sdk.start();
console.log("OpenTelemetry tracing initialized");

// Graceful shutdown
process.on("SIGTERM", () => {
  sdk.shutdown().then(() => process.exit(0));
});
```

<br />

```typescript
// src/index.ts - import tracing FIRST
import "./tracing";
import app from "./app";

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
```

<br />

With auto-instrumentation, every incoming HTTP request, outgoing HTTP call, and database query
automatically gets a span. The SDK propagates the trace context through HTTP headers
(`traceparent`), so when service A calls service B, both services' spans are linked under the same
trace ID.

<br />

For custom spans when you need more detail:

<br />

```typescript
// src/services/orders.ts
import { trace } from "@opentelemetry/api";

const tracer = trace.getTracer("task-api");

export async function processOrder(orderId: string) {
  // Create a custom span for this operation
  return tracer.startActiveSpan("processOrder", async (span) => {
    try {
      span.setAttribute("order.id", orderId);

      // Each sub-operation can have its own span
      const order = await tracer.startActiveSpan(
        "fetchOrder",
        async (fetchSpan) => {
          const result = await db.query("SELECT * FROM orders WHERE id = $1", [
            orderId,
          ]);
          fetchSpan.end();
          return result;
        }
      );

      await tracer.startActiveSpan(
        "validatePayment",
        async (paymentSpan) => {
          await paymentService.validate(order.paymentId);
          paymentSpan.end();
        }
      );

      span.setAttribute("order.status", "processed");
      span.end();
      return order;
    } catch (error) {
      span.recordException(error as Error);
      span.setStatus({ code: 2, message: (error as Error).message });
      span.end();
      throw error;
    }
  });
}
```

<br />

To view traces, you need a trace backend. For development, Jaeger is the easiest to set up:

<br />

```bash
# Run Jaeger locally with Docker
docker run -d --name jaeger \
  -p 16686:16686 \
  -p 4318:4318 \
  jaegertracing/all-in-one:latest

# Open http://localhost:16686 to view traces
```

<br />

In a Kubernetes cluster, you can deploy Jaeger alongside the OpenTelemetry Collector using the
Jaeger Operator or a Helm chart. The kube-prometheus-stack does not include tracing out of the box,
but Grafana can connect to Jaeger as a data source and display traces alongside your metrics
dashboards.

<br />

##### **The observability workflow in practice**
Let's walk through a realistic scenario to see how all three pillars work together.

<br />

**Scenario**: Users report that creating tasks is slow.

<br />

**Step 1: Check the dashboard.** Open your Grafana RED dashboard. You notice that the p99 latency
for POST /tasks has jumped from 100ms to 3 seconds in the last 30 minutes. The error rate is still
low, so requests are succeeding but they are slow.

<br />

**Step 2: Narrow down with metrics.** Add a PromQL query to check if the problem is specific to
one pod or all pods:

<br />

```promql
histogram_quantile(0.99,
  sum by (pod, le) (
    rate(http_request_duration_seconds_bucket{path="/tasks", method="POST"}[5m])
  )
)
```

<br />

All pods show the same slow latency, so the issue is not a single unhealthy pod.

<br />

**Step 3: Find a slow trace.** Go to Jaeger (or Grafana Tempo) and search for traces where the
operation is `POST /tasks` and the duration is greater than 2 seconds. You find several traces and
open one. The trace shows:

<br />

```plaintext
POST /tasks (3.1s)
  |-- Express middleware (2ms)
  |-- insertTask (3.05s)
      |-- pg.query: INSERT INTO tasks... (3.04s)  <-- the problem
```

<br />

The database INSERT is taking 3 seconds. That is abnormal.

<br />

**Step 4: Check the logs.** Search your logs for database-related errors in the last 30 minutes:

<br />

```json
{
  "level": "warn",
  "message": "Slow query detected",
  "query": "INSERT INTO tasks...",
  "duration_ms": 3041,
  "service": "task-api",
  "connection_pool_active": 19,
  "connection_pool_max": 20
}
```

<br />

The connection pool is almost full. You check further and find that a background job that runs every
30 minutes is holding connections open longer than expected. You fix the background job, and latency
returns to normal.

<br />

This is the observability workflow: alert or symptom, dashboard, trace, logs, root cause. Each pillar
narrowed the problem until you found the answer.

<br />

##### **Alerting basics**
Dashboards are useful for investigation, but you need alerts to know when something is wrong before
your users tell you. Prometheus supports alerting rules that evaluate PromQL expressions and fire
alerts when conditions are met.

<br />

Here is a PrometheusRule resource for a simple alert:

<br />

```yaml
# alert-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: task-api-alerts
  namespace: monitoring
  labels:
    release: monitoring  # Must match the kube-prometheus-stack release name
spec:
  groups:
    - name: task-api
      rules:
        # Alert when error rate exceeds 5% for 5 minutes
        - alert: HighErrorRate
          expr: |
            sum(rate(http_requests_total{service="task-api", status=~"5.."}[5m]))
            /
            sum(rate(http_requests_total{service="task-api"}[5m]))
            > 0.05
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High error rate on task-api"
            description: >
              The task-api error rate is {{ $value | humanizePercentage }}
              over the last 5 minutes.

        # Alert when p99 latency exceeds 1 second for 10 minutes
        - alert: HighLatency
          expr: |
            histogram_quantile(0.99,
              sum by (le) (rate(http_request_duration_seconds_bucket{service="task-api"}[5m]))
            ) > 1
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "High p99 latency on task-api"
            description: >
              The task-api p99 latency is {{ $value | humanizeDuration }}
              over the last 5 minutes.

        # Alert when a pod has restarted more than 3 times in an hour
        - alert: PodCrashLooping
          expr: |
            increase(kube_pod_container_status_restarts_total{
              namespace="task-api"
            }[1h]) > 3
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod crash-looping in task-api namespace"
            description: >
              Pod {{ $labels.pod }} has restarted {{ $value }} times
              in the last hour.
```

<br />

Apply the rule and Prometheus picks it up automatically:

<br />

```bash
kubectl apply -f alert-rules.yaml
```

<br />

**Alertmanager** receives alerts from Prometheus and routes them to the right destination: Slack,
PagerDuty, email, or a webhook. The kube-prometheus-stack includes Alertmanager. Here is a basic
configuration that sends alerts to a Slack channel:

<br />

```yaml
# In your monitoring-values.yaml, add Alertmanager configuration
alertmanager:
  config:
    global:
      slack_api_url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
    route:
      receiver: "slack-notifications"
      group_by: ["alertname", "namespace"]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
    receivers:
      - name: "slack-notifications"
        slack_configs:
          - channel: "#alerts"
            send_resolved: true
            title: '{{ .GroupLabels.alertname }}'
            text: >-
              {{ range .Alerts }}
              *{{ .Annotations.summary }}*
              {{ .Annotations.description }}
              {{ end }}
```

<br />

The key settings to understand:

<br />

> * **group_by**: Groups related alerts together so you get one notification instead of fifty when something goes wrong.
> * **group_wait**: How long to wait before sending the first notification after a group is created. Gives time for related alerts to arrive and get grouped.
> * **repeat_interval**: How often to re-send an unresolved alert. You do not want to get paged every 30 seconds for the same issue.
> * **send_resolved**: Sends a notification when the alert clears. Nice to know when the problem is fixed without checking manually.

<br />

##### **Connecting the dots: logs, metrics, and traces together**
The real power of observability comes when you connect all three pillars. The key is the **trace ID**.
When a request enters your system, it gets a unique trace ID. If you include that trace ID in your
logs and your metrics labels, you can jump from a log entry to the corresponding trace, or from an
alert to the exact logs that explain what happened.

<br />

Here is how to add the trace ID to your structured logs:

<br />

```typescript
// src/middleware/traceContext.ts
import { trace, context } from "@opentelemetry/api";
import { Request, Response, NextFunction } from "express";
import logger from "../logger";

export function traceContextMiddleware(
  req: Request,
  _res: Response,
  next: NextFunction
) {
  const span = trace.getSpan(context.active());
  if (span) {
    const spanContext = span.spanContext();
    // Attach trace ID to the request logger so all logs in this request
    // include the trace ID automatically
    req.log = logger.child({
      traceId: spanContext.traceId,
      spanId: spanContext.spanId,
    });
  }
  next();
}
```

<br />

Now every log entry from a request includes the trace ID:

<br />

```json
{
  "level": "error",
  "message": "Failed to process order",
  "traceId": "abc123def456789",
  "spanId": "def456789abc123",
  "orderId": "12345",
  "service": "task-api"
}
```

<br />

In Grafana, you can configure a data link from your log panel (Loki) to your trace panel (Jaeger or
Tempo). Click on a log entry and jump directly to the trace. This is the single most useful feature
for debugging production issues.

<br />

##### **What to observe: a starter checklist**
When you are just getting started, it is easy to get overwhelmed by the number of things you could
measure. Here is a practical starting point:

<br />

> * **For every API endpoint**: Request rate, error rate, and latency (the RED method). These three metrics cover most problems.
> * **For your infrastructure**: CPU usage, memory usage, disk usage, and network I/O per pod. The kube-prometheus-stack gives you these for free.
> * **For your database**: Active connections, query duration, and connection pool utilization. These are the most common source of application performance issues.
> * **For your application health**: Pod restarts, deployment replica status, and container readiness. These tell you if Kubernetes is struggling to keep your app running.

<br />

Start with these and add more metrics as you encounter specific problems. Do not try to measure
everything on day one.

<br />

##### **Advanced topics**
We covered the essentials in this article, but observability goes much deeper. Here are topics worth
exploring once you are comfortable with the basics:

<br />

> * **SLO-based alerting**: Instead of alerting on raw thresholds ("latency > 1s"), define Service Level Objectives and alert on error budget burn rate. This avoids noisy alerts and focuses on what matters to users.
> * **Log aggregation with Loki**: Loki is the logging equivalent of Prometheus. It indexes log metadata (labels) and stores the log content compressed, making it much cheaper than Elasticsearch for Kubernetes logging.
> * **Distributed tracing at scale with Tempo**: Grafana Tempo is a trace backend designed to work seamlessly with Grafana, Loki, and Prometheus. It supports trace-to-log and trace-to-metric correlation out of the box.
> * **Trace-based testing**: Use traces to verify that your services communicate correctly in integration tests. Tools like Tracetest let you write assertions against trace data.
> * **Custom metrics for business logic**: Track things like orders processed, revenue per minute, or user signups. These business metrics are often more valuable than technical metrics.

<br />

For a comprehensive deep dive into all of these topics, check out the
[SRE Observability Deep Dive](/blog/sre-observability-deep-dive-traces-logs-and-metrics). It covers
OpenTelemetry instrumentation patterns, Loki setup, Grafana Tempo, SLO-based alerting with
Pyrra, and production-grade observability architectures.

<br />

##### **Closing notes**
Observability is not optional. Once your application is running in production, you need to know what
it is doing, how it is performing, and when something goes wrong. The three pillars (logs, metrics,
and traces) give you complementary views into your system's behavior.

<br />

In this article we covered what observability is and why it matters, the three pillars and when to
use each one, structured logging with pino, Prometheus metrics with prom-client, installing
Prometheus and Grafana with the kube-prometheus-stack, basic PromQL queries for common scenarios,
building Grafana dashboards, distributed tracing with OpenTelemetry, alerting with PrometheusRule
and Alertmanager, and the observability workflow for debugging production issues.

<br />

The key takeaway is that observability is a workflow, not a tool. You do not just install Prometheus
and call it done. You instrument your application, build dashboards that answer real questions,
set up alerts that notify you before your users do, and practice the alert-dashboard-trace-log flow
until it becomes second nature.

<br />

In the next article we will cover CI/CD pipelines for Kubernetes, bringing together everything we
have built so far into an automated deployment workflow.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: Observabilidad en Kubernetes",
  author: "Gabriel Garrido",
  description: "Vamos a explorar los tres pilares de la observabilidad: logs, metricas y traces. Aprende logging estructurado, como instalar Prometheus y Grafana en EKS, PromQL basico, tracing distribuido con OpenTelemetry, y como instrumentar una API TypeScript...",
  tags: ~w(devops kubernetes observability prometheus grafana beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo quince de la serie DevOps desde Cero. En los articulos anteriores deployeamos
nuestra API TypeScript a Kubernetes y la empaquetamos con Helm. Todo esta corriendo, los pods estan
en verde, y la vida es buena. Pero despues alguien pregunta: "La API esta sana de verdad? Como
sabemos si los tiempos de respuesta estan empeorando? Que paso a las 3am cuando los usuarios
empezaron a quejarse?"

<br />

Sin observabilidad, estas volando a ciegas. Deployeaste tu app, pero no tenes idea de que esta
pasando adentro. La observabilidad te da la capacidad de entender el estado interno de tu sistema
examinando los datos que produce. Es la diferencia entre "algo esta roto" y "el endpoint /orders
esta devolviendo errores 500 porque el pool de conexiones a la base de datos esta agotado."

<br />

En este articulo vamos a cubrir los tres pilares de la observabilidad (logs, metricas y traces),
instalar Prometheus y Grafana en EKS usando Helm, armar un dashboard basico, instrumentar nuestra
API TypeScript con logging estructurado y un endpoint de metricas, configurar una alerta simple, y
recorrer el flujo de observabilidad que vas a usar durante incidentes reales. Esta es una
introduccion para principiantes. Si queres ir mas profundo en temas como alertas basadas en SLOs,
Loki para agregacion de logs, o patrones avanzados de OpenTelemetry, mira el
[Deep Dive de Observabilidad SRE](/blog/sre-observability-deep-dive-traces-logs-and-metrics) de la
serie SRE.

<br />

Vamos a meternos de lleno.

<br />

##### **Los tres pilares de la observabilidad**
La observabilidad esta construida sobre tres tipos de datos de telemetria. Cada uno responde una
pregunta diferente, y necesitas los tres para debuggear problemas de produccion efectivamente.

<br />

> * **Logs**: Eventos discretos que te dicen que paso. "El request abc123 fallo con un error 500 a las 14:32:05." Los logs dan el contexto mas rico porque pueden incluir detalles arbitrarios como bodies de requests, stack traces e IDs de usuario.
> * **Metricas**: Mediciones numericas a lo largo del tiempo. "La API manejo 150 requests por segundo con una latencia p99 de 200ms." Las metricas son baratas de almacenar, rapidas de consultar, y perfectas para dashboards y alertas.
> * **Traces**: El camino que un request toma a traves de tu sistema. "Este request paso por el API gateway, despues por el servicio de ordenes, despues por la base de datos, y la parte lenta fue la query a la base de datos." Los traces son esenciales cuando tenes multiples servicios comunicandose entre si.

<br />

Pensalo asi: las metricas te dicen que algo esta mal, los traces te dicen donde en el sistema esta
mal, y los logs te dicen por que esta mal. Aca esta el flujo:

<br />

```bash
# El flujo de observabilidad durante un incidente:
#
# 1. ALERTA (de metricas): "Tasa de errores > 5% en los ultimos 5 minutos"
#    -> Sabes que ALGO esta mal
#
# 2. DASHBOARD (metricas): Chequeando Grafana, ves que /orders tiene alta tasa de errores
#    -> Sabes QUE esta mal
#
# 3. TRACES: Encontras requests fallidos, ves que todos fallan en la llamada a la DB
#    -> Sabes DONDE esta mal
#
# 4. LOGS: Chequeando los logs del servicio de DB: "ERROR: demasiadas conexiones"
#    -> Sabes POR QUE esta mal
```

<br />

Vamos a cubrir cada pilar en detalle, empezando con los logs porque son los mas familiares.

<br />

##### **Logs: logging estructurado**
Si alguna vez usaste `console.log("algo se rompio")` en produccion, conoces el problema. Cuando
tenes miles de lineas de log fluyendo por tu sistema, encontrar la relevante es como buscar una
aguja en un pajar. Los logs no estructurados (strings de texto plano) son dificiles de buscar,
dificiles de filtrar y dificiles de agregar.

<br />

El logging estructurado resuelve esto escribiendo logs como objetos JSON con campos consistentes.
En vez de:

<br />

```plaintext
[2026-06-02 14:32:05] ERROR: Failed to process order 12345 for user john@example.com
```

<br />

Escribis:

<br />

```json
{
  "timestamp": "2026-06-02T14:32:05.123Z",
  "level": "error",
  "message": "Failed to process order",
  "orderId": "12345",
  "userId": "john@example.com",
  "service": "orders-api",
  "traceId": "abc123def456",
  "duration_ms": 1523
}
```

<br />

Ahora podes buscar todos los errores relacionados con un usuario especifico, una orden especifica, o
un trace especifico. Podes contar cuantos errores pasaron por servicio. Podes correlacionar logs con
traces usando el campo traceId. Este es el poder del logging estructurado.

<br />

**Los niveles de log** definen la severidad de una entrada de log. Usalos consistentemente:

<br />

> * **error**: Algo fallo y necesita atencion. Un request devolvio un 500, una query a la base de datos hizo timeout, una API externa no responde.
> * **warn**: Algo inesperado paso pero el sistema lo manejo. Un retry funciono, hubo un cache miss, se llamo a un endpoint deprecado.
> * **info**: Operaciones normales que vale la pena registrar. Un request se proceso exitosamente, un usuario se logueo, un job de background se completo.
> * **debug**: Informacion detallada util durante el desarrollo. Payloads de requests, queries SQL, estado interno. Desactivalo en produccion a menos que estes debuggeando activamente.

<br />

Agreguemos logging estructurado a nuestra API TypeScript usando `pino`, que es el logger JSON mas
rapido para Node.js:

<br />

```bash
# Instalar pino y el pretty-printer para desarrollo local
npm install pino pino-http
npm install -D pino-pretty
```

<br />

```typescript
// src/logger.ts
import pino from "pino";

const logger = pino({
  level: process.env.LOG_LEVEL || "info",
  // En produccion, output JSON crudo. Localmente, usar pino-pretty para legibilidad.
  transport:
    process.env.NODE_ENV !== "production"
      ? { target: "pino-pretty", options: { colorize: true } }
      : undefined,
  // Agregar campos por defecto a cada entrada de log
  base: {
    service: "task-api",
    version: process.env.APP_VERSION || "unknown",
  },
});

export default logger;
```

<br />

```typescript
// src/app.ts
import express from "express";
import pinoHttp from "pino-http";
import logger from "./logger";

const app = express();

// Loguear automaticamente cada request HTTP con metodo, URL, status y duracion
app.use(pinoHttp({ logger }));

app.get("/tasks", async (req, res) => {
  try {
    const tasks = await db.query("SELECT * FROM tasks");
    // Log de nivel info con contexto estructurado
    logger.info({ taskCount: tasks.length }, "Tasks retrieved successfully");
    res.json(tasks);
  } catch (error) {
    // Log de nivel error con el objeto error y contexto del request
    logger.error(
      { err: error, path: req.path, method: req.method },
      "Failed to retrieve tasks"
    );
    res.status(500).json({ error: "Internal server error" });
  }
});
```

<br />

Con `pino-http`, cada request automaticamente obtiene una entrada de log como esta:

<br />

```json
{
  "level": 30,
  "time": 1748870525123,
  "service": "task-api",
  "req": { "method": "GET", "url": "/tasks" },
  "res": { "statusCode": 200 },
  "responseTime": 45,
  "msg": "request completed"
}
```

<br />

Esto es exactamente el tipo de data que podes buscar y filtrar en un sistema de agregacion de logs
como Loki, Elasticsearch o CloudWatch Logs. Podes consultar cosas como "mostrame todos los requests
donde responseTime > 1000" o "mostrame todos los logs de nivel error del servicio task-api en la
ultima hora."

<br />

##### **Metricas: contando lo que importa**
Mientras los logs te cuentan sobre eventos individuales, las metricas te dicen sobre el
comportamiento general de tu sistema a lo largo del tiempo. Las metricas son mediciones numericas
recolectadas a intervalos regulares.

<br />

Hay tres tipos de metricas core que necesitas conocer:

<br />

> * **Counter**: Un valor que solo sube. Ejemplos: numero total de requests HTTP, numero total de errores, bytes totales transferidos. Generalmente te importa la tasa de cambio (requests por segundo) mas que el valor crudo.
> * **Gauge**: Un valor que puede subir y bajar. Ejemplos: uso actual de CPU, uso de memoria, numero de conexiones activas, profundidad de cola. Los gauges representan el estado actual de algo.
> * **Histogram**: Mide la distribucion de valores. Ejemplos: duracion de requests, tamano de respuestas. Los histogramas te permiten responder preguntas como "cual es la latencia del percentil 99?" que es mucho mas util que el promedio.

<br />

**Prometheus** es el sistema de metricas estandar en el ecosistema Kubernetes. Funciona con un
modelo pull: en vez de que tu aplicacion pushee metricas a un servidor, Prometheus scrapea el
endpoint de metricas de tu aplicacion a intervalos regulares (generalmente cada 15 o 30 segundos).

<br />

Asi es como funciona el flujo:

<br />

```plaintext
Tu App (endpoint /metrics)
  |
  v
Prometheus (scrapea cada 15s, almacena datos de series de tiempo)
  |
  v
Grafana (consulta Prometheus, renderiza dashboards)
  |
  v
Alertmanager (recibe alertas de Prometheus, envia notificaciones)
```

<br />

Agreguemos un endpoint `/metrics` a nuestra API TypeScript usando la libreria `prom-client`:

<br />

```bash
npm install prom-client
```

<br />

```typescript
// src/metrics.ts
import client from "prom-client";

// Crear un registry para contener todas las metricas
const register = new client.Registry();

// Agregar metricas por defecto de Node.js (CPU, memoria, event loop lag, etc.)
client.collectDefaultMetrics({ register });

// Counter custom: total de requests HTTP, etiquetado por metodo, path y status
export const httpRequestsTotal = new client.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "path", "status"] as const,
  registers: [register],
});

// Histogram custom: duracion de requests en segundos
export const httpRequestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Duration of HTTP requests in seconds",
  labelNames: ["method", "path", "status"] as const,
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  registers: [register],
});

// Gauge custom: numero de conexiones activas a la base de datos
export const dbActiveConnections = new client.Gauge({
  name: "db_active_connections",
  help: "Number of active database connections",
  registers: [register],
});

export { register };
```

<br />

```typescript
// src/middleware/metrics.ts
import { Request, Response, NextFunction } from "express";
import { httpRequestsTotal, httpRequestDuration } from "../metrics";

export function metricsMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
) {
  const start = Date.now();

  res.on("finish", () => {
    const duration = (Date.now() - start) / 1000;
    const path = req.route?.path || req.path;
    const labels = {
      method: req.method,
      path: path,
      status: res.statusCode.toString(),
    };

    httpRequestsTotal.inc(labels);
    httpRequestDuration.observe(labels, duration);
  });

  next();
}
```

<br />

```typescript
// src/app.ts - agregar el endpoint de metricas y el middleware
import { register } from "./metrics";
import { metricsMiddleware } from "./middleware/metrics";

// Aplicar el middleware de metricas a todas las rutas
app.use(metricsMiddleware);

// Exponer metricas para que Prometheus las scrapee
app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});
```

<br />

Cuando Prometheus scrapea `/metrics`, obtiene output como este:

<br />

```promql
# HELP http_requests_total Total number of HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/tasks",status="200"} 1523
http_requests_total{method="POST",path="/tasks",status="201"} 47
http_requests_total{method="GET",path="/tasks",status="500"} 3

# HELP http_request_duration_seconds Duration of HTTP requests in seconds
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",path="/tasks",status="200",le="0.05"} 1200
http_request_duration_seconds_bucket{method="GET",path="/tasks",status="200",le="0.1"} 1450
http_request_duration_seconds_bucket{method="GET",path="/tasks",status="200",le="0.25"} 1510
http_request_duration_seconds_bucket{method="GET",path="/tasks",status="200",le="+Inf"} 1523
```

<br />

Para que Prometheus descubra este endpoint en Kubernetes, agregas anotaciones a tu pod o servicio:

<br />

```yaml
# En el template de deployment de tu chart Helm o values
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "3000"
    prometheus.io/path: "/metrics"
```

<br />

##### **Instalando Prometheus y Grafana en EKS**
La forma mas facil de tener Prometheus y Grafana corriendo en Kubernetes es el chart Helm
`kube-prometheus-stack`. Este unico chart instala Prometheus, Grafana, Alertmanager, node-exporter
(para metricas del host), kube-state-metrics (para metricas de objetos Kubernetes), y un monton de
dashboards y reglas de alertas preconfiguradas.

<br />

```bash
# Agregar el repositorio Helm de la comunidad Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Crear un namespace para monitoreo
kubectl create namespace monitoring

# Instalar el kube-prometheus-stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=tu-password-seguro \
  --set prometheus.prometheusSpec.retention=7d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi
```

<br />

Eso es todo. Un solo comando Helm y tenes un stack de monitoreo completo. Verifiquemos que todo este
corriendo:

<br />

```bash
# Verificar todos los pods en el namespace monitoring
kubectl get pods -n monitoring

# Output esperado:
# NAME                                                     READY   STATUS    RESTARTS   AGE
# alertmanager-monitoring-kube-prometheus-alertmanager-0    2/2     Running   0          2m
# monitoring-grafana-6c4f8d5b7-x2k4f                      3/3     Running   0          2m
# monitoring-kube-prometheus-operator-7d9f5b8c9-abc12      1/1     Running   0          2m
# monitoring-kube-state-metrics-5f8d9b7c6-def34            1/1     Running   0          2m
# monitoring-prometheus-node-exporter-ghij5                1/1     Running   0          2m
# prometheus-monitoring-kube-prometheus-prometheus-0        2/2     Running   0          2m
```

<br />

Para acceder a Grafana localmente, usa port-forwarding:

<br />

```bash
# Forwardear Grafana a localhost:3001
kubectl port-forward svc/monitoring-grafana 3001:80 -n monitoring

# Abrir http://localhost:3001 en tu navegador
# Login: admin / tu-password-seguro
```

<br />

Para produccion, expondrias Grafana a traves de un Ingress con TLS. Aca hay un archivo de values
rapido para un setup tipo produccion:

<br />

```yaml
# monitoring-values.yaml
grafana:
  adminPassword: "${GRAFANA_ADMIN_PASSWORD}"
  ingress:
    enabled: true
    ingressClassName: alb
    hosts:
      - grafana.tudominio.com
    tls:
      - secretName: grafana-tls
        hosts:
          - grafana.tudominio.com

prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources:
            requests:
              storage: 50Gi
    # Decirle a Prometheus que scrapee pods con las anotaciones estandar
    podMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources:
            requests:
              storage: 5Gi
```

<br />

```bash
# Instalar con los values de produccion
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f monitoring-values.yaml
```

<br />

##### **Basicos de PromQL: consultando tus metricas**
PromQL es el lenguaje de consultas para Prometheus. Se ve raro al principio, pero solo necesitas
aprender un punado de patrones para cubrir la mayoria de los casos de uso.

<br />

**Vector instantaneo** - seleccionar el valor actual de una metrica:

<br />

```promql
# Todos los requests HTTP del task-api
http_requests_total{service="task-api"}

# Solo errores 500
http_requests_total{service="task-api", status="500"}
```

<br />

**Rate** - la funcion mas importante. Calcula la tasa por segundo de incremento para counters
en una ventana de tiempo:

<br />

```promql
# Requests por segundo en los ultimos 5 minutos
rate(http_requests_total[5m])

# Tasa de errores (solo 500s) por segundo
rate(http_requests_total{status="500"}[5m])
```

<br />

**Agregacion** - combinar multiples series de tiempo:

<br />

```promql
# Total de requests por segundo a traves de todas las instancias
sum(rate(http_requests_total[5m]))

# Requests por segundo agrupados por codigo de status
sum by (status) (rate(http_requests_total[5m]))

# Porcentaje de errores
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
* 100
```

<br />

**Cuantiles de histograma** - calcular percentiles:

<br />

```promql
# Latencia p99 (percentil 99)
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Latencia p50 (mediana)
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))

# Latencia p99 por endpoint
histogram_quantile(0.99, sum by (path, le) (rate(http_request_duration_seconds_bucket[5m])))
```

<br />

Aca hay algunas consultas que vas a usar todo el tiempo:

<br />

```promql
# Uso de CPU por pod (porcentaje)
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="task-api"}[5m])) * 100

# Uso de memoria por pod (megabytes)
sum by (pod) (container_memory_working_set_bytes{namespace="task-api"}) / 1024 / 1024

# Reinicios de pods (un reinicio generalmente significa que algo crasheo)
increase(kube_pod_container_status_restarts_total{namespace="task-api"}[1h])

# Replicas disponibles vs replicas deseadas (estan todos los pods sanos?)
kube_deployment_status_replicas_available{namespace="task-api"}
/
kube_deployment_spec_replicas{namespace="task-api"}
```

<br />

##### **Armando un dashboard en Grafana**
Grafana viene con cientos de dashboards pre-armados que podes importar. Para Kubernetes, el
kube-prometheus-stack ya incluye dashboards para metricas de nodos, metricas de pods y resumen del
cluster. Pero tambien vas a querer un dashboard custom para tu aplicacion.

<br />

**Importando un dashboard de la comunidad:**

<br />

1. Abri Grafana y anda a Dashboards > Import.
2. Ingresa un ID de dashboard de [grafana.com/dashboards](https://grafana.com/grafana/dashboards/).
   Por ejemplo, el dashboard `315` es uno popular para monitoreo de cluster Kubernetes.
3. Selecciona tu data source de Prometheus y hace click en Import.

<br />

Eso te da un dashboard listo en segundos. Ahora armemos uno custom para nuestra API.

<br />

**Creando un dashboard custom:**

<br />

1. Anda a Dashboards > New Dashboard > Add visualization.
2. Selecciona tu data source de Prometheus.
3. Para el primer panel, ingresa esta consulta PromQL:

<br />

```promql
sum by (status) (rate(http_requests_total{service="task-api"}[5m]))
```

<br />

4. Ponele como titulo "Request Rate by Status Code".
5. Elegi el tipo de visualizacion "Time series".
6. En Legend, configuralo como `{{status}}` para que cada linea se etiquete con su codigo de status.

<br />

Agrega mas paneles para las metricas que mas importan:

<br />

> * **Tasa de requests**: `sum(rate(http_requests_total{service="task-api"}[5m]))` como panel stat mostrando RPS total.
> * **Porcentaje de tasa de errores**: La consulta de porcentaje de errores de antes, mostrada como gauge con umbrales (verde < 1%, amarillo < 5%, rojo >= 5%).
> * **Latencia p99**: `histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{service="task-api"}[5m])))` como chart de series de tiempo.
> * **Conexiones activas a la DB**: `db_active_connections{service="task-api"}` como gauge.
> * **CPU y memoria de pods**: Las consultas de containers de la seccion anterior.

<br />

Un buen dashboard sigue el metodo USE (Utilization, Saturation, Errors) o el metodo RED (Rate,
Errors, Duration). Para una API, el metodo RED es el mas practico:

<br />

```plaintext
Layout de Dashboard RED:
+---------------------+-------------------+--------------------+
| Tasa de Requests    | Tasa de Errores   | Latencia p99       |
| [panel stat]        | [panel gauge]     | [panel stat]       |
+---------------------+-------------------+--------------------+
| Tasa de Requests por Codigo de Status (series de tiempo)     |
+--------------------------------------------------------------+
| Distribucion de Latencia: p50, p90, p99 (series de tiempo)   |
+--------------------------------------------------------------+
| Stream de Logs de Error (si usas Loki)                       |
+--------------------------------------------------------------+
```

<br />

Una vez que estes conforme con el dashboard, guardalo y anota el modelo JSON. Podes exportarlo y
guardarlo en tu repositorio Git para que se pueda provisionar automaticamente. El
kube-prometheus-stack soporta provisionamiento de dashboards a traves de ConfigMaps:

<br />

```yaml
# grafana-dashboard-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: task-api-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  task-api.json: |
    {
      "dashboard": {
        "title": "Task API",
        "panels": [ ... ]
      }
    }
```

<br />

##### **Traces: siguiendo un request a traves de servicios**
Los logs te dicen que paso en un solo servicio. Los traces te dicen que paso a traves de multiples
servicios para un solo request. Cada trace esta compuesto de **spans**, y cada span representa una
unidad de trabajo: un handler HTTP, una query a la base de datos, una llamada a una API externa.

<br />

Asi se ve un trace:

<br />

```plaintext
Trace ID: abc123def456
|
|-- Span: API Gateway (15ms)
|   |-- Span: Middleware de autenticacion (2ms)
|   |-- Span: Llamada HTTP a Orders Service (180ms)
|       |-- Span: Query a la DB: SELECT * FROM orders (150ms)  <-- el cuello de botella!
|       |-- Span: Escritura en cache (3ms)
|
Duracion total: 200ms
```

<br />

Sin tracing, verias que el API Gateway tardo 200ms pero no tendrias idea de que el cuello de botella
era una query lenta a la base de datos dentro del Orders Service. Con tracing, podes ver el desglose
exacto.

<br />

**OpenTelemetry** (OTel) es el estandar para instrumentar aplicaciones con traces (y metricas y
logs). Provee SDKs para todos los lenguajes principales y una forma vendor-neutral de exportar datos
de telemetria. Agreguemos tracing basico a nuestra API TypeScript:

<br />

```bash
# Instalar paquetes de OpenTelemetry
npm install @opentelemetry/api \
  @opentelemetry/sdk-node \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-http
```

<br />

```typescript
// src/tracing.ts - debe ser importado antes que todo lo demas
import { NodeSDK } from "@opentelemetry/sdk-node";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { Resource } from "@opentelemetry/resources";
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
} from "@opentelemetry/semantic-conventions";

const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: "task-api",
    [ATTR_SERVICE_VERSION]: process.env.APP_VERSION || "0.1.0",
  }),
  traceExporter: new OTLPTraceExporter({
    // Enviar traces a un OTel Collector o Jaeger
    url:
      process.env.OTEL_EXPORTER_OTLP_ENDPOINT ||
      "http://otel-collector:4318/v1/traces",
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      // Auto-instrumentar Express, HTTP y clientes de base de datos
      "@opentelemetry/instrumentation-express": { enabled: true },
      "@opentelemetry/instrumentation-http": { enabled: true },
      "@opentelemetry/instrumentation-pg": { enabled: true },
    }),
  ],
});

sdk.start();
console.log("OpenTelemetry tracing initialized");

// Shutdown graceful
process.on("SIGTERM", () => {
  sdk.shutdown().then(() => process.exit(0));
});
```

<br />

```typescript
// src/index.ts - importar tracing PRIMERO
import "./tracing";
import app from "./app";

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
```

<br />

Con auto-instrumentacion, cada request HTTP entrante, llamada HTTP saliente y query a la base de
datos automaticamente obtiene un span. El SDK propaga el contexto del trace a traves de headers HTTP
(`traceparent`), asi que cuando el servicio A llama al servicio B, los spans de ambos servicios se
enlazan bajo el mismo trace ID.

<br />

Para spans custom cuando necesitas mas detalle:

<br />

```typescript
// src/services/orders.ts
import { trace } from "@opentelemetry/api";

const tracer = trace.getTracer("task-api");

export async function processOrder(orderId: string) {
  // Crear un span custom para esta operacion
  return tracer.startActiveSpan("processOrder", async (span) => {
    try {
      span.setAttribute("order.id", orderId);

      // Cada sub-operacion puede tener su propio span
      const order = await tracer.startActiveSpan(
        "fetchOrder",
        async (fetchSpan) => {
          const result = await db.query("SELECT * FROM orders WHERE id = $1", [
            orderId,
          ]);
          fetchSpan.end();
          return result;
        }
      );

      await tracer.startActiveSpan(
        "validatePayment",
        async (paymentSpan) => {
          await paymentService.validate(order.paymentId);
          paymentSpan.end();
        }
      );

      span.setAttribute("order.status", "processed");
      span.end();
      return order;
    } catch (error) {
      span.recordException(error as Error);
      span.setStatus({ code: 2, message: (error as Error).message });
      span.end();
      throw error;
    }
  });
}
```

<br />

Para ver traces, necesitas un backend de traces. Para desarrollo, Jaeger es el mas facil de instalar:

<br />

```bash
# Correr Jaeger localmente con Docker
docker run -d --name jaeger \
  -p 16686:16686 \
  -p 4318:4318 \
  jaegertracing/all-in-one:latest

# Abrir http://localhost:16686 para ver traces
```

<br />

En un cluster Kubernetes, podes deployear Jaeger junto con el OpenTelemetry Collector usando el
Jaeger Operator o un chart Helm. El kube-prometheus-stack no incluye tracing out of the box, pero
Grafana puede conectarse a Jaeger como data source y mostrar traces junto a tus dashboards de
metricas.

<br />

##### **El flujo de observabilidad en la practica**
Recorramos un escenario realista para ver como los tres pilares trabajan juntos.

<br />

**Escenario**: Los usuarios reportan que crear tareas esta lento.

<br />

**Paso 1: Chequear el dashboard.** Abri tu dashboard RED en Grafana. Notas que la latencia p99
para POST /tasks salto de 100ms a 3 segundos en los ultimos 30 minutos. La tasa de errores sigue
baja, asi que los requests estan funcionando pero son lentos.

<br />

**Paso 2: Acotar con metricas.** Agrega una consulta PromQL para chequear si el problema es
especifico a un pod o a todos los pods:

<br />

```promql
histogram_quantile(0.99,
  sum by (pod, le) (
    rate(http_request_duration_seconds_bucket{path="/tasks", method="POST"}[5m])
  )
)
```

<br />

Todos los pods muestran la misma latencia lenta, asi que el problema no es un pod no saludable.

<br />

**Paso 3: Encontrar un trace lento.** Anda a Jaeger (o Grafana Tempo) y busca traces donde la
operacion sea `POST /tasks` y la duracion sea mayor a 2 segundos. Encontras varios traces y abris
uno. El trace muestra:

<br />

```plaintext
POST /tasks (3.1s)
  |-- Express middleware (2ms)
  |-- insertTask (3.05s)
      |-- pg.query: INSERT INTO tasks... (3.04s)  <-- el problema
```

<br />

El INSERT a la base de datos esta tardando 3 segundos. Eso es anormal.

<br />

**Paso 4: Chequear los logs.** Busca en tus logs errores relacionados con la base de datos en los
ultimos 30 minutos:

<br />

```json
{
  "level": "warn",
  "message": "Slow query detected",
  "query": "INSERT INTO tasks...",
  "duration_ms": 3041,
  "service": "task-api",
  "connection_pool_active": 19,
  "connection_pool_max": 20
}
```

<br />

El pool de conexiones esta casi lleno. Seguis investigando y encontras que un job de background que
corre cada 30 minutos esta manteniendo conexiones abiertas mas de lo esperado. Arreglas el job de
background, y la latencia vuelve a la normalidad.

<br />

Este es el flujo de observabilidad: alerta o sintoma, dashboard, trace, logs, causa raiz. Cada pilar
acoto el problema hasta que encontraste la respuesta.

<br />

##### **Basicos de alertas**
Los dashboards son utiles para investigacion, pero necesitas alertas para saber cuando algo esta mal
antes de que tus usuarios te digan. Prometheus soporta reglas de alerta que evaluan expresiones
PromQL y disparan alertas cuando se cumplen las condiciones.

<br />

Aca hay un recurso PrometheusRule para una alerta simple:

<br />

```yaml
# alert-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: task-api-alerts
  namespace: monitoring
  labels:
    release: monitoring  # Debe coincidir con el nombre del release kube-prometheus-stack
spec:
  groups:
    - name: task-api
      rules:
        # Alertar cuando la tasa de errores supere 5% por 5 minutos
        - alert: HighErrorRate
          expr: |
            sum(rate(http_requests_total{service="task-api", status=~"5.."}[5m]))
            /
            sum(rate(http_requests_total{service="task-api"}[5m]))
            > 0.05
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Alta tasa de errores en task-api"
            description: >
              La tasa de errores de task-api es {{ $value | humanizePercentage }}
              en los ultimos 5 minutos.

        # Alertar cuando la latencia p99 supere 1 segundo por 10 minutos
        - alert: HighLatency
          expr: |
            histogram_quantile(0.99,
              sum by (le) (rate(http_request_duration_seconds_bucket{service="task-api"}[5m]))
            ) > 1
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Alta latencia p99 en task-api"
            description: >
              La latencia p99 de task-api es {{ $value | humanizeDuration }}
              en los ultimos 5 minutos.

        # Alertar cuando un pod se reinicio mas de 3 veces en una hora
        - alert: PodCrashLooping
          expr: |
            increase(kube_pod_container_status_restarts_total{
              namespace="task-api"
            }[1h]) > 3
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod en crash-loop en el namespace task-api"
            description: >
              El pod {{ $labels.pod }} se reinicio {{ $value }} veces
              en la ultima hora.
```

<br />

Aplica la regla y Prometheus la levanta automaticamente:

<br />

```bash
kubectl apply -f alert-rules.yaml
```

<br />

**Alertmanager** recibe alertas de Prometheus y las routea al destino correcto: Slack, PagerDuty,
email o un webhook. El kube-prometheus-stack incluye Alertmanager. Aca hay una configuracion basica
que envia alertas a un canal de Slack:

<br />

```yaml
# En tu monitoring-values.yaml, agregar configuracion de Alertmanager
alertmanager:
  config:
    global:
      slack_api_url: "https://hooks.slack.com/services/TU/SLACK/WEBHOOK"
    route:
      receiver: "slack-notifications"
      group_by: ["alertname", "namespace"]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
    receivers:
      - name: "slack-notifications"
        slack_configs:
          - channel: "#alertas"
            send_resolved: true
            title: '{{ .GroupLabels.alertname }}'
            text: >-
              {{ range .Alerts }}
              *{{ .Annotations.summary }}*
              {{ .Annotations.description }}
              {{ end }}
```

<br />

Las configuraciones clave para entender:

<br />

> * **group_by**: Agrupa alertas relacionadas para que recibas una notificacion en vez de cincuenta cuando algo sale mal.
> * **group_wait**: Cuanto esperar antes de enviar la primera notificacion despues de que se crea un grupo. Da tiempo para que alertas relacionadas lleguen y se agrupen.
> * **repeat_interval**: Cada cuanto re-enviar una alerta no resuelta. No queres que te pageen cada 30 segundos por el mismo problema.
> * **send_resolved**: Envia una notificacion cuando la alerta se resuelve. Copado para saber cuando el problema se arreglo sin tener que chequear manualmente.

<br />

##### **Conectando los puntos: logs, metricas y traces juntos**
El verdadero poder de la observabilidad viene cuando conectas los tres pilares. La clave es el
**trace ID**. Cuando un request entra a tu sistema, recibe un trace ID unico. Si incluis ese trace
ID en tus logs y en las labels de tus metricas, podes saltar de una entrada de log al trace
correspondiente, o de una alerta a los logs exactos que explican que paso.

<br />

Asi se agrega el trace ID a tus logs estructurados:

<br />

```typescript
// src/middleware/traceContext.ts
import { trace, context } from "@opentelemetry/api";
import { Request, Response, NextFunction } from "express";
import logger from "../logger";

export function traceContextMiddleware(
  req: Request,
  _res: Response,
  next: NextFunction
) {
  const span = trace.getSpan(context.active());
  if (span) {
    const spanContext = span.spanContext();
    // Adjuntar trace ID al logger del request para que todos los logs
    // en este request incluyan el trace ID automaticamente
    req.log = logger.child({
      traceId: spanContext.traceId,
      spanId: spanContext.spanId,
    });
  }
  next();
}
```

<br />

Ahora cada entrada de log de un request incluye el trace ID:

<br />

```json
{
  "level": "error",
  "message": "Failed to process order",
  "traceId": "abc123def456789",
  "spanId": "def456789abc123",
  "orderId": "12345",
  "service": "task-api"
}
```

<br />

En Grafana, podes configurar un data link desde tu panel de logs (Loki) a tu panel de traces (Jaeger
o Tempo). Hacele click a una entrada de log y saltas directamente al trace. Esta es la funcionalidad
mas util para debuggear problemas de produccion.

<br />

##### **Que observar: una checklist para empezar**
Cuando recien empezas, es facil sentirse abrumado por la cantidad de cosas que podrias medir. Aca
hay un punto de partida practico:

<br />

> * **Para cada endpoint de API**: Tasa de requests, tasa de errores y latencia (el metodo RED). Estas tres metricas cubren la mayoria de los problemas.
> * **Para tu infraestructura**: Uso de CPU, uso de memoria, uso de disco y I/O de red por pod. El kube-prometheus-stack te da esto gratis.
> * **Para tu base de datos**: Conexiones activas, duracion de queries y utilizacion del pool de conexiones. Estas son la fuente mas comun de problemas de rendimiento de aplicaciones.
> * **Para la salud de tu aplicacion**: Reinicios de pods, estado de replicas del deployment y readiness de containers. Esto te dice si Kubernetes esta luchando para mantener tu app corriendo.

<br />

Empeza con esto y agrega mas metricas a medida que encuentres problemas especificos. No trates de
medir todo el primer dia.

<br />

##### **Temas avanzados**
Cubrimos lo esencial en este articulo, pero la observabilidad va mucho mas profundo. Aca hay temas
que vale la pena explorar una vez que estes comodo con lo basico:

<br />

> * **Alertas basadas en SLOs**: En vez de alertar por umbrales crudos ("latencia > 1s"), defini Service Level Objectives y alerta por tasa de quema de error budget. Esto evita alertas ruidosas y se enfoca en lo que le importa a los usuarios.
> * **Agregacion de logs con Loki**: Loki es el equivalente de logging de Prometheus. Indexa metadata de logs (labels) y almacena el contenido comprimido, haciendolo mucho mas barato que Elasticsearch para logging en Kubernetes.
> * **Tracing distribuido a escala con Tempo**: Grafana Tempo es un backend de traces disenado para funcionar sin fricciones con Grafana, Loki y Prometheus. Soporta correlacion trace-to-log y trace-to-metric out of the box.
> * **Testing basado en traces**: Usa traces para verificar que tus servicios se comunican correctamente en tests de integracion. Herramientas como Tracetest te permiten escribir assertions sobre datos de traces.
> * **Metricas custom para logica de negocio**: Trackea cosas como ordenes procesadas, revenue por minuto o signups de usuarios. Estas metricas de negocio son frecuentemente mas valiosas que las metricas tecnicas.

<br />

Para un deep dive completo en todos estos temas, mira el
[Deep Dive de Observabilidad SRE](/blog/sre-observability-deep-dive-traces-logs-and-metrics). Cubre
patrones de instrumentacion con OpenTelemetry, setup de Loki, Grafana Tempo, alertas basadas en SLOs
con Pyrra, y arquitecturas de observabilidad de nivel produccion.

<br />

##### **Notas finales**
La observabilidad no es opcional. Una vez que tu aplicacion esta corriendo en produccion, necesitas
saber que esta haciendo, como esta rindiendo, y cuando algo sale mal. Los tres pilares (logs,
metricas y traces) te dan vistas complementarias del comportamiento de tu sistema.

<br />

En este articulo cubrimos que es la observabilidad y por que importa, los tres pilares y cuando usar
cada uno, logging estructurado con pino, metricas de Prometheus con prom-client, instalacion de
Prometheus y Grafana con el kube-prometheus-stack, consultas PromQL basicas para escenarios comunes,
armado de dashboards en Grafana, tracing distribuido con OpenTelemetry, alertas con PrometheusRule y
Alertmanager, y el flujo de observabilidad para debuggear problemas de produccion.

<br />

El takeaway clave es que la observabilidad es un flujo de trabajo, no una herramienta. No solo
instalas Prometheus y lo das por terminado. Instrumentas tu aplicacion, armas dashboards que
responden preguntas reales, configuras alertas que te notifican antes que tus usuarios, y practicas
el flujo alerta-dashboard-trace-log hasta que se vuelva segunda naturaleza.

<br />

En el proximo articulo vamos a cubrir pipelines de CI/CD para Kubernetes, juntando todo lo que
construimos hasta ahora en un flujo de deployment automatizado.

<br />

Espero que te haya resultado util y lo hayas disfrutado! Hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en las [fuentes aca](https://github.com/kainlite/tr)
