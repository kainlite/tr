%{
  title: "DevOps from Zero to Hero: Helm Charts",
  author: "Gabriel Garrido",
  description: "We will learn how to package Kubernetes applications with Helm, create charts from scratch, use Go templates, manage releases, push to OCI registries, and test charts...",
  tags: ~w(devops kubernetes helm beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article twelve of the DevOps from Zero to Hero series. In the previous articles we learned
how to deploy containers to Kubernetes using raw YAML manifests. That works fine when you have a single
service with a handful of files, but as your applications grow and you start managing multiple
environments, raw manifests become painful to maintain.

<br />

Imagine you have a deployment, a service, an ingress, a configmap, and an HPA. Now multiply that by
three environments (dev, staging, production) where only a few values change: the image tag, the
replica count, the domain name. Suddenly you are copy-pasting YAML files, searching and replacing
values by hand, and praying you did not miss something. This is exactly the problem Helm solves.

<br />

Helm is the package manager for Kubernetes. It lets you define your application as a reusable template,
parameterize the parts that change, version the whole thing, and install or upgrade it with a single
command. If you have ever used `apt`, `brew`, or `npm`, Helm fills the same role for Kubernetes.

<br />

In this article we will cover what Helm is and why it exists, create a chart from scratch, dive into
template syntax and helpers, package a TypeScript API with all the resources it needs, manage releases
with install, upgrade, and rollback, push charts to OCI registries, and test our work. If you want to
see how Helm was used years ago, check out
[Getting started with Helm](/blog/getting_started_with_helm) and
[Deploying my apps with Helm](/blog/deploying_my_apps_with_helm), but keep in mind those articles
are from 2018 and cover Helm 2 which is now deprecated.

<br />

Let's get into it.

<br />

##### **What is Helm?**
Helm calls itself the package manager for Kubernetes, and that is a good description. There are four
core concepts you need to understand:

<br />

> * **Chart**: A collection of files that describe a related set of Kubernetes resources. Think of it as a package. A chart contains templates, default values, metadata, and optionally sub-charts for dependencies.
> * **Release**: A specific instance of a chart running in your cluster. You can install the same chart multiple times with different configurations, and each installation is a separate release with its own name and history.
> * **Repository**: A place where charts are stored and shared. This can be a traditional HTTP server, a Helm repository, or an OCI-compliant container registry (the modern approach).
> * **Values**: The configuration parameters that customize a chart for a specific deployment. You provide values to override the chart's defaults, and Helm uses them to render the templates into valid Kubernetes manifests.

<br />

Here is how these pieces fit together:

<br />

```plaintext
Chart (package definition)
  + Values (your configuration)
  = Release (running instance in your cluster)
    ├── Deployment (rendered from template)
    ├── Service (rendered from template)
    ├── Ingress (rendered from template)
    └── ConfigMap (rendered from template)
```

<br />

##### **Why Helm over raw manifests**
You might be wondering if you really need another tool. Here is what Helm gives you that raw YAML
does not:

<br />

> * **Templating**: Write your manifests once with placeholders, and render them with different values for each environment. No more copy-pasting YAML files.
> * **Versioning**: Every chart has a version. Every release tracks which version was installed and what values were used. You always know what is running.
> * **Rollback**: Made a bad deployment? `helm rollback` takes you back to the previous working state in seconds. Helm keeps a history of every release revision.
> * **Dependency management**: Your application depends on Redis? Add it as a chart dependency and Helm installs both together.
> * **Sharing**: Package your chart and push it to a registry. Anyone on your team (or the world) can install it with a single command.
> * **Lifecycle hooks**: Run jobs before or after install, upgrade, or delete. Great for database migrations, cache warming, or health checks.

<br />

The alternative is managing raw YAML with Kustomize or hand-rolled scripts. Kustomize is built into
kubectl and works well for simple overlay scenarios, but it does not give you versioning, rollback,
or a release history. For most teams, Helm is the better choice once you move beyond trivial
deployments.

<br />

##### **Helm 3 vs Helm 2: a brief history**
If you have seen older Helm tutorials, they mention something called Tiller. That was a server-side
component that Helm 2 required to run inside your cluster. Tiller had cluster-admin permissions and
was a significant security concern.

<br />

Helm 3 (released in November 2019) removed Tiller entirely. Here is what changed:

<br />

> * **No Tiller**: Helm now talks directly to the Kubernetes API using your kubeconfig credentials. No more deploying a privileged pod into your cluster.
> * **Three-way strategic merge**: Helm 3 compares the old manifest, the new manifest, and the live state in the cluster. This means manual changes to resources are detected and handled properly during upgrades.
> * **Release namespaces**: Releases are stored as Kubernetes secrets in the namespace where they are deployed, not in a central Tiller namespace.
> * **JSON Schema validation**: Charts can include a `values.schema.json` file to validate user-provided values before rendering.
> * **OCI registry support**: Charts can be stored in container registries like Docker Hub, GHCR, or ECR, just like container images.

<br />

If you are starting today, you will only ever use Helm 3. The `helm` binary you install from the
official site is Helm 3. Helm 2 reached end of life in November 2020, so there is no reason to use
it for new projects.

<br />

##### **Installing Helm**
Installing Helm is straightforward. Pick the method that matches your system:

<br />

```bash
# macOS with Homebrew
brew install helm

# Linux with the official install script
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Arch Linux
pacman -S helm

# Verify the installation
helm version
```

<br />

You should see output like:

<br />

```plaintext
version.BuildInfo{Version:"v3.17.x", GitCommit:"...", GitTreeState:"clean", GoVersion:"go1.23.x"}
```

<br />

##### **Creating a chart from scratch**
Let's create our first chart. Helm provides a scaffolding command:

<br />

```bash
helm create task-api
```

<br />

This creates a directory structure with everything you need:

<br />

```plaintext
task-api/
├── Chart.yaml          # Metadata: name, version, description
├── values.yaml         # Default configuration values
├── charts/             # Sub-charts (dependencies)
├── templates/          # Kubernetes manifest templates
│   ├── _helpers.tpl    # Named template helpers
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── serviceaccount.yaml
│   ├── NOTES.txt       # Post-install instructions shown to the user
│   └── tests/
│       └── test-connection.yaml
└── .helmignore         # Files to exclude when packaging
```

<br />

Let's go through the key files one by one.

<br />

##### **Chart.yaml: the chart metadata**
This file defines who your chart is. Think of it like a `package.json` for Helm:

<br />

```yaml
apiVersion: v2
name: task-api
description: A Helm chart for the Task API TypeScript application
type: application
version: 0.1.0
appVersion: "1.0.0"
```

<br />

> * **apiVersion**: Always `v2` for Helm 3 charts. Helm 2 used `v1`.
> * **name**: The name of the chart. Must be lowercase and may contain hyphens.
> * **description**: A short description displayed when searching repositories.
> * **type**: Either `application` (deploys resources) or `library` (only provides helpers for other charts).
> * **version**: The chart version. Follows semantic versioning. Bump this every time you change the chart.
> * **appVersion**: The version of the application being deployed. This is informational and does not affect chart behavior.

<br />

The distinction between `version` and `appVersion` is important. The chart version tracks changes
to the chart itself (templates, defaults). The app version tracks which version of your application
the chart deploys. They evolve independently.

<br />

##### **values.yaml: the default configuration**
This is the most important file in a chart. It defines every configurable parameter with sensible
defaults:

<br />

```yaml
replicaCount: 2

image:
  repository: ghcr.io/your-org/task-api
  pullPolicy: IfNotPresent
  tag: ""

nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

service:
  type: ClusterIP
  port: 3000

ingress:
  enabled: false
  className: "traefik"
  annotations: {}
  hosts:
    - host: task-api.example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

env:
  NODE_ENV: production
  PORT: "3000"
```

<br />

A few principles for structuring values:

<br />

> * **Group related settings**: Put all image-related values under `image`, all ingress settings under `ingress`, and so on. This makes it easy to find and override things.
> * **Provide sensible defaults**: The chart should work with zero overrides for a basic deployment. Production-specific settings (domain names, resource limits) are what users override.
> * **Use flat keys where possible**: Deeply nested values are harder to override with `--set`. Keep the nesting reasonable.
> * **Document with comments**: Add comments explaining what each value does, what valid options are, and what the default means.

<br />

##### **Template syntax: Go templates**
Helm templates use Go's `text/template` package with some extra functions from the Sprig library.
If you have never seen Go templates before, here is a quick introduction.

<br />

The basic syntax uses double curly braces `{{ }}` to insert dynamic content. Everything outside the
braces is rendered as-is. Let's look at the core patterns:

<br />

```yaml
# Simple value substitution
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-api
  labels:
    app: {{ .Chart.Name }}
    version: {{ .Chart.AppVersion }}
spec:
  replicas: {{ .Values.replicaCount }}
```

<br />

Helm provides several built-in objects that you can access in templates:

<br />

> * **`.Values`**: The merged result of values.yaml and any overrides the user provided. This is where most of your dynamic data comes from.
> * **`.Release`**: Information about the current release. `.Release.Name` is the release name, `.Release.Namespace` is the namespace, `.Release.IsUpgrade` tells you if this is an upgrade.
> * **`.Chart`**: Contents of Chart.yaml. `.Chart.Name`, `.Chart.Version`, `.Chart.AppVersion`.
> * **`.Template`**: Information about the current template file. Mostly used for debugging.
> * **`.Capabilities`**: Information about the Kubernetes cluster. `.Capabilities.APIVersions` lets you check if a specific API version exists.

<br />

##### **Conditionals and loops**
Templates support control flow. Here is how to conditionally include an ingress and loop over
hosts:

<br />

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "task-api.fullname" . }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ include "task-api.fullname" $ }}
                port:
                  number: {{ $.Values.service.port }}
          {{- end }}
    {{- end }}
  {{- if .Values.ingress.tls }}
  tls:
    {{- toYaml .Values.ingress.tls | nindent 4 }}
  {{- end }}
{{- end }}
```

<br />

A few things to notice:

<br />

> * **`{{- ... }}`**: The dash trims whitespace before the tag. Without it, you get blank lines in the output.
> * **`range`**: Loops over a list or map. Inside the loop, `.` refers to the current item.
> * **`$`**: Refers to the root scope. When you are inside a `range` block, `.` changes to the current item. Use `$` to access `.Values` or `.Release` from within a loop.
> * **`with`**: Sets the scope of `.` to the specified object. If the object is empty, the block is skipped entirely. It works like a combined "if not empty" and "set scope."
> * **`toYaml`**: Converts a Go data structure to YAML. Combined with `nindent`, it handles indentation correctly.
> * **`quote`**: Wraps the value in double quotes. Always quote hostnames and strings that might contain special characters.

<br />

##### **Helpers: _helpers.tpl**
The `_helpers.tpl` file (the underscore prefix tells Helm not to render it as a manifest) contains
reusable named templates. These are like functions you can call from any template:

<br />

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "task-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "task-api.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "task-api.labels" -}}
helm.sh/chart: {{ include "task-api.chart" . }}
{{ include "task-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "task-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "task-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

<br />

You call these named templates using `include`:

<br />

```yaml
metadata:
  name: {{ include "task-api.fullname" . }}
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
```

<br />

Why `include` instead of `template`? The `template` action outputs text directly and cannot be
piped to other functions. `include` returns the output as a string, so you can pipe it to `nindent`,
`trim`, or any other function. Always prefer `include` over `template`.

<br />

The `trunc 63` calls throughout the helpers are not arbitrary. Kubernetes labels and names have a
63-character limit (DNS label rules from RFC 1123). The helpers enforce this automatically.

<br />

##### **Packaging a TypeScript API: the full chart**
Let's build a complete chart for our task API from the series. We need a deployment, a service, an
ingress, a configmap, and an HPA. We already saw the ingress above, so let's cover the rest.

<br />

**Deployment template** (`templates/deployment.yaml`):

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "task-api.fullname" . }}
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "task-api.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "task-api.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "task-api.serviceAccountName" . }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.port }}
              protocol: TCP
          envFrom:
            - configMapRef:
                name: {{ include "task-api.fullname" . }}-config
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

<br />

Notice the `checksum/config` annotation on the pod template. This is a common Helm pattern. When
you change a ConfigMap, Kubernetes does not automatically restart the pods that use it. By hashing
the ConfigMap content into an annotation, any change to the ConfigMap produces a different hash,
which triggers a rolling update. Clever and simple.

<br />

Also notice that when autoscaling is enabled, we skip the `replicas` field. The HPA manages the
replica count in that case, and setting it in the deployment would conflict.

<br />

**ConfigMap template** (`templates/configmap.yaml`):

<br />

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "task-api.fullname" . }}-config
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
data:
  {{- range $key, $value := .Values.env }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
```

