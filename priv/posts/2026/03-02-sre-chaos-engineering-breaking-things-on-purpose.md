%{
  title: "SRE: Chaos Engineering, Breaking Things on Purpose",
  author: "Gabriel Garrido",
  description: "We will explore chaos engineering in Kubernetes using Litmus and Chaos Mesh, how to plan and run game days, and why breaking things on purpose is the best way to build reliable systems...",
  tags: ~w(sre kubernetes chaos-engineering reliability testing),
  published: true,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In the previous articles we covered [SLIs and SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[incident management](/blog/sre-incident-management-on-call-and-postmortems-as-code), and
[observability](/blog/sre-observability-deep-dive-traces-logs-and-metrics). You have metrics, alerts, traces,
runbooks, and postmortem processes. But how do you know any of it actually works before a real incident hits?

<br />

That is where chaos engineering comes in. The idea is simple: intentionally inject failures into your system
to verify that your resilience mechanisms, monitoring, alerting, and incident response processes work as
expected. It is like a fire drill, but for your infrastructure.

<br />

In this article we will cover the principles of chaos engineering, how to set up Litmus and Chaos Mesh in
Kubernetes, how to plan and run game days, and how to build a culture where breaking things on purpose is
not just accepted but encouraged.

<br />

Let's get into it.

<br />

##### **Why break things on purpose?**
Complex systems fail in complex ways. You cannot predict every failure mode by reading code or architecture
diagrams. The only way to truly understand how your system behaves under failure is to actually make it fail.

<br />

Chaos engineering helps you:

<br />

> * **Discover unknown failure modes** before they bite you in production at 3am
> * **Validate your monitoring and alerting** does your SLO alert actually fire when latency spikes?
> * **Test your runbooks** can the on-call engineer actually follow them under pressure?
> * **Build confidence** knowing your system can handle a pod crash or network partition makes you sleep better
> * **Reduce MTTR** practicing incident response makes you faster when real incidents happen

<br />

The Netflix engineering team, who pioneered chaos engineering with Chaos Monkey, put it best: "The best way to
avoid failure is to fail constantly."

<br />

##### **The chaos engineering process**
Chaos engineering is not just randomly killing pods. It is a disciplined process:

<br />

> 1. **Define steady state**: What does "normal" look like? Use your SLIs (from article 1) as the baseline.
> 2. **Hypothesize**: "If we kill one pod, the remaining pods should handle the load and the SLO should not be violated."
> 3. **Inject failure**: Actually kill the pod (or whatever failure you are testing).
> 4. **Observe**: Watch your metrics, traces, and logs. Did the system behave as expected?
> 5. **Learn**: If it did not behave as expected, you found a weakness. Fix it before a real failure finds it for you.

<br />

Always start small. Kill one pod, not the whole deployment. Add 100ms of latency, not 30 seconds. The goal
is controlled experiments, not uncontrolled chaos.

<br />

##### **Chaos Mesh: chaos engineering for Kubernetes**
Chaos Mesh is a CNCF project that provides a comprehensive set of chaos experiments for Kubernetes. It is
easy to install and has a nice web UI for managing experiments.

<br />

Install it with Helm:

<br />

```elixir
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock
```

<br />

Now let's define some experiments. All experiments are Kubernetes custom resources, so they fit perfectly
into a GitOps workflow with ArgoCD.

<br />

**1. Pod failure: kill a random pod**

<br />

```elixir
# chaos/pod-kill.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: tr-web-pod-kill
  namespace: default
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
  scheduler:
    cron: "@every 2h"  # Kill a pod every 2 hours
  duration: "60s"
```

<br />

This kills one random tr-web pod every 2 hours. If your deployment has multiple replicas and a proper
readiness probe, users should not notice anything. If they do, you found a problem.

<br />

**2. Network latency: add artificial delay**

<br />

```elixir
# chaos/network-delay.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: tr-web-network-delay
  namespace: default
spec:
  action: delay
  mode: all
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
  delay:
    latency: "200ms"
    jitter: "50ms"
    correlation: "25"
  direction: to
  target:
    selector:
      namespaces:
        - default
      labelSelectors:
        app: postgresql
    mode: all
  duration: "5m"
```

<br />

This adds 200ms of latency (with 50ms jitter) between your web pods and the database for 5 minutes.
This is incredibly useful for testing timeout configurations and retry logic.

<br />

**3. Network partition: isolate a service**

<br />

```elixir
# chaos/network-partition.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: tr-web-partition
  namespace: default
spec:
  action: partition
  mode: all
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
  direction: both
  target:
    selector:
      namespaces:
        - default
      labelSelectors:
        app: postgresql
    mode: all
  duration: "2m"
```

<br />

This completely cuts network traffic between your web pods and the database. Does your app crash? Does it
show a friendly error page? Does it recover when the network comes back? These are important questions.

<br />

**4. CPU stress: simulate resource contention**

<br />

```elixir
# chaos/cpu-stress.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: tr-web-cpu-stress
  namespace: default
spec:
  mode: one
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
  stressors:
    cpu:
      workers: 2
      load: 80
  duration: "5m"
```

<br />

This burns 80% CPU in one pod. With proper resource limits and HPA, your cluster should handle this gracefully.

<br />

**5. DNS failure: break name resolution**

<br />

```elixir
# chaos/dns-failure.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: DNSChaos
metadata:
  name: tr-web-dns-failure
  namespace: default
spec:
  action: error
  mode: all
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
  patterns:
    - "api.github.com"
  duration: "5m"
```

<br />

This makes DNS resolution fail for `api.github.com` from your web pods. Remember how we fixed the GitHub
sponsors API issue with a dedicated Hackney pool? This experiment verifies that fix actually works, the
database connections should not be affected even when GitHub is unreachable.

<br />

##### **Litmus: experiment workflows**
Litmus is another CNCF chaos engineering project that focuses on experiment workflows. While Chaos Mesh is
great for individual experiments, Litmus excels at orchestrating multi-step chaos scenarios.

<br />

Install Litmus:

<br />

```elixir
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm
helm repo update

helm install litmus litmuschaos/litmus \
  --namespace litmus \
  --create-namespace
```

<br />

A Litmus workflow lets you chain multiple chaos experiments together with validation steps:

<br />

```elixir
# litmus/workflow-resilience-test.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: tr-web-resilience-test
  namespace: litmus
spec:
  entrypoint: resilience-test
  templates:
    - name: resilience-test
      steps:
        # Step 1: Verify steady state
        - - name: verify-baseline
            template: check-slo

        # Step 2: Kill a pod
        - - name: pod-kill
            template: pod-kill-experiment

        # Step 3: Verify SLO is still met
        - - name: verify-after-pod-kill
            template: check-slo

        # Step 4: Add network latency
        - - name: network-delay
            template: network-delay-experiment

        # Step 5: Verify latency SLO
        - - name: verify-after-delay
            template: check-latency-slo

        # Step 6: Clean up and final check
        - - name: final-verification
            template: check-slo

    - name: check-slo
      container:
        image: curlimages/curl:latest
        command:
          - /bin/sh
          - -c
          - |
            # Query Prometheus for current SLI
            AVAILABILITY=$(curl -s "http://prometheus:9090/api/v1/query?query=sli:availability:ratio_rate5m" \
              | jq -r '.data.result[0].value[1]')

            echo "Current availability SLI: $AVAILABILITY"

            if (( $(echo "$AVAILABILITY < 0.999" | bc -l) )); then
              echo "FAIL: Availability below SLO target"
              exit 1
            fi

            echo "PASS: Availability within SLO target"

    - name: check-latency-slo
      container:
        image: curlimages/curl:latest
        command:
          - /bin/sh
          - -c
          - |
            LATENCY=$(curl -s "http://prometheus:9090/api/v1/query?query=sli:latency:ratio_rate5m" \
              | jq -r '.data.result[0].value[1]')

            echo "Current latency SLI: $LATENCY"

            # During chaos, we allow a slightly relaxed SLO
            if (( $(echo "$LATENCY < 0.95" | bc -l) )); then
              echo "FAIL: Latency severely degraded during chaos"
              exit 1
            fi

            echo "PASS: Latency within acceptable range during chaos"

    - name: pod-kill-experiment
      container:
        image: litmuschaos/litmus-checker:latest
        # ... pod kill configuration

    - name: network-delay-experiment
      container:
        image: litmuschaos/litmus-checker:latest
        # ... network delay configuration
```

<br />

This workflow verifies that your service stays within SLO targets even while being subjected to chaos. If
any verification step fails, you know you have a resilience gap to fix.

<br />

##### **Game days: structured chaos**
A game day is a scheduled event where the team intentionally injects failures and practices incident response.
It is like a fire drill, but everyone knows it is happening (mostly).

<br />

Here is how to plan and run a game day:

<br />

**Before the game day (1 week ahead)**

<br />

> * Choose a date and time (during business hours, never on a Friday)
> * Define the scenarios you want to test (2-3 per game day, no more)
> * Notify stakeholders that things might break
> * Assign roles: facilitator, chaos operator, observers
> * Prepare the experiments (have the YAML files ready)
> * Review runbooks for the scenarios you will test

<br />

**Game day checklist template:**

<br />

```elixir
# game-days/2026-02-25-checklist.md
# Game Day: February 25, 2026

## Pre-game
- [ ] All participants confirmed
- [ ] Stakeholders notified
- [ ] Monitoring dashboards open
- [ ] Runbooks accessible
- [ ] Rollback procedures ready
- [ ] Communication channel created (#gameday-2026-02-25)

## Scenario 1: Pod failure recovery
- **Hypothesis**: Killing 1 of 3 tr-web pods should not cause any user-visible errors
- **Experiment**: `chaos/pod-kill.yaml`
- **Success criteria**: Availability SLI stays above 99.9%
- **Duration**: 10 minutes
- **Results**: [ PASS / FAIL ]
- **Notes**: ___

## Scenario 2: Database latency spike
- **Hypothesis**: 200ms extra latency to DB should trigger the latency SLO alert but not the availability alert
- **Experiment**: `chaos/network-delay.yaml`
- **Success criteria**: Latency alert fires within 5 minutes, app remains functional
- **Duration**: 15 minutes
- **Results**: [ PASS / FAIL ]
- **Notes**: ___

## Scenario 3: External dependency failure
- **Hypothesis**: GitHub API being unreachable should not affect blog page load times
- **Experiment**: `chaos/dns-failure.yaml`
- **Success criteria**: Blog pages load normally, only sponsor section is empty
- **Duration**: 10 minutes
- **Results**: [ PASS / FAIL ]
- **Notes**: ___

## Post-game
- [ ] All experiments cleaned up
- [ ] Systems back to steady state
- [ ] Game day retro completed
- [ ] Action items created as GitHub issues
- [ ] Results shared with the team
```

<br />

**During the game day**

<br />

> * The facilitator keeps time and coordinates
> * The chaos operator applies experiments
> * Observers watch dashboards and logs (using the observability stack from article 3)
> * The on-call engineer responds as if it were a real incident
> * Everyone takes notes

<br />

**After the game day**

<br />

Run a retro (just like a postmortem but for the exercise). What worked? What did not? What surprised you?
Create action items for anything that needs fixing.

<br />

##### **Steady state validation with automated chaos**
Once you are comfortable with game days, you can start running automated chaos experiments in production.
This is the advanced level of chaos engineering.

<br />

The key is to tie chaos experiments to your SLO monitoring. If an experiment causes an SLO violation, it
stops automatically:

<br />

```elixir
# chaos/continuous-chaos.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: Schedule
metadata:
  name: continuous-pod-kill
  namespace: default
spec:
  schedule: "0 */4 * * *"  # Every 4 hours
  type: PodChaos
  historyLimit: 5
  concurrencyPolicy: Forbid
  podChaos:
    action: pod-kill
    mode: one
    selector:
      namespaces:
        - default
      labelSelectors:
        app: tr-web
    duration: "30s"
```

<br />

Combine this with an Alertmanager silence that suppresses the chaos-related page alert, but still tracks
the SLO impact:

<br />

```elixir
# Only silence the page alert, not the SLO recording
# This way you can see the SLO impact without getting paged
amtool silence add --alertmanager.url=http://alertmanager:9093 \
  --author="chaos-bot" \
  --comment="Scheduled chaos experiment" \
  --duration="5m" \
  alertname="TrWebPodKilled"
```

<br />

##### **Chaos engineering for Elixir/BEAM applications**
The BEAM VM has some unique characteristics that affect chaos engineering:

<br />

**Supervision trees handle many failures automatically.** When you kill an Elixir process, the supervisor
restarts it. This is great for resilience but means you need to test harder failures (like network partitions
or resource exhaustion) to find real issues.

<br />

**Hot code reloading can mask deployment issues.** If your app uses hot code reloading in production, you
should also test cold restarts.

<br />

**Distribution (Erlang clustering) is sensitive to network issues.** If your nodes are clustered (like our
app with `RELEASE_DISTRIBUTION=name`), test what happens when nodes lose connectivity:

<br />

```elixir
# chaos/cluster-partition.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: beam-cluster-partition
  namespace: default
spec:
  action: partition
  mode: all
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
    fieldSelectors:
      metadata.name: tr-web-0
  direction: both
  target:
    selector:
      namespaces:
        - default
      labelSelectors:
        app: tr-web
      fieldSelectors:
        metadata.name: tr-web-1
    mode: all
  duration: "5m"
```

<br />

This partitions two nodes of your Erlang cluster. Does your app handle the netsplit gracefully? Does it
recover when connectivity returns? These are important questions for clustered BEAM applications.

<br />

##### **What to test first**
If you are just starting with chaos engineering, here is a prioritized list:

<br />

> 1. **Single pod failure**: Can your service handle losing one instance? (This is the minimum)
> 2. **Dependency timeout**: What happens when an external service responds slowly?
> 3. **DNS failure**: Can your app handle name resolution failures gracefully?
> 4. **Resource exhaustion**: What happens when you hit CPU or memory limits?
> 5. **Network partition**: Can your service handle being cut off from a dependency?
> 6. **Disk pressure**: What happens when disk space runs low?
> 7. **Clock skew**: What happens when time drifts between nodes?

<br />

Start with #1 and work your way down. Each experiment should be repeated regularly, not just once.

<br />

##### **Safety guardrails**
Chaos engineering can go wrong if you are not careful. Here are non-negotiable safety rules:

<br />

> * **Always have a kill switch**. Every experiment must be stoppable immediately.
> * **Start in staging**. Never run a new experiment in production for the first time.
> * **Blast radius control**. Affect one pod, not all pods. One service, not all services.
> * **Time-bounded**. Every experiment has a duration. No open-ended chaos.
> * **Monitor continuously**. If SLOs are violated beyond acceptable thresholds, abort.
> * **Business hours only** (for manual experiments). Do not do game days on Fridays at 5pm.
> * **Communicate**. Everyone who needs to know should know that chaos is happening.

<br />

##### **Putting it all together**
Here is the chaos engineering maturity model:

<br />

> 1. **Level 0 - No chaos**: You hope things work. (Most teams start here)
> 2. **Level 1 - Manual game days**: Quarterly game days with pre-planned scenarios
> 3. **Level 2 - Automated chaos in staging**: Regular chaos experiments run automatically in staging
> 4. **Level 3 - Automated chaos in production**: Continuous chaos in production with SLO-based guardrails
> 5. **Level 4 - Chaos as CI**: Chaos experiments run as part of your deployment pipeline

<br />

You do not need to reach Level 4 to get value. Even Level 1 (quarterly game days) will dramatically improve
your team's confidence and incident response speed.

<br />

##### **Closing notes**
Chaos engineering is not about breaking things for fun. It is about building confidence that your systems can
handle the failures that will inevitably occur. Every experiment that passes tells you "this failure mode is
handled." Every experiment that fails tells you "fix this before a real failure finds it."

<br />

The tools we covered, Chaos Mesh, Litmus, game day checklists, are all free and work great in Kubernetes.
Start with a simple pod-kill experiment in staging and build from there. The hardest part is not the tooling,
it is getting organizational buy-in to intentionally break things. But once you show the team the first bug
you found through chaos, they will be convinced.

<br />

This wraps up our four-part SRE series. We went from measuring reliability (SLIs/SLOs) to responding to
failures (incident management) to seeing what is happening (observability) to proactively finding weaknesses
(chaos engineering). Together, these practices give you a solid foundation for running reliable systems.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Chaos Engineering, Rompiendo Cosas a Propósito",
  author: "Gabriel Garrido",
  description: "Vamos a explorar chaos engineering en Kubernetes usando Litmus y Chaos Mesh, cómo planificar y ejecutar game days, y por qué romper cosas a propósito es la mejor forma de construir sistemas confiables...",
  tags: ~w(sre kubernetes chaos-engineering reliability testing),
  published: true,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En los artículos anteriores cubrimos [SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[gestión de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code), y
[observabilidad](/blog/sre-observability-deep-dive-traces-logs-and-metrics). Tenés métricas, alertas, trazas,
runbooks y procesos de postmortem. Pero, ¿cómo sabés que algo de eso realmente funciona antes de que un
incidente real pase?

<br />

Ahí es donde entra el chaos engineering. La idea es simple: inyectar fallas intencionalmente en tu sistema
para verificar que tus mecanismos de resiliencia, monitoreo, alertas y procesos de respuesta a incidentes
funcionan como se espera. Es como un simulacro de incendio, pero para tu infraestructura.

<br />

En este artículo vamos a cubrir los principios del chaos engineering, cómo configurar Litmus y Chaos Mesh en
Kubernetes, cómo planificar y ejecutar game days, y cómo construir una cultura donde romper cosas a propósito
no solo es aceptado sino fomentado.

<br />

Vamos al tema.

<br />

##### **¿Por qué romper cosas a propósito?**
Los sistemas complejos fallan de maneras complejas. No podés predecir todos los modos de falla leyendo código
o diagramas de arquitectura. La única forma de realmente entender cómo se comporta tu sistema bajo fallas es
hacerlo fallar.

<br />

El chaos engineering te ayuda a:

<br />

> * **Descubrir modos de falla desconocidos** antes de que te muerdan en producción a las 3am
> * **Validar tu monitoreo y alertas**, ¿tu alerta de SLO realmente salta cuando la latencia sube?
> * **Probar tus runbooks**, ¿el ingeniero de guardia realmente puede seguirlos bajo presión?
> * **Construir confianza**, saber que tu sistema puede manejar un crash de pod o una partición de red te hace dormir mejor
> * **Reducir MTTR**, practicar respuesta a incidentes te hace más rápido cuando pasan incidentes reales

<br />

El equipo de ingeniería de Netflix, que fue pionero en chaos engineering con Chaos Monkey, lo dijo mejor:
"La mejor manera de evitar fallas es fallar constantemente."

<br />

##### **El proceso de chaos engineering**
Chaos engineering no es simplemente matar pods al azar. Es un proceso disciplinado:

<br />

> 1. **Definir estado estable**: ¿Cómo se ve "normal"? Usá tus SLIs (del artículo 1) como base.
> 2. **Hipotetizar**: "Si matamos un pod, los pods restantes deberían manejar la carga y el SLO no debería violarse."
> 3. **Inyectar falla**: Realmente matá el pod (o cualquier falla que estés probando).
> 4. **Observar**: Mirá tus métricas, trazas y logs. ¿El sistema se comportó como esperabas?
> 5. **Aprender**: Si no se comportó como esperabas, encontraste una debilidad. Arreglala antes de que una falla real la encuentre.

<br />

Siempre empezá de a poco. Matá un pod, no todo el deployment. Agregá 100ms de latencia, no 30 segundos. El
objetivo son experimentos controlados, no caos descontrolado.

<br />

##### **Chaos Mesh: chaos engineering para Kubernetes**
Chaos Mesh es un proyecto de la CNCF que provee un conjunto completo de experimentos de caos para Kubernetes.
Es fácil de instalar y tiene una interfaz web copada para manejar experimentos.

<br />

Instalalo con Helm:

<br />

```elixir
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock
```

<br />

Ahora definamos algunos experimentos. Todos los experimentos son custom resources de Kubernetes, así que
encajan perfectamente en un flujo de GitOps con ArgoCD.

<br />

**1. Falla de pod: matar un pod al azar**

<br />

```elixir
# chaos/pod-kill.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: tr-web-pod-kill
  namespace: default
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
  scheduler:
    cron: "@every 2h"  # Matar un pod cada 2 horas
  duration: "60s"
```

<br />

Esto mata un pod aleatorio de tr-web cada 2 horas. Si tu deployment tiene múltiples réplicas y un readiness
probe adecuado, los usuarios no deberían notar nada. Si lo notan, encontraste un problema.

<br />

**2. Latencia de red: agregar delay artificial**

<br />

```elixir
# chaos/network-delay.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: tr-web-network-delay
  namespace: default
spec:
  action: delay
  mode: all
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
  delay:
    latency: "200ms"
    jitter: "50ms"
    correlation: "25"
  direction: to
  target:
    selector:
      namespaces:
        - default
      labelSelectors:
        app: postgresql
    mode: all
  duration: "5m"
```

<br />

Esto agrega 200ms de latencia (con 50ms de jitter) entre tus pods web y la base de datos por 5 minutos.
Es increíblemente útil para probar configuraciones de timeout y lógica de reintentos.

<br />

**3. Partición de red: aislar un servicio**

<br />

```elixir
# chaos/network-partition.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: tr-web-partition
  namespace: default
spec:
  action: partition
  mode: all
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
  direction: both
  target:
    selector:
      namespaces:
        - default
      labelSelectors:
        app: postgresql
    mode: all
  duration: "2m"
```

<br />

Esto corta completamente el tráfico de red entre tus pods web y la base de datos. ¿Tu app crashea? ¿Muestra
una página de error amigable? ¿Se recupera cuando la red vuelve? Son preguntas importantes.

<br />

**4. Estrés de CPU: simular contención de recursos**

<br />

```elixir
# chaos/cpu-stress.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: tr-web-cpu-stress
  namespace: default
spec:
  mode: one
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
  stressors:
    cpu:
      workers: 2
      load: 80
  duration: "5m"
```

<br />

Esto quema 80% de CPU en un pod. Con resource limits apropiados y HPA, tu cluster debería manejar esto sin
problemas.

<br />

**5. Falla de DNS: romper la resolución de nombres**

<br />

```elixir
# chaos/dns-failure.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: DNSChaos
metadata:
  name: tr-web-dns-failure
  namespace: default
spec:
  action: error
  mode: all
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
  patterns:
    - "api.github.com"
  duration: "5m"
```

<br />

Esto hace que la resolución DNS falle para `api.github.com` desde tus pods web. ¿Recordás cómo arreglamos
el problema de la API de GitHub con un pool de Hackney dedicado? Este experimento verifica que ese arreglo
realmente funciona, las conexiones a la base de datos no deberían verse afectadas aunque GitHub sea
inalcanzable.

<br />

##### **Litmus: workflows de experimentos**
Litmus es otro proyecto de la CNCF que se enfoca en workflows de experimentos. Mientras Chaos Mesh es genial
para experimentos individuales, Litmus destaca en orquestar escenarios de caos con múltiples pasos.

<br />

Un workflow de Litmus te permite encadenar múltiples experimentos con pasos de validación:

<br />

```elixir
# litmus/workflow-resilience-test.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: tr-web-resilience-test
  namespace: litmus
spec:
  entrypoint: resilience-test
  templates:
    - name: resilience-test
      steps:
        # Paso 1: Verificar estado estable
        - - name: verify-baseline
            template: check-slo

        # Paso 2: Matar un pod
        - - name: pod-kill
            template: pod-kill-experiment

        # Paso 3: Verificar que el SLO todavía se cumple
        - - name: verify-after-pod-kill
            template: check-slo

        # Paso 4: Agregar latencia de red
        - - name: network-delay
            template: network-delay-experiment

        # Paso 5: Verificar SLO de latencia
        - - name: verify-after-delay
            template: check-latency-slo

        # Paso 6: Limpieza y verificación final
        - - name: final-verification
            template: check-slo
```

<br />

Este workflow verifica que tu servicio se mantiene dentro de los objetivos de SLO incluso mientras es
sometido a caos. Si algún paso de verificación falla, sabés que tenés una brecha de resiliencia que arreglar.

<br />

##### **Game days: caos estructurado**
Un game day es un evento programado donde el equipo inyecta fallas intencionalmente y practica respuesta a
incidentes. Es como un simulacro de incendio, pero todos saben que está pasando (casi todos).

<br />

Acá cómo planificar y ejecutar un game day:

<br />

**Antes del game day (1 semana antes)**

<br />

> * Elegí una fecha y hora (durante horario laboral, nunca un viernes)
> * Definí los escenarios que querés probar (2-3 por game day, no más)
> * Notificá a los stakeholders que las cosas pueden romperse
> * Asigná roles: facilitador, operador de caos, observadores
> * Preparar los experimentos (tener los archivos YAML listos)
> * Revisar runbooks para los escenarios que vas a probar

<br />

**Checklist template de game day:**

<br />

```elixir
# game-days/2026-02-25-checklist.md
# Game Day: 25 de Febrero, 2026

## Pre-game
- [ ] Todos los participantes confirmados
- [ ] Stakeholders notificados
- [ ] Dashboards de monitoreo abiertos
- [ ] Runbooks accesibles
- [ ] Procedimientos de rollback listos
- [ ] Canal de comunicación creado (#gameday-2026-02-25)

## Escenario 1: Recuperación ante falla de pod
- **Hipótesis**: Matar 1 de 3 pods de tr-web no debería causar errores visibles para el usuario
- **Experimento**: `chaos/pod-kill.yaml`
- **Criterio de éxito**: SLI de disponibilidad se mantiene por encima de 99.9%
- **Duración**: 10 minutos
- **Resultado**: [ PASS / FAIL ]
- **Notas**: ___

## Escenario 2: Pico de latencia en base de datos
- **Hipótesis**: 200ms de latencia extra a la DB debería disparar la alerta de SLO de latencia pero no la de disponibilidad
- **Experimento**: `chaos/network-delay.yaml`
- **Criterio de éxito**: La alerta de latencia salta en 5 minutos, la app sigue funcional
- **Duración**: 15 minutos
- **Resultado**: [ PASS / FAIL ]
- **Notas**: ___

## Escenario 3: Falla de dependencia externa
- **Hipótesis**: La API de GitHub estando inaccesible no debería afectar los tiempos de carga del blog
- **Experimento**: `chaos/dns-failure.yaml`
- **Criterio de éxito**: Las páginas del blog cargan normalmente, solo la sección de sponsors está vacía
- **Duración**: 10 minutos
- **Resultado**: [ PASS / FAIL ]
- **Notas**: ___

## Post-game
- [ ] Todos los experimentos limpiados
- [ ] Sistemas de vuelta al estado estable
- [ ] Retro del game day completada
- [ ] Acciones creadas como issues de GitHub
- [ ] Resultados compartidos con el equipo
```

<br />

**Durante el game day**

<br />

> * El facilitador mantiene el tiempo y coordina
> * El operador de caos aplica los experimentos
> * Los observadores miran dashboards y logs (usando el stack de observabilidad del artículo 3)
> * El ingeniero de guardia responde como si fuera un incidente real
> * Todos toman notas

<br />

**Después del game day**

<br />

Hacé una retro (igual que un postmortem pero para el ejercicio). ¿Qué funcionó? ¿Qué no? ¿Qué te sorprendió?
Creá acciones para todo lo que necesite arreglo.

<br />

##### **Chaos engineering para aplicaciones Elixir/BEAM**
La VM BEAM tiene algunas características únicas que afectan el chaos engineering:

<br />

**Los árboles de supervisión manejan muchas fallas automáticamente.** Cuando matás un proceso Elixir, el
supervisor lo reinicia. Esto es genial para la resiliencia pero significa que necesitás probar fallas más duras
(como particiones de red o agotamiento de recursos) para encontrar problemas reales.

<br />

**La distribución (clustering de Erlang) es sensible a problemas de red.** Si tus nodos están en cluster
(como nuestra app con `RELEASE_DISTRIBUTION=name`), probá qué pasa cuando los nodos pierden conectividad:

<br />

```elixir
# chaos/cluster-partition.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: beam-cluster-partition
  namespace: default
spec:
  action: partition
  mode: all
  selector:
    namespaces:
      - default
    labelSelectors:
      app: tr-web
    fieldSelectors:
      metadata.name: tr-web-0
  direction: both
  target:
    selector:
      namespaces:
        - default
      labelSelectors:
        app: tr-web
      fieldSelectors:
        metadata.name: tr-web-1
    mode: all
  duration: "5m"
```

<br />

Esto particiona dos nodos de tu cluster de Erlang. ¿Tu app maneja el netsplit de forma elegante? ¿Se recupera
cuando vuelve la conectividad? Son preguntas importantes para aplicaciones BEAM en cluster.

<br />

##### **Qué probar primero**
Si recién empezás con chaos engineering, acá hay una lista priorizada:

<br />

> 1. **Falla de un solo pod**: ¿Tu servicio puede manejar la pérdida de una instancia? (Esto es el mínimo)
> 2. **Timeout de dependencia**: ¿Qué pasa cuando un servicio externo responde lento?
> 3. **Falla de DNS**: ¿Tu app puede manejar fallas de resolución de nombres de forma elegante?
> 4. **Agotamiento de recursos**: ¿Qué pasa cuando llegás a los límites de CPU o memoria?
> 5. **Partición de red**: ¿Tu servicio puede manejar estar aislado de una dependencia?
> 6. **Presión de disco**: ¿Qué pasa cuando queda poco espacio en disco?
> 7. **Desfase de reloj**: ¿Qué pasa cuando el tiempo se desfasa entre nodos?

<br />

Empezá con el #1 y avanzá hacia abajo. Cada experimento debería repetirse regularmente, no solo una vez.

<br />

##### **Guardarraíles de seguridad**
El chaos engineering puede salir mal si no tenés cuidado. Acá hay reglas de seguridad no negociables:

<br />

> * **Siempre tené un kill switch**. Todo experimento tiene que poder detenerse inmediatamente.
> * **Empezá en staging**. Nunca corras un experimento nuevo en producción por primera vez.
> * **Control del radio de explosión**. Afectá un pod, no todos. Un servicio, no todos.
> * **Acotado en tiempo**. Todo experimento tiene una duración. Nada de caos sin fin.
> * **Monitoreá continuamente**. Si los SLOs se violan más allá de umbrales aceptables, abortá.
> * **Solo en horario laboral** (para experimentos manuales). No hagas game days un viernes a las 5pm.
> * **Comunicá**. Todos los que necesitan saber deberían saber que hay caos en curso.

<br />

##### **Juntando todo**
Acá está el modelo de madurez de chaos engineering:

<br />

> 1. **Nivel 0 - Sin caos**: Esperás que las cosas funcionen. (La mayoría de los equipos arrancan acá)
> 2. **Nivel 1 - Game days manuales**: Game days trimestrales con escenarios pre-planificados
> 3. **Nivel 2 - Caos automatizado en staging**: Experimentos regulares corren automáticamente en staging
> 4. **Nivel 3 - Caos automatizado en producción**: Caos continuo en producción con guardarraíles basados en SLOs
> 5. **Nivel 4 - Caos como CI**: Experimentos de caos corren como parte de tu pipeline de deployment

<br />

No necesitás llegar al Nivel 4 para obtener valor. Incluso el Nivel 1 (game days trimestrales) va a mejorar
dramáticamente la confianza de tu equipo y la velocidad de respuesta a incidentes.

<br />

##### **Notas finales**
Chaos engineering no se trata de romper cosas por diversión. Se trata de construir confianza en que tus sistemas
pueden manejar las fallas que inevitablemente van a ocurrir. Cada experimento que pasa te dice "este modo de
falla está manejado." Cada experimento que falla te dice "arreglá esto antes de que una falla real lo encuentre."

<br />

Las herramientas que cubrimos, Chaos Mesh, Litmus, checklists de game days, son todas gratis y funcionan
genial en Kubernetes. Empezá con un simple experimento de pod-kill en staging y construí desde ahí. Lo más
difícil no son las herramientas, es conseguir el buy-in organizacional para romper cosas intencionalmente. Pero
una vez que le mostrás al equipo el primer bug que encontraste a través del caos, se van a convencer.

<br />

Esto cierra nuestra serie de cuatro partes sobre SRE. Fuimos desde medir la confiabilidad (SLIs/SLOs) hasta
responder a fallas (gestión de incidentes) hasta ver lo que está pasando (observabilidad) hasta encontrar
debilidades proactivamente (chaos engineering). Juntas, estas prácticas te dan una base sólida para correr
sistemas confiables.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
