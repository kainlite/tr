%{
  title: "SRE: SLIs, SLOs, and Automations That Actually Help",
  author: "Gabriel Garrido",
  description: "We will explore how to define SLIs and SLOs as code, deploy them with ArgoCD, and use MCP servers to automate SRE workflows...",
  tags: ~w(sre kubernetes argocd observability automation),
  published: true,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In this article we will explore the practical side of Site Reliability Engineering (SRE), specifically how to define
Service Level Indicators (SLIs) and Service Level Objectives (SLOs) as code, deploy them using ArgoCD, and leverage
MCP servers and automations to make the whole process less painful.

<br />

If you have been doing operations or platform engineering for a while, you probably already know that monitoring alone
is not enough. Having a dashboard full of green lights does not mean your users are happy. SLIs and SLOs give you a
framework to measure what actually matters and make informed decisions about reliability vs. feature velocity.

<br />

Let's get into it.

<br />

##### **What is SRE anyway?**
Site Reliability Engineering is a discipline that applies software engineering practices to operations problems. Google
popularized the concept, but the core idea is simple: treat your infrastructure and operational processes as code,
measure what matters, and use error budgets to balance reliability with the speed of shipping new features.

<br />

The key components are:

> * **SLIs (Service Level Indicators)**: Metrics that measure the quality of your service from the user's perspective
> * **SLOs (Service Level Objectives)**: Targets you set for your SLIs (e.g., "99.9% of requests should succeed")
> * **Error Budgets**: The acceptable amount of unreliability (100% - SLO target)
> * **SLAs (Service Level Agreements)**: Business contracts based on SLOs (we won't focus on these here)

<br />

##### **Understanding SLIs**
An SLI is a carefully defined quantitative measure of some aspect of the level of service provided. The most common
SLIs are:

<br />

> * **Availability**: The proportion of requests that succeed
> * **Latency**: The proportion of requests that are faster than a threshold
> * **Quality**: The proportion of responses that are not degraded

<br />

The important thing here is the "proportion" part. SLIs are expressed as ratios:

```elixir
SLI = good events / total events
```

<br />

For example, for an HTTP service:

```elixir
# Availability SLI
availability = (total_requests - 5xx_errors) / total_requests

# Latency SLI
latency = requests_faster_than_300ms / total_requests
```

<br />

This is much more useful than raw metrics because it directly reflects user experience. A spike in errors that lasts
5 seconds is very different from one that lasts 5 minutes, and the ratio captures that difference over a time window.

<br />

##### **Understanding SLOs**
An SLO is the target value for an SLI over a specific time window. For example:

<br />

> * "99.9% of HTTP requests should return a non-error response over a 30-day rolling window"
> * "99% of requests should complete in less than 300ms over a 30-day rolling window"

<br />

The SLO gives you an **error budget**. If your SLO is 99.9%, your error budget is 0.1%. Over 30 days, that means
you can afford roughly 43 minutes of total downtime. This is incredibly powerful because it turns reliability into
a measurable resource you can spend. Want to do a risky deployment? Check your error budget first.

<br />

##### **Putting SLIs into code with Prometheus**
Now let's get practical. The most common way to implement SLIs is with Prometheus metrics. If you are running
workloads in Kubernetes, you probably already have Prometheus or a compatible system collecting metrics.

<br />

For a typical web service, you want to expose a histogram that tracks request duration and status:

```elixir
# If your application uses Prometheus client, expose something like:
# histogram: http_request_duration_seconds (with labels: method, path, status)
# counter: http_requests_total (with labels: method, path, status)

# For our Phoenix/Elixir app, we rely on phoenix_telemetry and peep to expose these.
# But the concept applies to any language.
```

<br />

With those metrics in Prometheus, you can define recording rules that calculate the SLI ratios. Here is an
example of Prometheus recording rules for an HTTP availability SLI:

```elixir
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sli-availability
  namespace: monitoring
spec:
  groups:
    - name: sli.availability
      interval: 30s
      rules:
        # Total requests rate over 5m window
        - record: sli:http_requests:rate5m
          expr: sum(rate(http_requests_total[5m]))

        # Error requests rate over 5m window (5xx responses)
        - record: sli:http_errors:rate5m
          expr: sum(rate(http_requests_total{status=~"5.."}[5m]))

        # Availability SLI (ratio of successful requests)
        - record: sli:availability:ratio_rate5m
          expr: |
            1 - (sli:http_errors:rate5m / sli:http_requests:rate5m)
```

<br />

And for a latency SLI:

```elixir
# prometheus-rules-latency.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sli-latency
  namespace: monitoring
spec:
  groups:
    - name: sli.latency
      interval: 30s
      rules:
        # Requests faster than 300ms
        - record: sli:http_request_duration:rate5m
          expr: sum(rate(http_request_duration_seconds_bucket{le="0.3"}[5m]))

        # All requests
        - record: sli:http_request_duration_total:rate5m
          expr: sum(rate(http_request_duration_seconds_count[5m]))

        # Latency SLI
        - record: sli:latency:ratio_rate5m
          expr: |
            sli:http_request_duration:rate5m / sli:http_request_duration_total:rate5m
```

<br />

These recording rules pre-compute the SLI ratios so you can use them in alerting and dashboards without running
expensive queries every time.

<br />

##### **SLOs as code with Sloth**
Writing Prometheus recording rules and alert rules by hand for every SLO gets tedious fast. That's where
[Sloth](https://github.com/slok/sloth) comes in. Sloth is a tool that generates all the Prometheus rules you need
from a simple SLO definition.

<br />

Here is an SLO definition for our service:

```elixir
# slos/tr-web.yaml
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata:
  name: tr-web
  namespace: default
spec:
  service: "tr-web"
  labels:
    team: "platform"
  slos:
    - name: "requests-availability"
      objective: 99.9
      description: "99.9% of HTTP requests should succeed"
      sli:
        events:
          error_query: sum(rate(http_requests_total{status=~"5..",service="tr-web"}[{{.window}}]))
          total_query: sum(rate(http_requests_total{service="tr-web"}[{{.window}}]))
      alerting:
        name: TrWebHighErrorRate
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "High error rate on tr-web"
        page_alert:
          labels:
            severity: critical
        ticket_alert:
          labels:
            severity: warning

    - name: "requests-latency"
      objective: 99.0
      description: "99% of requests should be faster than 300ms"
      sli:
        events:
          error_query: |
            sum(rate(http_request_duration_seconds_count{service="tr-web"}[{{.window}}]))
            -
            sum(rate(http_request_duration_seconds_bucket{le="0.3",service="tr-web"}[{{.window}}]))
          total_query: sum(rate(http_request_duration_seconds_count{service="tr-web"}[{{.window}}]))
      alerting:
        name: TrWebHighLatency
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "High latency on tr-web"
        page_alert:
          labels:
            severity: critical
        ticket_alert:
          labels:
            severity: warning
```

<br />

Then you generate the Prometheus rules:

```elixir
sloth generate -i slos/tr-web.yaml -o prometheus-rules/tr-web-slo.yaml
```

<br />

Sloth generates multi-window, multi-burn-rate alerts following the Google SRE book recommendations. You get
fast-burn alerts (something is very wrong right now) and slow-burn alerts (you are consuming error budget faster
than expected). This is a massive improvement over manually crafting alert thresholds.

<br />

##### **Deploying SLOs with ArgoCD**
Now that we have our SLO definitions and generated Prometheus rules as YAML files, we can deploy them the
GitOps way using ArgoCD. If you read my [previous article about GitOps](/blog/lets-talk-gitops), this will feel
familiar.

<br />

The idea is simple: store your SLO definitions and generated rules in a Git repository, and let ArgoCD sync them
to your cluster.

<br />

Here is the repository structure:

```elixir
slo-configs/
├── slos/
│   ├── tr-web.yaml            # Sloth SLO definitions
│   └── api-gateway.yaml
├── generated/
│   ├── tr-web-slo.yaml        # Generated PrometheusRule resources
│   └── api-gateway-slo.yaml
├── dashboards/
│   ├── tr-web-slo.json        # Grafana dashboard JSON
│   └── api-gateway-slo.json
└── argocd/
    └── application.yaml        # ArgoCD Application manifest
```

<br />

The ArgoCD Application manifest:

```elixir
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: slo-configs
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kainlite/slo-configs
    targetRevision: HEAD
    path: generated
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

With this setup, every time you update an SLO definition, regenerate the rules, and push to Git, ArgoCD
automatically applies the changes to your cluster. No manual kubectl commands, no forgetting to apply that one
file you changed last week.

<br />

You can also set up a CI step to automatically regenerate the Prometheus rules when the SLO definitions change:

```elixir
# .github/workflows/generate-slos.yaml
name: Generate SLO Rules

on:
  push:
    paths:
      - 'slos/**'

jobs:
  generate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Sloth
        run: |
          curl -L https://github.com/slok/sloth/releases/latest/download/sloth-linux-amd64 -o sloth
          chmod +x sloth

      - name: Generate rules
        run: |
          for slo in slos/*.yaml; do
            name=$(basename "$slo" .yaml)
            ./sloth generate -i "$slo" -o "generated/${name}-slo.yaml"
          done

      - name: Commit and push
        run: |
          git config user.name "github-actions"
          git config user.email "actions@github.com"
          git add generated/
          git diff --staged --quiet || git commit -m "chore: regenerate SLO rules"
          git push
```

<br />

Now you have a fully automated pipeline: edit an SLO definition, push, CI generates the rules, ArgoCD deploys
them. Beautiful.

<br />

##### **MCP servers for SRE automation**
This is where things get really interesting. Model Context Protocol (MCP) servers allow you to give AI assistants
like Claude access to your infrastructure tools. Imagine being able to ask "what's my current error budget for
tr-web?" and getting an actual answer from your live Prometheus data.

<br />

An MCP server is essentially an API that exposes tools an AI can call. You can build one that wraps your
Prometheus and Kubernetes APIs:

```elixir
// mcp-sre-server/src/main.rs
// A simplified example of an MCP server for SRE queries

use mcp_server::{Server, Tool, ToolResult};

#[derive(Tool)]
#[tool(name = "query_error_budget", description = "Query remaining error budget for a service")]
struct QueryErrorBudget {
    service: String,
    slo_name: String,
}

impl QueryErrorBudget {
    async fn execute(&self) -> ToolResult {
        let query = format!(
            r#"1 - (
                sli:availability:ratio_rate30d{{service="{}"}}
            ) / (1 - {}.0/100)"#,
            self.service, self.objective
        );

        let result = prometheus_query(&query).await?;
        ToolResult::text(format!(
            "Error budget for {}/{}: {:.2}% remaining",
            self.service, self.slo_name, result * 100.0
        ))
    }
}

#[derive(Tool)]
#[tool(name = "list_slo_violations", description = "List SLOs that are currently burning too fast")]
struct ListSloViolations;

impl ListSloViolations {
    async fn execute(&self) -> ToolResult {
        let query = r#"ALERTS{alertname=~".*SLO.*", alertstate="firing"}"#;
        let alerts = prometheus_query(query).await?;
        ToolResult::text(format!("Active SLO violations:\n{}", alerts))
    }
}

#[derive(Tool)]
#[tool(name = "get_deployment_risk", description = "Assess deployment risk based on current error budget")]
struct GetDeploymentRisk {
    service: String,
}

impl GetDeploymentRisk {
    async fn execute(&self) -> ToolResult {
        let budget = get_error_budget(&self.service).await?;
        let recent_deploys = get_recent_deploys(&self.service).await?;

        let risk = match budget {
            b if b > 0.5 => "LOW - plenty of error budget remaining",
            b if b > 0.2 => "MEDIUM - error budget is getting low",
            b if b > 0.0 => "HIGH - very little error budget left",
            _ => "CRITICAL - error budget exhausted, consider freezing deploys",
        };

        ToolResult::text(format!(
            "Deployment risk for {}: {}\nBudget remaining: {:.1}%\nRecent deploys: {}",
            self.service, risk, budget * 100.0, recent_deploys
        ))
    }
}
```

<br />

With this MCP server running, you can configure Claude Code or any MCP-compatible client to connect to it. Then
you get natural language access to your SRE data:

<br />

> * "What's the error budget for tr-web?" → Queries Prometheus, returns remaining budget
> * "Is it safe to deploy right now?" → Checks error budget + recent incidents
> * "Which SLOs are at risk this week?" → Lists SLOs with high burn rates
> * "Show me the latency trend for the last 24h" → Queries Prometheus and summarizes

<br />

You can also build MCP tools that integrate with ArgoCD:

```elixir
#[derive(Tool)]
#[tool(name = "argocd_sync_status", description = "Check ArgoCD sync status for SLO configs")]
struct ArgoCDSyncStatus;

impl ArgoCDSyncStatus {
    async fn execute(&self) -> ToolResult {
        let output = Command::new("argocd")
            .args(["app", "get", "slo-configs", "-o", "json"])
            .output()
            .await?;

        let app: ArgoApp = serde_json::from_slice(&output.stdout)?;
        ToolResult::text(format!(
            "SLO configs sync status: {}\nHealth: {}\nLast sync: {}",
            app.status.sync.status,
            app.status.health.status,
            app.status.sync.compared_to.revision
        ))
    }
}

#[derive(Tool)]
#[tool(name = "rollback_deployment", description = "Rollback a service deployment via ArgoCD")]
struct RollbackDeployment {
    service: String,
    revision: Option<String>,
}

impl RollbackDeployment {
    async fn execute(&self) -> ToolResult {
        // This would be gated behind confirmation in a real setup
        let revision = self.revision.as_deref().unwrap_or("HEAD~1");
        let output = Command::new("argocd")
            .args(["app", "rollback", &self.service, "--revision", revision])
            .output()
            .await?;

        ToolResult::text(format!("Rollback initiated for {} to {}", self.service, revision))
    }
}
```

<br />

The MCP server config in your Claude Code settings would look something like:

```elixir
{
  "mcpServers": {
    "sre-tools": {
      "command": "mcp-sre-server",
      "args": ["--prometheus-url", "http://prometheus:9090", "--argocd-url", "https://argocd.example.com"],
      "env": {
        "ARGOCD_AUTH_TOKEN": "your-token-here"
      }
    }
  }
}
```

<br />

##### **Automations that tie it all together**
The real power comes when you combine SLOs, ArgoCD, and MCP servers into automated workflows. Here are some
patterns that work well in practice:

<br />

**1. Automated deployment gates**

Use error budgets as deployment gates. If the error budget is below a threshold, block deployments automatically:

```elixir
# In your CI pipeline
- name: Check error budget
  run: |
    BUDGET=$(curl -s "http://prometheus:9090/api/v1/query?query=error_budget_remaining{service='tr-web'}" \
      | jq -r '.data.result[0].value[1]')

    if (( $(echo "$BUDGET < 0.1" | bc -l) )); then
      echo "Error budget below 10%, blocking deployment"
      exit 1
    fi
```

<br />

**2. Automated incident creation**

When an SLO is breached, automatically create an issue or incident:

```elixir
# alertmanager-config.yaml
receivers:
  - name: slo-breach
    webhook_configs:
      - url: http://incident-bot:8080/create
        send_resolved: true

route:
  routes:
    - match:
        severity: critical
        type: slo_breach
      receiver: slo-breach
```

<br />

**3. Weekly SLO reports**

Automate weekly SLO reporting to keep the team informed:

```elixir
# A CronJob that queries Prometheus and sends a summary to Slack
apiVersion: batch/v1
kind: CronJob
metadata:
  name: slo-weekly-report
  namespace: monitoring
spec:
  schedule: "0 9 * * 1"  # Every Monday at 9am
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: reporter
              image: kainlite/slo-reporter:latest
              env:
                - name: PROMETHEUS_URL
                  value: "http://prometheus:9090"
                - name: SLACK_WEBHOOK
                  valueFrom:
                    secretKeyRef:
                      name: slack-webhook
                      key: url
          restartPolicy: Never
```

<br />

**4. Error budget-based feature freeze**

This is one of the most powerful SRE patterns. When error budget is exhausted, the team should shift focus
from features to reliability work:

<br />

> * **Budget > 50%**: Ship features freely
> * **Budget 20-50%**: Be cautious with risky changes
> * **Budget 5-20%**: Focus on reliability improvements
> * **Budget < 5%**: Feature freeze, all hands on reliability

<br />

You can automate this by having your MCP server update a status page or Slack channel with the current
budget level, so everyone on the team knows where things stand without having to check dashboards.

<br />

##### **Putting it all together**
Here is a summary of what we built:

<br />

> 1. **SLIs as Prometheus metrics**: Recording rules that calculate availability and latency ratios
> 2. **SLOs with Sloth**: Declarative SLO definitions that generate multi-window, multi-burn-rate alerts
> 3. **GitOps with ArgoCD**: SLO configs stored in Git, automatically synced to the cluster
> 4. **MCP servers**: Natural language interface to query error budgets, check deployment risk, and manage ArgoCD
> 5. **Automations**: Deployment gates, incident creation, weekly reports, and error budget policies

<br />

The beauty of this approach is that each piece is simple on its own, but together they create a system where
reliability is measurable, automated, and part of the team's daily workflow rather than an afterthought.

<br />

##### **Closing notes**
SRE does not have to be complicated. Start with one SLI for your most important service, set a reasonable SLO,
and build from there. The tooling we covered (Prometheus, Sloth, ArgoCD, MCP servers) is all open source and
battle-tested.

<br />

The key takeaway is this: measure what matters to your users, set targets, and let automation handle the rest.
Your future self during the next on-call rotation will thank you.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: SLIs, SLOs y Automatizaciones Que Realmente Ayudan",
  author: "Gabriel Garrido",
  description: "Vamos a explorar cómo definir SLIs y SLOs como código, desplegarlos con ArgoCD, y usar servidores MCP para automatizar flujos de trabajo de SRE...",
  tags: ~w(sre kubernetes argocd observability automation),
  published: true,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En este artículo vamos a explorar el lado práctico de la Ingeniería de Confiabilidad de Sitio (SRE), específicamente
cómo definir Indicadores de Nivel de Servicio (SLIs) y Objetivos de Nivel de Servicio (SLOs) como código, desplegarlos
usando ArgoCD, y aprovechar servidores MCP y automatizaciones para hacer todo el proceso menos doloroso.

<br />

Si venís haciendo operaciones o ingeniería de plataformas hace un tiempo, probablemente ya sabés que el monitoreo solo
no alcanza. Tener un dashboard lleno de luces verdes no significa que tus usuarios estén contentos. Los SLIs y SLOs te
dan un marco para medir lo que realmente importa y tomar decisiones informadas sobre confiabilidad vs. velocidad de
entrega de features.

<br />

Vamos al tema.

<br />

##### **¿Qué es SRE?**
Site Reliability Engineering es una disciplina que aplica prácticas de ingeniería de software a problemas de operaciones.
Google popularizó el concepto, pero la idea central es simple: tratá tu infraestructura y procesos operativos como
código, medí lo que importa, y usá presupuestos de error para balancear confiabilidad con la velocidad de entrega de
nuevas funcionalidades.

<br />

Los componentes clave son:

> * **SLIs (Indicadores de Nivel de Servicio)**: Métricas que miden la calidad de tu servicio desde la perspectiva del usuario
> * **SLOs (Objetivos de Nivel de Servicio)**: Objetivos que definís para tus SLIs (ej: "99.9% de las requests deben ser exitosas")
> * **Presupuestos de Error**: La cantidad aceptable de falta de confiabilidad (100% - objetivo del SLO)
> * **SLAs (Acuerdos de Nivel de Servicio)**: Contratos comerciales basados en SLOs (no nos vamos a enfocar en estos acá)

<br />

##### **Entendiendo los SLIs**
Un SLI es una medida cuantitativa cuidadosamente definida de algún aspecto del nivel de servicio proporcionado. Los SLIs
más comunes son:

<br />

> * **Disponibilidad**: La proporción de requests que son exitosas
> * **Latencia**: La proporción de requests que son más rápidas que un umbral
> * **Calidad**: La proporción de respuestas que no están degradadas

<br />

Lo importante acá es la parte de "proporción". Los SLIs se expresan como ratios:

```elixir
SLI = eventos_buenos / eventos_totales
```

<br />

Por ejemplo, para un servicio HTTP:

```elixir
# SLI de Disponibilidad
disponibilidad = (requests_totales - errores_5xx) / requests_totales

# SLI de Latencia
latencia = requests_mas_rapidas_que_300ms / requests_totales
```

<br />

Esto es mucho más útil que métricas crudas porque refleja directamente la experiencia del usuario. Un pico de errores
que dura 5 segundos es muy diferente de uno que dura 5 minutos, y el ratio captura esa diferencia sobre una ventana
de tiempo.

<br />

##### **Entendiendo los SLOs**
Un SLO es el valor objetivo para un SLI sobre una ventana de tiempo específica. Por ejemplo:

<br />

> * "99.9% de las requests HTTP deben devolver una respuesta sin error en una ventana móvil de 30 días"
> * "99% de las requests deben completarse en menos de 300ms en una ventana móvil de 30 días"

<br />

El SLO te da un **presupuesto de error**. Si tu SLO es 99.9%, tu presupuesto de error es 0.1%. En 30 días, eso
significa que podés permitirte aproximadamente 43 minutos de tiempo de inactividad total. Esto es increíblemente
poderoso porque convierte la confiabilidad en un recurso medible que podés gastar. ¿Querés hacer un despliegue
riesgoso? Revisá tu presupuesto de error primero.

<br />

##### **Llevando los SLIs a código con Prometheus**
Ahora vamos a lo práctico. La forma más común de implementar SLIs es con métricas de Prometheus. Si estás corriendo
cargas de trabajo en Kubernetes, probablemente ya tenés Prometheus o un sistema compatible recolectando métricas.

<br />

Para un servicio web típico, querés exponer un histograma que rastree la duración de las requests y el estado:

```elixir
# Si tu aplicación usa el cliente de Prometheus, exponé algo como:
# histogram: http_request_duration_seconds (con labels: method, path, status)
# counter: http_requests_total (con labels: method, path, status)

# Para nuestra app Phoenix/Elixir, usamos phoenix_telemetry y peep para exponer estas métricas.
# Pero el concepto aplica a cualquier lenguaje.
```

<br />

Con esas métricas en Prometheus, podés definir recording rules que calculen los ratios del SLI. Acá hay un
ejemplo de reglas de Prometheus para un SLI de disponibilidad HTTP:

```elixir
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sli-availability
  namespace: monitoring
spec:
  groups:
    - name: sli.availability
      interval: 30s
      rules:
        # Tasa de requests totales en ventana de 5m
        - record: sli:http_requests:rate5m
          expr: sum(rate(http_requests_total[5m]))

        # Tasa de requests con error en ventana de 5m (respuestas 5xx)
        - record: sli:http_errors:rate5m
          expr: sum(rate(http_requests_total{status=~"5.."}[5m]))

        # SLI de disponibilidad (ratio de requests exitosas)
        - record: sli:availability:ratio_rate5m
          expr: |
            1 - (sli:http_errors:rate5m / sli:http_requests:rate5m)
```

<br />

Y para un SLI de latencia:

```elixir
# prometheus-rules-latency.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sli-latency
  namespace: monitoring
spec:
  groups:
    - name: sli.latency
      interval: 30s
      rules:
        # Requests más rápidas que 300ms
        - record: sli:http_request_duration:rate5m
          expr: sum(rate(http_request_duration_seconds_bucket{le="0.3"}[5m]))

        # Todas las requests
        - record: sli:http_request_duration_total:rate5m
          expr: sum(rate(http_request_duration_seconds_count[5m]))

        # SLI de latencia
        - record: sli:latency:ratio_rate5m
          expr: |
            sli:http_request_duration:rate5m / sli:http_request_duration_total:rate5m
```

<br />

Estas recording rules pre-computan los ratios del SLI para que puedas usarlos en alertas y dashboards sin ejecutar
consultas costosas cada vez.

<br />

##### **SLOs como código con Sloth**
Escribir recording rules y alert rules de Prometheus a mano para cada SLO se vuelve tedioso rápido. Ahí es donde
entra [Sloth](https://github.com/slok/sloth). Sloth es una herramienta que genera todas las reglas de Prometheus
que necesitás a partir de una definición simple de SLO.

<br />

Acá hay una definición de SLO para nuestro servicio:

```elixir
# slos/tr-web.yaml
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata:
  name: tr-web
  namespace: default
spec:
  service: "tr-web"
  labels:
    team: "platform"
  slos:
    - name: "requests-availability"
      objective: 99.9
      description: "99.9% de las requests HTTP deben ser exitosas"
      sli:
        events:
          error_query: sum(rate(http_requests_total{status=~"5..",service="tr-web"}[{{.window}}]))
          total_query: sum(rate(http_requests_total{service="tr-web"}[{{.window}}]))
      alerting:
        name: TrWebHighErrorRate
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "Tasa de error alta en tr-web"
        page_alert:
          labels:
            severity: critical
        ticket_alert:
          labels:
            severity: warning

    - name: "requests-latency"
      objective: 99.0
      description: "99% de las requests deben ser más rápidas que 300ms"
      sli:
        events:
          error_query: |
            sum(rate(http_request_duration_seconds_count{service="tr-web"}[{{.window}}]))
            -
            sum(rate(http_request_duration_seconds_bucket{le="0.3",service="tr-web"}[{{.window}}]))
          total_query: sum(rate(http_request_duration_seconds_count{service="tr-web"}[{{.window}}]))
      alerting:
        name: TrWebHighLatency
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "Latencia alta en tr-web"
        page_alert:
          labels:
            severity: critical
        ticket_alert:
          labels:
            severity: warning
```

<br />

Después generás las reglas de Prometheus:

```elixir
sloth generate -i slos/tr-web.yaml -o prometheus-rules/tr-web-slo.yaml
```

<br />

Sloth genera alertas multi-ventana y multi-tasa-de-quemado siguiendo las recomendaciones del libro de SRE de Google.
Obtenés alertas de quemado rápido (algo está muy mal ahora) y alertas de quemado lento (estás consumiendo presupuesto
de error más rápido de lo esperado). Esto es una mejora enorme comparado con definir umbrales de alerta manualmente.

<br />

##### **Desplegando SLOs con ArgoCD**
Ahora que tenemos nuestras definiciones de SLO y las reglas de Prometheus generadas como archivos YAML, podemos
desplegarlos de la manera GitOps usando ArgoCD. Si leíste mi [artículo anterior sobre GitOps](/blog/lets-talk-gitops),
esto te va a resultar familiar.

<br />

La idea es simple: almacená tus definiciones de SLO y reglas generadas en un repositorio Git, y dejá que ArgoCD las
sincronice con tu cluster.

<br />

Acá está la estructura del repositorio:

```elixir
slo-configs/
├── slos/
│   ├── tr-web.yaml            # Definiciones de SLO de Sloth
│   └── api-gateway.yaml
├── generated/
│   ├── tr-web-slo.yaml        # Recursos PrometheusRule generados
│   └── api-gateway-slo.yaml
├── dashboards/
│   ├── tr-web-slo.json        # JSON de dashboard de Grafana
│   └── api-gateway-slo.json
└── argocd/
    └── application.yaml        # Manifiesto de Application de ArgoCD
```

<br />

El manifiesto de Application de ArgoCD:

```elixir
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: slo-configs
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kainlite/slo-configs
    targetRevision: HEAD
    path: generated
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

Con este setup, cada vez que actualizás una definición de SLO, regenerás las reglas y pusheás a Git, ArgoCD
aplica automáticamente los cambios en tu cluster. Sin comandos manuales de kubectl, sin olvidarte de aplicar ese
archivo que cambiaste la semana pasada.

<br />

También podés configurar un paso de CI para regenerar automáticamente las reglas de Prometheus cuando cambian las
definiciones de SLO:

```elixir
# .github/workflows/generate-slos.yaml
name: Generate SLO Rules

on:
  push:
    paths:
      - 'slos/**'

jobs:
  generate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Sloth
        run: |
          curl -L https://github.com/slok/sloth/releases/latest/download/sloth-linux-amd64 -o sloth
          chmod +x sloth

      - name: Generate rules
        run: |
          for slo in slos/*.yaml; do
            name=$(basename "$slo" .yaml)
            ./sloth generate -i "$slo" -o "generated/${name}-slo.yaml"
          done

      - name: Commit and push
        run: |
          git config user.name "github-actions"
          git config user.email "actions@github.com"
          git add generated/
          git diff --staged --quiet || git commit -m "chore: regenerate SLO rules"
          git push
```

<br />

Ahora tenés un pipeline completamente automatizado: editás una definición de SLO, pusheás, CI genera las reglas,
ArgoCD las despliega. Hermoso.

<br />

##### **Servidores MCP para automatización de SRE**
Acá es donde las cosas se ponen realmente interesantes. Los servidores de Model Context Protocol (MCP) te permiten
darle a asistentes de IA como Claude acceso a tus herramientas de infraestructura. Imaginate poder preguntar "¿cuánto
presupuesto de error me queda para tr-web?" y obtener una respuesta real de tus datos en vivo de Prometheus.

<br />

Un servidor MCP es esencialmente una API que expone herramientas que una IA puede llamar. Podés construir uno que
envuelva tus APIs de Prometheus y Kubernetes:

```elixir
// mcp-sre-server/src/main.rs
// Un ejemplo simplificado de un servidor MCP para consultas de SRE

use mcp_server::{Server, Tool, ToolResult};

#[derive(Tool)]
#[tool(name = "query_error_budget", description = "Consultar presupuesto de error restante")]
struct QueryErrorBudget {
    service: String,
    slo_name: String,
}

impl QueryErrorBudget {
    async fn execute(&self) -> ToolResult {
        let query = format!(
            r#"1 - (
                sli:availability:ratio_rate30d{{service="{}"}}
            ) / (1 - {}.0/100)"#,
            self.service, self.objective
        );

        let result = prometheus_query(&query).await?;
        ToolResult::text(format!(
            "Presupuesto de error para {}/{}: {:.2}% restante",
            self.service, self.slo_name, result * 100.0
        ))
    }
}

#[derive(Tool)]
#[tool(name = "list_slo_violations", description = "Listar SLOs que están quemando demasiado rápido")]
struct ListSloViolations;

impl ListSloViolations {
    async fn execute(&self) -> ToolResult {
        let query = r#"ALERTS{alertname=~".*SLO.*", alertstate="firing"}"#;
        let alerts = prometheus_query(query).await?;
        ToolResult::text(format!("Violaciones de SLO activas:\n{}", alerts))
    }
}

#[derive(Tool)]
#[tool(name = "get_deployment_risk", description = "Evaluar riesgo de despliegue basado en presupuesto de error")]
struct GetDeploymentRisk {
    service: String,
}

impl GetDeploymentRisk {
    async fn execute(&self) -> ToolResult {
        let budget = get_error_budget(&self.service).await?;
        let recent_deploys = get_recent_deploys(&self.service).await?;

        let risk = match budget {
            b if b > 0.5 => "BAJO - bastante presupuesto de error disponible",
            b if b > 0.2 => "MEDIO - el presupuesto de error se está agotando",
            b if b > 0.0 => "ALTO - muy poco presupuesto de error",
            _ => "CRÍTICO - presupuesto de error agotado, considerá congelar despliegues",
        };

        ToolResult::text(format!(
            "Riesgo de despliegue para {}: {}\nPresupuesto restante: {:.1}%\nDespliegues recientes: {}",
            self.service, risk, budget * 100.0, recent_deploys
        ))
    }
}
```

<br />

Con este servidor MCP corriendo, podés configurar Claude Code o cualquier cliente compatible con MCP para conectarse.
Después tenés acceso en lenguaje natural a tus datos de SRE:

<br />

> * "¿Cuánto presupuesto de error tiene tr-web?" → Consulta Prometheus, devuelve el presupuesto restante
> * "¿Es seguro deployar ahora?" → Verifica presupuesto de error + incidentes recientes
> * "¿Qué SLOs están en riesgo esta semana?" → Lista SLOs con tasas de quemado altas
> * "Mostrá la tendencia de latencia de las últimas 24h" → Consulta Prometheus y resume

<br />

También podés construir herramientas MCP que se integren con ArgoCD:

```elixir
#[derive(Tool)]
#[tool(name = "argocd_sync_status", description = "Verificar estado de sincronización de ArgoCD")]
struct ArgoCDSyncStatus;

impl ArgoCDSyncStatus {
    async fn execute(&self) -> ToolResult {
        let output = Command::new("argocd")
            .args(["app", "get", "slo-configs", "-o", "json"])
            .output()
            .await?;

        let app: ArgoApp = serde_json::from_slice(&output.stdout)?;
        ToolResult::text(format!(
            "Estado de sincronización de SLO configs: {}\nSalud: {}\nÚltima sincronización: {}",
            app.status.sync.status,
            app.status.health.status,
            app.status.sync.compared_to.revision
        ))
    }
}

#[derive(Tool)]
#[tool(name = "rollback_deployment", description = "Hacer rollback de un despliegue via ArgoCD")]
struct RollbackDeployment {
    service: String,
    revision: Option<String>,
}

impl RollbackDeployment {
    async fn execute(&self) -> ToolResult {
        // Esto estaría protegido detrás de confirmación en un setup real
        let revision = self.revision.as_deref().unwrap_or("HEAD~1");
        let output = Command::new("argocd")
            .args(["app", "rollback", &self.service, "--revision", revision])
            .output()
            .await?;

        ToolResult::text(format!("Rollback iniciado para {} a {}", self.service, revision))
    }
}
```

<br />

La configuración del servidor MCP en tu configuración de Claude Code se vería algo así:

```elixir
{
  "mcpServers": {
    "sre-tools": {
      "command": "mcp-sre-server",
      "args": ["--prometheus-url", "http://prometheus:9090", "--argocd-url", "https://argocd.example.com"],
      "env": {
        "ARGOCD_AUTH_TOKEN": "tu-token-aca"
      }
    }
  }
}
```

<br />

##### **Automatizaciones que unen todo**
El verdadero poder viene cuando combinás SLOs, ArgoCD y servidores MCP en flujos de trabajo automatizados. Acá hay
algunos patrones que funcionan bien en la práctica:

<br />

**1. Puertas de despliegue automatizadas**

Usá presupuestos de error como puertas de despliegue. Si el presupuesto de error está por debajo de un umbral,
bloqueá despliegues automáticamente:

```elixir
# En tu pipeline de CI
- name: Verificar presupuesto de error
  run: |
    BUDGET=$(curl -s "http://prometheus:9090/api/v1/query?query=error_budget_remaining{service='tr-web'}" \
      | jq -r '.data.result[0].value[1]')

    if (( $(echo "$BUDGET < 0.1" | bc -l) )); then
      echo "Presupuesto de error por debajo del 10%, bloqueando despliegue"
      exit 1
    fi
```

<br />

**2. Creación automática de incidentes**

Cuando se rompe un SLO, creá automáticamente un issue o incidente:

```elixir
# alertmanager-config.yaml
receivers:
  - name: slo-breach
    webhook_configs:
      - url: http://incident-bot:8080/create
        send_resolved: true

route:
  routes:
    - match:
        severity: critical
        type: slo_breach
      receiver: slo-breach
```

<br />

**3. Reportes semanales de SLO**

Automatizá reportes semanales de SLO para mantener al equipo informado:

```elixir
# Un CronJob que consulta Prometheus y envía un resumen a Slack
apiVersion: batch/v1
kind: CronJob
metadata:
  name: slo-weekly-report
  namespace: monitoring
spec:
  schedule: "0 9 * * 1"  # Todos los lunes a las 9am
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: reporter
              image: kainlite/slo-reporter:latest
              env:
                - name: PROMETHEUS_URL
                  value: "http://prometheus:9090"
                - name: SLACK_WEBHOOK
                  valueFrom:
                    secretKeyRef:
                      name: slack-webhook
                      key: url
          restartPolicy: Never
```

<br />

**4. Congelamiento de features basado en presupuesto de error**

Este es uno de los patrones más poderosos de SRE. Cuando el presupuesto de error se agota, el equipo debería
cambiar el foco de features a trabajo de confiabilidad:

<br />

> * **Presupuesto > 50%**: Shippeá features libremente
> * **Presupuesto 20-50%**: Sé cauteloso con cambios riesgosos
> * **Presupuesto 5-20%**: Enfocate en mejoras de confiabilidad
> * **Presupuesto < 5%**: Congelamiento de features, todos a trabajar en confiabilidad

<br />

Podés automatizar esto haciendo que tu servidor MCP actualice una página de estado o canal de Slack con el nivel
actual de presupuesto, para que todos en el equipo sepan dónde están las cosas sin tener que revisar dashboards.

<br />

##### **Juntando todo**
Acá hay un resumen de lo que construimos:

<br />

> 1. **SLIs como métricas de Prometheus**: Recording rules que calculan ratios de disponibilidad y latencia
> 2. **SLOs con Sloth**: Definiciones declarativas de SLO que generan alertas multi-ventana y multi-tasa-de-quemado
> 3. **GitOps con ArgoCD**: Configuraciones de SLO almacenadas en Git, sincronizadas automáticamente al cluster
> 4. **Servidores MCP**: Interfaz de lenguaje natural para consultar presupuestos de error, verificar riesgo de despliegue y gestionar ArgoCD
> 5. **Automatizaciones**: Puertas de despliegue, creación de incidentes, reportes semanales y políticas de presupuesto de error

<br />

La belleza de este enfoque es que cada pieza es simple por sí sola, pero juntas crean un sistema donde la
confiabilidad es medible, automatizada y parte del flujo de trabajo diario del equipo en lugar de algo que se
piensa después.

<br />

##### **Notas finales**
SRE no tiene que ser complicado. Empezá con un SLI para tu servicio más importante, definí un SLO razonable y
construí desde ahí. Las herramientas que cubrimos (Prometheus, Sloth, ArgoCD, servidores MCP) son todas de código
abierto y probadas en batalla.

<br />

La conclusión clave es esta: medí lo que importa a tus usuarios, definí objetivos, y dejá que la automatización
se encargue del resto. Tu yo del futuro durante la próxima guardia te lo va a agradecer.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