<br />

This loops over every key-value pair in `.Values.env` and creates a ConfigMap entry. You add new
environment variables just by adding them to values.yaml, no template changes needed.

<br />

**Service template** (`templates/service.yaml`):

<br />

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "task-api.fullname" . }}
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "task-api.selectorLabels" . | nindent 4 }}
```

<br />

**HPA template** (`templates/hpa.yaml`):

<br />

```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "task-api.fullname" . }}
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "task-api.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
{{- end }}
```

<br />

The entire HPA template is wrapped in an `if` block. When autoscaling is disabled (the default),
this file produces no output at all.

<br />

##### **Overriding values**
There are two main ways to override the defaults in values.yaml when you install or upgrade a
release.

<br />

**Using `--set` for individual values:**

<br />

```bash
helm install my-api ./task-api \
  --set image.tag=v1.2.3 \
  --set replicaCount=3 \
  --set ingress.enabled=true
```

<br />

**Using `-f` (or `--values`) with a file:**

<br />

```bash
helm install my-api ./task-api -f production-values.yaml
```

<br />

Where `production-values.yaml` might look like:

<br />

```yaml
replicaCount: 3

image:
  tag: v1.2.3

ingress:
  enabled: true
  className: traefik
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: api.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: api-tls
      hosts:
        - api.example.com

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70

