%{
  title: "SRE: Release Engineering and Progressive Delivery",
  author: "Gabriel Garrido",
  description: "We will explore release engineering practices for reliable deployments, from canary releases with Argo Rollouts and blue-green deployments to feature flags, rollback automation, and deployment SLOs...",
  tags: ~w(sre kubernetes deployment ci-cd argocd),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Throughout this SRE series we have covered a lot of ground:
[SLIs and SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[incident management](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observability](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[capacity planning](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[secrets management](/blog/sre-secrets-management-in-kubernetes),
[cost optimization](/blog/sre-cost-optimization-in-the-cloud),
[dependency management](/blog/sre-dependency-management-and-graceful-degradation), and
[database reliability](/blog/sre-database-reliability). We have SLOs, alerts, runbooks, observability
pipelines, chaos experiments, and GitOps workflows. But none of that matters if your deployments keep
causing outages.

<br />

Deployments are the number one cause of incidents in most organizations. Every time you push new code to
production, you are introducing change, and change is where failures live. Release engineering is the
discipline of making deployments safe, predictable, and boring. Progressive delivery takes that further by
gradually rolling out changes to small subsets of users, validating at each step, and automatically rolling
back when something goes wrong.

<br />

In this article we will cover canary deployments with Argo Rollouts, blue-green deployments, feature flags
in Elixir, automatic rollback, deployment SLOs, ArgoCD sync hooks, GitOps-driven releases, and release
cadence policies.

<br />

Let's get into it.

<br />

##### **Canary deployments with Argo Rollouts**
A canary deployment sends a small percentage of traffic to the new version first. If the canary stays
healthy, you gradually increase traffic. If it gets sick, you pull it back before anyone else is affected.

<br />

Argo Rollouts is a Kubernetes controller that replaces the standard Deployment with a Rollout CRD giving
you fine-grained control over the rollout process. Install it first:

<br />

```bash
# Install Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Install the kubectl plugin
brew install argoproj/tap/kubectl-argo-rollouts
```

<br />

Now define a canary Rollout for our Elixir application:

<br />

```yaml
# rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: tr-web
spec:
  replicas: 4
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
          image: kainlite/tr:v1.2.0
          ports:
            - containerPort: 4000
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "512Mi"
          readinessProbe:
            httpGet:
              path: /healthz
              port: 4000
            initialDelaySeconds: 10
  strategy:
    canary:
      canaryService: tr-web-canary
      stableService: tr-web-stable
      trafficRouting:
        nginx:
          stableIngress: tr-web-ingress
      steps:
        - setWeight: 5
        - pause: { duration: 2m }
        - analysis:
            templates:
              - templateName: canary-success-rate
            args:
              - name: service-name
                value: tr-web-canary
        - setWeight: 20
        - pause: { duration: 3m }
        - analysis:
            templates:
              - templateName: canary-success-rate
        - setWeight: 50
        - pause: { duration: 5m }
        - setWeight: 100
```

<br />

The `steps` section defines the rollout process:

<br />

> 1. **5% traffic** goes to the new version, then pause for 2 minutes
> 2. **Analysis runs** checking error rate against our SLO
> 3. **20% traffic** if analysis passed, bump up and pause 3 minutes
> 4. **50% traffic** for 5 minutes
> 5. **100% traffic** full promotion if everything looks good

<br />

You also need stable and canary services:

<br />

```yaml
# services.yaml
apiVersion: v1
kind: Service
metadata:
  name: tr-web-stable
spec:
  selector:
    app: tr-web
  ports:
    - port: 80
      targetPort: 4000
---
apiVersion: v1
kind: Service
metadata:
  name: tr-web-canary
spec:
  selector:
    app: tr-web
  ports:
    - port: 80
      targetPort: 4000
```

<br />

To manage rollouts use the kubectl plugin:

<br />

```bash
# Watch the rollout
kubectl argo rollouts get rollout tr-web --watch

# Manually promote a paused rollout
kubectl argo rollouts promote tr-web

# Abort and go back to stable
kubectl argo rollouts abort tr-web
```

<br />

##### **Blue-green deployments**
Blue-green runs two complete environments side by side. "Blue" is the current version, "green" is the new
one. You deploy green, test it, and switch all traffic at once. If something breaks, you switch back to blue.

<br />

The tradeoff versus canary is simplicity (no gradual shifting) but you need double the resources during
deployment and all users move at once. Here is a blue-green Rollout:

<br />

```yaml
# blue-green-rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: tr-web-bluegreen
spec:
  replicas: 4
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
          image: kainlite/tr:v1.2.0
          ports:
            - containerPort: 4000
          readinessProbe:
            httpGet:
              path: /healthz
              port: 4000
  strategy:
    blueGreen:
      activeService: tr-web-active
      previewService: tr-web-preview
      autoPromotionEnabled: false
      scaleDownDelaySeconds: 30
      prePromotionAnalysis:
        templates:
          - templateName: bluegreen-smoke-test
        args:
          - name: service-name
            value: tr-web-preview
      postPromotionAnalysis:
        templates:
          - templateName: canary-success-rate
        args:
          - name: service-name
            value: tr-web-active
```

<br />

When you update the image tag:

<br />

> 1. **New pods are created** alongside existing ones
> 2. **Preview service** points to new pods for testing
> 3. **Pre-promotion analysis** runs smoke tests against preview
> 4. **Manual promotion** required since `autoPromotionEnabled` is false
> 5. **Traffic switches** all at once from blue to green
> 6. **Old pods scale down** after `scaleDownDelaySeconds`

<br />

##### **Feature flags**
Feature flags let you decouple deployment from release. You deploy code but the feature is hidden behind a
flag you can toggle at runtime without a new deployment.

<br />

Here is a simple feature flag system in Elixir using ETS:

<br />

```yaml
# lib/tr/feature_flags.ex
defmodule Tr.FeatureFlags do
  use GenServer

  @table :feature_flags

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def enabled?(feature) when is_atom(feature) do
    case :ets.lookup(@table, feature) do
      [{^feature, %{enabled: true, percentage: 100}}] -> true
      [{^feature, %{enabled: true, percentage: pct}}] -> :rand.uniform(100) <= pct
      _ -> false
    end
  end

  def enabled?(feature, user_id) when is_atom(feature) do
    case :ets.lookup(@table, feature) do
      [{^feature, %{enabled: true, percentage: 100}}] -> true
      [{^feature, %{enabled: true, percentage: pct}}] ->
        hash = :erlang.phash2({feature, user_id}, 100)
        hash < pct
      _ -> false
    end
  end

  def enable(feature, percentage \\ 100) when is_atom(feature) do
    GenServer.call(__MODULE__, {:enable, feature, percentage})
  end

  def disable(feature) when is_atom(feature) do
    GenServer.call(__MODULE__, {:disable, feature})
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    load_defaults()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:enable, feature, percentage}, _from, state) do
    :ets.insert(@table, {feature, %{enabled: true, percentage: percentage}})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:disable, feature}, _from, state) do
    :ets.insert(@table, {feature, %{enabled: false, percentage: 0}})
    {:reply, :ok, state}
  end

  defp load_defaults do
    defaults = Application.get_env(:tr, :feature_flags, [])
    Enum.each(defaults, fn {name, config} ->
      :ets.insert(@table, {name, config})
    end)
  end
end
```

<br />

Configure defaults and use it in your views:

<br />

```yaml
# config/config.exs
config :tr, :feature_flags, [
  new_search_ui: %{enabled: false, percentage: 0},
  dark_mode: %{enabled: true, percentage: 100},
  experimental_editor: %{enabled: true, percentage: 10}
]
```

<br />

```bash
# In a LiveView
def render(assigns) do
  ~H"""
  <%= if Tr.FeatureFlags.enabled?(:new_search_ui) do %>
    <.new_search_component />
  <% else %>
    <.legacy_search_component />
  <% end %>
  """
end
```

<br />

The `enabled?/2` variant uses consistent hashing so user 42 always gets the same result at any percentage.
You can progressively roll out:

<br />

```plaintext
Tr.FeatureFlags.enable(:new_search_ui, 25)  # 25% of users
Tr.FeatureFlags.enable(:new_search_ui, 50)  # 50% of users
Tr.FeatureFlags.enable(:new_search_ui, 100) # everyone
Tr.FeatureFlags.disable(:new_search_ui)     # kill switch
```

<br />

##### **Rollback automation**
The fastest way to recover from a bad deployment is to roll back. With proper automation, this can happen in
under a minute without human intervention.

<br />

With Argo Rollouts, rollback is automatic when analysis fails. The rollout is aborted and traffic shifts back
to the stable version. For ArgoCD deployments, you can automate rollback in your CI pipeline:

<br />

```yaml
# .github/workflows/deploy.yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to production
        run: |
          kubectl set image deployment/tr-web \
            tr-web=kainlite/tr:${{ github.sha }}

      - name: Wait for rollout
        id: rollout
        continue-on-error: true
        run: kubectl rollout status deployment/tr-web --timeout=180s

      - name: Run smoke tests
        id: smoke
        if: steps.rollout.outcome == 'success'
        continue-on-error: true
        run: |
          for i in $(seq 1 5); do
            STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
              https://techsquad.rocks/healthz)
            if [ "$STATUS" != "200" ]; then exit 1; fi
            sleep 2
          done

      - name: Rollback on failure
        if: steps.rollout.outcome == 'failure' || steps.smoke.outcome == 'failure'
        run: |
          echo "Deployment failed, rolling back..."
          kubectl rollout undo deployment/tr-web
          exit 1
```

<br />

You can also use kubectl directly for quick rollbacks:

<br />

```bash
# Kubernetes native rollback
kubectl rollout undo deployment/tr-web

# ArgoCD rollback to previous revision
argocd app history tr-web
argocd app rollback tr-web <previous-revision>
```

<br />

The key principle is that rollbacks should be automatic, fast, and require zero human decision-making.

<br />

##### **Deployment SLOs**
In the [SLIs and SLOs article](/blog/sre-slis-slos-and-automations-that-actually-help) we defined SLOs for
our services. Now we use those same SLOs as deployment gates. If a canary violates the SLO, the deployment
stops.

<br />

Argo Rollouts uses AnalysisTemplates to query Prometheus and decide whether a deployment is healthy:

<br />

```yaml
# analysis-template.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: canary-success-rate
spec:
  args:
    - name: service-name
  metrics:
    - name: success-rate
      interval: 30s
      count: 5
      successCondition: result[0] >= 0.99
      failureLimit: 2
      provider:
        prometheus:
          address: http://prometheus.monitoring.svc:9090
          query: |
            sum(rate(
              http_requests_total{service="{{args.service-name}}", status!~"5.."}[2m]
            )) /
            sum(rate(
              http_requests_total{service="{{args.service-name}}"}[2m]
            ))
```

<br />

This template:

<br />

> * **Queries Prometheus** every 30 seconds for the success rate
> * **Runs 5 measurements** for enough data to decide
> * **Requires 99% success rate** matching our SLO
> * **Allows 2 failures** before marking analysis as failed

<br />

You can also gate deployments on error budget. If less than 20% of your 30-day error budget remains, block
the deployment:

<br />

```yaml
# analysis-error-budget.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: error-budget-gate
spec:
  metrics:
    - name: error-budget-remaining
      interval: 1m
      count: 1
      successCondition: result[0] > 0.2
      provider:
        prometheus:
          address: http://prometheus.monitoring.svc:9090
          query: |
            1 - (
              (1 - (
                sum(rate(http_requests_total{service="tr-web", status!~"5.."}[30d])) /
                sum(rate(http_requests_total{service="tr-web"}[30d]))
              )) / (1 - 0.999)
            )
```

<br />

Combine multiple analyses in your rollout steps for comprehensive validation:

<br />

```yaml
steps:
  - setWeight: 10
  - pause: { duration: 2m }
  - analysis:
      templates:
        - templateName: canary-success-rate
        - templateName: canary-latency
      args:
        - name: service-name
          value: tr-web-canary
```

<br />

##### **Pre and post sync hooks**
ArgoCD supports resource hooks that run at specific points during sync. These are perfect for database
migrations before deployment, smoke tests after, and notifications at various stages.

<br />

Pre-sync hook for database migrations:

<br />

```yaml
# migration-hook.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: tr-web-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: kainlite/tr:v1.2.0
          command: ["/app/bin/tr"]
          args: ["eval", "Tr.Release.migrate()"]
          envFrom:
            - secretRef:
                name: tr-web-env
      restartPolicy: Never
  backoffLimit: 3
```

<br />

Post-sync hook for smoke tests:

<br />

```yaml
# smoke-test-hook.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: tr-web-smoke-test
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: smoke-test
          image: curlimages/curl:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://tr-web-stable/healthz)
              if [ "$STATUS" != "200" ]; then exit 1; fi
              echo "Smoke tests passed!"
      restartPolicy: Never
  backoffLimit: 1
```

<br />

Failure notification hook:

<br />

```yaml
# notification-hook.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: tr-web-notify
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: notify
          image: curlimages/curl:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              curl -X POST "${SLACK_WEBHOOK_URL}" \
                -H 'Content-Type: application/json' \
                -d '{"text": "Sync FAILED for tr-web in production!"}'
          envFrom:
            - secretRef:
                name: slack-webhook
      restartPolicy: Never
```

<br />

The available hook types are:

<br />

> * **PreSync** runs before sync (migrations, backups)
> * **Sync** runs during sync alongside other resources
> * **PostSync** runs after all resources are synced and healthy
> * **SyncFail** runs when sync fails (alert notifications)

<br />

##### **GitOps-driven releases**
With GitOps, every deployment is a git commit. This gives you a complete audit trail and the ability to use
git revert as a rollback mechanism.

<br />

The ArgoCD Image Updater detects new container images and updates the git repository automatically:

<br />

```yaml
# argocd-image-updater annotations on the Application
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: tr=kainlite/tr
    argocd-image-updater.argoproj.io/tr.update-strategy: semver
    argocd-image-updater.argoproj.io/tr.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/git-branch: main
```

<br />

For a PR-based flow with review before production, use a GitHub Action that creates a promotion PR:

<br />

```yaml
# .github/workflows/promote.yaml
name: Promote to Production
on:
  workflow_run:
    workflows: ["Build and Push"]
    types: [completed]
    branches: [main]

jobs:
  promote:
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    steps:
      - uses: actions/checkout@v4
        with:
          repository: kainlite/tr-infra
          token: ${{ secrets.INFRA_REPO_TOKEN }}

      - name: Update image tag
        run: |
          cd k8s/overlays/production
          kustomize edit set image \
            kainlite/tr=kainlite/tr:${{ github.event.workflow_run.head_sha }}

      - name: Create PR
        uses: peter-evans/create-pull-request@v6
        with:
          commit-message: "chore: bump tr-web to ${{ github.event.workflow_run.head_sha }}"
          title: "Deploy tr-web ${{ github.event.workflow_run.head_sha }}"
          branch: deploy/tr-web-${{ github.event.workflow_run.head_sha }}
          base: main
```

<br />

Use Kustomize overlays for environment promotion:

<br />

```yaml
# k8s/overlays/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: kainlite/tr
    newTag: abc123-staging
namespace: staging

# k8s/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: kainlite/tr
    newTag: v1.2.0
namespace: default
```

<br />

The full workflow:

<br />

> 1. **Developer pushes code** to the application repo
> 2. **CI builds and tests**, pushes a container image
> 3. **Image updater** detects new image and updates staging
> 4. **Staging tests pass** including canary analysis
> 5. **PR is created** to promote to production
> 6. **Team reviews and merges** the PR
> 7. **ArgoCD syncs** with the Argo Rollout strategy
> 8. **Canary analysis** validates against SLOs
> 9. **Full rollout** completes if healthy

<br />

Every step is traceable through git. If something goes wrong, `git revert` the promotion PR and ArgoCD
rolls back.

<br />

##### **Release cadence and freezes**
Great tooling is important, but you also need policies around when you deploy. ArgoCD supports sync windows:

<br />

```yaml
# argocd-project.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  syncWindows:
    # Allow syncs Monday-Thursday, 9am to 4pm UTC
    - kind: allow
      schedule: "0 9 * * 1-4"
      duration: 7h
      applications: ["*"]

    # No Friday afternoon deploys
    - kind: deny
      schedule: "0 14 * * 5"
      duration: 10h
      applications: ["*"]

    # End of year freeze (Dec 20 to Jan 1)
    - kind: deny
      schedule: "0 0 20 12 *"
      duration: 288h
      applications: ["*"]

    # Always allow manual syncs for emergencies
    - kind: allow
      schedule: "* * * * *"
      duration: 24h
      applications: ["*"]
      manualSync: true
```

<br />

Practical guidelines:

<br />

> * **Deploy often, deploy small**: smaller changes are easier to debug
> * **No Friday afternoon deploys**: unless you enjoy weekend pages
> * **Holiday freezes**: plan them in advance, communicate clearly
> * **Emergency exceptions**: always have a process for critical hotfixes
> * **Deploy windows**: deploy only when someone is around to watch

<br />

You can also enforce this in CI:

<br />

```bash
# check-deploy-window.sh
#!/bin/bash
set -euo pipefail

HOUR=$(date -u +%H)
DAY=$(date -u +%u)  # 1=Monday, 7=Sunday

if [ "$DAY" -ge 6 ]; then
  echo "Deploy blocked: no weekend deployments"; exit 1
fi

if [ "$DAY" -eq 5 ] && [ "$HOUR" -ge 14 ]; then
  echo "Deploy blocked: no Friday afternoon deployments"; exit 1
fi

if [ "$HOUR" -lt 9 ] || [ "$HOUR" -ge 16 ]; then
  echo "Deploy blocked: outside window (09:00-16:00 UTC)"; exit 1
fi

echo "Deploy window open, proceeding..."
```

<br />

The balance is between safety and velocity. Too many restrictions and your team stops deploying, which
actually makes deployments riskier because each one contains more changes.

<br />

##### **Closing notes**
Release engineering is about making deployments boring. When you have canary deployments that validate
against your SLOs, blue-green strategies with instant rollback, feature flags for decoupling deployment from
release, and GitOps pipelines with full audit trails, deployments become routine operations instead of
scary events.

<br />

Start with one piece, maybe canary deployments with a simple error rate analysis, and build from there.
The goal is not zero deployments, it is zero deployment-caused incidents. Ship fast, ship safely, and let
automation catch problems before your users do.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Ingeniería de Releases y Entrega Progresiva",
  author: "Gabriel Garrido",
  description: "Vamos a explorar prácticas de ingeniería de releases para deployments confiables, desde canary releases con Argo Rollouts y deployments blue-green hasta feature flags, automatización de rollbacks, y SLOs de deployment...",
  tags: ~w(sre kubernetes deployment ci-cd argocd),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
A lo largo de esta serie de SRE cubrimos un montón de terreno:
[SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[gestión de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observabilidad](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[planificación de capacidad](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[gestión de secretos](/blog/sre-secrets-management-in-kubernetes),
[optimización de costos](/blog/sre-cost-optimization-in-the-cloud),
[gestión de dependencias](/blog/sre-dependency-management-and-graceful-degradation), y
[confiabilidad de bases de datos](/blog/sre-database-reliability). Tenemos SLOs, alertas, runbooks,
pipelines de observabilidad, experimentos de caos y workflows de GitOps. Pero nada de eso importa si tus
deployments siguen causando incidentes.

<br />

Los deployments son la causa número uno de incidentes en la mayoría de las organizaciones. Cada vez que
empujás código nuevo a producción, estás introduciendo un cambio, y los cambios son donde viven las fallas.
La ingeniería de releases es la disciplina de hacer que los deployments sean seguros, predecibles y
aburridos. La entrega progresiva va un paso más allá, desplegando cambios gradualmente a subconjuntos
pequeños de usuarios, validando en cada paso, y haciendo rollback automáticamente cuando algo sale mal.

<br />

En este artículo vamos a cubrir canary deployments con Argo Rollouts, deployments blue-green, feature flags
en Elixir, rollback automático, SLOs de deployment, hooks de sync en ArgoCD, releases basados en GitOps, y
políticas de cadencia de releases.

<br />

Vamos al tema.

<br />

##### **Canary deployments con Argo Rollouts**
Un canary deployment manda un porcentaje pequeño de tráfico a la versión nueva primero. Si el canario se
mantiene saludable, vas aumentando el tráfico gradualmente. Si se enferma, lo sacás antes de que alguien
más se vea afectado.

<br />

Argo Rollouts es un controlador de Kubernetes que reemplaza el Deployment estándar con un CRD Rollout que
te da control detallado sobre el proceso de despliegue. Instalalo primero:

<br />

```bash
# Instalar Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Instalar el plugin de kubectl
brew install argoproj/tap/kubectl-argo-rollouts
```

<br />

Ahora definamos un Rollout canary para nuestra aplicación Elixir:

<br />

```yaml
# rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: tr-web
spec:
  replicas: 4
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
          image: kainlite/tr:v1.2.0
          ports:
            - containerPort: 4000
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "512Mi"
          readinessProbe:
            httpGet:
              path: /healthz
              port: 4000
            initialDelaySeconds: 10
  strategy:
    canary:
      canaryService: tr-web-canary
      stableService: tr-web-stable
      trafficRouting:
        nginx:
          stableIngress: tr-web-ingress
      steps:
        - setWeight: 5
        - pause: { duration: 2m }
        - analysis:
            templates:
              - templateName: canary-success-rate
            args:
              - name: service-name
                value: tr-web-canary
        - setWeight: 20
        - pause: { duration: 3m }
        - analysis:
            templates:
              - templateName: canary-success-rate
        - setWeight: 50
        - pause: { duration: 5m }
        - setWeight: 100
```

<br />

La sección `steps` define el proceso de rollout:

<br />

> 1. **5% del tráfico** va a la versión nueva, después pausa de 2 minutos
> 2. **El análisis corre** chequeando la tasa de error contra nuestro SLO
> 3. **20% del tráfico** si el análisis pasó, subimos y pausamos 3 minutos
> 4. **50% del tráfico** por 5 minutos
> 5. **100% del tráfico** promoción completa si todo se ve bien

<br />

También necesitás los services stable y canary:

<br />

```yaml
# services.yaml
apiVersion: v1
kind: Service
metadata:
  name: tr-web-stable
spec:
  selector:
    app: tr-web
  ports:
    - port: 80
      targetPort: 4000
---
apiVersion: v1
kind: Service
metadata:
  name: tr-web-canary
spec:
  selector:
    app: tr-web
  ports:
    - port: 80
      targetPort: 4000
```

<br />

Para manejar rollouts usá el plugin de kubectl:

<br />

```bash
# Ver el rollout
kubectl argo rollouts get rollout tr-web --watch

# Promover manualmente un rollout pausado
kubectl argo rollouts promote tr-web

# Abortar y volver a la versión estable
kubectl argo rollouts abort tr-web
```

<br />

##### **Deployments blue-green**
Blue-green corre dos ambientes completos en paralelo. "Blue" es la versión actual, "green" es la nueva.
Desplegás green, la testeás, y cambiás todo el tráfico de una. Si algo se rompe, volvés a blue.

<br />

El trade-off contra canary es simplicidad (sin cambio gradual) pero necesitás el doble de recursos durante
el deployment y todos los usuarios se mueven de golpe. Acá va un Rollout blue-green:

<br />

```yaml
# blue-green-rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: tr-web-bluegreen
spec:
  replicas: 4
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
          image: kainlite/tr:v1.2.0
          ports:
            - containerPort: 4000
          readinessProbe:
            httpGet:
              path: /healthz
              port: 4000
  strategy:
    blueGreen:
      activeService: tr-web-active
      previewService: tr-web-preview
      autoPromotionEnabled: false
      scaleDownDelaySeconds: 30
      prePromotionAnalysis:
        templates:
          - templateName: bluegreen-smoke-test
        args:
          - name: service-name
            value: tr-web-preview
      postPromotionAnalysis:
        templates:
          - templateName: canary-success-rate
        args:
          - name: service-name
            value: tr-web-active
```

<br />

Cuando actualizás el tag de la imagen:

<br />

> 1. **Se crean pods nuevos** al lado de los existentes
> 2. **El service preview** apunta a los pods nuevos para testear
> 3. **Análisis de pre-promoción** corre smoke tests contra preview
> 4. **Promoción manual** requerida ya que `autoPromotionEnabled` es false
> 5. **El tráfico cambia** todo de una de blue a green
> 6. **Los pods viejos escalan a cero** después de `scaleDownDelaySeconds`

<br />

##### **Feature flags**
Los feature flags te permiten desacoplar el deployment del release. Deployás el código pero la
funcionalidad está oculta detrás de un flag que podés activar en runtime sin un nuevo deployment.

<br />

Acá va un sistema de feature flags simple en Elixir usando ETS:

<br />

```yaml
# lib/tr/feature_flags.ex
defmodule Tr.FeatureFlags do
  use GenServer

  @table :feature_flags

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def enabled?(feature) when is_atom(feature) do
    case :ets.lookup(@table, feature) do
      [{^feature, %{enabled: true, percentage: 100}}] -> true
      [{^feature, %{enabled: true, percentage: pct}}] -> :rand.uniform(100) <= pct
      _ -> false
    end
  end

  def enabled?(feature, user_id) when is_atom(feature) do
    case :ets.lookup(@table, feature) do
      [{^feature, %{enabled: true, percentage: 100}}] -> true
      [{^feature, %{enabled: true, percentage: pct}}] ->
        hash = :erlang.phash2({feature, user_id}, 100)
        hash < pct
      _ -> false
    end
  end

  def enable(feature, percentage \\ 100) when is_atom(feature) do
    GenServer.call(__MODULE__, {:enable, feature, percentage})
  end

  def disable(feature) when is_atom(feature) do
    GenServer.call(__MODULE__, {:disable, feature})
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    load_defaults()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:enable, feature, percentage}, _from, state) do
    :ets.insert(@table, {feature, %{enabled: true, percentage: percentage}})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:disable, feature}, _from, state) do
    :ets.insert(@table, {feature, %{enabled: false, percentage: 0}})
    {:reply, :ok, state}
  end

  defp load_defaults do
    defaults = Application.get_env(:tr, :feature_flags, [])
    Enum.each(defaults, fn {name, config} ->
      :ets.insert(@table, {name, config})
    end)
  end
end
```

<br />

Configurá los defaults y usálo en tus vistas:

<br />

```yaml
# config/config.exs
config :tr, :feature_flags, [
  new_search_ui: %{enabled: false, percentage: 0},
  dark_mode: %{enabled: true, percentage: 100},
  experimental_editor: %{enabled: true, percentage: 10}
]
```

<br />

```bash
# En un LiveView
def render(assigns) do
  ~H"""
  <%= if Tr.FeatureFlags.enabled?(:new_search_ui) do %>
    <.new_search_component />
  <% else %>
    <.legacy_search_component />
  <% end %>
  """
end
```

<br />

La variante `enabled?/2` usa hashing consistente para que el usuario 42 siempre obtenga el mismo resultado
a cualquier porcentaje. Podés hacer rollout progresivo:

<br />

```plaintext
Tr.FeatureFlags.enable(:new_search_ui, 25)  # 25% de usuarios
Tr.FeatureFlags.enable(:new_search_ui, 50)  # 50% de usuarios
Tr.FeatureFlags.enable(:new_search_ui, 100) # todos
Tr.FeatureFlags.disable(:new_search_ui)     # kill switch
```

<br />

##### **Automatización de rollbacks**
La forma más rápida de recuperarte de un deployment malo es hacer rollback. Con la automatización correcta,
esto puede pasar en menos de un minuto sin intervención humana.

<br />

Con Argo Rollouts, el rollback es automático cuando el análisis falla. El rollout se aborta y el tráfico
vuelve a la versión estable. Para deployments con ArgoCD, podés automatizar el rollback en tu pipeline de
CI:

<br />

```yaml
# .github/workflows/deploy.yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy a producción
        run: |
          kubectl set image deployment/tr-web \
            tr-web=kainlite/tr:${{ github.sha }}

      - name: Esperar rollout
        id: rollout
        continue-on-error: true
        run: kubectl rollout status deployment/tr-web --timeout=180s

      - name: Correr smoke tests
        id: smoke
        if: steps.rollout.outcome == 'success'
        continue-on-error: true
        run: |
          for i in $(seq 1 5); do
            STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
              https://techsquad.rocks/healthz)
            if [ "$STATUS" != "200" ]; then exit 1; fi
            sleep 2
          done

      - name: Rollback si falla
        if: steps.rollout.outcome == 'failure' || steps.smoke.outcome == 'failure'
        run: |
          echo "Deployment falló, haciendo rollback..."
          kubectl rollout undo deployment/tr-web
          exit 1
```

<br />

También podés usar kubectl directamente para rollbacks rápidos:

<br />

```bash
# Rollback nativo de Kubernetes
kubectl rollout undo deployment/tr-web

# Rollback de ArgoCD a revisión anterior
argocd app history tr-web
argocd app rollback tr-web <revision-anterior>
```

<br />

El principio clave es que los rollbacks deben ser automáticos, rápidos, y no requerir decisión humana.

<br />

##### **SLOs de deployment**
En el [artículo de SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help) definimos SLOs para
nuestros servicios. Ahora usamos esos mismos SLOs como gates de deployment. Si un canary viola el SLO, el
deployment se detiene.

<br />

Argo Rollouts usa AnalysisTemplates para consultar Prometheus y decidir si un deployment está saludable:

<br />

```yaml
# analysis-template.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: canary-success-rate
spec:
  args:
    - name: service-name
  metrics:
    - name: success-rate
      interval: 30s
      count: 5
      successCondition: result[0] >= 0.99
      failureLimit: 2
      provider:
        prometheus:
          address: http://prometheus.monitoring.svc:9090
          query: |
            sum(rate(
              http_requests_total{service="{{args.service-name}}", status!~"5.."}[2m]
            )) /
            sum(rate(
              http_requests_total{service="{{args.service-name}}"}[2m]
            ))
```

<br />

Este template:

<br />

> * **Consulta Prometheus** cada 30 segundos por la tasa de éxito
> * **Corre 5 mediciones** para tener suficientes datos
> * **Requiere 99% de tasa de éxito** coincidiendo con nuestro SLO
> * **Permite 2 fallas** antes de marcar el análisis como fallido

<br />

También podés gatear deployments por error budget. Si queda menos del 20% de tu error budget de 30 días,
bloqueá el deployment:

<br />

```yaml
# analysis-error-budget.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: error-budget-gate
spec:
  metrics:
    - name: error-budget-remaining
      interval: 1m
      count: 1
      successCondition: result[0] > 0.2
      provider:
        prometheus:
          address: http://prometheus.monitoring.svc:9090
          query: |
            1 - (
              (1 - (
                sum(rate(http_requests_total{service="tr-web", status!~"5.."}[30d])) /
                sum(rate(http_requests_total{service="tr-web"}[30d]))
              )) / (1 - 0.999)
            )
```

<br />

Combiná múltiples análisis en los pasos de tu rollout para validación integral:

<br />

```yaml
steps:
  - setWeight: 10
  - pause: { duration: 2m }
  - analysis:
      templates:
        - templateName: canary-success-rate
        - templateName: canary-latency
      args:
        - name: service-name
          value: tr-web-canary
```

<br />

##### **Hooks de pre y post sync**
ArgoCD soporta hooks de recursos que corren en puntos específicos durante el sync. Son perfectos para
migraciones de base de datos antes del deployment, smoke tests después, y notificaciones en varias etapas.

<br />

Hook de pre-sync para migraciones de base de datos:

<br />

```yaml
# migration-hook.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: tr-web-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: kainlite/tr:v1.2.0
          command: ["/app/bin/tr"]
          args: ["eval", "Tr.Release.migrate()"]
          envFrom:
            - secretRef:
                name: tr-web-env
      restartPolicy: Never
  backoffLimit: 3
```

<br />

Hook de post-sync para smoke tests:

<br />

```yaml
# smoke-test-hook.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: tr-web-smoke-test
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: smoke-test
          image: curlimages/curl:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://tr-web-stable/healthz)
              if [ "$STATUS" != "200" ]; then exit 1; fi
              echo "¡Smoke tests pasaron!"
      restartPolicy: Never
  backoffLimit: 1
```

<br />

Hook de notificación por fallas:

<br />

```yaml
# notification-hook.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: tr-web-notify
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: notify
          image: curlimages/curl:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              curl -X POST "${SLACK_WEBHOOK_URL}" \
                -H 'Content-Type: application/json' \
                -d '{"text": "¡Sync FALLÓ para tr-web en producción!"}'
          envFrom:
            - secretRef:
                name: slack-webhook
      restartPolicy: Never
```

<br />

Los tipos de hooks disponibles son:

<br />

> * **PreSync** corre antes del sync (migraciones, backups)
> * **Sync** corre durante el sync junto con los otros recursos
> * **PostSync** corre después de que todos los recursos están sincronizados y saludables
> * **SyncFail** corre cuando el sync falla (notificaciones de alerta)

<br />

##### **Releases manejados por GitOps**
Con GitOps, cada deployment es un commit de git. Esto te da un audit trail completo y la capacidad de usar
git revert como mecanismo de rollback.

<br />

El ArgoCD Image Updater detecta nuevas imágenes de contenedor y actualiza el repositorio de git
automáticamente:

<br />

```yaml
# Annotations del image updater en la Application de ArgoCD
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: tr=kainlite/tr
    argocd-image-updater.argoproj.io/tr.update-strategy: semver
    argocd-image-updater.argoproj.io/tr.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/git-branch: main
```

<br />

Para un flujo basado en PRs con review antes de producción, usá un GitHub Action que cree un PR de
promoción:

<br />

```yaml
# .github/workflows/promote.yaml
name: Promover a Producción
on:
  workflow_run:
    workflows: ["Build and Push"]
    types: [completed]
    branches: [main]

jobs:
  promote:
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    steps:
      - uses: actions/checkout@v4
        with:
          repository: kainlite/tr-infra
          token: ${{ secrets.INFRA_REPO_TOKEN }}

      - name: Actualizar tag de imagen
        run: |
          cd k8s/overlays/production
          kustomize edit set image \
            kainlite/tr=kainlite/tr:${{ github.event.workflow_run.head_sha }}

      - name: Crear PR
        uses: peter-evans/create-pull-request@v6
        with:
          commit-message: "chore: bump tr-web a ${{ github.event.workflow_run.head_sha }}"
          title: "Deploy tr-web ${{ github.event.workflow_run.head_sha }}"
          branch: deploy/tr-web-${{ github.event.workflow_run.head_sha }}
          base: main
```

<br />

Usá overlays de Kustomize para promoción entre ambientes:

<br />

```yaml
# k8s/overlays/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: kainlite/tr
    newTag: abc123-staging
namespace: staging

# k8s/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: kainlite/tr
    newTag: v1.2.0
namespace: default
```

<br />

El workflow completo:

<br />

> 1. **El developer pushea código** al repo de la aplicación
> 2. **CI buildea y testea**, pushea una imagen de contenedor
> 3. **El image updater** detecta la nueva imagen y actualiza staging
> 4. **Los tests de staging pasan** incluyendo análisis canary
> 5. **Se crea un PR** para promover a producción
> 6. **El equipo revisa y mergea** el PR
> 7. **ArgoCD sincroniza** con la estrategia de Argo Rollout
> 8. **El análisis canary** valida contra los SLOs
> 9. **El rollout completo** se completa si todo está saludable

<br />

Cada paso es rastreable a través de git. Si algo sale mal, hacés `git revert` del PR de promoción y ArgoCD
hace rollback.

<br />

##### **Cadencia de releases y freezes**
Las herramientas copadas son importantes, pero también necesitás políticas sobre cuándo deployar. ArgoCD
soporta sync windows:

<br />

```yaml
# argocd-project.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  syncWindows:
    # Permitir syncs lunes a jueves, 9am a 4pm UTC
    - kind: allow
      schedule: "0 9 * * 1-4"
      duration: 7h
      applications: ["*"]

    # Nada de deploys viernes a la tarde
    - kind: deny
      schedule: "0 14 * * 5"
      duration: 10h
      applications: ["*"]

    # Freeze de fin de año (20 dic al 1 ene)
    - kind: deny
      schedule: "0 0 20 12 *"
      duration: 288h
      applications: ["*"]

    # Siempre permitir syncs manuales para emergencias
    - kind: allow
      schedule: "* * * * *"
      duration: 24h
      applications: ["*"]
      manualSync: true
```

<br />

Guías prácticas:

<br />

> * **Deployá seguido, deployá chico**: cambios más pequeños son más fáciles de debuggear
> * **Nada de deploys viernes a la tarde**: a menos que disfrutes los pages de fin de semana
> * **Freezes de feriados**: planeálos con anticipación, comunicalos claramente
> * **Excepciones de emergencia**: siempre tené un proceso para hotfixes críticos
> * **Ventanas de deploy**: deployá solo cuando haya alguien para mirar

<br />

También podés forzar esto en CI:

<br />

```bash
# check-deploy-window.sh
#!/bin/bash
set -euo pipefail

HOUR=$(date -u +%H)
DAY=$(date -u +%u)  # 1=Lunes, 7=Domingo

if [ "$DAY" -ge 6 ]; then
  echo "Deploy bloqueado: no se deploya en fin de semana"; exit 1
fi

if [ "$DAY" -eq 5 ] && [ "$HOUR" -ge 14 ]; then
  echo "Deploy bloqueado: no se deploya viernes a la tarde"; exit 1
fi

if [ "$HOUR" -lt 9 ] || [ "$HOUR" -ge 16 ]; then
  echo "Deploy bloqueado: fuera de ventana (09:00-16:00 UTC)"; exit 1
fi

echo "Ventana de deploy abierta, continuando..."
```

<br />

El balance es entre seguridad y velocidad. Demasiadas restricciones y tu equipo deja de deployar, lo que
en realidad hace los deployments más riesgosos porque cada uno contiene más cambios.

<br />

##### **Notas finales**
La ingeniería de releases se trata de hacer que los deployments sean aburridos. Cuando tenés canary
deployments que validan contra tus SLOs, estrategias blue-green con rollback instantáneo, feature flags
para desacoplar deployment de release, y pipelines de GitOps con audit trail completo, los deployments
se convierten en operaciones rutinarias en vez de eventos que dan miedo.

<br />

Empezá con una pieza, tal vez canary deployments con un análisis simple de tasa de error, y construí desde
ahí. El objetivo no es cero deployments, es cero incidentes causados por deployments. Shippeá rápido,
shippeá seguro, y dejá que la automatización atrape los problemas antes de que tus usuarios lo hagan.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
