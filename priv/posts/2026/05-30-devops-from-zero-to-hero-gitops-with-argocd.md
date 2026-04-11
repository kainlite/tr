%{
  title: "DevOps from Zero to Hero: GitOps with ArgoCD",
  author: "Gabriel Garrido",
  description: "We will learn what GitOps is, why it matters, and how to use ArgoCD to deploy applications to Kubernetes using Git as the single source of truth...",
  tags: ~w(devops kubernetes argocd gitops beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article fourteen of the DevOps from Zero to Hero series. In the previous article we learned
how to deploy our TypeScript API to an EKS cluster. We ran `kubectl apply` and `helm install` commands
to get things running, and that works fine when you are the only person deploying to a single cluster.
But what happens when your team grows, when you have multiple environments, or when someone applies a
quick fix directly in the cluster and forgets to update the YAML files in Git?

<br />

That is where GitOps comes in. GitOps is a way of managing your Kubernetes deployments where Git is
the single source of truth. Instead of running commands against the cluster, you push changes to a Git
repository and a controller inside the cluster picks them up and applies them automatically. No more
wondering what is running where. No more manual drift. Everything is tracked, reviewed, and
reproducible.

<br />

ArgoCD is the most popular GitOps tool for Kubernetes. It is a CNCF graduated project with an
excellent web UI, a powerful CLI, and native support for Helm, Kustomize, and plain YAML. In this
article we will install ArgoCD on our EKS cluster, deploy our TypeScript API through it, and learn how
the whole sync and reconciliation loop works.

<br />

If you are already comfortable with GitOps and want to learn about advanced patterns like
ApplicationSets, App of Apps, sync waves, multi-cluster management, RBAC, and notifications, check out
[GitOps with ArgoCD](/blog/sre-gitops-with-argocd) from the SRE series. This article stays
beginner-friendly and focuses on getting you from zero to a working GitOps setup.

<br />

Let's get into it.

<br />

##### **What is GitOps?**
GitOps is an operational model for Kubernetes where you declare what you want running in your cluster
in a Git repository, and a controller running inside the cluster continuously makes sure the real state
matches the declared state. If someone changes something manually or if a pod crashes and gets
recreated with different settings, the controller detects the drift and fixes it.

<br />

This is different from the traditional CI/CD approach where a pipeline runs `kubectl apply` or
`helm upgrade` at the end of a build. With that push-based model, the CI system needs credentials to
your cluster, drift goes undetected, and there is no easy way to know exactly what is running right
now. With GitOps, the flow is reversed: the controller lives inside the cluster, pulls the desired
state from Git, and handles the apply step itself.

<br />

```bash
# Traditional push-based CI/CD:
# Developer -> Git push -> CI builds -> CI runs kubectl apply -> Cluster
#                                       (CI needs cluster credentials)
#                                       (manual changes go undetected)

# Pull-based GitOps:
# Developer -> Git push -> Controller detects change -> Controller applies -> Cluster
#                          (controller lives in the cluster)
#                          (drift is detected and corrected automatically)
```

<br />

##### **GitOps principles**
There are four core principles that define a GitOps workflow:

<br />

> * **Declarative**: Your entire system is described as YAML or JSON files in Git. No imperative scripts, no manual steps, no one-off commands. You declare what you want, not how to get there.
> * **Versioned and immutable**: Every change goes through Git, which means every change is versioned, has an author, has a timestamp, and can be reviewed in a pull request. You get a full audit trail for free.
> * **Pulled automatically**: A controller running in your cluster watches the Git repository and pulls changes as they appear. You do not push to the cluster. This is more secure because cluster credentials never leave the cluster.
> * **Continuously reconciled**: The controller does not apply changes once and forget about them. It runs a loop that constantly compares the live state with the desired state. If they differ for any reason, it corrects the drift.

<br />

The big win here is that Git becomes the single source of truth. If you want to know what is running
in your cluster, look at Git. If you want to roll back, revert a commit. If you want to audit who
changed what and when, check the Git history. Everything flows through the same process: commit, push,
review, merge, and the controller takes care of the rest.

<br />

##### **Why ArgoCD**
There are several GitOps tools out there (Flux is another popular one), but ArgoCD has become the
go-to choice for most teams. Here is why:

<br />

> * **CNCF graduated**: ArgoCD is a graduated project in the Cloud Native Computing Foundation, which means it has passed rigorous security audits and has a large, active community.
> * **Great web UI**: ArgoCD ships with a dashboard where you can see every application, its sync status, health status, and the resource tree. This is incredibly helpful for debugging and for giving visibility to the whole team.
> * **Kubernetes-native**: ArgoCD uses Custom Resource Definitions (CRDs) to define applications. You manage ArgoCD itself with the same tools you use for everything else in Kubernetes.
> * **Multi-format support**: ArgoCD works with plain YAML manifests, Helm charts, Kustomize overlays, Jsonnet, and custom plugins. You do not have to change how you write your manifests.
> * **CLI and API**: Beyond the UI, ArgoCD has a full CLI and a gRPC/REST API for automation and scripting.

<br />

##### **Installing ArgoCD on EKS**
We are going to install ArgoCD on the EKS cluster we set up in the previous article. The recommended
way is using Helm. First, add the Argo Helm repository and create the namespace:

<br />

```bash
# Add the ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Create the argocd namespace
kubectl create namespace argocd
```

<br />

Now create a values file to configure the installation. We will keep it simple for now:

<br />

```yaml
# argocd-values.yaml
configs:
  params:
    # If you are terminating TLS at the load balancer or ingress,
    # set this so ArgoCD does not try to handle TLS itself
    server.insecure: true

server:
  service:
    type: LoadBalancer
```

<br />

This is a minimal configuration. We set `server.insecure: true` because in a typical EKS setup you
terminate TLS at the load balancer or ingress controller level. We also set the service type to
LoadBalancer so you can access the UI from your browser.

<br />

Install ArgoCD with Helm:

<br />

```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --values argocd-values.yaml \
  --wait

# Check that all pods are running
kubectl get pods -n argocd
```

<br />

You should see something like this:

<br />

```plaintext
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          2m
argocd-repo-server-6b7f8d7b4-x9k2l                 1/1     Running   0          2m
argocd-server-7c4f8b6d9-m3n8p                       1/1     Running   0          2m
argocd-redis-5b6c7d8e9-q4r7s                        1/1     Running   0          2m
argocd-applicationset-controller-8f9a1b2c3-t5u6v    1/1     Running   0          2m
argocd-notifications-controller-4d5e6f7a8-w9x0y     1/1     Running   0          2m
```

<br />

Now get the initial admin password and the load balancer URL:

<br />

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
# Save this password, you will need it to log in

# Get the load balancer URL
kubectl -n argocd get svc argocd-server \
  -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
```

<br />

Open that URL in your browser and log in with username `admin` and the password you just retrieved.
You should see the ArgoCD dashboard with no applications yet. We will create one shortly.

<br />

You can also install the ArgoCD CLI for managing things from the terminal:

<br />

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Log in to your ArgoCD instance
argocd login <load-balancer-url> --username admin --password <your-password> --insecure
```

<br />

Once logged in, change the default password:

<br />

```bash
argocd account update-password
```

<br />

##### **ArgoCD concepts**
Before we create our first application, let's understand the key concepts. ArgoCD has a handful of
building blocks that you will use all the time:

<br />

> * **Application**: The fundamental unit in ArgoCD. An Application defines a source (a Git repository with manifests or a Helm chart), a destination (a Kubernetes cluster and namespace), and a sync policy. Each Application represents one deployable unit.
> * **Project**: A logical grouping of Applications with access controls. Projects define which repositories and clusters an Application can use. The `default` project allows everything, which is fine for getting started.
> * **Repository**: A Git repository that ArgoCD watches. You register repositories with ArgoCD so it knows where to pull manifests from. Public repositories work out of the box. Private repositories need credentials.
> * **Sync**: The process of applying the desired state from Git to the cluster. When ArgoCD detects a difference between what is in Git and what is running in the cluster, it can sync (apply the changes) either automatically or when you click a button.
> * **Health**: ArgoCD understands Kubernetes resource health. A Deployment is healthy when all replicas are available. A Pod is healthy when it is running and ready. A Service is always healthy. ArgoCD shows you the health of every resource in your application.

<br />

These five concepts cover 90% of what you need to work with ArgoCD day to day. Let's put them together
by creating our first Application.

<br />

##### **Setting up a GitOps repository**
The first thing you need is a Git repository that contains your Kubernetes manifests. This is the
repository ArgoCD will watch. You can use the same repository as your application code, but the common
practice is to have a separate repository for deployment manifests. This separation makes the workflow
cleaner: application code changes trigger CI builds that produce new images, and deployment manifest
changes trigger ArgoCD syncs.

<br />

Let's create a simple GitOps repository structure:

<br />

```bash
# Create and initialize the repository
mkdir gitops-repo && cd gitops-repo
git init
mkdir -p apps/task-api
```

<br />

Now create the Kubernetes manifests for our TypeScript API. We will use plain YAML to keep things
simple, but remember that ArgoCD also supports Helm charts (which we built in article twelve).

<br />

```yaml
# apps/task-api/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: task-api
```

<br />

```yaml
# apps/task-api/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: task-api
  namespace: task-api
  labels:
    app: task-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: task-api
  template:
    metadata:
      labels:
        app: task-api
    spec:
      containers:
        - name: task-api
          image: ghcr.io/your-org/task-api:v1.0.0
          ports:
            - containerPort: 3000
          env:
            - name: NODE_ENV
              value: production
            - name: PORT
              value: "3000"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 20
```

<br />

```yaml
# apps/task-api/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: task-api
  namespace: task-api
spec:
  selector:
    app: task-api
  ports:
    - port: 80
      targetPort: 3000
  type: ClusterIP
```

<br />

Commit and push these files to your Git repository:

<br />

```bash
git add .
git commit -m "Add task-api manifests"
git remote add origin https://github.com/your-org/gitops-repo.git
git push -u origin main
```

<br />

##### **Creating your first ArgoCD Application**
Now let's tell ArgoCD about our application. You can do this through the UI, the CLI, or by applying
a YAML manifest. We will use the YAML manifest approach because it is declarative, versionable, and
follows the GitOps philosophy.

<br />

```yaml
# application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: task-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo
    targetRevision: main
    path: apps/task-api
  destination:
    server: https://kubernetes.default.svc
    namespace: task-api
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

<br />

Let's break down what each field means:

<br />

> * **metadata.namespace**: Applications always live in the `argocd` namespace, regardless of where they deploy resources.
> * **spec.project**: We use `default`, which has no restrictions. In a real team setup you would create dedicated projects with scoped access.
> * **spec.source.repoURL**: The Git repository ArgoCD watches.
> * **spec.source.targetRevision**: The branch, tag, or commit to track. Using `main` means ArgoCD follows the tip of the main branch.
> * **spec.source.path**: The directory inside the repository that contains the manifests.
> * **spec.destination.server**: The Kubernetes API server to deploy to. `https://kubernetes.default.svc` means the same cluster where ArgoCD is running.
> * **spec.destination.namespace**: The target namespace for the deployed resources.
> * **syncPolicy.syncOptions**: `CreateNamespace=true` tells ArgoCD to create the namespace if it does not exist.

<br />

Apply it:

<br />

```bash
kubectl apply -f application.yaml
```

<br />

If you open the ArgoCD UI now, you will see the `task-api` application. Its status will be
**OutOfSync** because we have not synced it yet. Let's do that.

<br />

##### **The sync loop: how ArgoCD detects drift and reconciles**
ArgoCD runs a reconciliation loop every three minutes by default. Here is what happens during each
cycle:

<br />

> * **Step 1**: The Application Controller reads the Application CRD and asks the Repository Server to clone the Git repo and render the manifests from the specified path.
> * **Step 2**: The Repository Server fetches the latest commit from the branch (or tag), reads the YAML files, and returns the rendered manifests. If you are using Helm, it runs `helm template`. If you are using Kustomize, it runs `kustomize build`.
> * **Step 3**: The Application Controller compares the rendered manifests with the live state of the resources in the cluster. It does a field-by-field comparison to detect any differences.
> * **Step 4**: If there are differences, ArgoCD marks the application as **OutOfSync** and shows you exactly what changed. Depending on your sync policy, it either waits for you to manually trigger a sync or applies the changes automatically.

<br />

```plaintext
Reconciliation loop (every 3 minutes):

  Git repository          ArgoCD                  Kubernetes cluster
  ┌──────────────┐    ┌───────────────┐        ┌──────────────────┐
  │ YAML files   │───>│ Repo Server   │        │ Live resources   │
  │ (desired     │    │ (renders      │        │ (actual state)   │
  │  state)      │    │  manifests)   │        │                  │
  └──────────────┘    └───────┬───────┘        └────────┬─────────┘
                              │                         │
                              v                         │
                      ┌───────────────┐                 │
                      │ App Controller │<────────────────┘
                      │ (compares     │
                      │  desired vs   │
                      │  actual)      │
                      └───────┬───────┘
                              │
                      OutOfSync? ──> Sync (apply changes)
                      Synced?   ──> Do nothing
```

<br />

This continuous loop is what makes GitOps powerful. If someone runs `kubectl edit` and changes a
replica count directly in the cluster, ArgoCD will detect the drift and either alert you or fix it
automatically (depending on your configuration).

<br />

##### **Manual sync vs auto-sync**
When we created our Application above, we did not enable auto-sync. This means ArgoCD will detect
changes but wait for you to manually trigger the sync. Let's do our first manual sync:

<br />

```bash
# Sync using the CLI
argocd app sync task-api

# Or you can click the "Sync" button in the ArgoCD UI
```

<br />

ArgoCD will apply all the manifests from the Git repository to the cluster. You can watch the progress
in the UI or with the CLI:

<br />

```bash
# Watch the sync progress
argocd app get task-api

# Check that the pods are running
kubectl get pods -n task-api
```

<br />

After the sync completes, the application status should show **Synced** and **Healthy**. Now let's
talk about when to use manual sync versus auto-sync.

<br />

**Manual sync** is good for:

<br />

> * **Production environments** where you want a human to review and approve every deployment.
> * **Initial setup** when you are getting comfortable with ArgoCD and want to see what it will do before it does it.
> * **Sensitive applications** where you need an extra layer of control.

<br />

**Auto-sync** is good for:

<br />

> * **Development and staging environments** where you want changes to be applied as soon as they are merged to the main branch.
> * **Infrastructure components** that should always match what is in Git (monitoring, logging, ingress controllers).
> * **Teams that have a solid review process** and trust that anything merged to main is ready to deploy.

<br />

To enable auto-sync, update the Application manifest:

<br />

```yaml
# application.yaml (with auto-sync enabled)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: task-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo
    targetRevision: main
    path: apps/task-api
  destination:
    server: https://kubernetes.default.svc
    namespace: task-api
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

The two new fields under `automated` are important:

<br />

> * **prune**: When set to `true`, ArgoCD will delete resources from the cluster that no longer exist in Git. If you remove a ConfigMap from your Git repository, ArgoCD removes it from the cluster too. Without this, deleted resources would linger forever.
> * **selfHeal**: When set to `true`, ArgoCD will revert any manual changes made to the cluster. If someone runs `kubectl scale deployment task-api --replicas=5` directly, ArgoCD will detect the drift and set it back to whatever is declared in Git.

<br />

Apply the updated manifest:

<br />

```bash
kubectl apply -f application.yaml
```

<br />

From now on, every time you push a change to the `apps/task-api` directory in the `main` branch,
ArgoCD will automatically apply it to the cluster within three minutes (or sooner if you configure
a webhook).

<br />

##### **Deploying the TypeScript API with a Helm chart**
In article twelve we created a Helm chart for our TypeScript API. ArgoCD has native Helm support, so
you can point an Application directly at a Helm chart in a Git repository. Let's set that up.

<br />

Assuming your GitOps repository has the Helm chart at `charts/task-api/`, create an Application
that uses it:

<br />

```yaml
# application-helm.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: task-api-helm
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo
    targetRevision: main
    path: charts/task-api
    helm:
      releaseName: task-api
      valueFiles:
        - values-production.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: task-api
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

The `spec.source.helm` section is where the Helm-specific configuration goes. `releaseName` is the
name Helm uses for the release, and `valueFiles` points to a values file relative to the chart
directory. You can also inline values directly:

<br />

```yaml
    helm:
      releaseName: task-api
      values: |
        replicaCount: 3
        image:
          repository: ghcr.io/your-org/task-api
          tag: v1.2.0
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            memory: 256Mi
```

<br />

This is how most teams handle deployments in practice: the Helm chart lives in the GitOps repository
(or in an OCI registry), and ArgoCD renders and applies it. To deploy a new version, you update the
image tag in the values file, commit, push, and ArgoCD takes care of the rest.

<br />

##### **Navigating the ArgoCD UI**
The ArgoCD web UI is one of its biggest selling points. Let's walk through what you will see.

<br />

**Application list view**: This is the main page. You see all your applications as cards, each
showing the application name, sync status (Synced, OutOfSync, Unknown), health status (Healthy,
Degraded, Progressing, Missing), the target revision, and the last sync time. Green means
everything is fine. Yellow means something is progressing. Red means something is wrong.

<br />

**Application detail view**: Click on an application to see its resource tree. This is a visual
representation of every Kubernetes resource managed by the application. For our task-api, you would
see the Deployment, which owns a ReplicaSet, which owns the individual Pods. The Service is shown
as a separate node. Each resource shows its health status with a colored icon.

<br />

**Resource diff view**: Click on any resource to see its details. The "Diff" tab shows you exactly
what is different between the desired state (from Git) and the live state (in the cluster). This is
extremely helpful for debugging sync issues.

<br />

**Sync status bar**: At the top of the detail view, you see the current sync status and a "Sync"
button. If the application is OutOfSync, you can click Sync to trigger a manual sync. You can also
choose to sync specific resources instead of the entire application.

<br />

**History and rollback**: The "History" tab shows every sync operation with the Git commit that
triggered it, the time it happened, and whether it succeeded or failed. You can roll back to any
previous sync from here.

<br />

##### **Rollback: reverting to a previous state**
Things go wrong. A bad image gets deployed, a configuration change breaks something, or a new version
has a bug. With GitOps, you have two ways to roll back.

<br />

**The GitOps way (recommended)**: Revert the commit in Git. This is the cleanest approach because
it keeps Git as the source of truth and creates an audit trail of the rollback:

<br />

```bash
# Revert the last commit
git revert HEAD --no-edit
git push

# ArgoCD detects the change and syncs automatically (if auto-sync is enabled)
# Or trigger a manual sync:
argocd app sync task-api
```

<br />

**The ArgoCD way (for emergencies)**: Use the ArgoCD CLI or UI to roll back to a previous sync.
This is faster but has a caveat: it does not change Git, so if auto-sync is enabled, ArgoCD will
eventually re-sync to the latest Git state and undo your rollback:

<br />

```bash
# View sync history
argocd app history task-api

# Example output:
# ID  DATE                 REVISION
# 3   2026-05-30 10:15:00  abc1234 (main)
# 2   2026-05-29 14:30:00  def5678 (main)
# 1   2026-05-28 09:00:00  ghi9012 (main)

# Roll back to sync ID 2
argocd app rollback task-api 2
```

<br />

If you use the ArgoCD rollback, make sure to also disable auto-sync first, or the controller will
re-apply the latest Git state and undo your rollback:

<br />

```bash
# Disable auto-sync before rolling back
argocd app set task-api --sync-policy none

# Roll back
argocd app rollback task-api 2

# Fix the issue in Git, then re-enable auto-sync
argocd app set task-api --sync-policy automated --self-heal --auto-prune
```

<br />

The key takeaway is that `git revert` is the preferred way to roll back in a GitOps workflow. It
keeps everything consistent and leaves a clear record of what happened and why.

<br />

##### **A typical GitOps workflow**
Let's put it all together and walk through what a typical deployment looks like end to end:

<br />

> * **Step 1**: A developer opens a pull request that changes the image tag in the deployment manifest (or the Helm values file) from `v1.0.0` to `v1.1.0`.
> * **Step 2**: The team reviews the change. Because it is just a YAML diff in a pull request, it is easy to see exactly what will change in the cluster.
> * **Step 3**: The pull request is merged to main.
> * **Step 4**: ArgoCD detects the new commit within three minutes (or immediately if you have a webhook configured). It compares the new desired state with the live state and finds that the image tag differs.
> * **Step 5**: If auto-sync is enabled, ArgoCD applies the change. The Deployment gets updated, Kubernetes performs a rolling update, and the new pods come up with the `v1.1.0` image.
> * **Step 6**: ArgoCD marks the application as Synced and Healthy once all pods are running and passing readiness checks.
> * **Step 7**: If something goes wrong, the team reverts the commit in Git and ArgoCD rolls back automatically.

<br />

This workflow gives you code review for infrastructure changes, a full audit trail in Git, automatic
deployment, automatic drift detection, and easy rollback. That is a lot of value for a relatively
simple setup.

<br />

##### **Advanced topics: where to go next**
Once you are comfortable with the basics covered here, there is a lot more ArgoCD can do. Here is a
quick overview of advanced topics:

<br />

> * **App of Apps pattern**: Instead of creating Application manifests one by one, you create a parent Application that manages child Applications. This lets you bootstrap an entire cluster with a single Application.
> * **ApplicationSets**: A way to generate multiple Applications from a single template. Useful for deploying the same application across multiple clusters or environments automatically.
> * **Sync waves and hooks**: Control the order in which resources are applied. For example, you can ensure that a database migration Job runs before the Deployment starts.
> * **RBAC and SSO**: Restrict who can see and sync which applications. Integrate with your identity provider for single sign-on.
> * **Notifications**: Send alerts to Slack, email, or other channels when syncs succeed or fail.

<br />

All of these topics are covered in depth in
[GitOps with ArgoCD](/blog/sre-gitops-with-argocd) from the SRE series. That article goes into
ApplicationSet generators, sync wave annotations, RBAC policies with AppProjects, notification
templates, monitoring ArgoCD with Prometheus, and more. Once you have the basics down from this
article, that is a great next step.

<br />

##### **Closing notes**
GitOps with ArgoCD gives you a deployment workflow that is declarative, versioned, automated, and
auditable. Instead of running commands against your cluster and hoping everyone follows the same
process, you push changes to Git and let ArgoCD handle the rest. Every change is reviewed in a pull
request, tracked in Git history, and automatically applied to the cluster.

<br />

In this article we covered what GitOps is and why it matters, installed ArgoCD on an EKS cluster with
Helm, learned the core concepts (Application, Project, Sync, Health), created our first Application
pointing at a Git repository, understood the reconciliation loop and how ArgoCD detects drift, compared
manual sync and auto-sync and when to use each, deployed our TypeScript API using both plain manifests
and a Helm chart, explored the ArgoCD UI, and learned how to roll back safely.

<br />

The next article will cover monitoring and observability, because deploying applications is only half
the battle. You also need to know if they are healthy and performing well.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: GitOps con ArgoCD",
  author: "Gabriel Garrido",
  description: "Vamos a aprender que es GitOps, por que importa, y como usar ArgoCD para deployear aplicaciones a Kubernetes usando Git como la unica fuente de verdad...",
  tags: ~w(devops kubernetes argocd gitops beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo catorce de la serie DevOps desde Cero. En el articulo anterior aprendimos
como deployear nuestra API TypeScript a un cluster EKS. Corrimos comandos `kubectl apply` y
`helm install` para poner las cosas a funcionar, y eso esta bien cuando vos sos la unica persona
deployeando a un solo cluster. Pero que pasa cuando tu equipo crece, cuando tenes multiples
entornos, o cuando alguien aplica un fix rapido directamente en el cluster y se olvida de actualizar
los archivos YAML en Git?

<br />

Ahi es donde entra GitOps. GitOps es una forma de gestionar tus deployments de Kubernetes donde Git
es la unica fuente de verdad. En vez de correr comandos contra el cluster, pusheas cambios a un
repositorio Git y un controlador dentro del cluster los toma y los aplica automaticamente. Se acabo
el preguntarse que esta corriendo donde. Se acabo el drift manual. Todo esta trackeado, revisado y
es reproducible.

<br />

ArgoCD es la herramienta GitOps mas popular para Kubernetes. Es un proyecto graduado de la CNCF con
una excelente interfaz web, un CLI poderoso, y soporte nativo para Helm, Kustomize y YAML plano. En
este articulo vamos a instalar ArgoCD en nuestro cluster EKS, deployear nuestra API TypeScript a
traves de el, y aprender como funciona todo el loop de sincronizacion y reconciliacion.

<br />

Si ya estas comodo con GitOps y queres aprender sobre patrones avanzados como ApplicationSets,
App of Apps, sync waves, gestion multi-cluster, RBAC y notificaciones, mira
[GitOps con ArgoCD](/blog/sre-gitops-with-argocd) de la serie SRE. Este articulo se mantiene
amigable para principiantes y se enfoca en llevarte de cero a un setup GitOps funcionando.

<br />

Vamos a ello.

<br />

##### **Que es GitOps?**
GitOps es un modelo operativo para Kubernetes donde declaras lo que queres corriendo en tu cluster
en un repositorio Git, y un controlador corriendo dentro del cluster se asegura continuamente de que
el estado real coincida con el estado declarado. Si alguien cambia algo manualmente o si un pod
crashea y se recrea con diferentes configuraciones, el controlador detecta el desfase y lo corrige.

<br />

Esto es diferente del enfoque tradicional de CI/CD donde un pipeline ejecuta `kubectl apply` o
`helm upgrade` al final de un build. Con ese modelo basado en push, el sistema de CI necesita
credenciales de tu cluster, el drift pasa desapercibido, y no hay una forma facil de saber
exactamente que esta corriendo en este momento. Con GitOps, el flujo se invierte: el controlador
vive dentro del cluster, pullea el estado deseado desde Git, y se encarga del paso de aplicacion
el mismo.

<br />

```bash
# CI/CD tradicional basado en push:
# Desarrollador -> Git push -> CI construye -> CI ejecuta kubectl apply -> Cluster
#                                              (CI necesita credenciales del cluster)
#                                              (los cambios manuales pasan desapercibidos)

# GitOps basado en pull:
# Desarrollador -> Git push -> Controlador detecta cambio -> Controlador aplica -> Cluster
#                              (el controlador vive en el cluster)
#                              (el drift se detecta y corrige automaticamente)
```

<br />

##### **Principios de GitOps**
Hay cuatro principios fundamentales que definen un workflow GitOps:

<br />

> * **Declarativo**: Todo tu sistema se describe como archivos YAML o JSON en Git. Sin scripts imperativos, sin pasos manuales, sin comandos one-off. Declaras lo que queres, no como llegar ahi.
> * **Versionado e inmutable**: Cada cambio pasa por Git, lo que significa que cada cambio esta versionado, tiene un autor, tiene un timestamp, y puede ser revisado en un pull request. Obtenes un audit trail completo gratis.
> * **Pulleado automaticamente**: Un controlador corriendo en tu cluster observa el repositorio Git y pullea cambios a medida que aparecen. No pusheas al cluster. Esto es mas seguro porque las credenciales del cluster nunca salen del cluster.
> * **Reconciliado continuamente**: El controlador no aplica cambios una vez y se olvida. Corre un loop que constantemente compara el estado vivo con el estado deseado. Si difieren por cualquier razon, corrige el drift.

<br />

La gran ventaja aca es que Git se convierte en la unica fuente de verdad. Si queres saber que esta
corriendo en tu cluster, mira Git. Si queres hacer rollback, revertir un commit. Si queres auditar
quien cambio que y cuando, revisa el historial de Git. Todo fluye por el mismo proceso: commit, push,
review, merge, y el controlador se encarga del resto.

<br />

##### **Por que ArgoCD**
Hay varias herramientas GitOps disponibles (Flux es otra opcion popular), pero ArgoCD se convirtio
en la opcion preferida para la mayoria de los equipos. Aca esta el por que:

<br />

> * **Graduado de la CNCF**: ArgoCD es un proyecto graduado en la Cloud Native Computing Foundation, lo que significa que paso auditorias de seguridad rigurosas y tiene una comunidad grande y activa.
> * **Excelente interfaz web**: ArgoCD viene con un dashboard donde podes ver cada aplicacion, su estado de sincronizacion, estado de salud, y el arbol de recursos. Esto es increiblemente util para debuggear y para dar visibilidad a todo el equipo.
> * **Nativo de Kubernetes**: ArgoCD usa Custom Resource Definitions (CRDs) para definir aplicaciones. Gestionas ArgoCD con las mismas herramientas que usas para todo lo demas en Kubernetes.
> * **Soporte multi-formato**: ArgoCD funciona con manifiestos YAML planos, charts de Helm, overlays de Kustomize, Jsonnet y plugins personalizados. No tenes que cambiar como escribis tus manifiestos.
> * **CLI y API**: Mas alla de la interfaz, ArgoCD tiene un CLI completo y una API gRPC/REST para automatizacion y scripting.

<br />

##### **Instalando ArgoCD en EKS**
Vamos a instalar ArgoCD en el cluster EKS que configuramos en el articulo anterior. La forma
recomendada es usando Helm. Primero, agrega el repositorio Helm de Argo y crea el namespace:

<br />

```bash
# Agregar el repositorio Helm de ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Crear el namespace de argocd
kubectl create namespace argocd
```

<br />

Ahora crea un archivo de values para configurar la instalacion. Lo vamos a mantener simple por ahora:

<br />

```yaml
# argocd-values.yaml
configs:
  params:
    # Si estas terminando TLS en el load balancer o ingress,
    # configura esto para que ArgoCD no intente manejar TLS el mismo
    server.insecure: true

server:
  service:
    type: LoadBalancer
```

<br />

Esta es una configuracion minima. Seteamos `server.insecure: true` porque en un setup tipico de EKS
terminas TLS en el load balancer o ingress controller. Tambien seteamos el tipo de servicio a
LoadBalancer para que puedas acceder a la interfaz desde tu navegador.

<br />

Instala ArgoCD con Helm:

<br />

```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --values argocd-values.yaml \
  --wait

# Verificar que todos los pods estan corriendo
kubectl get pods -n argocd
```

<br />

Deberias ver algo como esto:

<br />

```plaintext
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          2m
argocd-repo-server-6b7f8d7b4-x9k2l                 1/1     Running   0          2m
argocd-server-7c4f8b6d9-m3n8p                       1/1     Running   0          2m
argocd-redis-5b6c7d8e9-q4r7s                        1/1     Running   0          2m
argocd-applicationset-controller-8f9a1b2c3-t5u6v    1/1     Running   0          2m
argocd-notifications-controller-4d5e6f7a8-w9x0y     1/1     Running   0          2m
```

<br />

Ahora obtene la password de admin inicial y la URL del load balancer:

<br />

```bash
# Obtener la password de admin inicial
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
# Guarda esta password, la vas a necesitar para iniciar sesion

# Obtener la URL del load balancer
kubectl -n argocd get svc argocd-server \
  -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
```

<br />

Abri esa URL en tu navegador e inicia sesion con usuario `admin` y la password que acabas de obtener.
Deberias ver el dashboard de ArgoCD sin aplicaciones todavia. Vamos a crear una en un momento.

<br />

Tambien podes instalar el CLI de ArgoCD para gestionar cosas desde la terminal:

<br />

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Iniciar sesion en tu instancia de ArgoCD
argocd login <load-balancer-url> --username admin --password <tu-password> --insecure
```

<br />

Una vez logueado, cambia la password por defecto:

<br />

```bash
argocd account update-password
```

<br />

##### **Conceptos de ArgoCD**
Antes de crear nuestra primera aplicacion, entendamos los conceptos clave. ArgoCD tiene un punado
de bloques de construccion que vas a usar todo el tiempo:

<br />

> * **Application**: La unidad fundamental en ArgoCD. Una Application define un source (un repositorio Git con manifiestos o un chart de Helm), un destination (un cluster de Kubernetes y namespace), y una sync policy. Cada Application representa una unidad deployeable.
> * **Project**: Un agrupamiento logico de Applications con controles de acceso. Los Projects definen que repositorios y clusters puede usar una Application. El proyecto `default` permite todo, lo cual esta bien para empezar.
> * **Repository**: Un repositorio Git que ArgoCD observa. Registras repositorios con ArgoCD para que sepa de donde pullear manifiestos. Los repositorios publicos funcionan de una. Los privados necesitan credenciales.
> * **Sync**: El proceso de aplicar el estado deseado desde Git al cluster. Cuando ArgoCD detecta una diferencia entre lo que esta en Git y lo que esta corriendo en el cluster, puede sincronizar (aplicar los cambios) automaticamente o cuando vos haces click en un boton.
> * **Health**: ArgoCD entiende la salud de los recursos de Kubernetes. Un Deployment esta sano cuando todas las replicas estan disponibles. Un Pod esta sano cuando esta corriendo y listo. Un Service siempre esta sano. ArgoCD te muestra la salud de cada recurso en tu aplicacion.

<br />

Estos cinco conceptos cubren el 90% de lo que necesitas para trabajar con ArgoCD dia a dia. Vamos a
ponerlos juntos creando nuestra primera Application.

<br />

##### **Configurando un repositorio GitOps**
Lo primero que necesitas es un repositorio Git que contenga tus manifiestos de Kubernetes. Este es
el repositorio que ArgoCD va a observar. Podes usar el mismo repositorio que tu codigo de aplicacion,
pero la practica comun es tener un repositorio separado para los manifiestos de deployment. Esta
separacion hace el workflow mas limpio: los cambios de codigo de aplicacion disparan builds de CI
que producen nuevas imagenes, y los cambios de manifiestos de deployment disparan syncs de ArgoCD.

<br />

Vamos a crear una estructura simple de repositorio GitOps:

<br />

```bash
# Crear e inicializar el repositorio
mkdir gitops-repo && cd gitops-repo
git init
mkdir -p apps/task-api
```

<br />

Ahora crea los manifiestos de Kubernetes para nuestra API TypeScript. Vamos a usar YAML plano para
mantener las cosas simples, pero recorda que ArgoCD tambien soporta charts de Helm (que creamos en
el articulo doce).

<br />

```yaml
# apps/task-api/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: task-api
```

<br />

```yaml
# apps/task-api/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: task-api
  namespace: task-api
  labels:
    app: task-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: task-api
  template:
    metadata:
      labels:
        app: task-api
    spec:
      containers:
        - name: task-api
          image: ghcr.io/your-org/task-api:v1.0.0
          ports:
            - containerPort: 3000
          env:
            - name: NODE_ENV
              value: production
            - name: PORT
              value: "3000"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 20
```

<br />

```yaml
# apps/task-api/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: task-api
  namespace: task-api
spec:
  selector:
    app: task-api
  ports:
    - port: 80
      targetPort: 3000
  type: ClusterIP
```

<br />

Commitea y pushea estos archivos a tu repositorio Git:

<br />

```bash
git add .
git commit -m "Add task-api manifests"
git remote add origin https://github.com/your-org/gitops-repo.git
git push -u origin main
```

<br />

##### **Creando tu primera Application en ArgoCD**
Ahora vamos a decirle a ArgoCD sobre nuestra aplicacion. Podes hacer esto a traves de la interfaz
web, el CLI, o aplicando un manifiesto YAML. Vamos a usar el enfoque de manifiesto YAML porque es
declarativo, versionable y sigue la filosofia GitOps.

<br />

```yaml
# application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: task-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo
    targetRevision: main
    path: apps/task-api
  destination:
    server: https://kubernetes.default.svc
    namespace: task-api
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

<br />

Veamos que significa cada campo:

<br />

> * **metadata.namespace**: Las Applications siempre viven en el namespace `argocd`, sin importar donde deployen recursos.
> * **spec.project**: Usamos `default`, que no tiene restricciones. En un setup real de equipo crearias proyectos dedicados con acceso limitado.
> * **spec.source.repoURL**: El repositorio Git que ArgoCD observa.
> * **spec.source.targetRevision**: La branch, tag o commit a seguir. Usar `main` significa que ArgoCD sigue la punta de la branch main.
> * **spec.source.path**: El directorio dentro del repositorio que contiene los manifiestos.
> * **spec.destination.server**: El servidor API de Kubernetes donde deployear. `https://kubernetes.default.svc` significa el mismo cluster donde esta corriendo ArgoCD.
> * **spec.destination.namespace**: El namespace destino para los recursos deployeados.
> * **syncPolicy.syncOptions**: `CreateNamespace=true` le dice a ArgoCD que cree el namespace si no existe.

<br />

Aplicalo:

<br />

```bash
kubectl apply -f application.yaml
```

<br />

Si abris la interfaz de ArgoCD ahora, vas a ver la aplicacion `task-api`. Su estado va a ser
**OutOfSync** porque todavia no la sincronizamos. Vamos a hacerlo.

<br />

##### **El loop de sincronizacion: como ArgoCD detecta drift y reconcilia**
ArgoCD corre un loop de reconciliacion cada tres minutos por defecto. Esto es lo que pasa durante
cada ciclo:

<br />

> * **Paso 1**: El Application Controller lee el CRD Application y le pide al Repository Server que clone el repositorio Git y renderice los manifiestos del path especificado.
> * **Paso 2**: El Repository Server obtiene el ultimo commit de la branch (o tag), lee los archivos YAML, y devuelve los manifiestos renderizados. Si estas usando Helm, ejecuta `helm template`. Si estas usando Kustomize, ejecuta `kustomize build`.
> * **Paso 3**: El Application Controller compara los manifiestos renderizados con el estado vivo de los recursos en el cluster. Hace una comparacion campo por campo para detectar cualquier diferencia.
> * **Paso 4**: Si hay diferencias, ArgoCD marca la aplicacion como **OutOfSync** y te muestra exactamente que cambio. Dependiendo de tu sync policy, o espera a que vos dispares un sync manualmente o aplica los cambios automaticamente.

<br />

```plaintext
Loop de reconciliacion (cada 3 minutos):

  Repositorio Git       ArgoCD                  Cluster Kubernetes
  ┌──────────────┐    ┌───────────────┐        ┌──────────────────┐
  │ Archivos     │───>│ Repo Server   │        │ Recursos vivos   │
  │ YAML (estado │    │ (renderiza    │        │ (estado actual)  │
  │ deseado)     │    │  manifiestos) │        │                  │
  └──────────────┘    └───────┬───────┘        └────────┬─────────┘
                              │                         │
                              v                         │
                      ┌───────────────┐                 │
                      │ App Controller │<────────────────┘
                      │ (compara      │
                      │  deseado vs   │
                      │  actual)      │
                      └───────┬───────┘
                              │
                      OutOfSync? ──> Sync (aplicar cambios)
                      Synced?   ──> No hacer nada
```

<br />

Este loop continuo es lo que hace a GitOps poderoso. Si alguien ejecuta `kubectl edit` y cambia la
cantidad de replicas directamente en el cluster, ArgoCD va a detectar el drift y o te alerta o lo
corrige automaticamente (dependiendo de tu configuracion).

<br />

##### **Sync manual vs auto-sync**
Cuando creamos nuestra Application antes, no habilitamos auto-sync. Esto significa que ArgoCD va a
detectar cambios pero esperar a que vos dispares el sync manualmente. Hagamos nuestro primer sync
manual:

<br />

```bash
# Sincronizar usando el CLI
argocd app sync task-api

# O podes hacer click en el boton "Sync" en la interfaz de ArgoCD
```

<br />

ArgoCD va a aplicar todos los manifiestos del repositorio Git al cluster. Podes ver el progreso en
la interfaz o con el CLI:

<br />

```bash
# Ver el progreso del sync
argocd app get task-api

# Verificar que los pods estan corriendo
kubectl get pods -n task-api
```

<br />

Despues de que se complete el sync, el estado de la aplicacion deberia mostrar **Synced** y
**Healthy**. Ahora hablemos de cuando usar sync manual versus auto-sync.

<br />

**Sync manual** es bueno para:

<br />

> * **Entornos de produccion** donde queres que un humano revise y apruebe cada deployment.
> * **Setup inicial** cuando te estas familiarizando con ArgoCD y queres ver que va a hacer antes de que lo haga.
> * **Aplicaciones sensibles** donde necesitas una capa extra de control.

<br />

**Auto-sync** es bueno para:

<br />

> * **Entornos de desarrollo y staging** donde queres que los cambios se apliquen apenas se mergean a la branch main.
> * **Componentes de infraestructura** que siempre deberian coincidir con lo que esta en Git (monitoreo, logging, ingress controllers).
> * **Equipos que tienen un proceso de review solido** y confian en que todo lo mergeado a main esta listo para deployear.

<br />

Para habilitar auto-sync, actualiza el manifiesto de la Application:

<br />

```yaml
# application.yaml (con auto-sync habilitado)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: task-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo
    targetRevision: main
    path: apps/task-api
  destination:
    server: https://kubernetes.default.svc
    namespace: task-api
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

Los dos campos nuevos bajo `automated` son importantes:

<br />

> * **prune**: Cuando esta en `true`, ArgoCD va a eliminar recursos del cluster que ya no existen en Git. Si eliminas un ConfigMap de tu repositorio Git, ArgoCD lo elimina del cluster tambien. Sin esto, los recursos eliminados quedarian para siempre.
> * **selfHeal**: Cuando esta en `true`, ArgoCD va a revertir cualquier cambio manual hecho en el cluster. Si alguien ejecuta `kubectl scale deployment task-api --replicas=5` directamente, ArgoCD va a detectar el drift y lo va a volver a lo que esta declarado en Git.

<br />

Aplica el manifiesto actualizado:

<br />

```bash
kubectl apply -f application.yaml
```

<br />

De ahora en mas, cada vez que pushees un cambio al directorio `apps/task-api` en la branch `main`,
ArgoCD lo va a aplicar automaticamente al cluster en menos de tres minutos (o antes si configuras
un webhook).

<br />

##### **Deployeando la API TypeScript con un chart de Helm**
En el articulo doce creamos un chart de Helm para nuestra API TypeScript. ArgoCD tiene soporte nativo
de Helm, asi que podes apuntar una Application directamente a un chart de Helm en un repositorio Git.
Vamos a configurarlo.

<br />

Asumiendo que tu repositorio GitOps tiene el chart de Helm en `charts/task-api/`, crea una
Application que lo use:

<br />

```yaml
# application-helm.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: task-api-helm
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo
    targetRevision: main
    path: charts/task-api
    helm:
      releaseName: task-api
      valueFiles:
        - values-production.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: task-api
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

La seccion `spec.source.helm` es donde va la configuracion especifica de Helm. `releaseName` es el
nombre que Helm usa para el release, y `valueFiles` apunta a un archivo de values relativo al
directorio del chart. Tambien podes poner valores inline directamente:

<br />

```yaml
    helm:
      releaseName: task-api
      values: |
        replicaCount: 3
        image:
          repository: ghcr.io/your-org/task-api
          tag: v1.2.0
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            memory: 256Mi
```

<br />

Asi es como la mayoria de los equipos manejan deployments en la practica: el chart de Helm vive en
el repositorio GitOps (o en un registry OCI), y ArgoCD lo renderiza y aplica. Para deployear una
nueva version, actualizas el tag de la imagen en el archivo de values, commiteas, pusheas, y ArgoCD
se encarga del resto.

<br />

##### **Navegando la interfaz de ArgoCD**
La interfaz web de ArgoCD es uno de sus mayores puntos de venta. Veamos que vas a encontrar.

<br />

**Vista de lista de aplicaciones**: Esta es la pagina principal. Ves todas tus aplicaciones como
tarjetas, cada una mostrando el nombre de la aplicacion, estado de sync (Synced, OutOfSync, Unknown),
estado de salud (Healthy, Degraded, Progressing, Missing), la revision target, y la hora del ultimo
sync. Verde significa que todo esta bien. Amarillo significa que algo esta progresando. Rojo significa
que algo anda mal.

<br />

**Vista de detalle de aplicacion**: Hace click en una aplicacion para ver su arbol de recursos. Es
una representacion visual de cada recurso de Kubernetes gestionado por la aplicacion. Para nuestra
task-api, verias el Deployment, que es dueno de un ReplicaSet, que es dueno de los Pods individuales.
El Service se muestra como un nodo separado. Cada recurso muestra su estado de salud con un icono
de color.

<br />

**Vista de diff de recursos**: Hace click en cualquier recurso para ver sus detalles. La pestana
"Diff" te muestra exactamente que es diferente entre el estado deseado (de Git) y el estado vivo
(en el cluster). Esto es extremadamente util para debuggear problemas de sync.

<br />

**Barra de estado de sync**: En la parte superior de la vista de detalle, ves el estado actual de
sync y un boton "Sync". Si la aplicacion esta OutOfSync, podes hacer click en Sync para disparar un
sync manual. Tambien podes elegir sincronizar recursos especificos en vez de la aplicacion entera.

<br />

**Historial y rollback**: La pestana "History" muestra cada operacion de sync con el commit de Git
que la disparo, la hora en que ocurrio, y si fue exitosa o fallo. Podes hacer rollback a cualquier
sync anterior desde aca.

<br />

##### **Rollback: volviendo a un estado anterior**
Las cosas salen mal. Una imagen mala se deployea, un cambio de configuracion rompe algo, o una nueva
version tiene un bug. Con GitOps, tenes dos formas de hacer rollback.

<br />

**La forma GitOps (recomendada)**: Revertir el commit en Git. Este es el enfoque mas limpio porque
mantiene a Git como la fuente de verdad y crea un audit trail del rollback:

<br />

```bash
# Revertir el ultimo commit
git revert HEAD --no-edit
git push

# ArgoCD detecta el cambio y sincroniza automaticamente (si auto-sync esta habilitado)
# O dispara un sync manual:
argocd app sync task-api
```

<br />

**La forma ArgoCD (para emergencias)**: Usa el CLI o la interfaz de ArgoCD para hacer rollback a un
sync anterior. Esto es mas rapido pero tiene una salvedad: no cambia Git, asi que si auto-sync esta
habilitado, ArgoCD eventualmente va a re-sincronizar al ultimo estado de Git y deshacer tu rollback:

<br />

```bash
# Ver historial de syncs
argocd app history task-api

# Ejemplo de salida:
# ID  DATE                 REVISION
# 3   2026-05-30 10:15:00  abc1234 (main)
# 2   2026-05-29 14:30:00  def5678 (main)
# 1   2026-05-28 09:00:00  ghi9012 (main)

# Rollback al sync ID 2
argocd app rollback task-api 2
```

<br />

Si usas el rollback de ArgoCD, asegurate de deshabilitar auto-sync primero, o el controlador va a
re-aplicar el ultimo estado de Git y deshacer tu rollback:

<br />

```bash
# Deshabilitar auto-sync antes de hacer rollback
argocd app set task-api --sync-policy none

# Rollback
argocd app rollback task-api 2

# Arreglar el problema en Git, luego re-habilitar auto-sync
argocd app set task-api --sync-policy automated --self-heal --auto-prune
```

<br />

La conclusion clave es que `git revert` es la forma preferida de hacer rollback en un workflow GitOps.
Mantiene todo consistente y deja un registro claro de que paso y por que.

<br />

##### **Un workflow GitOps tipico**
Juntemos todo y recorramos como se ve un deployment tipico de punta a punta:

<br />

> * **Paso 1**: Un desarrollador abre un pull request que cambia el tag de la imagen en el manifiesto de deployment (o el archivo de values de Helm) de `v1.0.0` a `v1.1.0`.
> * **Paso 2**: El equipo revisa el cambio. Como es solo un diff YAML en un pull request, es facil ver exactamente que va a cambiar en el cluster.
> * **Paso 3**: El pull request se mergea a main.
> * **Paso 4**: ArgoCD detecta el nuevo commit en menos de tres minutos (o inmediatamente si tenes un webhook configurado). Compara el nuevo estado deseado con el estado vivo y encuentra que el tag de la imagen difiere.
> * **Paso 5**: Si auto-sync esta habilitado, ArgoCD aplica el cambio. El Deployment se actualiza, Kubernetes hace un rolling update, y los nuevos pods levantan con la imagen `v1.1.0`.
> * **Paso 6**: ArgoCD marca la aplicacion como Synced y Healthy una vez que todos los pods estan corriendo y pasando los readiness checks.
> * **Paso 7**: Si algo sale mal, el equipo revierte el commit en Git y ArgoCD hace rollback automaticamente.

<br />

Este workflow te da code review para cambios de infraestructura, un audit trail completo en Git,
deployment automatico, deteccion automatica de drift, y rollback facil. Eso es mucho valor para un
setup relativamente simple.

<br />

##### **Temas avanzados: hacia donde ir despues**
Una vez que estes comodo con lo basico cubierto aca, hay mucho mas que ArgoCD puede hacer. Aca va un
panorama rapido de temas avanzados:

<br />

> * **Patron App of Apps**: En vez de crear manifiestos de Application uno por uno, creas una Application padre que gestiona Applications hijos. Esto te permite bootstrapear un cluster entero con una sola Application.
> * **ApplicationSets**: Una forma de generar multiples Applications desde un solo template. Util para deployear la misma aplicacion en multiples clusters o entornos automaticamente.
> * **Sync waves y hooks**: Controlar el orden en que los recursos se aplican. Por ejemplo, podes asegurar que un Job de migracion de base de datos corra antes de que arranque el Deployment.
> * **RBAC y SSO**: Restringir quien puede ver y sincronizar que aplicaciones. Integrar con tu proveedor de identidad para single sign-on.
> * **Notificaciones**: Enviar alertas a Slack, email u otros canales cuando los syncs tienen exito o fallan.

<br />

Todos estos temas estan cubiertos en profundidad en
[GitOps con ArgoCD](/blog/sre-gitops-with-argocd) de la serie SRE. Ese articulo entra en detalle
sobre generadores de ApplicationSet, anotaciones de sync wave, politicas RBAC con AppProjects,
templates de notificaciones, monitoreo de ArgoCD con Prometheus, y mas. Una vez que tengas lo basico
de este articulo, ese es un gran siguiente paso.

<br />

##### **Notas finales**
GitOps con ArgoCD te da un workflow de deployment que es declarativo, versionado, automatizado y
auditable. En vez de correr comandos contra tu cluster y esperar que todos sigan el mismo proceso,
pusheas cambios a Git y dejas que ArgoCD se encargue del resto. Cada cambio se revisa en un pull
request, se trackea en el historial de Git, y se aplica automaticamente al cluster.

<br />

En este articulo cubrimos que es GitOps y por que importa, instalamos ArgoCD en un cluster EKS con
Helm, aprendimos los conceptos clave (Application, Project, Sync, Health), creamos nuestra primera
Application apuntando a un repositorio Git, entendimos el loop de reconciliacion y como ArgoCD
detecta drift, comparamos sync manual y auto-sync y cuando usar cada uno, deployeamos nuestra API
TypeScript usando manifiestos planos y un chart de Helm, exploramos la interfaz de ArgoCD, y
aprendimos como hacer rollback de forma segura.

<br />

El proximo articulo va a cubrir monitoreo y observabilidad, porque deployear aplicaciones es solo la
mitad de la batalla. Tambien necesitas saber si estan sanas y rindiendo bien.

<br />

Espero que te haya resultado util y lo hayas disfrutado, hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, mandame un mensaje para que se corrija.

Tambien, podes revisar el codigo fuente y los cambios en los [fuentes aca](https://github.com/kainlite/tr)

<br />