env:
  NODE_ENV: production
  PORT: "3000"
  LOG_LEVEL: info
```

<br />

The file approach is better for anything beyond a couple of values. You can version control your
environment-specific files (`dev-values.yaml`, `staging-values.yaml`, `production-values.yaml`)
and get all the benefits of Git history for configuration changes.

<br />

You can also combine both approaches. Values from `-f` files are applied first, then `--set`
overrides on top. This is useful when you want a base file plus a one-off override:

<br />

```bash
helm install my-api ./task-api \
  -f production-values.yaml \
  --set image.tag=v1.2.4
```

<br />

##### **Installing and managing releases**
Here is the full lifecycle of a Helm release.

<br />

**Install a release:**

<br />

```bash
# Install from a local chart directory
helm install my-api ./task-api -n task-api --create-namespace

# Install from a repository
helm install my-api my-repo/task-api -n task-api --create-namespace

# Install and wait for all pods to be ready
helm install my-api ./task-api -n task-api --create-namespace --wait --timeout 5m
```

<br />

The `--wait` flag tells Helm to wait until all resources are in a ready state before marking the
release as successful. Combined with `--timeout`, this gives you a clear success or failure signal.
Without `--wait`, Helm marks the release as deployed as soon as the manifests are submitted to the
API server, regardless of whether the pods actually start.

<br />

**Check release status:**

<br />

```bash
# List all releases in a namespace
helm list -n task-api

# Get detailed status of a release
helm status my-api -n task-api

# See the values that were used for the current release
helm get values my-api -n task-api

# See all values (including defaults)
helm get values my-api -n task-api --all

# See the rendered manifests
helm get manifest my-api -n task-api
```

<br />

**Upgrade a release:**

<br />

```bash
# Upgrade with a new image tag
helm upgrade my-api ./task-api -n task-api --set image.tag=v1.3.0

# Upgrade with a values file
helm upgrade my-api ./task-api -n task-api -f production-values.yaml

# Install or upgrade (idempotent, great for CI/CD)
helm upgrade --install my-api ./task-api -n task-api -f production-values.yaml
```

<br />

The `upgrade --install` pattern is the most common in CI/CD pipelines. It installs the release if
it does not exist, or upgrades it if it does. This makes your pipeline idempotent, you can run it
multiple times without errors.

<br />

**View release history:**

<br />

```bash
helm history my-api -n task-api
```

<br />

```plaintext
REVISION  UPDATED                   STATUS      CHART           APP VERSION  DESCRIPTION
1         2026-05-24 10:00:00       superseded  task-api-0.1.0  1.0.0        Install complete
2         2026-05-24 14:30:00       superseded  task-api-0.1.0  1.1.0        Upgrade complete
3         2026-05-24 15:00:00       deployed    task-api-0.2.0  1.2.0        Upgrade complete
```

<br />

**Rollback to a previous revision:**

<br />

```bash
# Rollback to the previous revision
helm rollback my-api -n task-api

# Rollback to a specific revision
helm rollback my-api 1 -n task-api
```

<br />

Rollback is one of the strongest arguments for Helm. If a deployment goes wrong, you can revert to
any previous state in seconds. No need to figure out which YAML files to apply or which image tag
was running before. Helm tracks all of that for you.

<br />

**Uninstall a release:**

<br />

```bash
# Remove the release and all its resources
helm uninstall my-api -n task-api

# Keep the release history (useful for auditing)
helm uninstall my-api -n task-api --keep-history
```

<br />

##### **OCI registries: the modern approach**
Traditional Helm repositories are HTTP servers that host an `index.yaml` file listing all available
charts. They work, but they require maintaining a separate piece of infrastructure.

<br />

The modern approach is to store Helm charts in OCI-compliant container registries, the same
registries you already use for Docker images. GitHub Container Registry (GHCR), Docker Hub, ECR,
GCR, and Azure Container Registry all support Helm OCI charts.

<br />

Here is how to package and push a chart to GHCR:

<br />

```bash
# Log in to GHCR
echo $GITHUB_TOKEN | helm registry login ghcr.io --username your-username --password-stdin

# Package the chart
helm package ./task-api

# This creates task-api-0.1.0.tgz in the current directory

# Push to GHCR
helm push task-api-0.1.0.tgz oci://ghcr.io/your-org/charts

# Pull from GHCR
helm pull oci://ghcr.io/your-org/charts/task-api --version 0.1.0

# Install directly from GHCR
helm install my-api oci://ghcr.io/your-org/charts/task-api --version 0.1.0 -n task-api
```

<br />

The OCI approach has several advantages:

<br />

> * **No index.yaml**: No need to rebuild and host a chart index. The registry handles discovery.
> * **Same infrastructure**: If you already use GHCR for Docker images, you do not need to set up anything else.
> * **Access control**: Registry permissions apply to charts the same way they apply to images.
> * **Immutable tags**: Once you push a version, it cannot be overwritten (depending on registry settings). This guarantees reproducibility.

<br />

In a CI/CD pipeline, you would build and push the chart alongside the Docker image:

<br />

```yaml
# .github/workflows/release.yaml (relevant excerpt)
- name: Push Helm chart to GHCR
  run: |
    echo "${{ secrets.GITHUB_TOKEN }}" | helm registry login ghcr.io \
      --username ${{ github.actor }} --password-stdin
    helm package ./charts/task-api --version ${{ github.ref_name }}
    helm push task-api-${{ github.ref_name }}.tgz oci://ghcr.io/${{ github.repository_owner }}/charts
```

<br />

##### **Chart testing**
Before you install a chart in a real cluster, you should validate it. Helm provides several tools
for this.

<br />

**Linting:**

<br />

```bash
# Check for issues in chart structure and templates
helm lint ./task-api

# Lint with specific values
helm lint ./task-api -f production-values.yaml
```

<br />

`helm lint` catches common mistakes: missing required fields in Chart.yaml, template syntax errors,
indentation problems, and deprecated API versions. Run it in CI on every pull request.

<br />

**Template rendering:**

<br />

```bash
# Render templates without installing
helm template my-api ./task-api

# Render with specific values and save to a file for review
helm template my-api ./task-api -f production-values.yaml > rendered.yaml

# Render and validate against the cluster's API
helm template my-api ./task-api --validate
```

<br />

`helm template` renders the templates locally and prints the resulting YAML. This is incredibly
useful for debugging. If something looks wrong in the output, the problem is in your templates or
values, not in Kubernetes. The `--validate` flag adds API server validation, which catches issues
like using a removed API version.

<br />

**Release testing:**

<br />

```bash
# Run the chart's test pods
helm test my-api -n task-api
```

<br />

Helm supports test hooks. These are pods defined in `templates/tests/` that run when you execute
`helm test`. A typical test verifies that the deployed application is reachable:

<br />

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "task-api.fullname" . }}-test-connection"
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
spec:
  containers:
    - name: wget
      image: busybox
      command: ['wget']
      args: ['{{ include "task-api.fullname" . }}:{{ .Values.service.port }}/health']
  restartPolicy: Never
```

