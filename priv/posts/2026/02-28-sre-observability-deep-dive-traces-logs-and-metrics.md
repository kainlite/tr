%{
  title: "SRE: Observability Deep Dive: Traces, Logs, and Metrics",
  author: "Gabriel Garrido",
  description: "We will explore the three pillars of observability, how to instrument your applications with OpenTelemetry, build useful dashboards in Grafana, and set up log aggregation that actually helps during incidents...",
  tags: ~w(sre kubernetes observability opentelemetry grafana),
  published: true,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In the previous articles we covered [SLIs, SLOs and automations](/blog/sre-slis-slos-and-automations-that-actually-help)
and [incident management](/blog/sre-incident-management-on-call-and-postmortems-as-code). Both of those assume you can
actually see what is happening in your systems. That is what observability is about.

<br />

Monitoring tells you when something is broken. Observability tells you why. The difference matters when you are at 3am
trying to figure out why latency spiked: you need to go from "something is slow" to "this specific database query in
this specific service is slow because it is doing a full table scan" in minutes, not hours.

<br />

In this article we are going to cover the three pillars of observability (metrics, logs, traces), how to instrument
your applications with OpenTelemetry, how to build Grafana dashboards that are actually useful during incidents, and
how to set up log aggregation with Loki. All with practical examples you can apply to your Kubernetes workloads.

<br />

Let's get into it.

<br />

##### **The three pillars**
Observability is built on three types of telemetry data, each with a different purpose:

<br />

> * **Metrics**: Aggregated numerical data over time. "How many requests per second?" "What is the p99 latency?" Fast to query, cheap to store, great for alerting and dashboards.
> * **Logs**: Discrete events with context. "Request X failed with error Y at time Z." Rich in detail but expensive to store and slow to query at scale.
> * **Traces**: The journey of a request through multiple services. "This request hit service A, then B, then C, and the slow part was the call from B to the database." Essential for debugging distributed systems.

<br />

The key insight is that these three are complementary. Metrics tell you something is wrong. Logs tell you what went
wrong. Traces tell you where in the system it went wrong. You need all three.

<br />

```elixir
# The observability flow during an incident:
#
# 1. METRICS: Alert fires: "p99 latency > 300ms for 5 minutes"
#    └─ You know WHAT is wrong
#
# 2. TRACES: Find slow traces: "90% of slow requests go through payment-service → db"
#    └─ You know WHERE it is wrong
#
# 3. LOGS: Check payment-service logs: "ERROR: connection pool exhausted, waited 5s for connection"
#    └─ You know WHY it is wrong
```

<br />

##### **OpenTelemetry: one SDK to instrument them all**
OpenTelemetry (OTel) is the standard for instrumenting applications. It provides a single SDK that can emit
metrics, logs, and traces from your application code. The beauty is that you instrument once and can send the
data to any backend (Prometheus, Jaeger, Grafana, Datadog, etc.).

<br />

For our Elixir/Phoenix application, the setup looks like this:

<br />

```elixir
# mix.exs - add OpenTelemetry dependencies
defp deps do
  [
    # OpenTelemetry core
    {:opentelemetry, "~> 1.4"},
    {:opentelemetry_api, "~> 1.3"},
    {:opentelemetry_exporter, "~> 1.7"},

    # Auto-instrumentation libraries
    {:opentelemetry_phoenix, "~> 2.0"},
    {:opentelemetry_ecto, "~> 1.2"},
    {:opentelemetry_finch, "~> 0.2"},

    # ... your existing deps
  ]
end
```

<br />

Then configure the OpenTelemetry SDK:

<br />

```elixir
# config/runtime.exs
if config_env() == :prod do
  config :opentelemetry,
    span_processor: :batch,
    traces_exporter: :otlp

  config :opentelemetry_exporter,
    otlp_protocol: :grpc,
    otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") || "http://otel-collector:4317"
end
```

<br />

And set up the auto-instrumentation in your application startup:

<br />

```elixir
# lib/tr/application.ex
def start(_type, _args) do
  # Set up OpenTelemetry instrumentation
  OpentelemetryPhoenix.setup(adapter: :bandit)
  OpentelemetryEcto.setup([:tr, :repo])

  children = [
    # ... your existing children
  ]

  opts = [strategy: :one_for_one, name: Tr.Supervisor]
  Supervisor.start_link(children, opts)
end
```

<br />

With just this setup, every HTTP request to your Phoenix app automatically gets a trace with spans for the
controller action, Ecto queries, and outgoing HTTP calls. No manual instrumentation needed for the basics.

<br />

For custom spans when you need more detail:

<br />

```elixir
# lib/tr/search.ex
require OpenTelemetry.Tracer, as: Tracer

def search(term) do
  Tracer.with_span "search.execute" do
    Tracer.set_attribute("search.term", term)

    results =
      Tracer.with_span "search.query_index" do
        Haystack.index(index_name())
        |> Haystack.query(term)
      end

    Tracer.set_attribute("search.results_count", length(results))
    results
  end
end
```

<br />

##### **The OpenTelemetry Collector**
You do not want your application sending telemetry directly to backends. The OpenTelemetry Collector sits
between your apps and your backends, handling batching, retry, filtering, and routing.

<br />

Deploy it as a DaemonSet in Kubernetes so every node has a local collector:

<br />

```elixir
# otel-collector/daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-collector
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
        - name: collector
          image: otel/opentelemetry-collector-contrib:0.96.0
          ports:
            - containerPort: 4317   # gRPC OTLP receiver
              protocol: TCP
            - containerPort: 4318   # HTTP OTLP receiver
              protocol: TCP
          volumeMounts:
            - name: config
              mountPath: /etc/otelcol-contrib
      volumes:
        - name: config
          configMap:
            name: otel-collector-config
```

<br />

The collector configuration routes data to the right backends:

<br />

```elixir
# otel-collector/config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: monitoring
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch:
        timeout: 5s
        send_batch_size: 1000

      # Add resource attributes
      resource:
        attributes:
          - key: k8s.cluster.name
            value: "production"
            action: upsert

      # Filter out health check traces (noise)
      filter:
        traces:
          span:
            - 'attributes["http.target"] == "/health"'
            - 'attributes["http.target"] == "/ready"'

    exporters:
      # Traces to Tempo
      otlp/tempo:
        endpoint: tempo:4317
        tls:
          insecure: true

      # Metrics to Prometheus
      prometheus:
        endpoint: 0.0.0.0:8889

      # Logs to Loki
      loki:
        endpoint: http://loki:3100/loki/api/v1/push

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, resource, filter]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [prometheus]
        logs:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [loki]
```

<br />

This gives you a clean separation: your apps send everything to the local collector, and the collector
handles routing to Tempo (traces), Prometheus (metrics), and Loki (logs).

<br />

##### **Distributed tracing with Tempo**
Grafana Tempo is an excellent trace backend. It is easy to deploy, scales well, and integrates natively
with Grafana for visualization.

<br />

Deploy Tempo in your cluster:

<br />

```elixir
# tempo/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tempo
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tempo
  template:
    metadata:
      labels:
        app: tempo
    spec:
      containers:
        - name: tempo
          image: grafana/tempo:2.4.0
          ports:
            - containerPort: 3200  # HTTP API
            - containerPort: 4317  # gRPC OTLP
          volumeMounts:
            - name: config
              mountPath: /etc/tempo
            - name: data
              mountPath: /var/tempo
      volumes:
        - name: config
          configMap:
            name: tempo-config
        - name: data
          persistentVolumeClaim:
            claimName: tempo-data
```

<br />

With Tempo, you can search for traces by service name, operation, duration, status, or any attribute you
set on your spans. The most useful queries during an incident:

<br />

```elixir
# Find slow traces (latency > 1s) for a specific service
{ resource.service.name = "tr-web" } && duration > 1s

# Find error traces
{ resource.service.name = "tr-web" } && status = error

# Find traces for a specific endpoint
{ resource.service.name = "tr-web" && span.http.target = "/blog" }

# Find traces with database queries over 500ms
{ span.db.system = "postgresql" } && duration > 500ms
```

<br />

The real power of tracing shows up in distributed systems. When a request flows through service A → B → C,
and it is slow, the trace immediately shows you which hop introduced the latency. Without traces, you would
be grepping logs in three different services trying to correlate timestamps.

<br />

##### **Log aggregation with Loki**
Grafana Loki is like Prometheus but for logs. It indexes metadata (labels) rather than the full log content,
making it much cheaper to operate than Elasticsearch-based solutions.

<br />

For Kubernetes, the simplest setup uses Promtail as a DaemonSet to ship container logs to Loki:

<br />

```elixir
# promtail/daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: promtail
  template:
    metadata:
      labels:
        app: promtail
    spec:
      containers:
        - name: promtail
          image: grafana/promtail:2.9.0
          args:
            - -config.file=/etc/promtail/config.yaml
          volumeMounts:
            - name: config
              mountPath: /etc/promtail
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: containers
              mountPath: /var/lib/docker/containers
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: promtail-config
        - name: varlog
          hostPath:
            path: /var/log
        - name: containers
          hostPath:
            path: /var/lib/docker/containers
```

<br />

Promtail automatically discovers pods and enriches logs with Kubernetes labels (namespace, pod name,
container name). You can then query logs in Grafana using LogQL:

<br />

```elixir
# All logs from the tr-web deployment
{namespace="default", app="tr-web"}

# Error logs only
{namespace="default", app="tr-web"} |= "error" != "404"

# Structured log parsing (if using JSON logs)
{namespace="default", app="tr-web"} | json | level="error"

# Counting errors per minute
count_over_time({namespace="default", app="tr-web"} |= "error" [1m])

# Find slow database queries
{namespace="default", app="tr-web"} |= "query" | json | duration > 500
```

<br />

For our Elixir app, structured logging makes Loki much more powerful. Use a JSON logger backend:

<br />

```elixir
# config/prod.exs
config :logger, :console,
  format: {LogfmtEx, :format},
  metadata: [:request_id, :trace_id, :span_id, :user_id]
```

<br />

The `trace_id` in your logs is the key. It lets you jump from a log line to the full distributed trace in
Tempo, connecting the three pillars seamlessly.

<br />

##### **Grafana dashboards that actually help**
Most dashboards are useless during incidents because they show too much information and none of it is
actionable. Here is how to build dashboards that help:

<br />

**1. The RED dashboard (Rate, Errors, Duration)**

This is the single most useful dashboard for any service. Three panels:

<br />

```elixir
# Rate: requests per second
sum(rate(http_requests_total{service="tr-web"}[5m]))

# Errors: error rate percentage
sum(rate(http_requests_total{service="tr-web", status=~"5.."}[5m]))
/
sum(rate(http_requests_total{service="tr-web"}[5m])) * 100

# Duration: latency percentiles
histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{service="tr-web"}[5m])) by (le))
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service="tr-web"}[5m])) by (le))
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service="tr-web"}[5m])) by (le))
```

<br />

**2. The SLO dashboard**

Show error budget burn rate alongside the actual SLI values. This connects to the Sloth-generated recording
rules from the first article:

<br />

```elixir
# Current SLI value (availability over 30 days)
sli:availability:ratio_rate30d{service="tr-web"}

# Error budget remaining
1 - (
  (1 - sli:availability:ratio_rate30d{service="tr-web"})
  /
  (1 - 0.999)
)

# Burn rate (how fast are we consuming error budget)
sli:availability:burn_rate5m{service="tr-web"}
```

<br />

**3. The USE dashboard for infrastructure (Utilization, Saturation, Errors)**

For each infrastructure component (CPU, memory, disk, network):

<br />

```elixir
# CPU utilization
sum(rate(container_cpu_usage_seconds_total{pod=~"tr-web.*"}[5m]))
/
sum(kube_pod_container_resource_limits{pod=~"tr-web.*", resource="cpu"})

# Memory utilization
sum(container_memory_working_set_bytes{pod=~"tr-web.*"})
/
sum(kube_pod_container_resource_limits{pod=~"tr-web.*", resource="memory"})

# Ecto connection pool utilization
ecto_repo_pool_size{repo="Tr.Repo"}
- ecto_repo_pool_idle{repo="Tr.Repo"}
```

<br />

**Dashboard design principles:**

<br />

> * Put the most important panels at the top. During an incident nobody scrolls.
> * Use consistent time ranges across panels. If one panel shows 5m rate and another shows 1h, it is confusing.
> * Add annotations for deployments. A vertical line showing "deploy v1.2.3" helps correlate changes with issues.
> * Use thresholds to color panels red/yellow/green based on SLO targets.
> * Include links to runbooks in panel descriptions.

<br />

##### **Correlating across the three pillars**
The real power of observability comes when you can seamlessly move between metrics, traces, and logs. Grafana
makes this possible through exemplars and data source linking.

<br />

**Exemplars** are trace IDs attached to metric data points. When you see a spike in your latency graph, you
can click on it and jump directly to a trace that was part of that spike:

<br />

```elixir
# In your Prometheus recording rules, enable exemplars
# Prometheus automatically captures trace_id from OTLP metrics

# In Grafana, enable exemplars on your metric panels:
# Panel settings → Query → Exemplars → enabled
```

<br />

**Trace-to-logs linking** lets you click from a trace span to the corresponding logs in Loki:

<br />

```elixir
# In Grafana, configure the Tempo data source with a link to Loki:
# Data Sources → Tempo → Trace to logs
#   - Data source: Loki
#   - Tags: k8s.pod.name → pod
#   - Filter by trace ID: true
```

<br />

With this setup, your debugging flow during an incident becomes:

<br />

> 1. See a spike in the RED dashboard (metrics)
> 2. Click an exemplar to open a trace from that time window
> 3. Find the slow span in the trace (e.g., a database query)
> 4. Click through to logs for that pod around that timestamp
> 5. See the actual error message in the logs

<br />

This entire flow takes seconds, not the minutes or hours of manual log grepping.

<br />

##### **Instrumenting Elixir with OpenTelemetry: practical patterns**
Here are some practical patterns for instrumenting Elixir applications beyond the auto-instrumentation basics:

<br />

**Background jobs (like our Quantum tasks)**

<br />

```elixir
# lib/tr/sponsors.ex
require OpenTelemetry.Tracer, as: Tracer

def start do
  Tracer.with_span "sponsors.sync", %{kind: :internal} do
    start_app()

    sponsors = get_sponsors(100)
    nodes = get_in(sponsors, ["data", "user", "sponsors", "nodes"]) || []

    Tracer.set_attribute("sponsors.count", length(nodes))

    Enum.each(nodes, fn sponsor ->
      Tr.SponsorsCache.add_or_update(sponsor)
    end)

    :ok
  end
end
```

<br />

**GenServer operations**

<br />

```elixir
# lib/tr/sponsors_cache.ex
def handle_call({:get, login}, _from, state) do
  Tracer.with_span "sponsors_cache.get" do
    Tracer.set_attribute("sponsor.login", login)
    result = Map.get(state, login)
    {:reply, result, state}
  end
end
```

<br />

**LiveView interactions**

<br />

```elixir
# lib/tr_web/live/search_live.ex
def handle_event("search", %{"q" => query}, socket) do
  Tracer.with_span "live.search", %{attributes: %{"search.query" => query}} do
    results = Tr.Search.search(query)
    Tracer.set_attribute("search.results_count", length(results))
    {:noreply, assign(socket, results: results, query: query)}
  end
end
```

<br />

##### **Alerting on observability data**
Combine your SLO-based alerts (from article 1) with observability-driven alerts:

<br />

```elixir
# alerts.yaml
groups:
  - name: observability.alerts
    rules:
      # Alert when trace error rate spikes
      - alert: HighTraceErrorRate
        expr: |
          sum(rate(traces_spanmetrics_calls_total{status_code="STATUS_CODE_ERROR", service_name="tr-web"}[5m]))
          /
          sum(rate(traces_spanmetrics_calls_total{service_name="tr-web"}[5m]))
          > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected in traces"
          dashboard: "https://grafana.example.com/d/red-dashboard"

      # Alert when log error rate spikes
      - alert: HighLogErrorRate
        expr: |
          sum(rate({namespace="default", app="tr-web"} |= "error" [5m]))
          > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate in logs"

      # Alert when a database query is consistently slow
      - alert: SlowDatabaseQueries
        expr: |
          histogram_quantile(0.95,
            sum(rate(ecto_repo_query_duration_seconds_bucket{repo="Tr.Repo"}[5m])) by (le, source)
          ) > 1.0
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Database queries from {{ $labels.source }} are consistently slow"
```

<br />

##### **Putting it all together**
Here is the complete observability stack for a Kubernetes-based application:

<br />

> 1. **OpenTelemetry SDK** in your application emits metrics, traces, and enriches logs with trace context
> 2. **OTel Collector** (DaemonSet) receives telemetry, processes it, and routes to backends
> 3. **Prometheus** stores metrics and evaluates SLO-based alert rules
> 4. **Tempo** stores traces and enables trace search
> 5. **Loki + Promtail** aggregates logs from all containers
> 6. **Grafana** ties everything together with dashboards, exemplars, and cross-linking
> 7. **Alertmanager** routes alerts to PagerDuty based on severity

<br />

The ArgoCD-managed manifests from article 1 can deploy all of this. Store the configs in Git, let ArgoCD
sync them, and you have a fully GitOps-managed observability stack.

<br />

##### **What to avoid**
Some common observability anti-patterns:

<br />

> * **Do not log everything**. High-cardinality logs are expensive. Log events, not every function call.
> * **Do not trace everything**. Filter out health checks and readiness probes. They are noise.
> * **Do not create a dashboard for every metric**. Start with RED and USE, add more only when needed.
> * **Do not forget sampling**. In production at scale, trace 10-20% of requests. Sample 100% of errors.
> * **Do not skip structured logging**. Unstructured logs ("something went wrong") are almost useless in Loki.

<br />

##### **Closing notes**
Observability is not about having more data. It is about having the right data connected in the right way so
you can go from "something is wrong" to "I know exactly what is wrong and why" in minutes.

<br />

The stack we covered: OpenTelemetry, Prometheus, Tempo, Loki, Grafana: is all open source and runs
beautifully in Kubernetes. Start with auto-instrumentation (it takes 10 minutes to set up), build a RED
dashboard, and add more instrumentation as you need it.

<br />

In the next article we will explore chaos engineering: how to proactively break your systems to build
confidence in your observability and incident response processes.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Observabilidad a Fondo: Trazas, Logs y Métricas",
  author: "Gabriel Garrido",
  description: "Vamos a explorar los tres pilares de la observabilidad, cómo instrumentar tus aplicaciones con OpenTelemetry, construir dashboards útiles en Grafana, y configurar agregación de logs que realmente ayude durante incidentes...",
  tags: ~w(sre kubernetes observability opentelemetry grafana),
  published: true,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En los artículos anteriores cubrimos [SLIs, SLOs y automatizaciones](/blog/sre-slis-slos-and-automations-that-actually-help)
y [gestión de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code). Ambos asumen que realmente
podés ver lo que está pasando en tus sistemas. De eso se trata la observabilidad.

<br />

El monitoreo te dice cuándo algo está roto. La observabilidad te dice por qué. La diferencia importa cuando estás a
las 3am tratando de entender por qué la latencia subió: necesitás pasar de "algo está lento" a "esta consulta
específica a la base de datos en este servicio específico es lenta porque está haciendo un full table scan" en minutos,
no en horas.

<br />

En este artículo vamos a cubrir los tres pilares de la observabilidad (métricas, logs, trazas), cómo instrumentar
tus aplicaciones con OpenTelemetry, cómo construir dashboards de Grafana que sean realmente útiles durante incidentes,
y cómo configurar agregación de logs con Loki. Todo con ejemplos prácticos que podés aplicar a tus cargas de trabajo
en Kubernetes.

<br />

Vamos al tema.

<br />

##### **Los tres pilares**
La observabilidad se construye sobre tres tipos de datos de telemetría, cada uno con un propósito diferente:

<br />

> * **Métricas**: Datos numéricos agregados a lo largo del tiempo. "¿Cuántas requests por segundo?" "¿Cuál es la latencia p99?" Rápidas de consultar, baratas de almacenar, geniales para alertas y dashboards.
> * **Logs**: Eventos discretos con contexto. "La request X falló con error Y en el momento Z." Ricos en detalle pero caros de almacenar y lentos de consultar a escala.
> * **Trazas**: El recorrido de una request a través de múltiples servicios. "Esta request pasó por el servicio A, después B, después C, y la parte lenta fue la llamada de B a la base de datos." Esenciales para debuggear sistemas distribuidos.

<br />

La idea clave es que estos tres son complementarios. Las métricas te dicen que algo anda mal. Los logs te dicen qué
salió mal. Las trazas te dicen en qué parte del sistema salió mal. Necesitás los tres.

<br />

```elixir
# El flujo de observabilidad durante un incidente:
#
# 1. MÉTRICAS: Alerta salta: "latencia p99 > 300ms por 5 minutos"
#    └─ Sabés QUÉ anda mal
#
# 2. TRAZAS: Encontrás trazas lentas: "90% de las requests lentas pasan por payment-service → db"
#    └─ Sabés DÓNDE anda mal
#
# 3. LOGS: Revisás logs de payment-service: "ERROR: pool de conexiones agotado, esperó 5s por conexión"
#    └─ Sabés POR QUÉ anda mal
```

<br />

##### **OpenTelemetry: un SDK para instrumentar todo**
OpenTelemetry (OTel) es el estándar para instrumentar aplicaciones. Provee un único SDK que puede emitir
métricas, logs y trazas desde tu código. Lo lindo es que instrumentás una vez y podés enviar los datos a
cualquier backend (Prometheus, Jaeger, Grafana, Datadog, etc.).

<br />

Para nuestra aplicación Elixir/Phoenix, el setup se ve así:

<br />

```elixir
# mix.exs - agregar dependencias de OpenTelemetry
defp deps do
  [
    # OpenTelemetry core
    {:opentelemetry, "~> 1.4"},
    {:opentelemetry_api, "~> 1.3"},
    {:opentelemetry_exporter, "~> 1.7"},

    # Librerías de auto-instrumentación
    {:opentelemetry_phoenix, "~> 2.0"},
    {:opentelemetry_ecto, "~> 1.2"},
    {:opentelemetry_finch, "~> 0.2"},

    # ... tus deps existentes
  ]
end
```

<br />

Después configurás el SDK de OpenTelemetry:

<br />

```elixir
# config/runtime.exs
if config_env() == :prod do
  config :opentelemetry,
    span_processor: :batch,
    traces_exporter: :otlp

  config :opentelemetry_exporter,
    otlp_protocol: :grpc,
    otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") || "http://otel-collector:4317"
end
```

<br />

Y configurás la auto-instrumentación en el arranque de tu aplicación:

<br />

```elixir
# lib/tr/application.ex
def start(_type, _args) do
  # Configurar instrumentación de OpenTelemetry
  OpentelemetryPhoenix.setup(adapter: :bandit)
  OpentelemetryEcto.setup([:tr, :repo])

  children = [
    # ... tus children existentes
  ]

  opts = [strategy: :one_for_one, name: Tr.Supervisor]
  Supervisor.start_link(children, opts)
end
```

<br />

Con solo este setup, cada request HTTP a tu app Phoenix automáticamente tiene una traza con spans para la
acción del controller, las consultas de Ecto, y las llamadas HTTP salientes. Sin instrumentación manual para
lo básico.

<br />

Para spans customizados cuando necesitás más detalle:

<br />

```elixir
# lib/tr/search.ex
require OpenTelemetry.Tracer, as: Tracer

def search(term) do
  Tracer.with_span "search.execute" do
    Tracer.set_attribute("search.term", term)

    results =
      Tracer.with_span "search.query_index" do
        Haystack.index(index_name())
        |> Haystack.query(term)
      end

    Tracer.set_attribute("search.results_count", length(results))
    results
  end
end
```

<br />

##### **El Collector de OpenTelemetry**
No querés que tu aplicación envíe telemetría directamente a los backends. El Collector de OpenTelemetry se
sienta entre tus apps y tus backends, manejando batching, reintentos, filtrado y ruteo.

<br />

Deployalo como un DaemonSet en Kubernetes para que cada nodo tenga un collector local:

<br />

```elixir
# otel-collector/daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-collector
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
        - name: collector
          image: otel/opentelemetry-collector-contrib:0.96.0
          ports:
            - containerPort: 4317   # receptor OTLP gRPC
              protocol: TCP
            - containerPort: 4318   # receptor OTLP HTTP
              protocol: TCP
          volumeMounts:
            - name: config
              mountPath: /etc/otelcol-contrib
      volumes:
        - name: config
          configMap:
            name: otel-collector-config
```

<br />

La configuración del collector rutea datos a los backends correctos:

<br />

```elixir
# otel-collector/config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: monitoring
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch:
        timeout: 5s
        send_batch_size: 1000

      # Agregar atributos de recurso
      resource:
        attributes:
          - key: k8s.cluster.name
            value: "production"
            action: upsert

      # Filtrar trazas de health check (ruido)
      filter:
        traces:
          span:
            - 'attributes["http.target"] == "/health"'
            - 'attributes["http.target"] == "/ready"'

    exporters:
      # Trazas a Tempo
      otlp/tempo:
        endpoint: tempo:4317
        tls:
          insecure: true

      # Métricas a Prometheus
      prometheus:
        endpoint: 0.0.0.0:8889

      # Logs a Loki
      loki:
        endpoint: http://loki:3100/loki/api/v1/push

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, resource, filter]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [prometheus]
        logs:
          receivers: [otlp]
          processors: [batch, resource]
          exporters: [loki]
```

<br />

Esto te da una separación limpia: tus apps envían todo al collector local, y el collector maneja el ruteo a
Tempo (trazas), Prometheus (métricas) y Loki (logs).

<br />

##### **Trazabilidad distribuida con Tempo**
Grafana Tempo es un excelente backend de trazas. Es fácil de deployar, escala bien, y se integra nativamente
con Grafana para visualización.

<br />

Las consultas más útiles durante un incidente:

<br />

```elixir
# Encontrar trazas lentas (latencia > 1s) para un servicio específico
{ resource.service.name = "tr-web" } && duration > 1s

# Encontrar trazas con error
{ resource.service.name = "tr-web" } && status = error

# Encontrar trazas para un endpoint específico
{ resource.service.name = "tr-web" && span.http.target = "/blog" }

# Encontrar trazas con consultas a DB de más de 500ms
{ span.db.system = "postgresql" } && duration > 500ms
```

<br />

El verdadero poder del tracing se muestra en sistemas distribuidos. Cuando una request fluye por servicio
A → B → C, y es lenta, la traza inmediatamente te muestra qué hop introdujo la latencia. Sin trazas, estarías
greppeando logs en tres servicios diferentes tratando de correlacionar timestamps.

<br />

##### **Agregación de logs con Loki**
Grafana Loki es como Prometheus pero para logs. Indexa metadatos (labels) en lugar del contenido completo del
log, haciéndolo mucho más barato de operar que soluciones basadas en Elasticsearch.

<br />

Para Kubernetes, el setup más simple usa Promtail como DaemonSet para enviar logs de contenedores a Loki.
Promtail descubre pods automáticamente y enriquece los logs con labels de Kubernetes (namespace, nombre del
pod, nombre del contenedor). Después podés consultar logs en Grafana usando LogQL:

<br />

```elixir
# Todos los logs del deployment tr-web
{namespace="default", app="tr-web"}

# Solo logs de error
{namespace="default", app="tr-web"} |= "error" != "404"

# Parseo de logs estructurados (si usás logs JSON)
{namespace="default", app="tr-web"} | json | level="error"

# Contando errores por minuto
count_over_time({namespace="default", app="tr-web"} |= "error" [1m])

# Encontrar consultas lentas a la base de datos
{namespace="default", app="tr-web"} |= "query" | json | duration > 500
```

<br />

Para nuestra app Elixir, el logging estructurado hace a Loki mucho más poderoso:

<br />

```elixir
# config/prod.exs
config :logger, :console,
  format: {LogfmtEx, :format},
  metadata: [:request_id, :trace_id, :span_id, :user_id]
```

<br />

El `trace_id` en tus logs es la clave. Te permite saltar de una línea de log a la traza distribuida completa
en Tempo, conectando los tres pilares sin problemas.

<br />

##### **Dashboards de Grafana que realmente ayudan**
La mayoría de los dashboards son inútiles durante incidentes porque muestran demasiada información y nada de
ella es accionable. Acá cómo construir dashboards que ayuden:

<br />

**1. El dashboard RED (Rate, Errors, Duration)**

Este es el dashboard más útil para cualquier servicio. Tres paneles:

<br />

```elixir
# Tasa: requests por segundo
sum(rate(http_requests_total{service="tr-web"}[5m]))

# Errores: porcentaje de tasa de error
sum(rate(http_requests_total{service="tr-web", status=~"5.."}[5m]))
/
sum(rate(http_requests_total{service="tr-web"}[5m])) * 100

# Duración: percentiles de latencia
histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{service="tr-web"}[5m])) by (le))
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service="tr-web"}[5m])) by (le))
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service="tr-web"}[5m])) by (le))
```

<br />

**2. El dashboard de SLO**

Mostrá la tasa de quemado del presupuesto de error junto con los valores reales del SLI:

<br />

```elixir
# Valor actual del SLI (disponibilidad en 30 días)
sli:availability:ratio_rate30d{service="tr-web"}

# Presupuesto de error restante
1 - (
  (1 - sli:availability:ratio_rate30d{service="tr-web"})
  /
  (1 - 0.999)
)
```

<br />

**Principios de diseño de dashboards:**

<br />

> * Poné los paneles más importantes arriba. Durante un incidente nadie scrollea.
> * Usá rangos de tiempo consistentes en todos los paneles.
> * Agregá anotaciones para deploys. Una línea vertical mostrando "deploy v1.2.3" ayuda a correlacionar cambios con problemas.
> * Usá umbrales para colorear paneles en rojo/amarillo/verde basándose en objetivos de SLO.
> * Incluí links a runbooks en las descripciones de los paneles.

<br />

##### **Correlacionando los tres pilares**
El verdadero poder de la observabilidad viene cuando podés moverte sin problemas entre métricas, trazas y logs.
Grafana hace esto posible a través de exemplars y linking entre data sources.

<br />

Los **exemplars** son trace IDs adjuntados a puntos de datos de métricas. Cuando ves un pico en tu gráfico de
latencia, podés hacer clic y saltar directamente a una traza que fue parte de ese pico.

<br />

El **linking de traza a logs** te permite hacer clic desde un span de traza a los logs correspondientes en Loki.

<br />

Con este setup, tu flujo de debugging durante un incidente se convierte en:

<br />

> 1. Ves un pico en el dashboard RED (métricas)
> 2. Hacés clic en un exemplar para abrir una traza de esa ventana de tiempo
> 3. Encontrás el span lento en la traza (ej: una consulta a la base de datos)
> 4. Hacés clic para ir a los logs de ese pod alrededor de ese timestamp
> 5. Ves el mensaje de error real en los logs

<br />

Todo este flujo toma segundos, no los minutos u horas de greppear logs manualmente.

<br />

##### **Instrumentando Elixir con OpenTelemetry: patrones prácticos**
Acá van algunos patrones prácticos para instrumentar aplicaciones Elixir más allá de la auto-instrumentación
básica:

<br />

**Jobs en background (como nuestras tareas de Quantum)**

<br />

```elixir
# lib/tr/sponsors.ex
require OpenTelemetry.Tracer, as: Tracer

def start do
  Tracer.with_span "sponsors.sync", %{kind: :internal} do
    start_app()

    sponsors = get_sponsors(100)
    nodes = get_in(sponsors, ["data", "user", "sponsors", "nodes"]) || []

    Tracer.set_attribute("sponsors.count", length(nodes))

    Enum.each(nodes, fn sponsor ->
      Tr.SponsorsCache.add_or_update(sponsor)
    end)

    :ok
  end
end
```

<br />

**Operaciones de GenServer**

<br />

```elixir
# lib/tr/sponsors_cache.ex
def handle_call({:get, login}, _from, state) do
  Tracer.with_span "sponsors_cache.get" do
    Tracer.set_attribute("sponsor.login", login)
    result = Map.get(state, login)
    {:reply, result, state}
  end
end
```

<br />

**Interacciones de LiveView**

<br />

```elixir
# lib/tr_web/live/search_live.ex
def handle_event("search", %{"q" => query}, socket) do
  Tracer.with_span "live.search", %{attributes: %{"search.query" => query}} do
    results = Tr.Search.search(query)
    Tracer.set_attribute("search.results_count", length(results))
    {:noreply, assign(socket, results: results, query: query)}
  end
end
```

<br />

##### **Qué evitar**
Algunos anti-patrones comunes de observabilidad:

<br />

> * **No loguees todo**. Logs de alta cardinalidad son caros. Logueá eventos, no cada llamada a función.
> * **No traces todo**. Filtrá health checks y readiness probes. Son ruido.
> * **No crees un dashboard para cada métrica**. Empezá con RED y USE, agregá más solo cuando sea necesario.
> * **No te olvides del sampling**. En producción a escala, traceá 10-20% de las requests. Sampleá 100% de los errores.
> * **No te saltees el logging estructurado**. Logs no estructurados ("algo salió mal") son casi inútiles en Loki.

<br />

##### **Notas finales**
La observabilidad no se trata de tener más datos. Se trata de tener los datos correctos conectados de la manera
correcta para que puedas pasar de "algo anda mal" a "sé exactamente qué anda mal y por qué" en minutos.

<br />

El stack que cubrimos: OpenTelemetry, Prometheus, Tempo, Loki, Grafana, es todo open source y corre hermosamente
en Kubernetes. Empezá con auto-instrumentación (se configura en 10 minutos), construí un dashboard RED, y agregá
más instrumentación a medida que la necesites.

<br />

En el próximo artículo vamos a explorar chaos engineering: cómo romper proactivamente tus sistemas para construir
confianza en tu observabilidad y procesos de respuesta a incidentes.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
