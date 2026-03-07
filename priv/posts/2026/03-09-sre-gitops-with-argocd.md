%{
  title: "SRE: GitOps with ArgoCD",
  author: "Gabriel Garrido",
  description: "We will explore GitOps principles with ArgoCD, from Application CRDs and App of Apps patterns to sync strategies, multi-cluster management with ApplicationSets, and monitoring your GitOps workflows...",
  tags: ~w(sre kubernetes argocd gitops ci-cd),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Throughout this SRE series we have covered [SLIs and SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[incident management](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observability](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose), and
[capacity planning](/blog/sre-capacity-planning-autoscaling-and-load-testing). All of those practices assume
that when you change something, the change is tracked, reviewed, auditable, and easy to roll back. That is
exactly what GitOps gives you.

<br />

If you have been deploying to Kubernetes with `kubectl apply` or CI pipelines that push directly to the cluster,
you probably know the pain: someone applies a hotfix manually, another person runs a different version of a
manifest, and before you know it the cluster state has drifted from what is in your repository. Nobody knows
what is actually running. GitOps solves this by making Git the single source of truth and using a controller
to continuously reconcile the cluster state with what is declared in your repository.

<br />

Let's get into it.

<br />

##### **What is GitOps?**
GitOps is an operational model where the desired state of your infrastructure and applications is declared in Git.
A controller running in your cluster watches the Git repository and ensures the live state matches the declared
state. If something drifts, the controller corrects it automatically.

<br />

The core principles are:

<br />

> * **Declarative configuration**: Everything is described as YAML or JSON manifests in Git. No imperative scripts, no manual steps.
> * **Git as the single source of truth**: The Git repository is the only place where changes are made. What is in Git is what runs in the cluster.
> * **Pull-based reconciliation**: Instead of CI pushing to the cluster, a controller inside the cluster pulls the desired state from Git. This is more secure because the cluster credentials never leave the cluster.
> * **Continuous reconciliation**: The controller does not just apply changes once. It continuously compares the live state with the desired state and corrects any drift.

<br />

This is fundamentally different from traditional push-based CI/CD where a pipeline runs `kubectl apply` after
a build. With push-based CD, if someone changes something in the cluster manually, your CI does not know about
it. With GitOps, the controller detects the drift and fixes it.

<br />

```elixir
# Push-based CI/CD (traditional):
# Developer → Git push → CI builds → CI runs kubectl apply → Cluster
#                                     (CI needs cluster credentials)
#                                     (drift goes undetected)
#
# Pull-based GitOps:
# Developer → Git push → Controller detects change → Controller applies → Cluster
#                         (controller lives in cluster, watches Git continuously)
#                         (drift is detected and corrected automatically)
```

<br />

##### **ArgoCD architecture**
ArgoCD is the most popular GitOps controller for Kubernetes. It is a CNCF graduated project with a
well-defined architecture.

<br />

> * **API Server**: The gRPC/REST server that powers the web UI, CLI, and external integrations. Handles authentication, RBAC, and serves the application state.
> * **Repository Server**: Clones Git repositories and generates Kubernetes manifests. Supports plain YAML, Kustomize, Helm, Jsonnet, and custom plugins.
> * **Application Controller**: The brain of ArgoCD. Watches Application resources, compares desired state (from Git) with live state (from the cluster), and performs sync operations when they differ.
> * **Redis**: Caching layer for the repository server and application controller.
> * **ApplicationSet Controller**: Manages ApplicationSet resources that generate multiple Applications from a single definition.

<br />

```elixir
# ArgoCD reconciliation loop (runs every 3 minutes by default):
# 1. Application Controller reads the Application CRD
# 2. Asks Repo Server to fetch and render manifests from Git
# 3. Controller compares rendered manifests with live cluster state
# 4. If they differ:
#    - With auto-sync: Controller applies the changes
#    - Without auto-sync: Controller marks the app as OutOfSync
# 5. Controller updates Application status, loop repeats
```

<br />

##### **Installing ArgoCD**
The recommended approach is using Helm. Create the namespace and install:

<br />

```elixir
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

<br />

Here is a production-ready values file:

<br />

```elixir
# argocd-values.yaml
configs:
  params:
    server.insecure: true
    timeout.reconciliation: 180s
  cm:
    statusbadge.enabled: "true"
    kustomize.buildOptions: "--enable-helm"

server:
  replicas: 2
  ingress:
    enabled: true
    ingressClassName: nginx
    hostname: argocd.example.com
    tls: true

controller:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      memory: 1Gi

repoServer:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 512Mi
```

<br />

```elixir
helm install argocd argo/argo-cd \
  --namespace argocd \
  --values argocd-values.yaml \
  --wait

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Login and change password
argocd login argocd.example.com --username admin --password <your-password>
argocd account update-password
```

<br />

##### **Application CRDs**
The Application CRD is the fundamental building block. It defines what to deploy, where, and how to keep it
in sync:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/kainlite/my-app-manifests
    targetRevision: main
    path: overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true       # Delete resources no longer in Git
      selfHeal: true    # Revert manual changes
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas   # Ignore if HPA manages replicas
```

<br />

> * **source**: Where to find the manifests. `repoURL`, `targetRevision` (branch/tag), and `path` (directory within the repo).
> * **destination**: Where to deploy. `server` is the Kubernetes API endpoint, `namespace` is the target namespace.
> * **syncPolicy**: How to keep things in sync. `automated` enables auto-sync, `prune` deletes removed resources, `selfHeal` reverts manual changes.
> * **ignoreDifferences**: Fields to ignore when comparing desired vs. live state, useful for fields set dynamically by the cluster.

<br />

##### **The App of Apps pattern**
When you have many applications, managing each Application resource individually becomes tedious. The App of Apps
pattern creates a parent Application that manages child Application manifests.

<br />

```elixir
# Repository structure
gitops-repo/
├── apps/                          # Parent app points here
│   ├── my-app.yaml               # Child Application manifests
│   ├── monitoring.yaml
│   ├── cert-manager.yaml
│   └── ingress-nginx.yaml
├── my-app/
│   ├── base/
│   └── overlays/
│       ├── staging/
│       └── production/
└── monitoring/
```

<br />

The parent Application:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kainlite/gitops-repo
    targetRevision: main
    path: apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

<br />

Child applications use `sync-wave` annotations to control deployment order. Infrastructure components get
wave `0`, application workloads get wave `2`:

<br />

```elixir
# apps/cert-manager.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # Deploy infrastructure first
spec:
  project: default
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.16.3
    helm:
      releaseName: cert-manager
      values: |
        installCRDs: true
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

##### **Sync strategies**
ArgoCD gives you fine-grained control over how and when syncs happen. A common pattern is auto-sync for
staging and manual for production:

<br />

```elixir
# Auto-sync: changes applied automatically
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git
    selfHeal: true   # Revert manual cluster changes

# Manual sync: omit the automated section
syncPolicy:
  syncOptions:
    - CreateNamespace=true
```

<br />

Retry policies handle transient failures:

<br />

```elixir
syncPolicy:
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

<br />

Sync windows restrict when ArgoCD can sync, useful for change freezes:

<br />

```elixir
# In the AppProject spec
spec:
  syncWindows:
    - kind: allow
      schedule: "0 9 * * 1-5"   # Mon-Fri at 9am
      duration: 8h
      applications: ["*"]
    - kind: deny
      schedule: "0 0 20 12 *"   # Holiday freeze
      duration: 336h
      applications: ["*"]
      clusters: ["production"]
```

<br />

##### **Health checks and custom health**
ArgoCD has built-in health checks for standard Kubernetes resources. For custom resources (CRDs), you can
write Lua health check scripts:

<br />

> * **Healthy**: The resource is operating correctly
> * **Progressing**: Not yet healthy but making progress
> * **Degraded**: The resource has an error
> * **Suspended**: The resource is paused
> * **Missing**: The resource does not exist

<br />

```elixir
# Custom health check for cert-manager Certificate (in argocd-cm ConfigMap)
resource.customizations.health.cert-manager.io_Certificate: |
  hs = {}
  if obj.status ~= nil then
    if obj.status.conditions ~= nil then
      for i, condition in ipairs(obj.status.conditions) do
        if condition.type == "Ready" and condition.status == "False" then
          hs.status = "Degraded"
          hs.message = condition.message
          return hs
        end
        if condition.type == "Ready" and condition.status == "True" then
          hs.status = "Healthy"
          hs.message = condition.message
          return hs
        end
      end
    end
  end
  hs.status = "Progressing"
  hs.message = "Waiting for certificate"
  return hs
```

<br />

##### **Rollback patterns**
One of the biggest advantages of GitOps is that rollback is just a `git revert`. ArgoCD also provides
its own rollback mechanisms for emergencies.

<br />

```elixir
# The GitOps way: revert the commit in Git
git revert HEAD --no-edit
git push
# ArgoCD detects the change and syncs automatically

# ArgoCD history-based rollback
argocd app history my-app
argocd app rollback my-app 2
# Note: this does not revert Git, so auto-sync will eventually re-apply
# Disable auto-sync first or also revert in Git
```

<br />

##### **Multi-cluster management with ApplicationSets**
ApplicationSets generate multiple Applications from a template using generators. Instead of manually creating
an Application for each cluster, you define a template and a generator that produces the variations.

<br />

**List generator**: Provide explicit parameter sets:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: staging
            url: https://staging-api.example.com
          - cluster: production
            url: https://production-api.example.com
  template:
    metadata:
      name: "my-app-{{cluster}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/kainlite/gitops-repo
        targetRevision: main
        path: "my-app/overlays/{{cluster}}"
      destination:
        server: "{{url}}"
        namespace: my-app
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

<br />

**Cluster generator**: Automatically creates Applications for every matching cluster:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: monitoring-stack
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: production
  template:
    metadata:
      name: "monitoring-{{name}}"
    spec:
      project: monitoring
      source:
        repoURL: https://github.com/kainlite/gitops-repo
        targetRevision: main
        path: monitoring
      destination:
        server: "{{server}}"
        namespace: monitoring
```

<br />

**Git generator**: Creates Applications based on directory structure or config files:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: team-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/kainlite/gitops-repo
        revision: main
        directories:
          - path: "teams/*/apps/*"
  template:
    metadata:
      name: "{{path.basename}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/kainlite/gitops-repo
        targetRevision: main
        path: "{{path}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{path.basename}}"
```

<br />

##### **Kustomize and Helm integration**
ArgoCD natively supports both Kustomize and Helm. It renders manifests at sync time, so you do not need
to run these tools in your CI pipeline.

<br />

For Kustomize, just point the Application source to the overlay directory:

<br />

```elixir
# overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: Deployment
      name: my-app
    patch: |
      - op: replace
        path: /spec/replicas
        value: 3
images:
  - name: kainlite/my-app
    newTag: v1.2.3
```

<br />

For Helm charts from a chart repository:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: argocd
spec:
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 67.9.0
    helm:
      releaseName: prometheus
      values: |
        prometheus:
          prometheusSpec:
            retention: 30d
            storageSpec:
              volumeClaimTemplate:
                spec:
                  resources:
                    requests:
                      storage: 50Gi
        grafana:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    syncOptions:
      - ServerSideApply=true
```

<br />

##### **RBAC and SSO**
Projects are the primary mechanism for restricting access. Each project defines which repositories,
clusters, and namespaces an application can use:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: payments-team
  namespace: argocd
spec:
  description: "Payments team project"
  sourceRepos:
    - "https://github.com/kainlite/payments-*"
  destinations:
    - server: https://kubernetes.default.svc
      namespace: "payments-*"
  namespaceResourceWhitelist:
    - group: "apps"
      kind: Deployment
    - group: ""
      kind: Service
    - group: ""
      kind: ConfigMap
    - group: ""
      kind: Secret
  roles:
    - name: developer
      policies:
        - p, proj:payments-team:developer, applications, get, payments-team/*, allow
        - p, proj:payments-team:developer, applications, sync, payments-team/*, allow
      groups:
        - payments-developers
    - name: admin
      policies:
        - p, proj:payments-team:admin, applications, *, payments-team/*, allow
      groups:
        - payments-admins
```

<br />

SSO with OIDC:

<br />

```elixir
# In argocd-cm ConfigMap
oidc.config: |
  name: Keycloak
  issuer: https://keycloak.example.com/realms/engineering
  clientID: argocd
  clientSecret: $oidc.keycloak.clientSecret
  requestedScopes: ["openid", "profile", "email", "groups"]

# In argocd-rbac-cm ConfigMap
policy.default: role:readonly
policy.csv: |
  g, platform-admins, role:admin
  g, payments-developers, proj:payments-team:developer
  p, role:readonly, applications, get, */*, allow
```

<br />

##### **Notifications**
ArgoCD Notifications sends alerts on sync events. It is included in the Helm chart since ArgoCD 2.6+:

<br />

```elixir
# argocd-notifications-cm ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token

  template.app-sync-succeeded: |
    slack:
      attachments: |
        [{"color": "#18be52", "title": "{{.app.metadata.name}} synced successfully",
          "fields": [
            {"title": "Revision", "value": "{{.app.status.sync.revision}}", "short": true},
            {"title": "Namespace", "value": "{{.app.spec.destination.namespace}}", "short": true}
          ]}]

  template.app-sync-failed: |
    slack:
      attachments: |
        [{"color": "#E96D76", "title": "{{.app.metadata.name}} sync FAILED",
          "fields": [
            {"title": "Error", "value": "{{range .app.status.conditions}}{{.message}}{{end}}"}
          ]}]

  trigger.on-sync-succeeded: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [app-sync-succeeded]
  trigger.on-sync-failed: |
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [app-sync-failed]
```

<br />

Subscribe applications to notifications with annotations:

<br />

```elixir
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: deployments
    notifications.argoproj.io/subscribe.on-sync-failed.slack: deployments-alerts
```

<br />

##### **Monitoring ArgoCD itself**
ArgoCD exposes Prometheus metrics out of the box. Here are the key metrics to watch:

<br />

> * **argocd_app_info**: Gauge with sync status and health per application
> * **argocd_app_sync_total**: Counter of sync operations (track deployment frequency)
> * **argocd_app_reconcile_bucket**: Histogram of reconciliation duration
> * **argocd_git_request_total**: Counter of Git requests (failures mean ArgoCD cannot reach your repos)
> * **argocd_cluster_api_resource_objects**: Gauge of tracked objects per cluster (memory planning)

<br />

```elixir
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: argocd-alerts
  namespace: monitoring
spec:
  groups:
    - name: argocd.rules
      rules:
        - alert: ArgoCDAppOutOfSync
          expr: argocd_app_info{sync_status="OutOfSync"} == 1
          for: 30m
          labels:
            severity: warning
          annotations:
            summary: "ArgoCD app {{ $labels.name }} out of sync for 30m+"

        - alert: ArgoCDAppUnhealthy
          expr: argocd_app_info{health_status!~"Healthy|Progressing"} == 1
          for: 15m
          labels:
            severity: critical
          annotations:
            summary: "ArgoCD app {{ $labels.name }} is {{ $labels.health_status }}"

        - alert: ArgoCDSyncFailing
          expr: increase(argocd_app_sync_total{phase!="Succeeded"}[1h]) > 3
          labels:
            severity: critical
          annotations:
            summary: "More than 3 failed syncs in 1h for {{ $labels.name }}"

        - alert: ArgoCDGitFetchErrors
          expr: increase(argocd_git_request_total{request_type="fetch", result="error"}[10m]) > 5
          labels:
            severity: warning
          annotations:
            summary: "ArgoCD cannot fetch from Git repositories"
```

<br />

Make sure Prometheus scrapes ArgoCD metrics:

<br />

```elixir
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: argocd
  namespaceSelector:
    matchNames: [argocd]
  endpoints:
    - port: metrics
      interval: 30s
```

<br />

##### **Closing notes**
GitOps with ArgoCD gives you a deployment workflow that is auditable, repeatable, and self-healing. By
treating Git as the single source of truth and letting a controller handle reconciliation, you eliminate
an entire class of problems related to configuration drift and manual deployments. The combination of
Application CRDs, the App of Apps pattern, ApplicationSets, and proper RBAC gives you a solid foundation
for managing anything from a single cluster to a fleet of clusters across multiple environments.

<br />

This article continues the SRE series where we have been building up the practices and tools needed to run
reliable systems. GitOps is the glue that ties everything together, because all the SLO definitions,
monitoring configurations, and infrastructure changes we covered in previous articles should flow through
Git and be reconciled by ArgoCD.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: GitOps con ArgoCD",
  author: "Gabriel Garrido",
  description: "Vamos a explorar los principios de GitOps con ArgoCD, desde Application CRDs y patrones App of Apps hasta estrategias de sincronización, gestión multi-cluster con ApplicationSets, y monitoreo de tus flujos GitOps...",
  tags: ~w(sre kubernetes argocd gitops ci-cd),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
A lo largo de esta serie de SRE cubrimos [SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[gestión de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observabilidad](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[ingeniería del caos](/blog/sre-chaos-engineering-breaking-things-on-purpose) y
[planificación de capacidad](/blog/sre-capacity-planning-autoscaling-and-load-testing). Todas esas prácticas
asumen que cuando cambiás algo, el cambio queda registrado, revisado, auditable y es fácil de revertir. Eso
es exactamente lo que te da GitOps.

<br />

Si venís desplegando en Kubernetes con `kubectl apply` o pipelines de CI que pushean directo al cluster,
probablemente conocés el dolor: alguien aplica un hotfix manual, otra persona ejecuta una versión diferente
de un manifiesto, y antes de que te des cuenta el estado del cluster se desfasó de lo que hay en tu
repositorio. Nadie sabe qué es lo que realmente está corriendo. GitOps resuelve esto haciendo de Git la
única fuente de verdad y usando un controlador para reconciliar continuamente el estado del cluster con
lo que está declarado en tu repositorio.

<br />

Vamos al tema.

<br />

##### **¿Qué es GitOps?**
GitOps es un modelo operativo donde el estado deseado de tu infraestructura y aplicaciones se declara en Git.
Un controlador corriendo en tu cluster observa el repositorio Git y se asegura de que el estado vivo coincida
con el estado declarado. Si algo se desfasa, el controlador lo corrige automáticamente.

<br />

Los principios centrales son:

<br />

> * **Configuración declarativa**: Todo se describe como manifiestos YAML o JSON en Git. Sin scripts imperativos, sin pasos manuales.
> * **Git como la única fuente de verdad**: El repositorio Git es el único lugar donde se hacen cambios. Lo que está en Git es lo que corre en el cluster.
> * **Reconciliación basada en pull**: En vez de que el CI pushee al cluster, un controlador dentro del cluster pullea el estado deseado desde Git. Esto es más seguro porque las credenciales del cluster nunca salen del cluster.
> * **Reconciliación continua**: El controlador no solo aplica cambios una vez. Compara continuamente el estado vivo con el estado deseado y corrige cualquier desfase.

<br />

Esto es fundamentalmente diferente al CI/CD tradicional basado en push donde un pipeline ejecuta
`kubectl apply` después de un build. Con CD basado en push, si alguien cambia algo en el cluster
manualmente, tu CI no se entera. Con GitOps, el controlador detecta el desfase y lo corrige.

<br />

```elixir
# CI/CD basado en push (tradicional):
# Desarrollador → Git push → CI construye → CI ejecuta kubectl apply → Cluster
#                                            (CI necesita credenciales del cluster)
#                                            (el desfase no se detecta)
#
# GitOps basado en pull:
# Desarrollador → Git push → Controlador detecta cambio → Controlador aplica → Cluster
#                             (el controlador vive en el cluster, observa Git continuamente)
#                             (el desfase se detecta y corrige automáticamente)
```

<br />

##### **Arquitectura de ArgoCD**
ArgoCD es el controlador GitOps más popular para Kubernetes. Es un proyecto graduado de la CNCF con una
arquitectura bien definida.

<br />

> * **API Server**: El servidor gRPC/REST que alimenta la interfaz web, la CLI y las integraciones externas. Maneja autenticación, RBAC y sirve el estado de las aplicaciones.
> * **Repository Server**: Clona repositorios Git y genera manifiestos de Kubernetes. Soporta YAML plano, Kustomize, Helm, Jsonnet y plugins personalizados.
> * **Application Controller**: El cerebro de ArgoCD. Observa los recursos Application, compara el estado deseado (de Git) con el estado vivo (del cluster) y ejecuta operaciones de sync cuando difieren.
> * **Redis**: Capa de caché para el repository server y el application controller.
> * **ApplicationSet Controller**: Gestiona los recursos ApplicationSet que generan múltiples Applications a partir de una sola definición.

<br />

```elixir
# Loop de reconciliación de ArgoCD (corre cada 3 minutos por defecto):
# 1. El Application Controller lee el CRD Application
# 2. Le pide al Repo Server que obtenga y renderice manifiestos desde Git
# 3. El Controller compara los manifiestos renderizados con el estado vivo del cluster
# 4. Si difieren:
#    - Con auto-sync: el Controller aplica los cambios
#    - Sin auto-sync: el Controller marca la app como OutOfSync
# 5. El Controller actualiza el estado del Application, el loop se repite
```

<br />

##### **Instalando ArgoCD**
El enfoque recomendado es usando Helm. Creá el namespace e instalá:

<br />

```elixir
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

<br />

Acá hay un archivo de valores listo para producción:

<br />

```elixir
# argocd-values.yaml
configs:
  params:
    server.insecure: true
    timeout.reconciliation: 180s
  cm:
    statusbadge.enabled: "true"
    kustomize.buildOptions: "--enable-helm"

server:
  replicas: 2
  ingress:
    enabled: true
    ingressClassName: nginx
    hostname: argocd.example.com
    tls: true

controller:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      memory: 1Gi

repoServer:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 512Mi
```

<br />

```elixir
helm install argocd argo/argo-cd \
  --namespace argocd \
  --values argocd-values.yaml \
  --wait

# Obtener la contraseña inicial de admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Login y cambiar contraseña
argocd login argocd.example.com --username admin --password <tu-contraseña>
argocd account update-password
```

<br />

##### **Application CRDs**
El CRD Application es el bloque fundamental. Define qué desplegar, dónde y cómo mantenerlo sincronizado:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/kainlite/my-app-manifests
    targetRevision: main
    path: overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true       # Borrar recursos que ya no están en Git
      selfHeal: true    # Revertir cambios manuales
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas   # Ignorar si el HPA gestiona las réplicas
```

<br />

> * **source**: De dónde obtener los manifiestos. `repoURL`, `targetRevision` (rama/tag) y `path` (directorio dentro del repo).
> * **destination**: Dónde desplegar. `server` es el endpoint de la API de Kubernetes, `namespace` es el namespace destino.
> * **syncPolicy**: Cómo mantener las cosas sincronizadas. `automated` habilita auto-sync, `prune` borra recursos eliminados, `selfHeal` revierte cambios manuales.
> * **ignoreDifferences**: Campos a ignorar al comparar estado deseado vs. vivo, útil para campos seteados dinámicamente por el cluster.

<br />

##### **El patrón App of Apps**
Cuando tenés muchas aplicaciones, gestionar cada recurso Application individualmente se vuelve tedioso. El
patrón App of Apps crea un Application padre que gestiona manifiestos de Applications hijo.

<br />

```elixir
# Estructura del repositorio
gitops-repo/
├── apps/                          # El app padre apunta acá
│   ├── my-app.yaml               # Manifiestos Application hijo
│   ├── monitoring.yaml
│   ├── cert-manager.yaml
│   └── ingress-nginx.yaml
├── my-app/
│   ├── base/
│   └── overlays/
│       ├── staging/
│       └── production/
└── monitoring/
```

<br />

El Application padre:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kainlite/gitops-repo
    targetRevision: main
    path: apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

<br />

Las aplicaciones hijo usan anotaciones `sync-wave` para controlar el orden de despliegue. Componentes de
infraestructura tienen wave `0`, cargas de trabajo de aplicación tienen wave `2`:

<br />

```elixir
# apps/cert-manager.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # Desplegar infraestructura primero
spec:
  project: default
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.16.3
    helm:
      releaseName: cert-manager
      values: |
        installCRDs: true
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

##### **Estrategias de sincronización**
ArgoCD te da control granular sobre cómo y cuándo ocurren los syncs. Un patrón común es auto-sync para
staging y manual para producción:

<br />

```elixir
# Auto-sync: los cambios se aplican automáticamente
syncPolicy:
  automated:
    prune: true      # Borrar recursos removidos de Git
    selfHeal: true   # Revertir cambios manuales en el cluster

# Sync manual: omitir la sección automated
syncPolicy:
  syncOptions:
    - CreateNamespace=true
```

<br />

Las políticas de reintento manejan fallos transitorios:

<br />

```elixir
syncPolicy:
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

<br />

Las ventanas de sync restringen cuándo ArgoCD puede sincronizar, útil para congelamientos de cambios:

<br />

```elixir
# En el spec del AppProject
spec:
  syncWindows:
    - kind: allow
      schedule: "0 9 * * 1-5"   # Lun-Vie a las 9am
      duration: 8h
      applications: ["*"]
    - kind: deny
      schedule: "0 0 20 12 *"   # Congelamiento de fiestas
      duration: 336h
      applications: ["*"]
      clusters: ["production"]
```

<br />

##### **Health checks y health personalizado**
ArgoCD tiene health checks integrados para recursos estándar de Kubernetes. Para recursos custom (CRDs),
podés escribir scripts de health check en Lua:

<br />

> * **Healthy**: El recurso está operando correctamente
> * **Progressing**: Todavía no está saludable pero está progresando
> * **Degraded**: El recurso tiene un error
> * **Suspended**: El recurso está pausado
> * **Missing**: El recurso no existe

<br />

```elixir
# Health check personalizado para Certificate de cert-manager (en ConfigMap argocd-cm)
resource.customizations.health.cert-manager.io_Certificate: |
  hs = {}
  if obj.status ~= nil then
    if obj.status.conditions ~= nil then
      for i, condition in ipairs(obj.status.conditions) do
        if condition.type == "Ready" and condition.status == "False" then
          hs.status = "Degraded"
          hs.message = condition.message
          return hs
        end
        if condition.type == "Ready" and condition.status == "True" then
          hs.status = "Healthy"
          hs.message = condition.message
          return hs
        end
      end
    end
  end
  hs.status = "Progressing"
  hs.message = "Waiting for certificate"
  return hs
```

<br />

##### **Patrones de rollback**
Una de las mayores ventajas de GitOps es que el rollback es simplemente un `git revert`. ArgoCD también
provee sus propios mecanismos de rollback para emergencias.

<br />

```elixir
# La forma GitOps: revertir el commit en Git
git revert HEAD --no-edit
git push
# ArgoCD detecta el cambio y sincroniza automáticamente

# Rollback basado en historial de ArgoCD
argocd app history my-app
argocd app rollback my-app 2
# Nota: esto no revierte Git, así que auto-sync eventualmente va a re-aplicar
# Deshabilitá auto-sync primero o también revertí en Git
```

<br />

##### **Gestión multi-cluster con ApplicationSets**
Los ApplicationSets generan múltiples Applications a partir de un template usando generadores. En vez de
crear manualmente un Application para cada cluster, definís un template y un generador que produce las
variaciones.

<br />

**Generador list**: Proveé conjuntos de parámetros explícitos:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: staging
            url: https://staging-api.example.com
          - cluster: production
            url: https://production-api.example.com
  template:
    metadata:
      name: "my-app-{{cluster}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/kainlite/gitops-repo
        targetRevision: main
        path: "my-app/overlays/{{cluster}}"
      destination:
        server: "{{url}}"
        namespace: my-app
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

<br />

**Generador cluster**: Crea Applications automáticamente para cada cluster que matchea:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: monitoring-stack
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: production
  template:
    metadata:
      name: "monitoring-{{name}}"
    spec:
      project: monitoring
      source:
        repoURL: https://github.com/kainlite/gitops-repo
        targetRevision: main
        path: monitoring
      destination:
        server: "{{server}}"
        namespace: monitoring
```

<br />

**Generador git**: Crea Applications basándose en la estructura de directorios o archivos de config:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: team-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/kainlite/gitops-repo
        revision: main
        directories:
          - path: "teams/*/apps/*"
  template:
    metadata:
      name: "{{path.basename}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/kainlite/gitops-repo
        targetRevision: main
        path: "{{path}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{path.basename}}"
```

<br />

##### **Integración con Kustomize y Helm**
ArgoCD soporta nativamente tanto Kustomize como Helm. Renderiza los manifiestos en el momento del sync,
así que no necesitás correr estas herramientas en tu pipeline de CI.

<br />

Para Kustomize, simplemente apuntá el source del Application al directorio del overlay:

<br />

```elixir
# overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: Deployment
      name: my-app
    patch: |
      - op: replace
        path: /spec/replicas
        value: 3
images:
  - name: kainlite/my-app
    newTag: v1.2.3
```

<br />

Para charts de Helm desde un repositorio de charts:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: argocd
spec:
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 67.9.0
    helm:
      releaseName: prometheus
      values: |
        prometheus:
          prometheusSpec:
            retention: 30d
            storageSpec:
              volumeClaimTemplate:
                spec:
                  resources:
                    requests:
                      storage: 50Gi
        grafana:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    syncOptions:
      - ServerSideApply=true
```

<br />

##### **RBAC y SSO**
Los proyectos son el mecanismo principal para restringir acceso. Cada proyecto define qué repositorios,
clusters y namespaces puede usar una aplicación:

<br />

```elixir
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: payments-team
  namespace: argocd
spec:
  description: "Proyecto del equipo de pagos"
  sourceRepos:
    - "https://github.com/kainlite/payments-*"
  destinations:
    - server: https://kubernetes.default.svc
      namespace: "payments-*"
  namespaceResourceWhitelist:
    - group: "apps"
      kind: Deployment
    - group: ""
      kind: Service
    - group: ""
      kind: ConfigMap
    - group: ""
      kind: Secret
  roles:
    - name: developer
      policies:
        - p, proj:payments-team:developer, applications, get, payments-team/*, allow
        - p, proj:payments-team:developer, applications, sync, payments-team/*, allow
      groups:
        - payments-developers
    - name: admin
      policies:
        - p, proj:payments-team:admin, applications, *, payments-team/*, allow
      groups:
        - payments-admins
```

<br />

SSO con OIDC:

<br />

```elixir
# En el ConfigMap argocd-cm
oidc.config: |
  name: Keycloak
  issuer: https://keycloak.example.com/realms/engineering
  clientID: argocd
  clientSecret: $oidc.keycloak.clientSecret
  requestedScopes: ["openid", "profile", "email", "groups"]

# En el ConfigMap argocd-rbac-cm
policy.default: role:readonly
policy.csv: |
  g, platform-admins, role:admin
  g, payments-developers, proj:payments-team:developer
  p, role:readonly, applications, get, */*, allow
```

<br />

##### **Notificaciones**
ArgoCD Notifications envía alertas cuando ocurren eventos de sync. Viene incluido en el chart de Helm
desde ArgoCD 2.6+:

<br />

```elixir
# ConfigMap argocd-notifications-cm
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token

  template.app-sync-succeeded: |
    slack:
      attachments: |
        [{"color": "#18be52", "title": "{{.app.metadata.name}} se sincronizó exitosamente",
          "fields": [
            {"title": "Revisión", "value": "{{.app.status.sync.revision}}", "short": true},
            {"title": "Namespace", "value": "{{.app.spec.destination.namespace}}", "short": true}
          ]}]

  template.app-sync-failed: |
    slack:
      attachments: |
        [{"color": "#E96D76", "title": "{{.app.metadata.name}} sync FALLÓ",
          "fields": [
            {"title": "Error", "value": "{{range .app.status.conditions}}{{.message}}{{end}}"}
          ]}]

  trigger.on-sync-succeeded: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [app-sync-succeeded]
  trigger.on-sync-failed: |
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [app-sync-failed]
```

<br />

Suscribí aplicaciones a notificaciones con anotaciones:

<br />

```elixir
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: deployments
    notifications.argoproj.io/subscribe.on-sync-failed.slack: deployments-alerts
```

<br />

##### **Monitoreando ArgoCD en sí mismo**
ArgoCD expone métricas de Prometheus listas para usar. Acá están las métricas clave para observar:

<br />

> * **argocd_app_info**: Gauge con estado de sync y health por aplicación
> * **argocd_app_sync_total**: Counter de operaciones de sync (rastreá la frecuencia de despliegues)
> * **argocd_app_reconcile_bucket**: Histograma de duración de reconciliación
> * **argocd_git_request_total**: Counter de requests Git (fallos significan que ArgoCD no puede llegar a tus repos)
> * **argocd_cluster_api_resource_objects**: Gauge de objetos rastreados por cluster (planificación de memoria)

<br />

```elixir
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: argocd-alerts
  namespace: monitoring
spec:
  groups:
    - name: argocd.rules
      rules:
        - alert: ArgoCDAppOutOfSync
          expr: argocd_app_info{sync_status="OutOfSync"} == 1
          for: 30m
          labels:
            severity: warning
          annotations:
            summary: "La app de ArgoCD {{ $labels.name }} fuera de sync por 30m+"

        - alert: ArgoCDAppUnhealthy
          expr: argocd_app_info{health_status!~"Healthy|Progressing"} == 1
          for: 15m
          labels:
            severity: critical
          annotations:
            summary: "La app de ArgoCD {{ $labels.name }} está {{ $labels.health_status }}"

        - alert: ArgoCDSyncFailing
          expr: increase(argocd_app_sync_total{phase!="Succeeded"}[1h]) > 3
          labels:
            severity: critical
          annotations:
            summary: "Más de 3 syncs fallidos en 1h para {{ $labels.name }}"

        - alert: ArgoCDGitFetchErrors
          expr: increase(argocd_git_request_total{request_type="fetch", result="error"}[10m]) > 5
          labels:
            severity: warning
          annotations:
            summary: "ArgoCD no puede fetchear de los repositorios Git"
```

<br />

Asegurate de que Prometheus scrapee las métricas de ArgoCD:

<br />

```elixir
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: argocd
  namespaceSelector:
    matchNames: [argocd]
  endpoints:
    - port: metrics
      interval: 30s
```

<br />

##### **Notas finales**
GitOps con ArgoCD te da un flujo de trabajo de despliegue que es auditable, repetible y se auto-repara. Al
tratar a Git como la única fuente de verdad y dejar que un controlador maneje la reconciliación, eliminás
toda una clase de problemas relacionados con el drift de configuración y los despliegues manuales. La
combinación de Application CRDs, el patrón App of Apps, ApplicationSets y RBAC apropiado te da una base
sólida para gestionar desde un solo cluster hasta una flota de clusters a través de múltiples entornos.

<br />

Este artículo continúa la serie de SRE donde venimos construyendo las prácticas y herramientas necesarias
para correr sistemas confiables. GitOps es el pegamento que une todo, porque todas las definiciones de SLO,
configuraciones de monitoreo y cambios de infraestructura que cubrimos en artículos anteriores deberían
fluir a través de Git y ser reconciliados por ArgoCD.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