<br />

This pod runs `wget` against the service's health endpoint. If it succeeds, the test passes. If it
fails, you know something is wrong with the deployment.

<br />

##### **Managing multiple charts: Helmfile and ArgoCD**
Once you have more than a handful of charts, you need a way to manage them together. Two tools
stand out.

<br />

**Helmfile** is a declarative spec for deploying multiple Helm charts. Instead of running `helm
install` and `helm upgrade` commands manually, you define everything in a `helmfile.yaml`:

<br />

```yaml
# helmfile.yaml
repositories:
  - name: bitnami
    url: https://charts.bitnami.com/bitnami

releases:
  - name: task-api
    namespace: task-api
    chart: ./charts/task-api
    values:
      - environments/{{ .Environment.Name }}/task-api.yaml

  - name: redis
    namespace: task-api
    chart: bitnami/redis
    version: 18.6.1
    values:
      - environments/{{ .Environment.Name }}/redis.yaml
```

<br />

Then deploy everything with:

<br />

```bash
helmfile -e production apply
```

<br />

**ArgoCD** takes a different approach. Instead of running commands, you define your desired state in
Git and ArgoCD continuously reconciles the cluster to match. ArgoCD has native Helm support, so you
point it at a Git repository containing your chart and values, and it handles the rest:

<br />

```yaml
# ArgoCD Application manifest
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: task-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo
    targetRevision: main
    path: charts/task-api
    helm:
      valueFiles:
        - ../../environments/production/task-api.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: task-api
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
```

<br />

ArgoCD is the GitOps approach. Every change goes through a pull request, gets reviewed, merged to
main, and ArgoCD applies it automatically. No one runs `helm install` or `kubectl apply` manually.
This is how most production teams operate today. If you want to dig deeper into ArgoCD, check out
[GitOps with ArgoCD](/blog/sre-gitops-with-argocd) from the SRE series.

<br />

##### **Common patterns and tips**
Here are some patterns you will encounter often when working with Helm.

<br />

**Use `helm upgrade --install` in CI/CD.** This makes deployments idempotent. Whether the release
exists or not, the command does the right thing.

<br />

**Always set resource requests and limits.** The default values.yaml should include reasonable
resource values. Without them, a single pod can consume all cluster resources.

<br />

**Use the checksum annotation pattern.** As we saw earlier, hashing ConfigMap content into a pod
annotation triggers rolling updates when configuration changes. This saves you from the "I changed
the ConfigMap but nothing happened" surprise.

<br />

**Pin your chart versions.** When installing from a repository, always specify `--version`. Without
it, Helm installs the latest version, which might introduce breaking changes.

<br />

**Keep secrets out of values.yaml.** Never put passwords, API keys, or tokens in values files that
get committed to Git. Use Kubernetes Secrets managed by an external tool like External Secrets
Operator or Sealed Secrets.

<br />

**Use `helm diff` for safe upgrades.** The `helm-diff` plugin shows you exactly what will change
before you upgrade:

<br />

```bash
# Install the diff plugin
helm plugin install https://github.com/databus23/helm-diff

# Preview changes before upgrading
helm diff upgrade my-api ./task-api -f production-values.yaml -n task-api
```

<br />

This is especially valuable in production where you want to review changes before applying them.

<br />

##### **Closing notes**
Helm takes the pain out of managing Kubernetes applications. Instead of juggling raw YAML files
across environments, you define your application once as a chart, parameterize the things that
change, and let Helm handle the rendering, versioning, and lifecycle management.

<br />

In this article we covered what Helm is and why it exists, created a chart from scratch with all
the templates a real application needs, explored Go template syntax including conditionals, loops,
and built-in objects, built reusable helpers, managed releases with install, upgrade, rollback, and
history, pushed charts to OCI registries for modern distribution, and validated everything with
lint, template, and test.

<br />

The key takeaway is that Helm is not just about templating YAML. It is about giving your Kubernetes
deployments a proper lifecycle: versioned releases, configuration management, rollback capability,
and a shared language for your team to talk about what is running where.

<br />

