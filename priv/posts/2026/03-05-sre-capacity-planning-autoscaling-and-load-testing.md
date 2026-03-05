%{
  title: "SRE: Capacity Planning, Autoscaling, and Load Testing",
  author: "Gabriel Garrido",
  description: "We will explore how to right-size your Kubernetes workloads, configure HPA and VPA for automatic scaling, use KEDA for event-driven scaling, and load test with k6 to validate your capacity...",
  tags: ~w(sre kubernetes scaling load-testing performance),
  published: true,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Throughout this SRE series we have covered [SLIs and SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[incident management](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observability](/blog/sre-observability-deep-dive-traces-logs-and-metrics), and
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose). All of that assumes your system has
enough capacity to serve traffic. But how do you know if it does? And what happens when traffic doubles overnight?

<br />

Capacity planning is the art of ensuring your infrastructure can handle current and future demand without
over-provisioning (wasting money) or under-provisioning (degrading service). In Kubernetes, this means getting
resource requests and limits right, configuring autoscalers properly, and validating your setup with load tests.

<br />

In this article we will cover resource requests and limits, the Horizontal Pod Autoscaler (HPA), the Vertical
Pod Autoscaler (VPA), KEDA for event-driven scaling, and load testing with k6 to make sure everything works
under pressure.

<br />

Let's get into it.

<br />

##### **Resource requests and limits: the foundation**
Before you can autoscale anything, you need to understand resource requests and limits. These are the most
misunderstood concepts in Kubernetes, and getting them wrong causes more outages than most people realize.

<br />

> * **Requests**: The minimum resources a pod needs. The scheduler uses this to decide where to place the pod.
> * **Limits**: The maximum resources a pod can use. If the pod exceeds its memory limit, it gets OOM-killed.

<br />

Here is how to set them for our Elixir application:

<br />

```elixir
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tr-web
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: tr-web
  template:
    metadata:
      labels:
        app: tr-web
    spec:
      containers:
        - name: tr-web
          image: kainlite/tr:latest
          resources:
            requests:
              cpu: "250m"      # 0.25 CPU cores
              memory: "256Mi"  # 256 MB RAM
            limits:
              cpu: "1000m"     # 1 CPU core
              memory: "512Mi"  # 512 MB RAM
          ports:
            - containerPort: 4000
```

<br />

**Common mistakes:**

<br />

> * **Setting requests = limits**: This gives you guaranteed QoS but wastes resources. Only do this for critical databases.
> * **Not setting requests**: Pods get BestEffort QoS and are the first to be evicted under pressure.
> * **Setting memory limits too low**: BEAM applications use memory for ETS tables, process heaps, and binary data. Too-tight limits cause random OOM kills.
> * **Setting CPU limits at all**: There is a growing consensus that CPU limits cause more harm than good due to throttling. Consider setting only CPU requests and no CPU limits.

<br />

**The CPU limits debate:**

<br />

CPU limits in Kubernetes use CFS (Completely Fair Scheduler) throttling. Even if the node has idle CPU, a
pod hitting its CPU limit will be throttled. This causes latency spikes that are hard to debug because
everything looks fine from a resource usage perspective.

<br />

```elixir
# Option A: With CPU limits (safe but can cause throttling)
resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    cpu: "1000m"
    memory: "512Mi"

# Option B: Without CPU limits (better performance, requires good monitoring)
resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    memory: "512Mi"  # Keep memory limits, drop CPU limits
```

<br />

If you go with Option B, make sure you have good monitoring to detect noisy neighbor issues.

<br />

##### **Right-sizing with VPA**
The Vertical Pod Autoscaler (VPA) watches your pod's actual resource usage and recommends or automatically
adjusts the requests and limits. This is incredibly useful because guessing the right values is hard.

<br />

Install VPA:

<br />

```elixir
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler
./hack/vpa-up.sh
```

<br />

Create a VPA resource in recommendation mode (safest to start):

<br />

```elixir
# vpa/tr-web-vpa.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: tr-web-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tr-web
  updatePolicy:
    updateMode: "Off"  # Start with recommendations only
  resourcePolicy:
    containerPolicies:
      - containerName: tr-web
        minAllowed:
          cpu: "100m"
          memory: "128Mi"
        maxAllowed:
          cpu: "2000m"
          memory: "1Gi"
```

<br />

After a few days of collecting data, check the recommendations:

<br />

```elixir
kubectl describe vpa tr-web-vpa

# Output will look like:
# Recommendation:
#   Container Recommendations:
#     Container Name: tr-web
#     Lower Bound:
#       Cpu:     150m
#       Memory:  200Mi
#     Target:
#       Cpu:     280m
#       Memory:  310Mi
#     Upper Bound:
#       Cpu:     500m
#       Memory:  450Mi
```

<br />

The "Target" values are what VPA recommends for your requests. Use them as a starting point and validate
with load testing.

<br />

Once you trust the recommendations, you can switch to `updateMode: "Auto"` to let VPA adjust resources
automatically. Be aware that VPA does this by evicting and recreating pods with new resource values, so make
sure you have enough replicas to handle the disruption.

<br />

##### **Horizontal Pod Autoscaler (HPA)**
HPA scales the number of pods based on metrics. The most common setup scales on CPU or memory usage, but
you can also scale on custom metrics from Prometheus.

<br />

**Basic HPA on CPU:**

<br />

```elixir
# hpa/tr-web-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: tr-web-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tr-web
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 120
```

<br />

Key settings:

<br />

> * **minReplicas: 2**: Always have at least 2 pods for redundancy
> * **maxReplicas: 10**: Cap to prevent runaway scaling (and runaway costs)
> * **averageUtilization: 70**: Scale up when average CPU across pods exceeds 70%
> * **scaleUp stabilization: 60s**: Wait 60 seconds before scaling up to avoid flapping
> * **scaleDown stabilization: 300s**: Wait 5 minutes before scaling down to handle traffic oscillations

<br />

**HPA on custom Prometheus metrics:**

<br />

Scaling on CPU is a blunt instrument. For a web service, scaling on requests-per-second or latency is much
more responsive. This requires the Prometheus Adapter:

<br />

```elixir
# Install Prometheus Adapter
helm install prometheus-adapter prometheus-community/prometheus-adapter \
  --namespace monitoring \
  --set prometheus.url=http://prometheus:9090
```

<br />

Configure the adapter to expose your SLI metrics to the Kubernetes metrics API:

<br />

```elixir
# prometheus-adapter/config.yaml
rules:
  - seriesQuery: 'http_requests_total{namespace!="",pod!=""}'
    resources:
      overrides:
        namespace: {resource: "namespace"}
        pod: {resource: "pod"}
    name:
      matches: "^(.*)_total$"
      as: "${1}_per_second"
    metricsQuery: 'sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)'

  - seriesQuery: 'http_request_duration_seconds_bucket{namespace!="",pod!=""}'
    resources:
      overrides:
        namespace: {resource: "namespace"}
        pod: {resource: "pod"}
    name:
      as: "http_request_duration_p99"
    metricsQuery: 'histogram_quantile(0.99, sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (le, <<.GroupBy>>))'
```

<br />

Then create an HPA that scales on requests per second per pod:

<br />

```elixir
# hpa/tr-web-hpa-custom.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: tr-web-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tr-web
  minReplicas: 2
  maxReplicas: 10
  metrics:
    # Scale on requests per second per pod
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "100"  # Scale up if any pod handles more than 100 rps

    # Also consider latency
    - type: Pods
      pods:
        metric:
          name: http_request_duration_p99
        target:
          type: AverageValue
          averageValue: "300m"  # Scale up if p99 > 300ms
```

<br />

This is much better than CPU-based scaling because it reacts to actual traffic patterns rather than resource
consumption, which can be misleading (the BEAM VM manages memory differently than most runtimes).

<br />

##### **KEDA: event-driven autoscaling**
KEDA (Kubernetes Event-Driven Autoscaling) takes HPA to the next level by supporting dozens of event sources.
It is particularly useful for scaling based on queue depth, cron schedules, or external metrics.

<br />

Install KEDA:

<br />

```elixir
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace
```

<br />

**Scale based on Prometheus metrics (SLO-aware scaling):**

<br />

```elixir
# keda/tr-web-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: tr-web-scaledobject
  namespace: default
spec:
  scaleTargetRef:
    name: tr-web
  minReplicaCount: 2
  maxReplicaCount: 15
  pollingInterval: 30
  cooldownPeriod: 300
  triggers:
    # Scale based on request rate
    - type: prometheus
      metadata:
        serverAddress: http://prometheus.monitoring:9090
        metricName: http_requests_rate
        query: sum(rate(http_requests_total{service="tr-web"}[2m]))
        threshold: "200"  # Scale up when total RPS exceeds 200
        activationThreshold: "50"  # Start scaling at 50 RPS

    # Scale based on error budget burn rate
    - type: prometheus
      metadata:
        serverAddress: http://prometheus.monitoring:9090
        metricName: error_budget_burn_rate
        query: sli:availability:burn_rate5m{service="tr-web"}
        threshold: "5"  # Scale up when burning error budget 5x faster than normal
```

<br />

The error budget trigger is particularly clever. When your service is burning through error budget faster than
expected (which means reliability is degrading), KEDA adds more replicas to absorb the load. This ties capacity
planning directly to your SLOs.

<br />

**Cron-based scaling for predictable traffic patterns:**

<br />

```elixir
# keda/tr-web-cron-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: tr-web-cron
  namespace: default
spec:
  scaleTargetRef:
    name: tr-web
  minReplicaCount: 2
  maxReplicaCount: 10
  triggers:
    # Scale up during business hours
    - type: cron
      metadata:
        timezone: America/Argentina/Buenos_Aires
        start: "0 8 * * 1-5"   # Monday-Friday 8am
        end: "0 20 * * 1-5"    # Monday-Friday 8pm
        desiredReplicas: "4"

    # Scale up for newsletter sends (if applicable)
    - type: cron
      metadata:
        timezone: America/Argentina/Buenos_Aires
        start: "0 10 * * 2"    # Tuesday 10am (newsletter day)
        end: "0 12 * * 2"      # Tuesday 12pm
        desiredReplicas: "6"
```

<br />

If you know your traffic patterns (and you should, from your observability data), proactive scaling avoids
the lag that reactive autoscaling introduces. Why wait for CPU to spike when you know traffic increases every
morning at 8am?

<br />

##### **Cluster autoscaling**
Pod autoscaling is only useful if there are nodes with capacity to schedule new pods. The Cluster Autoscaler
adds and removes nodes based on pending pod requests.

<br />

For a K3s cluster (like the one this blog runs on), you can use a combination of the Cluster Autoscaler and
cloud provider integration. For self-managed clusters, you need to think about this differently.

<br />

Key considerations:

<br />

> * **Node provisioning time**: Cloud nodes take 2-5 minutes to provision. Plan your HPA to give enough headroom for this delay.
> * **Over-provisioning**: Keep a buffer pod (a low-priority deployment that consumes resources but can be preempted) to ensure there is always room for quick scale-ups.
> * **Pod Disruption Budgets**: Ensure the cluster autoscaler does not remove nodes with critical pods.

<br />

```elixir
# Buffer pod to keep spare capacity
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capacity-buffer
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: capacity-buffer
  template:
    metadata:
      labels:
        app: capacity-buffer
    spec:
      priorityClassName: low-priority
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.9
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: -10
globalDefault: false
description: "Low priority for buffer pods that can be preempted"
```

<br />

The buffer pod reserves capacity that can be instantly freed when a real workload needs it. The real pods
have default priority and preempt the buffer pod, which then triggers the cluster autoscaler to add a new
node for the buffer.

<br />

##### **Load testing with k6**
All the autoscaling configuration in the world is useless if you have not validated it under real load. k6 is
an excellent load testing tool that makes it easy to define test scenarios.

<br />

Install k6:

<br />

```elixir
# On Arch Linux
sudo pacman -S k6

# Or via Docker
docker run --rm -i grafana/k6 run - <script.js
```

<br />

**Basic load test for the blog:**

<br />

```elixir
// load-tests/blog-basic.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 50 },   // Ramp up to 50 users over 2 minutes
    { duration: '5m', target: 50 },   // Stay at 50 users for 5 minutes
    { duration: '2m', target: 100 },  // Ramp up to 100 users
    { duration: '5m', target: 100 },  // Stay at 100 users
    { duration: '2m', target: 0 },    // Ramp down to 0
  ],
  thresholds: {
    // SLO-aligned thresholds
    http_req_duration: ['p(99)<300'],    // 99% of requests under 300ms
    http_req_failed: ['rate<0.001'],     // Less than 0.1% error rate
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

export default function () {
  // Simulate a typical user browsing the blog
  const pages = [
    '/blog',
    '/blog/sre-slis-slos-and-automations-that-actually-help',
    '/blog/debugging-distroless-containers-when-your-container-has-no-shell',
    '/blog/kubernetes-rbac-deep-dive-understanding-authorization-with-kubectl-and-curl',
  ];

  const page = pages[Math.floor(Math.random() * pages.length)];
  const res = http.get(`${BASE_URL}${page}`);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'body contains content': (r) => r.body.length > 1000,
  });

  sleep(Math.random() * 3 + 1); // Random think time between 1-4 seconds
}
```

<br />

**Load test for search (LiveView WebSocket):**

<br />

```elixir
// load-tests/search-load.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 20 },
    { duration: '3m', target: 20 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

export default function () {
  // Load the search page
  const searchPage = http.get(`${BASE_URL}/search`);
  check(searchPage, {
    'search page loads': (r) => r.status === 200,
  });

  sleep(1);

  // Note: k6 does not natively support WebSocket LiveView connections
  // For full LiveView load testing, use the k6 WebSocket extension
  // or test the HTTP fallback mode
}
```

<br />

**Autoscaling validation test:**

<br />

This is the most important load test. It validates that your HPA kicks in correctly under load:

<br />

```elixir
// load-tests/autoscale-validation.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const errorCount = new Counter('errors');
const scalingLatency = new Trend('scaling_latency');

export const options = {
  stages: [
    // Phase 1: Baseline (should run with min replicas)
    { duration: '2m', target: 10 },

    // Phase 2: Ramp to trigger scale-up
    { duration: '1m', target: 200 },

    // Phase 3: Sustained high load (HPA should scale up)
    { duration: '10m', target: 200 },

    // Phase 4: Ramp down (HPA should eventually scale down)
    { duration: '2m', target: 10 },

    // Phase 5: Sustained low load
    { duration: '5m', target: 10 },
  ],
  thresholds: {
    http_req_duration: ['p(99)<500'],  // Even under load, p99 < 500ms
    http_req_failed: ['rate<0.005'],   // Less than 0.5% errors
    errors: ['count<50'],              // Less than 50 total errors
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

export default function () {
  const res = http.get(`${BASE_URL}/blog`);

  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'latency < 500ms': (r) => r.timings.duration < 500,
  });

  if (!success) {
    errorCount.add(1);
  }

  sleep(Math.random() * 2 + 0.5);
}
```

<br />

Run the test while watching your HPA:

<br />

```elixir
# Terminal 1: Run the load test
k6 run --env BASE_URL=https://your-app.example.com load-tests/autoscale-validation.js

# Terminal 2: Watch HPA
kubectl get hpa tr-web-hpa --watch

# Terminal 3: Watch pods scaling
kubectl get pods -l app=tr-web --watch
```

<br />

What you want to see:

<br />

> * During Phase 1: 2 replicas (minReplicas), low resource usage
> * During Phase 2-3: HPA scales up to 4-6 replicas within 2-3 minutes of high load
> * During Phase 3: Latency stays within SLO even at high load
> * During Phase 4-5: HPA gradually scales back down to 2 replicas after the stabilization window

<br />

If the scale-up takes too long and latency spikes during Phase 2, you need to either:

> * Lower the averageUtilization threshold
> * Reduce the scaleUp stabilization window
> * Use proactive cron-based scaling for predictable traffic patterns

<br />

##### **Capacity planning as a practice**
Beyond autoscaling, capacity planning is an ongoing practice:

<br />

**1. Track resource utilization trends**

<br />

```elixir
# Grafana query: CPU utilization trend over 30 days
avg_over_time(
  sum(rate(container_cpu_usage_seconds_total{pod=~"tr-web.*"}[5m]))
  /
  sum(kube_pod_container_resource_requests{pod=~"tr-web.*", resource="cpu"})
  [30d:1h]
)
```

<br />

If your average utilization is consistently above 80%, you need more capacity. If it is consistently below
20%, you are over-provisioned and wasting money.

<br />

**2. Review after every major change**

After launching a new feature, check if resource usage patterns changed. A new background job might increase
memory usage. A new API endpoint might increase CPU usage during peak hours.

<br />

**3. Plan for growth**

If your traffic is growing 10% month-over-month, your autoscaler maxReplicas needs to accommodate that growth.
Review your max limits quarterly and adjust.

<br />

##### **Putting it all together**
Here is the complete capacity management setup:

<br />

> 1. **VPA in recommendation mode** tells you what resources your pods actually need
> 2. **Resource requests** are set based on VPA recommendations and validated with load tests
> 3. **HPA with custom metrics** scales pods based on traffic (not just CPU)
> 4. **KEDA cron triggers** proactively scale for known traffic patterns
> 5. **Cluster Autoscaler** adds nodes when pods cannot be scheduled
> 6. **Buffer pods** ensure instant capacity for scale-up events
> 7. **k6 load tests** validate the entire scaling pipeline regularly

<br />

This gives you a system that handles traffic spikes automatically, right-sizes resources based on actual usage,
and gives you confidence that your SLOs will hold under load.

<br />

##### **Closing notes**
Capacity planning does not have to be guesswork. With VPA recommendations, SLO-aligned autoscaling, and regular
load testing, you can be confident that your infrastructure handles whatever traffic comes its way.

<br />

The most important takeaway: autoscaling is not a substitute for understanding your workload. Know your traffic
patterns, test your scaling limits, and always have a plan for what happens when traffic exceeds your maximum
capacity. The answer to "what happens if we get 10x traffic?" should never be "I don't know."

<br />

This concludes our five-part SRE series. From SLIs/SLOs to incident management, observability, chaos
engineering, and now capacity planning, you have the tools and practices to run reliable systems at any scale.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Planificación de Capacidad, Autoescalamiento y Pruebas de Carga",
  author: "Gabriel Garrido",
  description: "Vamos a explorar cómo dimensionar correctamente tus workloads de Kubernetes, configurar HPA y VPA para escalamiento automático, usar KEDA para escalamiento basado en eventos, y hacer pruebas de carga con k6...",
  tags: ~w(sre kubernetes scaling load-testing performance),
  published: true,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
A lo largo de esta serie de SRE cubrimos [SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[gestión de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observabilidad](/blog/sre-observability-deep-dive-traces-logs-and-metrics), y
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose). Todo eso asume que tu sistema tiene
suficiente capacidad para servir tráfico. ¿Pero cómo sabés si la tiene? ¿Y qué pasa cuando el tráfico se
duplica de un día para el otro?

<br />

La planificación de capacidad es el arte de asegurar que tu infraestructura pueda manejar la demanda actual y
futura sin sobre-provisionar (desperdiciar plata) o sub-provisionar (degradar el servicio). En Kubernetes, esto
significa acertar con los resource requests y limits, configurar autoscalers correctamente, y validar tu setup
con pruebas de carga.

<br />

En este artículo vamos a cubrir resource requests y limits, el Horizontal Pod Autoscaler (HPA), el Vertical
Pod Autoscaler (VPA), KEDA para escalamiento basado en eventos, y pruebas de carga con k6 para asegurarnos de
que todo funciona bajo presión.

<br />

Vamos al tema.

<br />

##### **Resource requests y limits: la base**
Antes de poder autoescalar cualquier cosa, necesitás entender resource requests y limits. Son los conceptos
más malinterpretados en Kubernetes, y configurarlos mal causa más caídas de las que la mayoría piensa.

<br />

> * **Requests**: Los recursos mínimos que un pod necesita. El scheduler usa esto para decidir dónde ubicar el pod.
> * **Limits**: Los recursos máximos que un pod puede usar. Si el pod excede su limit de memoria, es OOM-killed.

<br />

Acá cómo configurarlos para nuestra aplicación Elixir:

<br />

```elixir
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tr-web
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: tr-web
  template:
    metadata:
      labels:
        app: tr-web
    spec:
      containers:
        - name: tr-web
          image: kainlite/tr:latest
          resources:
            requests:
              cpu: "250m"      # 0.25 cores de CPU
              memory: "256Mi"  # 256 MB RAM
            limits:
              cpu: "1000m"     # 1 core de CPU
              memory: "512Mi"  # 512 MB RAM
          ports:
            - containerPort: 4000
```

<br />

**Errores comunes:**

<br />

> * **Poner requests = limits**: Esto te da QoS garantizado pero desperdicia recursos. Solo hacelo para bases de datos críticas.
> * **No poner requests**: Los pods reciben QoS BestEffort y son los primeros en ser desalojados bajo presión.
> * **Poner memory limits muy bajos**: Las aplicaciones BEAM usan memoria para tablas ETS, heaps de procesos, y datos binarios. Limits muy ajustados causan OOM kills aleatorios.
> * **Poner CPU limits**: Hay un consenso creciente de que los CPU limits causan más daño que beneficio por el throttling. Considerá poner solo CPU requests y no CPU limits.

<br />

**El debate de los CPU limits:**

<br />

Los CPU limits en Kubernetes usan throttling de CFS (Completely Fair Scheduler). Incluso si el nodo tiene CPU
ociosa, un pod que llegue a su CPU limit va a ser throttleado. Esto causa picos de latencia difíciles de
debuggear porque todo parece bien desde la perspectiva de uso de recursos.

<br />

```elixir
# Opción A: Con CPU limits (seguro pero puede causar throttling)
resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    cpu: "1000m"
    memory: "512Mi"

# Opción B: Sin CPU limits (mejor performance, requiere buen monitoreo)
resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    memory: "512Mi"  # Mantener memory limits, sacar CPU limits
```

<br />

Si vas por la Opción B, asegurate de tener buen monitoreo para detectar problemas de noisy neighbor.

<br />

##### **Dimensionamiento correcto con VPA**
El Vertical Pod Autoscaler (VPA) observa el uso real de recursos de tus pods y recomienda o ajusta
automáticamente los requests y limits. Es increíblemente útil porque adivinar los valores correctos es difícil.

<br />

Creá un recurso VPA en modo recomendación (lo más seguro para arrancar):

<br />

```elixir
# vpa/tr-web-vpa.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: tr-web-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tr-web
  updatePolicy:
    updateMode: "Off"  # Arrancar solo con recomendaciones
  resourcePolicy:
    containerPolicies:
      - containerName: tr-web
        minAllowed:
          cpu: "100m"
          memory: "128Mi"
        maxAllowed:
          cpu: "2000m"
          memory: "1Gi"
```

<br />

Después de unos días recolectando datos, revisá las recomendaciones:

<br />

```elixir
kubectl describe vpa tr-web-vpa

# La salida se ve así:
# Recommendation:
#   Container Recommendations:
#     Container Name: tr-web
#     Lower Bound:
#       Cpu:     150m
#       Memory:  200Mi
#     Target:
#       Cpu:     280m
#       Memory:  310Mi
#     Upper Bound:
#       Cpu:     500m
#       Memory:  450Mi
```

<br />

Los valores "Target" son lo que VPA recomienda para tus requests. Usalos como punto de partida y validá con
pruebas de carga.

<br />

##### **Horizontal Pod Autoscaler (HPA)**
HPA escala la cantidad de pods basándose en métricas. El setup más común escala por uso de CPU o memoria, pero
también podés escalar por métricas custom de Prometheus.

<br />

**HPA básico por CPU:**

<br />

```elixir
# hpa/tr-web-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: tr-web-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tr-web
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 120
```

<br />

Configuraciones clave:

<br />

> * **minReplicas: 2**: Siempre tené al menos 2 pods para redundancia
> * **maxReplicas: 10**: Tope para prevenir escalamiento descontrolado (y costos descontrolados)
> * **averageUtilization: 70**: Escalar cuando el CPU promedio entre pods supera 70%
> * **scaleUp stabilization: 60s**: Esperar 60 segundos antes de escalar para evitar flapping
> * **scaleDown stabilization: 300s**: Esperar 5 minutos antes de reducir para manejar oscilaciones de tráfico

<br />

**HPA con métricas custom de Prometheus:**

<br />

Escalar por CPU es un instrumento tosco. Para un servicio web, escalar por requests-por-segundo o latencia es
mucho más responsivo. Esto requiere el Prometheus Adapter:

<br />

```elixir
# Creá un HPA que escale por requests por segundo por pod:
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: tr-web-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tr-web
  minReplicas: 2
  maxReplicas: 10
  metrics:
    # Escalar por requests por segundo por pod
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "100"  # Escalar si algún pod maneja más de 100 rps

    # También considerar latencia
    - type: Pods
      pods:
        metric:
          name: http_request_duration_p99
        target:
          type: AverageValue
          averageValue: "300m"  # Escalar si p99 > 300ms
```

<br />

Esto es mucho mejor que escalar por CPU porque reacciona a patrones de tráfico reales en lugar de consumo de
recursos, que puede ser engañoso (la VM BEAM maneja la memoria de forma diferente a la mayoría de los runtimes).

<br />

##### **KEDA: autoescalamiento basado en eventos**
KEDA (Kubernetes Event-Driven Autoscaling) lleva al HPA al siguiente nivel soportando docenas de fuentes de
eventos. Es particularmente útil para escalar basándose en profundidad de colas, schedules cron, o métricas
externas.

<br />

**Escalamiento basado en métricas de Prometheus (consciente de SLOs):**

<br />

```elixir
# keda/tr-web-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: tr-web-scaledobject
  namespace: default
spec:
  scaleTargetRef:
    name: tr-web
  minReplicaCount: 2
  maxReplicaCount: 15
  pollingInterval: 30
  cooldownPeriod: 300
  triggers:
    # Escalar basado en tasa de requests
    - type: prometheus
      metadata:
        serverAddress: http://prometheus.monitoring:9090
        metricName: http_requests_rate
        query: sum(rate(http_requests_total{service="tr-web"}[2m]))
        threshold: "200"
        activationThreshold: "50"

    # Escalar basado en tasa de quemado del presupuesto de error
    - type: prometheus
      metadata:
        serverAddress: http://prometheus.monitoring:9090
        metricName: error_budget_burn_rate
        query: sli:availability:burn_rate5m{service="tr-web"}
        threshold: "5"  # Escalar cuando se quema presupuesto 5x más rápido de lo normal
```

<br />

El trigger de presupuesto de error es particularmente inteligente. Cuando tu servicio está quemando presupuesto
de error más rápido de lo esperado (lo que significa que la confiabilidad se está degradando), KEDA agrega más
réplicas para absorber la carga. Esto conecta la planificación de capacidad directamente con tus SLOs.

<br />

**Escalamiento por cron para patrones de tráfico predecibles:**

<br />

```elixir
# keda/tr-web-cron-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: tr-web-cron
  namespace: default
spec:
  scaleTargetRef:
    name: tr-web
  minReplicaCount: 2
  maxReplicaCount: 10
  triggers:
    # Escalar durante horario laboral
    - type: cron
      metadata:
        timezone: America/Argentina/Buenos_Aires
        start: "0 8 * * 1-5"   # Lunes a viernes 8am
        end: "0 20 * * 1-5"    # Lunes a viernes 8pm
        desiredReplicas: "4"
```

<br />

Si conocés tus patrones de tráfico (y deberías, de tus datos de observabilidad), el escalamiento proactivo
evita la demora que introduce el autoescalamiento reactivo. ¿Por qué esperar a que el CPU suba si sabés que
el tráfico aumenta todas las mañanas a las 8am?

<br />

##### **Pruebas de carga con k6**
Toda la configuración de autoscaling del mundo es inútil si no la validaste bajo carga real. k6 es una
excelente herramienta de pruebas de carga que hace fácil definir escenarios.

<br />

**Prueba de carga básica para el blog:**

<br />

```elixir
// load-tests/blog-basic.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 50 },   // Subir a 50 usuarios en 2 minutos
    { duration: '5m', target: 50 },   // Mantener en 50 usuarios por 5 minutos
    { duration: '2m', target: 100 },  // Subir a 100 usuarios
    { duration: '5m', target: 100 },  // Mantener en 100 usuarios
    { duration: '2m', target: 0 },    // Bajar a 0
  ],
  thresholds: {
    // Umbrales alineados con SLOs
    http_req_duration: ['p(99)<300'],    // 99% de las requests bajo 300ms
    http_req_failed: ['rate<0.001'],     // Menos de 0.1% tasa de error
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

export default function () {
  // Simular un usuario típico navegando el blog
  const pages = [
    '/blog',
    '/blog/sre-slis-slos-and-automations-that-actually-help',
    '/blog/debugging-distroless-containers-when-your-container-has-no-shell',
  ];

  const page = pages[Math.floor(Math.random() * pages.length)];
  const res = http.get(`${BASE_URL}${page}`);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'body contains content': (r) => r.body.length > 1000,
  });

  sleep(Math.random() * 3 + 1); // Think time aleatorio entre 1-4 segundos
}
```

<br />

**Prueba de validación de autoscaling:**

<br />

Esta es la prueba de carga más importante. Valida que tu HPA arranca correctamente bajo carga:

<br />

```elixir
// load-tests/autoscale-validation.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const errorCount = new Counter('errors');

export const options = {
  stages: [
    // Fase 1: Línea base (debería correr con min replicas)
    { duration: '2m', target: 10 },

    // Fase 2: Rampa para disparar scale-up
    { duration: '1m', target: 200 },

    // Fase 3: Carga alta sostenida (HPA debería escalar)
    { duration: '10m', target: 200 },

    // Fase 4: Rampa de bajada (HPA debería eventualmente reducir)
    { duration: '2m', target: 10 },

    // Fase 5: Carga baja sostenida
    { duration: '5m', target: 10 },
  ],
  thresholds: {
    http_req_duration: ['p(99)<500'],  // Incluso bajo carga, p99 < 500ms
    http_req_failed: ['rate<0.005'],   // Menos de 0.5% errores
    errors: ['count<50'],              // Menos de 50 errores totales
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

export default function () {
  const res = http.get(`${BASE_URL}/blog`);

  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'latency < 500ms': (r) => r.timings.duration < 500,
  });

  if (!success) {
    errorCount.add(1);
  }

  sleep(Math.random() * 2 + 0.5);
}
```

<br />

Corré la prueba mientras mirás tu HPA:

<br />

```elixir
# Terminal 1: Correr la prueba de carga
k6 run --env BASE_URL=https://your-app.example.com load-tests/autoscale-validation.js

# Terminal 2: Mirar HPA
kubectl get hpa tr-web-hpa --watch

# Terminal 3: Mirar pods escalando
kubectl get pods -l app=tr-web --watch
```

<br />

Lo que querés ver:

<br />

> * Durante Fase 1: 2 réplicas (minReplicas), bajo uso de recursos
> * Durante Fase 2-3: HPA escala a 4-6 réplicas dentro de 2-3 minutos de alta carga
> * Durante Fase 3: La latencia se mantiene dentro del SLO incluso con alta carga
> * Durante Fase 4-5: HPA gradualmente reduce a 2 réplicas después de la ventana de estabilización

<br />

##### **Planificación de capacidad como práctica**
Más allá del autoescalamiento, la planificación de capacidad es una práctica continua:

<br />

**1. Rastreá tendencias de utilización de recursos**

Si tu utilización promedio está consistentemente por encima del 80%, necesitás más capacidad. Si está
consistentemente por debajo del 20%, estás sobre-provisionado y desperdiciando plata.

<br />

**2. Revisá después de cada cambio importante**

Después de lanzar una feature nueva, verificá si los patrones de uso de recursos cambiaron. Un job nuevo en
background podría aumentar el uso de memoria. Un endpoint nuevo podría aumentar el uso de CPU en horas pico.

<br />

**3. Planificá para el crecimiento**

Si tu tráfico crece 10% mes a mes, tu maxReplicas del autoscaler necesita acomodar ese crecimiento. Revisá
tus límites máximos trimestralmente y ajustá.

<br />

##### **Juntando todo**
Acá está el setup completo de gestión de capacidad:

<br />

> 1. **VPA en modo recomendación** te dice qué recursos tus pods realmente necesitan
> 2. **Resource requests** se configuran basándose en recomendaciones de VPA y se validan con pruebas de carga
> 3. **HPA con métricas custom** escala pods basándose en tráfico (no solo CPU)
> 4. **Triggers cron de KEDA** escalan proactivamente para patrones de tráfico conocidos
> 5. **Cluster Autoscaler** agrega nodos cuando los pods no pueden ser schedulados
> 6. **Buffer pods** aseguran capacidad instantánea para eventos de scale-up
> 7. **Pruebas de carga con k6** validan todo el pipeline de escalamiento regularmente

<br />

Esto te da un sistema que maneja picos de tráfico automáticamente, dimensiona recursos basándose en uso real,
y te da confianza en que tus SLOs se van a mantener bajo carga.

<br />

##### **Notas finales**
La planificación de capacidad no tiene que ser adivinanza. Con recomendaciones de VPA, autoescalamiento
alineado con SLOs, y pruebas de carga regulares, podés tener confianza en que tu infraestructura maneja
cualquier tráfico que llegue.

<br />

La conclusión más importante: el autoescalamiento no es sustituto de entender tu workload. Conocé tus patrones
de tráfico, probá tus límites de escalamiento, y siempre tené un plan para lo que pasa cuando el tráfico
excede tu capacidad máxima. La respuesta a "¿qué pasa si recibimos 10x de tráfico?" nunca debería ser
"no sé."

<br />

Esto concluye nuestra serie de cinco partes sobre SRE. Desde SLIs/SLOs hasta gestión de incidentes,
observabilidad, chaos engineering, y ahora planificación de capacidad, tenés las herramientas y prácticas
para correr sistemas confiables a cualquier escala.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