In the next article we will look at monitoring and observability for our Kubernetes workloads,
because deploying an application is only half the job. You also need to know if it is healthy and
performing well.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: Helm Charts",
  author: "Gabriel Garrido",
  description: "Vamos a aprender como empaquetar aplicaciones Kubernetes con Helm, crear charts desde cero, usar Go templates, gestionar releases, pushear a registries OCI, y testear charts...",
  tags: ~w(devops kubernetes helm beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo doce de la serie DevOps desde Cero. En los articulos anteriores aprendimos
como deployear containers a Kubernetes usando manifiestos YAML crudos. Eso funciona bien cuando
tenes un solo servicio con un punado de archivos, pero a medida que tus aplicaciones crecen y
empezas a gestionar multiples entornos, los manifiestos crudos se vuelven dolorosos de mantener.

<br />

Imaginate que tenes un deployment, un service, un ingress, un configmap y un HPA. Ahora multiplica
eso por tres entornos (dev, staging, produccion) donde solo cambian algunos valores: el tag de la
imagen, la cantidad de replicas, el nombre de dominio. De repente estas copiando y pegando archivos
YAML, buscando y reemplazando valores a mano, y rezando para no haberte olvidado de algo. Este es
exactamente el problema que Helm resuelve.

<br />

Helm es el gestor de paquetes para Kubernetes. Te permite definir tu aplicacion como un template
reutilizable, parametrizar las partes que cambian, versionar todo, e instalar o actualizar con un
solo comando. Si alguna vez usaste `apt`, `brew` o `npm`, Helm cumple el mismo rol para Kubernetes.

<br />

En este articulo vamos a cubrir que es Helm y por que existe, crear un chart desde cero, meternos
en la sintaxis de templates y helpers, empaquetar una API TypeScript con todos los recursos que
necesita, gestionar releases con install, upgrade y rollback, pushear charts a registries OCI, y
testear nuestro trabajo. Si queres ver como se usaba Helm hace anos, mira
[Getting started with Helm](/blog/getting_started_with_helm) y
[Deploying my apps with Helm](/blog/deploying_my_apps_with_helm), pero tene en cuenta que esos
articulos son del 2018 y cubren Helm 2 que ya esta deprecado.

<br />

Vamos a ello.

<br />

##### **Que es Helm?**
Helm se autodefine como el gestor de paquetes para Kubernetes, y es una buena descripcion. Hay
cuatro conceptos clave que necesitas entender:

<br />

> * **Chart**: Una coleccion de archivos que describen un conjunto relacionado de recursos Kubernetes. Pensalo como un paquete. Un chart contiene templates, valores por defecto, metadata, y opcionalmente sub-charts para dependencias.
> * **Release**: Una instancia especifica de un chart corriendo en tu cluster. Podes instalar el mismo chart multiples veces con diferentes configuraciones, y cada instalacion es un release separado con su propio nombre e historial.
> * **Repository**: Un lugar donde se almacenan y comparten charts. Puede ser un servidor HTTP tradicional, un repositorio Helm, o un registry de containers compatible con OCI (el enfoque moderno).
> * **Values**: Los parametros de configuracion que personalizan un chart para un deployment especifico. Provees values para sobreescribir los defaults del chart, y Helm los usa para renderizar los templates en manifiestos Kubernetes validos.

<br />

Asi es como encajan estas piezas:

<br />

```plaintext
Chart (definicion del paquete)
  + Values (tu configuracion)
  = Release (instancia corriendo en tu cluster)
    ├── Deployment (renderizado desde template)
    ├── Service (renderizado desde template)
    ├── Ingress (renderizado desde template)
    └── ConfigMap (renderizado desde template)
```

<br />

##### **Por que Helm en vez de manifiestos crudos**
Tal vez te preguntes si realmente necesitas otra herramienta. Esto es lo que Helm te da que el YAML
crudo no:

<br />

> * **Templating**: Escribi tus manifiestos una vez con placeholders, y renderizalos con diferentes valores para cada entorno. Se acabo el copiar y pegar archivos YAML.
> * **Versionado**: Cada chart tiene una version. Cada release trackea que version se instalo y que values se usaron. Siempre sabes que esta corriendo.
> * **Rollback**: Hiciste un deployment malo? `helm rollback` te lleva al estado anterior en segundos. Helm mantiene un historial de cada revision del release.
> * **Gestion de dependencias**: Tu aplicacion depende de Redis? Agregalo como dependencia del chart y Helm instala ambos juntos.
> * **Compartir**: Empaqueta tu chart y pushealo a un registry. Cualquiera de tu equipo (o del mundo) puede instalarlo con un solo comando.
> * **Lifecycle hooks**: Correr jobs antes o despues de install, upgrade o delete. Genial para migraciones de base de datos, cache warming o health checks.

<br />

La alternativa es gestionar YAML crudo con Kustomize o scripts hechos a mano. Kustomize viene
integrado en kubectl y funciona bien para escenarios simples de overlay, pero no te da versionado,
rollback ni historial de releases. Para la mayoria de los equipos, Helm es la mejor opcion una vez
que vas mas alla de deployments triviales.

<br />

##### **Helm 3 vs Helm 2: breve historia**
Si viste tutoriales viejos de Helm, mencionan algo llamado Tiller. Era un componente server-side
que Helm 2 requeria para correr dentro de tu cluster. Tiller tenia permisos de cluster-admin y
era una preocupacion de seguridad significativa.

<br />

Helm 3 (lanzado en noviembre de 2019) elimino Tiller por completo. Esto es lo que cambio:

<br />

> * **Sin Tiller**: Helm ahora habla directamente con la API de Kubernetes usando tus credenciales del kubeconfig. No mas deployear un pod privilegiado en tu cluster.
> * **Three-way strategic merge**: Helm 3 compara el manifiesto viejo, el nuevo y el estado actual en el cluster. Esto significa que los cambios manuales a recursos se detectan y manejan correctamente durante los upgrades.
> * **Release namespaces**: Los releases se guardan como secrets de Kubernetes en el namespace donde se deployean, no en un namespace central de Tiller.
> * **Validacion con JSON Schema**: Los charts pueden incluir un archivo `values.schema.json` para validar los values provistos por el usuario antes de renderizar.
> * **Soporte de registries OCI**: Los charts se pueden almacenar en registries de containers como Docker Hub, GHCR o ECR, igual que las imagenes de containers.

<br />

Si empezas hoy, solo vas a usar Helm 3. El binario `helm` que instalas del sitio oficial es
Helm 3. Helm 2 llego a su end of life en noviembre de 2020, asi que no hay razon para usarlo
en proyectos nuevos.

<br />

##### **Instalando Helm**
Instalar Helm es sencillo. Elegi el metodo que corresponda a tu sistema:

<br />

```bash
# macOS con Homebrew
brew install helm

# Linux con el script oficial de instalacion
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Arch Linux
pacman -S helm

# Verificar la instalacion
helm version
```

<br />

Deberias ver una salida como:

<br />

```plaintext
version.BuildInfo{Version:"v3.17.x", GitCommit:"...", GitTreeState:"clean", GoVersion:"go1.23.x"}
```

<br />

##### **Creando un chart desde cero**
Vamos a crear nuestro primer chart. Helm provee un comando de scaffolding:

<br />

```bash
helm create task-api
```

<br />

Esto crea una estructura de directorios con todo lo que necesitas:

<br />

```plaintext
task-api/
├── Chart.yaml          # Metadata: nombre, version, descripcion
├── values.yaml         # Valores de configuracion por defecto
├── charts/             # Sub-charts (dependencias)
├── templates/          # Templates de manifiestos Kubernetes
│   ├── _helpers.tpl    # Helpers de templates con nombre
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── serviceaccount.yaml
│   ├── NOTES.txt       # Instrucciones post-instalacion mostradas al usuario
│   └── tests/
│       └── test-connection.yaml
└── .helmignore         # Archivos a excluir al empaquetar
```

<br />

Vamos a repasar los archivos clave uno por uno.

<br />

##### **Chart.yaml: la metadata del chart**
Este archivo define quien es tu chart. Pensalo como un `package.json` para Helm:

<br />

```yaml
apiVersion: v2
name: task-api
description: A Helm chart for the Task API TypeScript application
type: application
version: 0.1.0
appVersion: "1.0.0"
```

<br />

> * **apiVersion**: Siempre `v2` para charts de Helm 3. Helm 2 usaba `v1`.
> * **name**: El nombre del chart. Debe ser minuscula y puede contener guiones.
> * **description**: Una descripcion corta que se muestra al buscar en repositorios.
> * **type**: `application` (deployea recursos) o `library` (solo provee helpers para otros charts).
> * **version**: La version del chart. Sigue versionado semantico. Bumpeala cada vez que cambies el chart.
> * **appVersion**: La version de la aplicacion que se deployea. Es informativa y no afecta el comportamiento del chart.

<br />

La distincion entre `version` y `appVersion` es importante. La version del chart trackea cambios
al chart en si (templates, defaults). La version de la app trackea que version de tu aplicacion
deployea el chart. Evolucionan independientemente.

<br />

##### **values.yaml: la configuracion por defecto**
Este es el archivo mas importante de un chart. Define cada parametro configurable con defaults
razonables:

<br />

```yaml
replicaCount: 2

image:
  repository: ghcr.io/your-org/task-api
  pullPolicy: IfNotPresent
  tag: ""

nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

service:
  type: ClusterIP
  port: 3000

ingress:
  enabled: false
  className: "traefik"
  annotations: {}
  hosts:
    - host: task-api.example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

env:
  NODE_ENV: production
  PORT: "3000"
```

<br />

Algunos principios para estructurar values:

<br />

> * **Agrupa configuraciones relacionadas**: Pone todos los valores de imagen bajo `image`, toda la configuracion de ingress bajo `ingress`, y asi. Esto hace facil encontrar y sobreescribir cosas.
> * **Provee defaults razonables**: El chart deberia funcionar con cero overrides para un deployment basico. Las configuraciones especificas de produccion (nombres de dominio, limites de recursos) son lo que los usuarios sobreescriben.
> * **Usa claves planas donde sea posible**: Los values profundamente anidados son mas dificiles de sobreescribir con `--set`. Mantene el anidamiento razonable.
> * **Documenta con comentarios**: Agrega comentarios explicando que hace cada valor, cuales son las opciones validas, y que significa el default.

<br />

##### **Sintaxis de templates: Go templates**
Los templates de Helm usan el paquete `text/template` de Go con algunas funciones extra de la
libreria Sprig. Si nunca viste Go templates antes, aca tenes una introduccion rapida.

<br />

La sintaxis basica usa dobles llaves `{{ }}` para insertar contenido dinamico. Todo lo que esta
fuera de las llaves se renderiza tal cual. Veamos los patrones principales:

<br />

```yaml
# Sustitucion simple de valores
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-api
  labels:
    app: {{ .Chart.Name }}
    version: {{ .Chart.AppVersion }}
spec:
  replicas: {{ .Values.replicaCount }}
```

<br />

Helm provee varios objetos built-in que podes acceder en los templates:

<br />

> * **`.Values`**: El resultado mergeado de values.yaml y cualquier override que el usuario provea. De aca viene la mayoria de tu data dinamica.
> * **`.Release`**: Informacion sobre el release actual. `.Release.Name` es el nombre del release, `.Release.Namespace` es el namespace, `.Release.IsUpgrade` te dice si es un upgrade.
> * **`.Chart`**: Contenidos de Chart.yaml. `.Chart.Name`, `.Chart.Version`, `.Chart.AppVersion`.
> * **`.Template`**: Informacion sobre el archivo de template actual. Se usa mayormente para debugging.
> * **`.Capabilities`**: Informacion sobre el cluster Kubernetes. `.Capabilities.APIVersions` te permite verificar si una API version especifica existe.

<br />

##### **Condicionales y loops**
Los templates soportan flujo de control. Asi es como incluir condicionalmente un ingress y
loopear sobre hosts:

<br />

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "task-api.fullname" . }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ include "task-api.fullname" $ }}
                port:
                  number: {{ $.Values.service.port }}
          {{- end }}
    {{- end }}
  {{- if .Values.ingress.tls }}
  tls:
    {{- toYaml .Values.ingress.tls | nindent 4 }}
  {{- end }}
{{- end }}
```

<br />

Algunas cosas para notar:

<br />

> * **`{{- ... }}`**: El guion recorta el whitespace antes del tag. Sin el, te quedan lineas en blanco en la salida.
> * **`range`**: Itera sobre una lista o mapa. Dentro del loop, `.` se refiere al item actual.
> * **`$`**: Se refiere al scope raiz. Cuando estas dentro de un bloque `range`, `.` cambia al item actual. Usa `$` para acceder a `.Values` o `.Release` desde dentro de un loop.
> * **`with`**: Establece el scope de `.` al objeto especificado. Si el objeto esta vacio, el bloque se saltea por completo. Funciona como un "si no esta vacio" y "establecer scope" combinados.
> * **`toYaml`**: Convierte una estructura de datos Go a YAML. Combinado con `nindent`, maneja la indentacion correctamente.
> * **`quote`**: Envuelve el valor en comillas dobles. Siempre cita hostnames y strings que puedan contener caracteres especiales.

<br />

##### **Helpers: _helpers.tpl**
El archivo `_helpers.tpl` (el prefijo guion bajo le dice a Helm que no lo renderice como un
manifiesto) contiene templates con nombre reutilizables. Son como funciones que podes llamar desde
cualquier template:

<br />

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "task-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "task-api.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "task-api.labels" -}}
helm.sh/chart: {{ include "task-api.chart" . }}
{{ include "task-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "task-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "task-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

<br />

Llamar estos templates con nombre se hace usando `include`:

<br />

```yaml
metadata:
  name: {{ include "task-api.fullname" . }}
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
```

<br />

Por que `include` en vez de `template`? La accion `template` escribe texto directamente y no se
puede pipear a otras funciones. `include` retorna la salida como string, asi que la podes pipear a
`nindent`, `trim`, o cualquier otra funcion. Siempre preferi `include` sobre `template`.

<br />

Las llamadas a `trunc 63` a lo largo de los helpers no son arbitrarias. Las labels y nombres de
Kubernetes tienen un limite de 63 caracteres (reglas de DNS label del RFC 1123). Los helpers
aplican esto automaticamente.

<br />

##### **Empaquetando una API TypeScript: el chart completo**
Construyamos un chart completo para nuestra API de tareas de la serie. Necesitamos un deployment,
un service, un ingress, un configmap y un HPA. Ya vimos el ingress arriba, asi que cubramos el
resto.

<br />

**Template de Deployment** (`templates/deployment.yaml`):

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "task-api.fullname" . }}
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "task-api.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "task-api.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "task-api.serviceAccountName" . }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.port }}
              protocol: TCP
          envFrom:
            - configMapRef:
                name: {{ include "task-api.fullname" . }}-config
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

<br />

Nota la anotacion `checksum/config` en el template del pod. Este es un patron comun de Helm.
Cuando cambias un ConfigMap, Kubernetes no reinicia automaticamente los pods que lo usan. Al
hashear el contenido del ConfigMap en una anotacion, cualquier cambio al ConfigMap produce un hash
diferente, lo que dispara un rolling update. Inteligente y simple.

<br />

Tambien nota que cuando autoscaling esta habilitado, nos salteamos el campo `replicas`. El HPA
gestiona la cantidad de replicas en ese caso, y setearlo en el deployment causaria conflictos.

<br />

**Template de ConfigMap** (`templates/configmap.yaml`):

<br />

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "task-api.fullname" . }}-config
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
data:
  {{- range $key, $value := .Values.env }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
```

<br />

Esto itera sobre cada par clave-valor en `.Values.env` y crea una entrada en el ConfigMap. Agregas
nuevas variables de entorno simplemente agregandolas a values.yaml, sin necesidad de cambiar el
template.

<br />

**Template de Service** (`templates/service.yaml`):

<br />

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "task-api.fullname" . }}
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "task-api.selectorLabels" . | nindent 4 }}
```

<br />

**Template de HPA** (`templates/hpa.yaml`):

<br />

```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "task-api.fullname" . }}
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "task-api.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
{{- end }}
```

<br />

El template completo del HPA esta envuelto en un bloque `if`. Cuando autoscaling esta deshabilitado
(el default), este archivo no produce ninguna salida.

<br />

##### **Sobreescribiendo values**
Hay dos formas principales de sobreescribir los defaults de values.yaml cuando instalas o
actualizas un release.

<br />

**Usando `--set` para valores individuales:**

<br />

```bash
helm install my-api ./task-api \
  --set image.tag=v1.2.3 \
  --set replicaCount=3 \
  --set ingress.enabled=true
```

<br />

**Usando `-f` (o `--values`) con un archivo:**

<br />

```bash
helm install my-api ./task-api -f production-values.yaml
```

<br />

Donde `production-values.yaml` podria verse asi:

<br />

```yaml
replicaCount: 3

image:
  tag: v1.2.3

ingress:
  enabled: true
  className: traefik
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: api.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: api-tls
      hosts:
        - api.example.com

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70

env:
  NODE_ENV: production
  PORT: "3000"
  LOG_LEVEL: info
```

<br />

El enfoque de archivo es mejor para cualquier cosa mas alla de un par de valores. Podes versionar
tus archivos especificos por entorno (`dev-values.yaml`, `staging-values.yaml`,
`production-values.yaml`) y obtener todos los beneficios del historial de Git para cambios de
configuracion.

<br />

Tambien podes combinar ambos enfoques. Los values de archivos `-f` se aplican primero, despues los
overrides de `--set` encima. Esto es util cuando queres un archivo base mas un override puntual:

<br />

```bash
helm install my-api ./task-api \
  -f production-values.yaml \
  --set image.tag=v1.2.4
```

<br />

##### **Instalando y gestionando releases**
Aca tenes el ciclo de vida completo de un release de Helm.

<br />

**Instalar un release:**

<br />

```bash
# Instalar desde un directorio de chart local
helm install my-api ./task-api -n task-api --create-namespace

# Instalar desde un repositorio
helm install my-api my-repo/task-api -n task-api --create-namespace

# Instalar y esperar a que todos los pods esten ready
helm install my-api ./task-api -n task-api --create-namespace --wait --timeout 5m
```

<br />

El flag `--wait` le dice a Helm que espere hasta que todos los recursos esten en estado ready antes
de marcar el release como exitoso. Combinado con `--timeout`, te da una senal clara de exito o
fallo. Sin `--wait`, Helm marca el release como deployed apenas los manifiestos se envian al API
server, sin importar si los pods realmente arrancan.

<br />

**Verificar estado del release:**

<br />

```bash
# Listar todos los releases en un namespace
helm list -n task-api

# Obtener estado detallado de un release
helm status my-api -n task-api

# Ver los values que se usaron para el release actual
helm get values my-api -n task-api

# Ver todos los values (incluyendo defaults)
helm get values my-api -n task-api --all

# Ver los manifiestos renderizados
helm get manifest my-api -n task-api
```

<br />

**Actualizar un release:**

<br />

```bash
# Upgrade con un nuevo image tag
helm upgrade my-api ./task-api -n task-api --set image.tag=v1.3.0

# Upgrade con un archivo de values
helm upgrade my-api ./task-api -n task-api -f production-values.yaml

# Install o upgrade (idempotente, genial para CI/CD)
helm upgrade --install my-api ./task-api -n task-api -f production-values.yaml
```

<br />

El patron `upgrade --install` es el mas comun en pipelines de CI/CD. Instala el release si no
existe, o lo actualiza si ya existe. Esto hace tu pipeline idempotente, podes correrlo multiples
veces sin errores.

<br />

**Ver historial de releases:**

<br />

```bash
helm history my-api -n task-api
```

<br />

```plaintext
REVISION  UPDATED                   STATUS      CHART           APP VERSION  DESCRIPTION
1         2026-05-24 10:00:00       superseded  task-api-0.1.0  1.0.0        Install complete
2         2026-05-24 14:30:00       superseded  task-api-0.1.0  1.1.0        Upgrade complete
3         2026-05-24 15:00:00       deployed    task-api-0.2.0  1.2.0        Upgrade complete
```

<br />

**Rollback a una revision anterior:**

<br />

```bash
# Rollback a la revision anterior
helm rollback my-api -n task-api

# Rollback a una revision especifica
helm rollback my-api 1 -n task-api
```

<br />

El rollback es uno de los argumentos mas fuertes a favor de Helm. Si un deployment sale mal, podes
volver a cualquier estado anterior en segundos. No necesitas averiguar que archivos YAML aplicar o
que image tag estaba corriendo antes. Helm trackea todo eso por vos.

<br />

**Desinstalar un release:**

<br />

```bash
# Eliminar el release y todos sus recursos
helm uninstall my-api -n task-api

# Mantener el historial del release (util para auditoria)
helm uninstall my-api -n task-api --keep-history
```

<br />

##### **Registries OCI: el enfoque moderno**
Los repositorios Helm tradicionales son servidores HTTP que hostean un archivo `index.yaml`
listando todos los charts disponibles. Funcionan, pero requieren mantener una pieza separada de
infraestructura.

<br />

El enfoque moderno es almacenar charts Helm en registries de containers compatibles con OCI, los
mismos registries que ya usas para imagenes Docker. GitHub Container Registry (GHCR), Docker Hub,
ECR, GCR, y Azure Container Registry todos soportan charts Helm OCI.

<br />

Asi es como empaquetar y pushear un chart a GHCR:

<br />

```bash
# Login a GHCR
echo $GITHUB_TOKEN | helm registry login ghcr.io --username your-username --password-stdin

# Empaquetar el chart
helm package ./task-api

# Esto crea task-api-0.1.0.tgz en el directorio actual

# Push a GHCR
helm push task-api-0.1.0.tgz oci://ghcr.io/your-org/charts

# Pull desde GHCR
helm pull oci://ghcr.io/your-org/charts/task-api --version 0.1.0

# Instalar directamente desde GHCR
helm install my-api oci://ghcr.io/your-org/charts/task-api --version 0.1.0 -n task-api
```

<br />

El enfoque OCI tiene varias ventajas:

<br />

> * **Sin index.yaml**: No necesitas reconstruir y hostear un indice de charts. El registry se encarga del descubrimiento.
> * **Misma infraestructura**: Si ya usas GHCR para imagenes Docker, no necesitas configurar nada mas.
> * **Control de acceso**: Los permisos del registry aplican a charts de la misma forma que aplican a imagenes.
> * **Tags inmutables**: Una vez que pusheas una version, no se puede sobreescribir (dependiendo de la configuracion del registry). Esto garantiza reproducibilidad.

<br />

En un pipeline de CI/CD, construirias y pushearias el chart junto con la imagen Docker:

<br />

```yaml
# .github/workflows/release.yaml (extracto relevante)
- name: Push Helm chart to GHCR
  run: |
    echo "${{ secrets.GITHUB_TOKEN }}" | helm registry login ghcr.io \
      --username ${{ github.actor }} --password-stdin
    helm package ./charts/task-api --version ${{ github.ref_name }}
    helm push task-api-${{ github.ref_name }}.tgz oci://ghcr.io/${{ github.repository_owner }}/charts
```

<br />

##### **Testeando charts**
Antes de instalar un chart en un cluster real, deberias validarlo. Helm provee varias herramientas
para esto.

<br />

**Linting:**

<br />

```bash
# Verificar problemas en la estructura del chart y templates
helm lint ./task-api

# Lint con values especificos
helm lint ./task-api -f production-values.yaml
```

<br />

`helm lint` atrapa errores comunes: campos requeridos faltantes en Chart.yaml, errores de sintaxis
en templates, problemas de indentacion, y API versions deprecadas. Correlo en CI en cada pull
request.

<br />

**Renderizado de templates:**

<br />

```bash
# Renderizar templates sin instalar
helm template my-api ./task-api

# Renderizar con values especificos y guardar a un archivo para revisar
helm template my-api ./task-api -f production-values.yaml > rendered.yaml

# Renderizar y validar contra la API del cluster
helm template my-api ./task-api --validate
```

<br />

`helm template` renderiza los templates localmente y printea el YAML resultante. Esto es
increiblemente util para debugging. Si algo se ve mal en la salida, el problema esta en tus
templates o values, no en Kubernetes. El flag `--validate` agrega validacion del API server, lo
que atrapa problemas como usar una API version removida.

<br />

**Testing de releases:**

<br />

```bash
# Correr los test pods del chart
helm test my-api -n task-api
```

<br />

Helm soporta test hooks. Son pods definidos en `templates/tests/` que se ejecutan cuando corres
`helm test`. Un test tipico verifica que la aplicacion deployeada es alcanzable:

<br />

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "task-api.fullname" . }}-test-connection"
  labels:
    {{- include "task-api.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
spec:
  containers:
    - name: wget
      image: busybox
      command: ['wget']
      args: ['{{ include "task-api.fullname" . }}:{{ .Values.service.port }}/health']
  restartPolicy: Never
```

<br />

Este pod ejecuta `wget` contra el endpoint de health del service. Si tiene exito, el test pasa. Si
falla, sabes que algo anda mal con el deployment.

<br />

##### **Gestionando multiples charts: Helmfile y ArgoCD**
Una vez que tenes mas de un punado de charts, necesitas una forma de gestionarlos juntos. Dos
herramientas se destacan.

<br />

**Helmfile** es una spec declarativa para deployear multiples charts Helm. En vez de correr
comandos `helm install` y `helm upgrade` manualmente, definis todo en un `helmfile.yaml`:

<br />

```yaml
# helmfile.yaml
repositories:
  - name: bitnami
    url: https://charts.bitnami.com/bitnami

releases:
  - name: task-api
    namespace: task-api
    chart: ./charts/task-api
    values:
      - environments/{{ .Environment.Name }}/task-api.yaml

  - name: redis
    namespace: task-api
    chart: bitnami/redis
    version: 18.6.1
    values:
      - environments/{{ .Environment.Name }}/redis.yaml
```

<br />

Despues deployeas todo con:

<br />

```bash
helmfile -e production apply
```

<br />

**ArgoCD** tiene un enfoque diferente. En vez de correr comandos, definis tu estado deseado en Git
y ArgoCD continuamente reconcilia el cluster para matchear. ArgoCD tiene soporte nativo de Helm,
asi que lo apuntas a un repositorio Git que contiene tu chart y values, y el se encarga del resto:

<br />

```yaml
# Manifiesto de Application de ArgoCD
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: task-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo
    targetRevision: main
    path: charts/task-api
    helm:
      valueFiles:
        - ../../environments/production/task-api.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: task-api
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
```

<br />

ArgoCD es el enfoque GitOps. Cada cambio pasa por un pull request, se revisa, se mergea a main, y
ArgoCD lo aplica automaticamente. Nadie corre `helm install` o `kubectl apply` manualmente. Asi es
como operan la mayoria de los equipos de produccion hoy. Si queres profundizar en ArgoCD, mira
[GitOps with ArgoCD](/blog/sre-gitops-with-argocd) de la serie SRE.

<br />

##### **Patrones comunes y tips**
Aca hay algunos patrones que vas a encontrar seguido al trabajar con Helm.

<br />

**Usa `helm upgrade --install` en CI/CD.** Esto hace los deployments idempotentes. Ya sea que el
release exista o no, el comando hace lo correcto.

<br />

**Siempre setea resource requests y limits.** El values.yaml por defecto deberia incluir valores de
recursos razonables. Sin ellos, un solo pod puede consumir todos los recursos del cluster.

<br />

**Usa el patron de anotacion checksum.** Como vimos antes, hashear el contenido del ConfigMap en
una anotacion del pod dispara rolling updates cuando la configuracion cambia. Esto te salva de la
sorpresa "cambie el ConfigMap pero no paso nada."

<br />

**Pinea las versiones de tus charts.** Cuando instalas desde un repositorio, siempre especifica
`--version`. Sin el, Helm instala la ultima version, que podria introducir breaking changes.

<br />

**Mantene los secrets fuera de values.yaml.** Nunca pongas passwords, API keys o tokens en archivos
de values que se commitean a Git. Usa Kubernetes Secrets gestionados por una herramienta externa
como External Secrets Operator o Sealed Secrets.

<br />

**Usa `helm diff` para upgrades seguros.** El plugin `helm-diff` te muestra exactamente que va a
cambiar antes de upgradear:

<br />

```bash
# Instalar el plugin diff
helm plugin install https://github.com/databus23/helm-diff

# Previsualizar cambios antes de upgradear
helm diff upgrade my-api ./task-api -f production-values.yaml -n task-api
```

<br />

Esto es especialmente valioso en produccion donde queres revisar los cambios antes de aplicarlos.

<br />

##### **Notas finales**
Helm saca el dolor de gestionar aplicaciones Kubernetes. En vez de hacer malabares con archivos
YAML crudos entre entornos, definis tu aplicacion una vez como chart, parametrizas las cosas que
cambian, y dejas que Helm se encargue del renderizado, versionado y gestion del ciclo de vida.

<br />

En este articulo cubrimos que es Helm y por que existe, creamos un chart desde cero con todos los
templates que una aplicacion real necesita, exploramos la sintaxis de Go templates incluyendo
condicionales, loops y objetos built-in, construimos helpers reutilizables, gestionamos releases
con install, upgrade, rollback e historial, pusheamos charts a registries OCI para distribucion
moderna, y validamos todo con lint, template y test.

<br />

El takeaway clave es que Helm no se trata solo de templatear YAML. Se trata de darle a tus
deployments de Kubernetes un ciclo de vida apropiado: releases versionados, gestion de
configuracion, capacidad de rollback, y un lenguaje compartido para que tu equipo hable de que
esta corriendo donde.

<br />

En el proximo articulo vamos a ver monitoreo y observabilidad para nuestros workloads de
Kubernetes, porque deployear una aplicacion es solo la mitad del trabajo. Tambien necesitas saber
si esta sana y con buen rendimiento.

<br />

Espero que te haya resultado util y lo hayas disfrutado! Hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en las [fuentes aca](https://github.com/kainlite/tr)

<br />
