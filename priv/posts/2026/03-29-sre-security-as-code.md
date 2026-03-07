%{
  title: "SRE: Security as Code",
  author: "Gabriel Garrido",
  description: "We will explore security as code practices for Kubernetes, from OPA Gatekeeper policies and Pod Security Standards to image scanning with Trivy, network policies, runtime security with Falco, and supply chain security...",
  tags: ~w(sre kubernetes security opa policy),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In the previous articles we covered [SLIs and SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[incident management](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observability](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[capacity planning](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[secrets management](/blog/sre-secrets-management-in-kubernetes),
[cost optimization](/blog/sre-cost-optimization-in-the-cloud),
[dependency management](/blog/sre-dependency-management-and-graceful-degradation),
[database reliability](/blog/sre-database-reliability), and
[release engineering](/blog/sre-release-engineering-and-progressive-delivery). All of those topics assume that
your cluster and workloads are secure, but security is often treated as an afterthought or someone else's problem.

<br />

That stops today. Security is an SRE concern because a security incident is just another type of incident that
burns your error budget, erodes user trust, and creates operational chaos. The shift-left approach means we define
security policies as code, enforce them automatically, and treat security violations the same way we treat SLO
breaches: with measurable indicators, automated responses, and continuous improvement.

<br />

In this article we are going to cover the full security-as-code stack for Kubernetes: admission control with OPA
Gatekeeper, Pod Security Standards, network policies, image scanning in CI, RBAC hardening, audit logging,
runtime security with Falco, and supply chain security with Cosign and Kyverno. All as code, all automated.

<br />

Let's get into it.

<br />

##### **OPA and Gatekeeper policies**
Open Policy Agent (OPA) is a general-purpose policy engine, and Gatekeeper is the Kubernetes-native way to use it.
Gatekeeper acts as an admission controller that intercepts every request to the Kubernetes API server and evaluates
it against your policies before allowing or denying it.

<br />

The beauty of this approach is that your security policies become code that lives in Git, gets reviewed in PRs, and
is enforced automatically. No more hoping that developers remember to add the right labels or avoid privileged
containers.

<br />

**Installing Gatekeeper**

Getting Gatekeeper into your cluster is straightforward with Helm:

<br />

```sql
# Install Gatekeeper via Helm
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --set replicas=3 \
  --set audit.replicas=2 \
  --set audit.logLevel=INFO
```

<br />

Or if you prefer a declarative ArgoCD approach:

<br />

```yaml
# argocd/gatekeeper-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gatekeeper
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://open-policy-agent.github.io/gatekeeper/charts
    chart: gatekeeper
    targetRevision: 3.15.0
    helm:
      values: |
        replicas: 3
        audit:
          replicas: 2
          logLevel: INFO
  destination:
    server: https://kubernetes.default.svc
    namespace: gatekeeper-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

**ConstraintTemplate: Require labels**

Gatekeeper uses two resources: ConstraintTemplates (the policy logic in Rego) and Constraints (how to apply them).
Here is a template that requires specific labels on all resources:

<br />

```yaml
# policies/templates/require-labels.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels

        violation[{"msg": msg, "details": {"missing_labels": missing}}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Resource is missing required labels: %v", [missing])
        }
```

<br />

And the constraint that applies it to all namespaces:

<br />

```yaml
# policies/constraints/require-labels.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: all-must-have-owner
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Namespace"]
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet"]
  parameters:
    labels:
      - "app.kubernetes.io/name"
      - "app.kubernetes.io/managed-by"
      - "team"
```

<br />

**ConstraintTemplate: Block privileged pods**

This one is critical. Privileged containers have full access to the host, which means a container escape gives an
attacker root on the node:

<br />

```yaml
# policies/templates/block-privileged.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sblockprivileged
spec:
  crd:
    spec:
      names:
        kind: K8sBlockPrivileged
      validation:
        openAPIV3Schema:
          type: object
          properties:
            allowedImages:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sblockprivileged

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          container.securityContext.privileged == true
          msg := sprintf("Privileged containers are not allowed: %v", [container.name])
        }

        violation[{"msg": msg}] {
          container := input.review.object.spec.initContainers[_]
          container.securityContext.privileged == true
          msg := sprintf("Privileged init containers are not allowed: %v", [container.name])
        }
```

<br />

```yaml
# policies/constraints/block-privileged.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockPrivileged
metadata:
  name: no-privileged-containers
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet", "DaemonSet"]
    excludedNamespaces:
      - kube-system
      - gatekeeper-system
```

<br />

**ConstraintTemplate: Enforce image registry**

You probably do not want random Docker Hub images running in production. This policy restricts images to your
trusted registries:

<br />

```yaml
# policies/templates/allowed-registries.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sallowedregistries
spec:
  crd:
    spec:
      names:
        kind: K8sAllowedRegistries
      validation:
        openAPIV3Schema:
          type: object
          properties:
            registries:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sallowedregistries

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not registry_allowed(container.image)
          msg := sprintf("Image '%v' is from an untrusted registry. Allowed registries: %v",
            [container.image, input.parameters.registries])
        }

        violation[{"msg": msg}] {
          container := input.review.object.spec.initContainers[_]
          not registry_allowed(container.image)
          msg := sprintf("Init container image '%v' is from an untrusted registry. Allowed registries: %v",
            [container.image, input.parameters.registries])
        }

        registry_allowed(image) {
          registry := input.parameters.registries[_]
          startswith(image, registry)
        }
```

<br />

```yaml
# policies/constraints/allowed-registries.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRegistries
metadata:
  name: trusted-registries-only
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet", "DaemonSet"]
    excludedNamespaces:
      - kube-system
  parameters:
    registries:
      - "ghcr.io/kainlite/"
      - "docker.io/kainlite/"
      - "registry.k8s.io/"
      - "quay.io/"
```

<br />

With these three policies alone you already have a strong foundation: every resource needs ownership labels,
no one can run privileged containers, and only images from trusted registries are allowed.

<br />

##### **Pod Security Standards**
Kubernetes ships with built-in Pod Security Standards (PSS) that provide three levels of security profiles. These
work at the namespace level and do not require any external controller like Gatekeeper. They are a great starting
point if you want something simple that covers the basics.

<br />

The three profiles are:

<br />

> * **Privileged**: Unrestricted. Allows everything. Used for system-level workloads like CNI plugins and monitoring agents.
> * **Baseline**: Prevents known privilege escalations. Blocks hostNetwork, hostPID, privileged containers, and most dangerous capabilities. Good default for most workloads.
> * **Restricted**: Heavily restricted. Requires non-root, drops all capabilities, disallows privilege escalation. The gold standard for application workloads.

<br />

**Namespace-level enforcement**

You apply PSS profiles using labels on namespaces. There are three modes:

<br />

> * **enforce**: Rejects pods that violate the policy
> * **audit**: Allows pods but logs violations
> * **warn**: Allows pods but shows a warning to the user

<br />

A good rollout strategy is to start with warn and audit, review violations, fix them, and then switch to enforce:

<br />

```yaml
# namespaces/production.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

<br />

```yaml
# namespaces/staging.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: staging
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

<br />

```yaml
# namespaces/monitoring.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

<br />

**Making your pods compliant**

For the restricted profile, your pods need to meet several requirements. Here is what a compliant pod spec looks
like:

<br />

```yaml
# deployments/tr-web.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tr-web
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: tr-web
  template:
    metadata:
      labels:
        app.kubernetes.io/name: tr-web
        app.kubernetes.io/managed-by: argocd
        team: platform
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: tr-web
          image: ghcr.io/kainlite/tr:latest
          ports:
            - containerPort: 4000
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
```

<br />

The key security settings are: `runAsNonRoot`, `allowPrivilegeEscalation: false`, dropping all capabilities,
read-only root filesystem, and a seccomp profile. If any of those are missing, the restricted profile will reject
the pod.

<br />

##### **Network policies**
By default, every pod in Kubernetes can talk to every other pod. That is terrible for security. If an attacker
compromises one pod, they can freely move laterally to every other service in the cluster. Network policies fix
this by defining which traffic is allowed.

<br />

**Default deny everything**

The first thing you should do is create a default deny policy for every namespace. This blocks all traffic that
is not explicitly allowed:

<br />

```yaml
# network-policies/default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

<br />

Now nothing can talk to anything. Time to allow the traffic you actually need.

<br />

**Allow specific traffic**

Here is a policy that allows the web frontend to receive traffic from the ingress controller and talk to the
database:

<br />

```yaml
# network-policies/tr-web.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-tr-web
  namespace: production
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: tr-web
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
          podSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
      ports:
        - protocol: TCP
          port: 4000
  egress:
    # Allow DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Allow database access
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: postgresql
      ports:
        - protocol: TCP
          port: 5432
```

<br />

**Cilium network policies**

If you are using Cilium as your CNI, you get access to more powerful network policies that can filter at L7 (HTTP,
gRPC, DNS):

<br />

```yaml
# cilium-policies/tr-web-l7.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: tr-web-l7-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: tr-web
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: ingress-nginx
            io.kubernetes.pod.namespace: ingress-nginx
      toPorts:
        - ports:
            - port: "4000"
              protocol: TCP
          rules:
            http:
              - method: GET
              - method: POST
                path: "/api/.*"
              - method: HEAD
  egress:
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: postgresql
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
    # DNS policy
    - toEndpoints:
        - matchLabels:
            k8s-app: kube-dns
            io.kubernetes.pod.namespace: kube-system
      toPorts:
        - ports:
            - port: "53"
              protocol: ANY
          rules:
            dns:
              - matchPattern: "*.production.svc.cluster.local"
              - matchPattern: "*.kube-system.svc.cluster.local"
```

<br />

The L7 filtering is incredibly powerful. You can restrict not just which pods can talk to each other but also
which HTTP methods and paths are allowed. This means even if an attacker compromises the web pod, they can only
make the exact API calls that the web pod is supposed to make.

<br />

##### **Image scanning in CI**
Catching vulnerabilities before they reach your cluster is much better than detecting them at runtime. Trivy is
an excellent open-source scanner that checks container images for known CVEs, misconfigurations, and exposed
secrets.

<br />

**Trivy in GitHub Actions**

Here is a complete CI workflow that scans your images and blocks the deployment if high-severity vulnerabilities
are found:

<br />

```hcl
# .github/workflows/security-scan.yaml
name: Security Scan

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  trivy-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: |
          docker build -t ghcr.io/kainlite/tr:${{ github.sha }} .

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ghcr.io/kainlite/tr:${{ github.sha }}
          format: table
          exit-code: 1
          ignore-unfixed: true
          vuln-type: os,library
          severity: CRITICAL,HIGH
          output: trivy-results.txt

      - name: Run Trivy for SARIF output
        uses: aquasecurity/trivy-action@master
        if: always()
        with:
          image-ref: ghcr.io/kainlite/tr:${{ github.sha }}
          format: sarif
          output: trivy-results.sarif
          ignore-unfixed: true
          vuln-type: os,library
          severity: CRITICAL,HIGH

      - name: Upload Trivy scan results to GitHub Security tab
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: trivy-results.sarif

      - name: Scan Kubernetes manifests
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: ./k8s/
          format: table
          exit-code: 1
          severity: CRITICAL,HIGH
```

<br />

The key parts are: `exit-code: 1` makes the pipeline fail when vulnerabilities are found, `ignore-unfixed: true`
skips CVEs that do not have a fix yet (so you do not block on things you cannot fix), and the SARIF upload pushes
results to the GitHub Security tab for visibility.

<br />

**Scanning Helm charts and IaC**

Trivy can also scan your Kubernetes manifests, Helm charts, and Terraform files for misconfigurations:

<br />

```yaml
# .github/workflows/iac-scan.yaml
name: IaC Security Scan

on:
  pull_request:
    paths:
      - 'k8s/**'
      - 'terraform/**'
      - 'charts/**'

jobs:
  trivy-config-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Scan Kubernetes manifests
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: ./k8s/
          format: table
          exit-code: 1
          severity: CRITICAL,HIGH

      - name: Scan Terraform
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: ./terraform/
          format: table
          exit-code: 1
          severity: CRITICAL,HIGH

      - name: Scan Helm charts
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: ./charts/
          format: table
          exit-code: 0
          severity: CRITICAL,HIGH,MEDIUM
```

<br />

This catches issues like containers running as root, missing resource limits, missing network policies, and
overly permissive RBAC before they ever get merged.

<br />

##### **RBAC best practices**
Role-Based Access Control (RBAC) is how you control who can do what in your Kubernetes cluster. The principle of
least privilege is simple: give every user, service account, and automation only the permissions they actually need
and nothing more.

<br />

**ClusterRole vs Role**

The first rule: prefer Role over ClusterRole whenever possible. A Role is scoped to a namespace, so a compromised
service account can only affect that namespace. A ClusterRole applies cluster-wide.

<br />

```yaml
# rbac/tr-web-role.yaml
# Namespace-scoped role for the application
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tr-web
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["tr-web-config"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tr-web
  namespace: production
subjects:
  - kind: ServiceAccount
    name: tr-web
    namespace: production
roleRef:
  kind: Role
  name: tr-web
  apiGroup: rbac.authorization.k8s.io
```

<br />

**Service account hardening**

Every pod should have its own service account with only the permissions it needs. The default service account in
each namespace should have no permissions and automount should be disabled:

<br />

```yaml
# rbac/default-sa-lockdown.yaml
# Disable automounting for the default service account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: production
automountServiceAccountToken: false
---
# Create a dedicated service account for the app
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tr-web
  namespace: production
  labels:
    app.kubernetes.io/name: tr-web
    team: platform
automountServiceAccountToken: true
```

<br />

**Aggregated ClusterRoles for team access**

For human access to the cluster, use aggregated ClusterRoles that compose permissions from multiple smaller roles.
This makes it easy to add new permissions without editing a monolithic role:

<br />

```yaml
# rbac/team-roles.yaml
# Base read-only role for all team members
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: team-readonly
  labels:
    rbac.kainlite.com/aggregate-to-developer: "true"
    rbac.kainlite.com/aggregate-to-sre: "true"
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps", "events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
---
# Additional permissions for developers
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer-extra
  labels:
    rbac.kainlite.com/aggregate-to-developer: "true"
rules:
  - apiGroups: [""]
    resources: ["pods/log", "pods/portforward"]
    verbs: ["get", "create"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
---
# Additional permissions for SREs
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sre-extra
  labels:
    rbac.kainlite.com/aggregate-to-sre: "true"
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["patch", "update"]
  - apiGroups: ["apps"]
    resources: ["deployments/rollback"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch", "cordon", "uncordon"]
---
# Aggregated role for developers
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
aggregationRule:
  clusterRoleSelectors:
    - matchLabels:
        rbac.kainlite.com/aggregate-to-developer: "true"
rules: []
---
# Aggregated role for SREs
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sre
aggregationRule:
  clusterRoleSelectors:
    - matchLabels:
        rbac.kainlite.com/aggregate-to-sre: "true"
rules: []
```

<br />

The aggregation pattern means you can add a new ClusterRole with the right label and it automatically gets included
in the aggregated role. No need to edit the parent role, which means fewer merge conflicts and cleaner Git history.

<br />

##### **Audit logging**
Kubernetes audit logging records every request to the API server. This is essential for security investigations,
compliance requirements, and understanding who did what and when. Without audit logs, a security incident turns into
guesswork.

<br />

**Audit policy**

You need an audit policy that defines what to log and at what level. Here is a practical policy that captures the
important events without drowning you in noise:

<br />

```hcl
# audit/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Do not log requests to certain non-resource URL paths
  - level: None
    nonResourceURLs:
      - /healthz*
      - /readyz*
      - /livez*
      - /metrics

  # Do not log watch requests (too noisy)
  - level: None
    verbs: ["watch"]

  # Do not log kube-proxy and system:nodes
  - level: None
    users:
      - system:kube-proxy
    verbs: ["get", "list"]

  # Log secret access at Metadata level (do not log the secret values)
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]

  # Log all changes to pods and deployments at RequestResponse level
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: ""
        resources: ["pods", "pods/exec", "pods/portforward"]
      - group: "apps"
        resources: ["deployments", "statefulsets", "daemonsets"]

  # Log RBAC changes at RequestResponse level
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["clusterroles", "clusterrolebindings", "roles", "rolebindings"]

  # Log namespace changes
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: ""
        resources: ["namespaces"]

  # Log everything else at Metadata level
  - level: Metadata
    omitStages:
      - RequestReceived
```

<br />

**Sending audit logs to your observability stack**

The audit logs need to go somewhere useful. If you are using the Loki stack from the observability article, you can
configure the API server to write audit logs to a file and have Promtail ship them to Loki:

<br />

```hcl
# audit/promtail-audit-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-audit-config
  namespace: monitoring
data:
  promtail.yaml: |
    server:
      http_listen_port: 3101

    positions:
      filename: /tmp/positions.yaml

    clients:
      - url: http://loki:3100/loki/api/v1/push

    scrape_configs:
      - job_name: kubernetes-audit
        static_configs:
          - targets:
              - localhost
            labels:
              job: kubernetes-audit
              __path__: /var/log/kubernetes/audit/*.log
        pipeline_stages:
          - json:
              expressions:
                level: level
                verb: verb
                user: user.username
                resource: objectRef.resource
                namespace: objectRef.namespace
                name: objectRef.name
                responseCode: responseStatus.code
          - labels:
              level:
              verb:
              user:
              resource:
              namespace:
          - timestamp:
              source: stageTimestamp
              format: RFC3339Nano
```

<br />

With audit logs in Loki, you can create Grafana dashboards that show who is accessing your cluster, what changes
are being made, and alert on suspicious activity like someone creating a ClusterRoleBinding or exec-ing into a
production pod.

<br />

##### **Falco for runtime security**
Gatekeeper and PSS prevent bad configurations from entering the cluster, but what about runtime attacks? That is
where Falco comes in. Falco monitors system calls at the kernel level and alerts when it detects suspicious
behavior like a shell being spawned in a container, sensitive files being read, or unexpected network connections.

<br />

**Installing Falco**

Falco can be installed as a DaemonSet using Helm:

<br />

```sql
# Install Falco with Helm
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set falcosidekick.enabled=true \
  --set falcosidekick.config.slack.webhookurl="https://hooks.slack.com/services/XXX" \
  --set driver.kind=ebpf \
  --set collectors.kubernetes.enabled=true
```

<br />

Or as an ArgoCD application:

<br />

```yaml
# argocd/falco-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: falco
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://falcosecurity.github.io/charts
    chart: falco
    targetRevision: 4.2.0
    helm:
      values: |
        driver:
          kind: ebpf
        falcosidekick:
          enabled: true
          config:
            slack:
              webhookurl: "https://hooks.slack.com/services/XXX"
              minimumpriority: warning
            prometheus:
              extralabels: "source:falco"
        collectors:
          kubernetes:
            enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: falco
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

**Custom Falco rules**

Falco ships with a comprehensive set of default rules, but you should add custom rules specific to your
environment. Here are some practical examples:

<br />

```yaml
# falco/custom-rules.yaml
# Detect exec into production pods
- rule: Exec into production pod
  desc: Detect when someone execs into a pod in the production namespace
  condition: >
    spawned_process
    and container
    and k8s.ns.name = "production"
    and proc.pname = "runc:[2:INIT]"
  output: >
    Shell spawned in production pod
    (user=%ka.user.name pod=%k8s.pod.name ns=%k8s.ns.name
     container=%container.name command=%proc.cmdline)
  priority: WARNING
  tags: [security, shell, production]

# Detect reading sensitive files
- rule: Read sensitive file in container
  desc: Detect read of sensitive files like /etc/shadow or private keys
  condition: >
    open_read
    and container
    and (fd.name startswith /etc/shadow
      or fd.name startswith /etc/gshadow
      or fd.name contains id_rsa
      or fd.name contains id_ed25519
      or fd.name endswith .pem
      or fd.name endswith .key)
  output: >
    Sensitive file read in container
    (user=%user.name file=%fd.name pod=%k8s.pod.name
     ns=%k8s.ns.name container=%container.name)
  priority: WARNING
  tags: [security, filesystem, sensitive]

# Detect unexpected outbound connections
- rule: Unexpected outbound connection from production
  desc: Detect outbound connections to IPs not in the allowed list
  condition: >
    outbound
    and container
    and k8s.ns.name = "production"
    and not (fd.sip in (allowed_outbound_ips))
    and not (fd.sport in (53, 443, 5432))
  output: >
    Unexpected outbound connection from production
    (pod=%k8s.pod.name ns=%k8s.ns.name ip=%fd.sip port=%fd.sport
     command=%proc.cmdline container=%container.name)
  priority: NOTICE
  tags: [security, network, production]

# Detect container drift (new executables written and executed)
- rule: Container drift detected
  desc: Detect when new executables are written to a container filesystem and then executed
  condition: >
    spawned_process
    and container
    and proc.is_exe_upper_layer = true
  output: >
    Drift detected: new executable run in container
    (user=%user.name command=%proc.cmdline pod=%k8s.pod.name
     ns=%k8s.ns.name container=%container.name image=%container.image.repository)
  priority: ERROR
  tags: [security, drift]

# Detect crypto mining
- rule: Detect crypto mining activity
  desc: Detect processes known to be associated with cryptocurrency mining
  condition: >
    spawned_process
    and container
    and (proc.name in (xmrig, minerd, cpuminer, cryptonight)
      or proc.cmdline contains "stratum+tcp"
      or proc.cmdline contains "pool.minexmr")
  output: >
    Possible crypto mining detected
    (pod=%k8s.pod.name ns=%k8s.ns.name process=%proc.name
     command=%proc.cmdline container=%container.name)
  priority: CRITICAL
  tags: [security, crypto, mining]
```

<br />

**Loading custom rules**

You can deploy custom rules as a ConfigMap and tell Falco to load them:

<br />

```yaml
# falco/custom-rules-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-custom-rules
  namespace: falco
data:
  custom-rules.yaml: |
    - list: allowed_outbound_ips
      items: ["10.0.0.0/8", "172.16.0.0/12"]

    - rule: Exec into production pod
      desc: Detect when someone execs into a pod in the production namespace
      condition: >
        spawned_process
        and container
        and k8s.ns.name = "production"
        and proc.pname = "runc:[2:INIT]"
      output: >
        Shell spawned in production pod
        (user=%ka.user.name pod=%k8s.pod.name ns=%k8s.ns.name
         container=%container.name command=%proc.cmdline)
      priority: WARNING
      tags: [security, shell, production]
```

<br />

Falco gives you visibility into what is actually happening inside your containers at the system call level. Combined
with network policies (which control what traffic is allowed) and Gatekeeper (which controls what configurations are
allowed), you have defense in depth covering configuration time, network layer, and runtime.

<br />

##### **Supply chain security**
Your container images are only as trustworthy as the process that built them. Supply chain attacks, where an
attacker compromises a dependency or build pipeline to inject malicious code, have become increasingly common.
The solution is to sign your images and verify those signatures before allowing them to run.

<br />

**Signing images with Cosign**

Cosign from the Sigstore project makes it easy to sign and verify container images. Here is how to integrate it
into your CI pipeline:

<br />

```yaml
# .github/workflows/build-and-sign.yaml
name: Build, Sign, and Push

on:
  push:
    branches: [main]

permissions:
  contents: read
  packages: write
  id-token: write  # Required for keyless signing

jobs:
  build-sign-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Cosign
        uses: sigstore/cosign-installer@main

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push image
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ghcr.io/kainlite/tr:${{ github.sha }}

      - name: Sign the image with Cosign (keyless)
        env:
          COSIGN_EXPERIMENTAL: "true"
        run: |
          cosign sign --yes \
            ghcr.io/kainlite/tr@${{ steps.build.outputs.digest }}

      - name: Generate SBOM
        uses: anchore/sbom-action@v0
        with:
          image: ghcr.io/kainlite/tr:${{ github.sha }}
          format: spdx-json
          output-file: sbom.spdx.json

      - name: Attach SBOM to image
        run: |
          cosign attach sbom \
            --sbom sbom.spdx.json \
            ghcr.io/kainlite/tr@${{ steps.build.outputs.digest }}

      - name: Upload SBOM as artifact
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.spdx.json
```

<br />

The `--yes` flag uses keyless signing, which means Cosign gets a short-lived certificate from Sigstore's Fulcio CA
tied to your GitHub Actions OIDC identity. No long-lived keys to manage or rotate.

<br />

**SBOM generation**

A Software Bill of Materials (SBOM) is a list of every component in your image. It is essential for tracking which
of your images are affected when a new CVE is published. The workflow above generates an SPDX-format SBOM and
attaches it to the image in the registry.

<br />

**Verifying signatures with Kyverno**

Now that your images are signed, you need to enforce that only signed images can run in the cluster. Kyverno is a
Kubernetes policy engine that can verify Cosign signatures at admission time:

<br />

```yaml
# kyverno/verify-image-signature.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signatures
  annotations:
    policies.kyverno.io/title: Verify Image Signatures
    policies.kyverno.io/description: >
      Verify that all container images are signed with Cosign
      using keyless signing from our GitHub Actions workflows.
spec:
  validationFailureAction: Enforce
  background: false
  webhookTimeoutSeconds: 30
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - production
                - staging
      verifyImages:
        - imageReferences:
            - "ghcr.io/kainlite/*"
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/kainlite/tr/.github/workflows/*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor:
                      url: https://rekor.sigstore.dev
          mutateDigest: true
          required: true
```

<br />

```yaml
# kyverno/require-sbom.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-sbom-attestation
spec:
  validationFailureAction: Audit
  background: false
  rules:
    - name: check-sbom
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - production
      verifyImages:
        - imageReferences:
            - "ghcr.io/kainlite/*"
          attestations:
            - type: https://spdx.dev/Document
              attestors:
                - entries:
                    - keyless:
                        subject: "https://github.com/kainlite/tr/.github/workflows/*"
                        issuer: "https://token.actions.githubusercontent.com"
              conditions:
                - all:
                    - key: "{{ creationInfo.created }}"
                      operator: NotEquals
                      value: ""
```

<br />

With this setup, the full supply chain flow is: GitHub Actions builds the image, signs it with Cosign using keyless
signing, generates and attaches an SBOM, and Kyverno verifies the signature before allowing the image to run in
the cluster. If someone pushes an unsigned image or an image that was not built by your CI pipeline, Kyverno
rejects it.

<br />

##### **Security SLOs**
If you have been following the SRE series, you know that if you cannot measure it, you cannot improve it. Security
is no different. Just like you track availability and latency SLOs, you should track security metrics as SLIs.

<br />

**Vulnerability remediation time**

How long does it take your team to patch a critical CVE after it is discovered? This is one of the most important
security metrics:

<br />

```yaml
# prometheus-rules/security-slis.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: security-slis
  namespace: monitoring
spec:
  groups:
    - name: security.slis
      interval: 1h
      rules:
        # Track critical vulnerability count over time
        - record: security:critical_cves:total
          expr: |
            sum(trivy_vulnerability_count{severity="CRITICAL"})

        # Track high vulnerability count
        - record: security:high_cves:total
          expr: |
            sum(trivy_vulnerability_count{severity="HIGH"})

        # Track time since oldest unpatched critical CVE
        - record: security:oldest_critical_cve_age_days
          expr: |
            (time() - min(trivy_vulnerability_first_seen{severity="CRITICAL"})) / 86400

        # Policy violations detected by Gatekeeper audit
        - record: security:policy_violations:total
          expr: |
            sum(gatekeeper_violations)

        # Falco alerts rate
        - record: security:falco_alerts:rate1h
          expr: |
            sum(rate(falco_events_total{priority=~"WARNING|ERROR|CRITICAL"}[1h]))
```

<br />

**Security SLOs definition**

Define concrete SLOs for your security posture:

<br />

```yaml
# security-slos.yaml
security_slos:
  vulnerability_remediation:
    description: "Critical CVEs must be patched within 7 days"
    sli: security:oldest_critical_cve_age_days
    objective: 7
    measurement: "Days since oldest unpatched critical CVE"

  policy_compliance:
    description: "Zero Gatekeeper policy violations in production"
    sli: security:policy_violations:total
    objective: 0
    measurement: "Total active policy violations"

  runtime_security:
    description: "Zero critical Falco alerts in production"
    sli: security:falco_alerts:rate1h
    objective: 0
    measurement: "Critical and error Falco alerts per hour"

  image_signing:
    description: "100% of production images must be signed"
    sli: kyverno:policy_violations:image_signature
    objective: 0
    measurement: "Unsigned images blocked or running"
```

<br />

**Alerting on security SLOs**

Set up alerts that fire when your security SLOs are at risk:

<br />

```yaml
# prometheus-rules/security-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: security-alerts
  namespace: monitoring
spec:
  groups:
    - name: security.alerts
      rules:
        - alert: CriticalCVEUnpatchedTooLong
          expr: security:oldest_critical_cve_age_days > 5
          for: 1h
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Critical CVE has been unpatched for more than 5 days"
            description: "Oldest unpatched critical CVE is {{ $value }} days old. SLO target is 7 days."
            runbook: "https://runbooks.example.com/patch-critical-cve"

        - alert: GatekeeperPolicyViolations
          expr: security:policy_violations:total > 0
          for: 5m
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Gatekeeper policy violations detected"
            description: "{{ $value }} policy violations found in the cluster."

        - alert: FalcoCriticalAlert
          expr: security:falco_alerts:rate1h > 0
          for: 0m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "Falco detected critical security event"
            description: "Falco is reporting {{ $value }} critical/error events per hour."
```

<br />

Treating security metrics as SLIs gives you the same benefits as reliability SLOs: you can measure progress, set
targets, alert when things drift, and make data-driven decisions about where to invest your security efforts.

<br />

##### **Putting it all together**
Here is a summary of the full security-as-code stack we built:

<br />

> 1. **OPA Gatekeeper**: Admission control policies that enforce labels, block privileged containers, and restrict image registries
> 2. **Pod Security Standards**: Built-in namespace-level security profiles (Privileged, Baseline, Restricted)
> 3. **Network policies**: Default deny with explicit allow rules, L7 filtering with Cilium
> 4. **Image scanning with Trivy**: CI pipeline that blocks deployments with critical vulnerabilities
> 5. **RBAC hardening**: Least privilege roles, service account isolation, aggregated ClusterRoles
> 6. **Audit logging**: Recording API server activity and shipping to your observability stack
> 7. **Falco runtime security**: Detecting suspicious behavior at the system call level
> 8. **Supply chain security**: Image signing with Cosign, SBOM generation, verification with Kyverno
> 9. **Security SLOs**: Measuring and alerting on vulnerability remediation time and compliance metrics

<br />

Each layer covers a different phase of the attack surface: Gatekeeper and PSS prevent bad configurations, network
policies limit blast radius, Trivy catches known vulnerabilities, RBAC restricts access, audit logs provide
forensic evidence, Falco detects runtime attacks, and supply chain security ensures image integrity.

<br />

No single layer is perfect, but together they create defense in depth that makes it significantly harder for an
attacker to succeed and much easier for you to detect and respond when something does go wrong.

<br />

##### **Closing notes**
Security as code is not about buying expensive tools or achieving perfect compliance scores. It is about applying
the same engineering discipline we use for reliability to security: define policies as code, enforce them
automatically, measure compliance, and continuously improve.

<br />

Start small. If you do nothing else, add a default deny network policy to your production namespace and enable
the restricted Pod Security Standard. Those two changes alone will significantly reduce your attack surface. Then
layer on Gatekeeper policies, image scanning, Falco, and supply chain security as your team's maturity grows.

<br />

The important thing is to make security a continuous process, not a one-time audit. Treat CVE remediation time
like you treat latency SLOs. Track it, alert on it, and invest in improving it. Your future self during the next
security incident will thank you.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Seguridad como Código",
  author: "Gabriel Garrido",
  description: "Vamos a explorar prácticas de seguridad como código para Kubernetes, desde políticas de OPA Gatekeeper y Pod Security Standards hasta escaneo de imágenes con Trivy, network policies, seguridad en runtime con Falco, y seguridad de la cadena de suministro...",
  tags: ~w(sre kubernetes security opa policy),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En los artículos anteriores cubrimos [SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[gestión de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observabilidad](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[ingeniería del caos](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[planificación de capacidad](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[gestión de secretos](/blog/sre-secrets-management-in-kubernetes),
[optimización de costos](/blog/sre-cost-optimization-in-the-cloud),
[gestión de dependencias](/blog/sre-dependency-management-and-graceful-degradation),
[confiabilidad de bases de datos](/blog/sre-database-reliability), y
[ingeniería de releases](/blog/sre-release-engineering-and-progressive-delivery). Todos esos temas asumen que
tu cluster y tus workloads son seguros, pero la seguridad muchas veces se trata como algo que se ve después o
como problema de otro.

<br />

Eso se termina hoy. La seguridad es una preocupación de SRE porque un incidente de seguridad es simplemente otro
tipo de incidente que quema tu presupuesto de error, erosiona la confianza de los usuarios y genera caos
operacional. El enfoque shift-left significa que definimos políticas de seguridad como código, las aplicamos
automáticamente y tratamos las violaciones de seguridad de la misma forma que tratamos las violaciones de SLOs:
con indicadores medibles, respuestas automatizadas y mejora continua.

<br />

En este artículo vamos a cubrir el stack completo de seguridad como código para Kubernetes: control de admisión
con OPA Gatekeeper, Pod Security Standards, network policies, escaneo de imágenes en CI, hardening de RBAC,
audit logging, seguridad en runtime con Falco, y seguridad de la cadena de suministro con Cosign y Kyverno. Todo
como código, todo automatizado.

<br />

Vamos al tema.

<br />

##### **Políticas con OPA y Gatekeeper**
Open Policy Agent (OPA) es un motor de políticas de uso general, y Gatekeeper es la forma nativa de Kubernetes de
usarlo. Gatekeeper actúa como un controlador de admisión que intercepta cada request al API server de Kubernetes
y la evalúa contra tus políticas antes de permitirla o denegarla.

<br />

Lo bueno de este enfoque es que tus políticas de seguridad se vuelven código que vive en Git, se revisa en PRs y
se aplica automáticamente. No más rezar para que los desarrolladores se acuerden de poner los labels correctos o
evitar contenedores privilegiados.

<br />

**Instalando Gatekeeper**

Instalar Gatekeeper en tu cluster es sencillo con Helm:

<br />

```sql
# Instalar Gatekeeper via Helm
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --set replicas=3 \
  --set audit.replicas=2 \
  --set audit.logLevel=INFO
```

<br />

O si preferís un enfoque declarativo con ArgoCD:

<br />

```yaml
# argocd/gatekeeper-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gatekeeper
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://open-policy-agent.github.io/gatekeeper/charts
    chart: gatekeeper
    targetRevision: 3.15.0
    helm:
      values: |
        replicas: 3
        audit:
          replicas: 2
          logLevel: INFO
  destination:
    server: https://kubernetes.default.svc
    namespace: gatekeeper-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

<br />

**ConstraintTemplate: Requerir labels**

Gatekeeper usa dos recursos: ConstraintTemplates (la lógica de la política en Rego) y Constraints (cómo
aplicarlas). Acá hay un template que requiere labels específicos en todos los recursos:

<br />

```yaml
# policies/templates/require-labels.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels

        violation[{"msg": msg, "details": {"missing_labels": missing}}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Al recurso le faltan labels requeridos: %v", [missing])
        }
```

<br />

Y el constraint que lo aplica a todos los namespaces:

<br />

```yaml
# policies/constraints/require-labels.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: all-must-have-owner
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Namespace"]
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet"]
  parameters:
    labels:
      - "app.kubernetes.io/name"
      - "app.kubernetes.io/managed-by"
      - "team"
```

<br />

**ConstraintTemplate: Bloquear pods privilegiados**

Esta es crítica. Los contenedores privilegiados tienen acceso total al host, lo que significa que un escape de
contenedor le da al atacante root en el nodo:

<br />

```yaml
# policies/templates/block-privileged.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sblockprivileged
spec:
  crd:
    spec:
      names:
        kind: K8sBlockPrivileged
      validation:
        openAPIV3Schema:
          type: object
          properties:
            allowedImages:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sblockprivileged

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          container.securityContext.privileged == true
          msg := sprintf("Los contenedores privilegiados no están permitidos: %v", [container.name])
        }

        violation[{"msg": msg}] {
          container := input.review.object.spec.initContainers[_]
          container.securityContext.privileged == true
          msg := sprintf("Los init containers privilegiados no están permitidos: %v", [container.name])
        }
```

<br />

```yaml
# policies/constraints/block-privileged.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockPrivileged
metadata:
  name: no-privileged-containers
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet", "DaemonSet"]
    excludedNamespaces:
      - kube-system
      - gatekeeper-system
```

<br />

**ConstraintTemplate: Forzar registry de imágenes**

Probablemente no querés imágenes random de Docker Hub corriendo en producción. Esta política restringe las
imágenes a tus registries de confianza:

<br />

```yaml
# policies/templates/allowed-registries.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sallowedregistries
spec:
  crd:
    spec:
      names:
        kind: K8sAllowedRegistries
      validation:
        openAPIV3Schema:
          type: object
          properties:
            registries:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sallowedregistries

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not registry_allowed(container.image)
          msg := sprintf("La imagen '%v' es de un registry no confiable. Registries permitidos: %v",
            [container.image, input.parameters.registries])
        }

        violation[{"msg": msg}] {
          container := input.review.object.spec.initContainers[_]
          not registry_allowed(container.image)
          msg := sprintf("La imagen del init container '%v' es de un registry no confiable. Registries permitidos: %v",
            [container.image, input.parameters.registries])
        }

        registry_allowed(image) {
          registry := input.parameters.registries[_]
          startswith(image, registry)
        }
```

<br />

```yaml
# policies/constraints/allowed-registries.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRegistries
metadata:
  name: trusted-registries-only
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet", "DaemonSet"]
    excludedNamespaces:
      - kube-system
  parameters:
    registries:
      - "ghcr.io/kainlite/"
      - "docker.io/kainlite/"
      - "registry.k8s.io/"
      - "quay.io/"
```

<br />

Con estas tres políticas solas ya tenés una base sólida: cada recurso necesita labels de ownership, nadie
puede correr contenedores privilegiados, y solo imágenes de registries de confianza están permitidas.

<br />

##### **Pod Security Standards**
Kubernetes trae incorporados los Pod Security Standards (PSS) que proporcionan tres niveles de perfiles de
seguridad. Funcionan a nivel de namespace y no requieren ningún controlador externo como Gatekeeper. Son un
excelente punto de partida si querés algo simple que cubra lo básico.

<br />

Los tres perfiles son:

<br />

> * **Privileged**: Sin restricciones. Permite todo. Se usa para workloads a nivel de sistema como plugins de CNI y agentes de monitoreo.
> * **Baseline**: Previene escalaciones de privilegios conocidas. Bloquea hostNetwork, hostPID, contenedores privilegiados y la mayoría de las capabilities peligrosas. Buen default para la mayoría de los workloads.
> * **Restricted**: Altamente restringido. Requiere non-root, dropea todas las capabilities, no permite escalación de privilegios. El estándar de oro para workloads de aplicaciones.

<br />

**Enforcement a nivel de namespace**

Aplicás los perfiles PSS usando labels en los namespaces. Hay tres modos:

<br />

> * **enforce**: Rechaza pods que violan la política
> * **audit**: Permite pods pero registra las violaciones
> * **warn**: Permite pods pero muestra un warning al usuario

<br />

Una buena estrategia de rollout es empezar con warn y audit, revisar las violaciones, corregirlas, y después
cambiar a enforce:

<br />

```yaml
# namespaces/production.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

<br />

```yaml
# namespaces/staging.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: staging
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

<br />

**Haciendo tus pods compatibles**

Para el perfil restricted, tus pods necesitan cumplir varios requisitos. Así se ve un pod spec compatible:

<br />

```yaml
# deployments/tr-web.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tr-web
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: tr-web
  template:
    metadata:
      labels:
        app.kubernetes.io/name: tr-web
        app.kubernetes.io/managed-by: argocd
        team: platform
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: tr-web
          image: ghcr.io/kainlite/tr:latest
          ports:
            - containerPort: 4000
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
```

<br />

Las configuraciones de seguridad clave son: `runAsNonRoot`, `allowPrivilegeEscalation: false`, dropear todas las
capabilities, filesystem root de solo lectura, y un perfil de seccomp. Si falta alguna, el perfil restricted va
a rechazar el pod.

<br />

##### **Network policies**
Por defecto, cada pod en Kubernetes puede hablar con todos los demás pods. Eso es terrible para la seguridad. Si
un atacante compromete un pod, puede moverse libremente de forma lateral a cualquier otro servicio en el cluster.
Las network policies solucionan esto definiendo qué tráfico está permitido.

<br />

**Default deny para todo**

Lo primero que deberías hacer es crear una política default deny para cada namespace. Esto bloquea todo el
tráfico que no esté explícitamente permitido:

<br />

```yaml
# network-policies/default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

<br />

Ahora nada puede hablar con nada. Es hora de permitir el tráfico que realmente necesitás.

<br />

**Permitir tráfico específico**

Acá hay una política que permite al frontend web recibir tráfico del ingress controller y hablar con la base
de datos:

<br />

```yaml
# network-policies/tr-web.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-tr-web
  namespace: production
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: tr-web
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
          podSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
      ports:
        - protocol: TCP
          port: 4000
  egress:
    # Permitir DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Permitir acceso a la base de datos
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: postgresql
      ports:
        - protocol: TCP
          port: 5432
```

<br />

**Network policies con Cilium**

Si estás usando Cilium como tu CNI, tenés acceso a network policies más poderosas que pueden filtrar a nivel
L7 (HTTP, gRPC, DNS):

<br />

```yaml
# cilium-policies/tr-web-l7.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: tr-web-l7-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: tr-web
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: ingress-nginx
            io.kubernetes.pod.namespace: ingress-nginx
      toPorts:
        - ports:
            - port: "4000"
              protocol: TCP
          rules:
            http:
              - method: GET
              - method: POST
                path: "/api/.*"
              - method: HEAD
  egress:
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: postgresql
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
    # Política de DNS
    - toEndpoints:
        - matchLabels:
            k8s-app: kube-dns
            io.kubernetes.pod.namespace: kube-system
      toPorts:
        - ports:
            - port: "53"
              protocol: ANY
          rules:
            dns:
              - matchPattern: "*.production.svc.cluster.local"
              - matchPattern: "*.kube-system.svc.cluster.local"
```

<br />

El filtrado L7 es increíblemente poderoso. Podés restringir no solo qué pods pueden hablar entre sí, sino
también qué métodos HTTP y paths están permitidos. Esto significa que incluso si un atacante compromete el pod
web, solo puede hacer exactamente las llamadas API que el pod web se supone que hace.

<br />

##### **Escaneo de imágenes en CI**
Detectar vulnerabilidades antes de que lleguen a tu cluster es mucho mejor que detectarlas en runtime. Trivy es
un excelente escáner open-source que chequea imágenes de contenedores por CVEs conocidos, misconfiguraciones y
secretos expuestos.

<br />

**Trivy en GitHub Actions**

Acá hay un workflow completo de CI que escanea tus imágenes y bloquea el deployment si se encuentran
vulnerabilidades de alta severidad:

<br />

```hcl
# .github/workflows/security-scan.yaml
name: Security Scan

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  trivy-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: |
          docker build -t ghcr.io/kainlite/tr:${{ github.sha }} .

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ghcr.io/kainlite/tr:${{ github.sha }}
          format: table
          exit-code: 1
          ignore-unfixed: true
          vuln-type: os,library
          severity: CRITICAL,HIGH
          output: trivy-results.txt

      - name: Run Trivy for SARIF output
        uses: aquasecurity/trivy-action@master
        if: always()
        with:
          image-ref: ghcr.io/kainlite/tr:${{ github.sha }}
          format: sarif
          output: trivy-results.sarif
          ignore-unfixed: true
          vuln-type: os,library
          severity: CRITICAL,HIGH

      - name: Upload Trivy scan results to GitHub Security tab
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: trivy-results.sarif

      - name: Scan Kubernetes manifests
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: ./k8s/
          format: table
          exit-code: 1
          severity: CRITICAL,HIGH
```

<br />

Las partes clave son: `exit-code: 1` hace que el pipeline falle cuando se encuentran vulnerabilidades,
`ignore-unfixed: true` saltea CVEs que todavía no tienen fix (para no bloquearte en cosas que no podés
arreglar), y la subida SARIF manda los resultados a la pestaña Security de GitHub para visibilidad.

<br />

**Escaneando Helm charts e IaC**

Trivy también puede escanear tus manifiestos de Kubernetes, Helm charts y archivos de Terraform por
misconfiguraciones:

<br />

```yaml
# .github/workflows/iac-scan.yaml
name: IaC Security Scan

on:
  pull_request:
    paths:
      - 'k8s/**'
      - 'terraform/**'
      - 'charts/**'

jobs:
  trivy-config-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Scan Kubernetes manifests
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: ./k8s/
          format: table
          exit-code: 1
          severity: CRITICAL,HIGH

      - name: Scan Terraform
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: ./terraform/
          format: table
          exit-code: 1
          severity: CRITICAL,HIGH

      - name: Scan Helm charts
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: ./charts/
          format: table
          exit-code: 0
          severity: CRITICAL,HIGH,MEDIUM
```

<br />

Esto detecta problemas como contenedores corriendo como root, limits de recursos faltantes, network policies
faltantes y RBAC demasiado permisivo antes de que se mergeen.

<br />

##### **Buenas prácticas de RBAC**
Role-Based Access Control (RBAC) es cómo controlás quién puede hacer qué en tu cluster de Kubernetes. El
principio de menor privilegio es simple: dale a cada usuario, service account y automatización solo los permisos
que realmente necesita y nada más.

<br />

**ClusterRole vs Role**

La primera regla: preferí Role sobre ClusterRole siempre que sea posible. Un Role tiene alcance de namespace,
así que un service account comprometido solo puede afectar ese namespace. Un ClusterRole aplica a todo el cluster.

<br />

```yaml
# rbac/tr-web-role.yaml
# Role con alcance de namespace para la aplicación
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tr-web
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["tr-web-config"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tr-web
  namespace: production
subjects:
  - kind: ServiceAccount
    name: tr-web
    namespace: production
roleRef:
  kind: Role
  name: tr-web
  apiGroup: rbac.authorization.k8s.io
```

<br />

**Hardening de service accounts**

Cada pod debería tener su propio service account con solo los permisos que necesita. El service account por
defecto en cada namespace no debería tener permisos y el automount debería estar deshabilitado:

<br />

```yaml
# rbac/default-sa-lockdown.yaml
# Deshabilitar automounting para el service account por defecto
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: production
automountServiceAccountToken: false
---
# Crear un service account dedicado para la app
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tr-web
  namespace: production
  labels:
    app.kubernetes.io/name: tr-web
    team: platform
automountServiceAccountToken: true
```

<br />

**ClusterRoles agregados para acceso de equipo**

Para el acceso humano al cluster, usá ClusterRoles agregados que componen permisos de varios roles más chicos.
Esto hace fácil agregar nuevos permisos sin editar un role monolítico:

<br />

```yaml
# rbac/team-roles.yaml
# Role base de solo lectura para todos los miembros del equipo
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: team-readonly
  labels:
    rbac.kainlite.com/aggregate-to-developer: "true"
    rbac.kainlite.com/aggregate-to-sre: "true"
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps", "events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
---
# Permisos adicionales para desarrolladores
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer-extra
  labels:
    rbac.kainlite.com/aggregate-to-developer: "true"
rules:
  - apiGroups: [""]
    resources: ["pods/log", "pods/portforward"]
    verbs: ["get", "create"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
---
# Permisos adicionales para SREs
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sre-extra
  labels:
    rbac.kainlite.com/aggregate-to-sre: "true"
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["patch", "update"]
  - apiGroups: ["apps"]
    resources: ["deployments/rollback"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch", "cordon", "uncordon"]
---
# Role agregado para desarrolladores
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
aggregationRule:
  clusterRoleSelectors:
    - matchLabels:
        rbac.kainlite.com/aggregate-to-developer: "true"
rules: []
---
# Role agregado para SREs
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sre
aggregationRule:
  clusterRoleSelectors:
    - matchLabels:
        rbac.kainlite.com/aggregate-to-sre: "true"
rules: []
```

<br />

El patrón de agregación significa que podés agregar un nuevo ClusterRole con el label correcto y automáticamente
se incluye en el role agregado. No necesitás editar el role padre, lo que significa menos conflictos de merge y un
historial de Git más limpio.

<br />

##### **Audit logging**
El audit logging de Kubernetes registra cada request al API server. Esto es esencial para investigaciones de
seguridad, requisitos de compliance y entender quién hizo qué y cuándo. Sin audit logs, un incidente de seguridad
se convierte en adivinanzas.

<br />

**Política de auditoría**

Necesitás una política de auditoría que defina qué loguear y a qué nivel. Acá hay una política práctica que
captura los eventos importantes sin ahogarte en ruido:

<br />

```yaml
# audit/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # No loguear requests a ciertos paths de URLs no-resource
  - level: None
    nonResourceURLs:
      - /healthz*
      - /readyz*
      - /livez*
      - /metrics

  # No loguear requests de watch (demasiado ruidosas)
  - level: None
    verbs: ["watch"]

  # No loguear kube-proxy y system:nodes
  - level: None
    users:
      - system:kube-proxy
    verbs: ["get", "list"]

  # Loguear acceso a secrets a nivel Metadata (no loguear los valores del secret)
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]

  # Loguear todos los cambios en pods y deployments a nivel RequestResponse
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: ""
        resources: ["pods", "pods/exec", "pods/portforward"]
      - group: "apps"
        resources: ["deployments", "statefulsets", "daemonsets"]

  # Loguear cambios de RBAC a nivel RequestResponse
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["clusterroles", "clusterrolebindings", "roles", "rolebindings"]

  # Loguear cambios de namespaces
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: ""
        resources: ["namespaces"]

  # Loguear todo lo demás a nivel Metadata
  - level: Metadata
    omitStages:
      - RequestReceived
```

<br />

**Enviando audit logs a tu stack de observabilidad**

Los audit logs necesitan ir a algún lugar útil. Si estás usando el stack de Loki del artículo de observabilidad,
podés configurar el API server para escribir audit logs a un archivo y hacer que Promtail los envíe a Loki:

<br />

```hcl
# audit/promtail-audit-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-audit-config
  namespace: monitoring
data:
  promtail.yaml: |
    server:
      http_listen_port: 3101

    positions:
      filename: /tmp/positions.yaml

    clients:
      - url: http://loki:3100/loki/api/v1/push

    scrape_configs:
      - job_name: kubernetes-audit
        static_configs:
          - targets:
              - localhost
            labels:
              job: kubernetes-audit
              __path__: /var/log/kubernetes/audit/*.log
        pipeline_stages:
          - json:
              expressions:
                level: level
                verb: verb
                user: user.username
                resource: objectRef.resource
                namespace: objectRef.namespace
                name: objectRef.name
                responseCode: responseStatus.code
          - labels:
              level:
              verb:
              user:
              resource:
              namespace:
          - timestamp:
              source: stageTimestamp
              format: RFC3339Nano
```

<br />

Con audit logs en Loki, podés crear dashboards de Grafana que muestren quién está accediendo a tu cluster, qué
cambios se están haciendo, y alertar sobre actividad sospechosa como alguien creando un ClusterRoleBinding o
haciendo exec en un pod de producción.

<br />

##### **Falco para seguridad en runtime**
Gatekeeper y PSS previenen que configuraciones malas entren al cluster, pero, ¿qué pasa con ataques en runtime?
Ahí es donde entra Falco. Falco monitorea system calls a nivel de kernel y alerta cuando detecta comportamiento
sospechoso como un shell siendo creado en un contenedor, archivos sensibles siendo leídos, o conexiones de red
inesperadas.

<br />

**Instalando Falco**

Falco se puede instalar como DaemonSet usando Helm:

<br />

```sql
# Instalar Falco con Helm
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set falcosidekick.enabled=true \
  --set falcosidekick.config.slack.webhookurl="https://hooks.slack.com/services/XXX" \
  --set driver.kind=ebpf \
  --set collectors.kubernetes.enabled=true
```

<br />

**Reglas custom de Falco**

Falco viene con un conjunto completo de reglas por defecto, pero deberías agregar reglas custom específicas para
tu entorno. Acá van algunos ejemplos prácticos:

<br />

```yaml
# falco/custom-rules.yaml
# Detectar exec en pods de producción
- rule: Exec en pod de producción
  desc: Detectar cuando alguien hace exec en un pod del namespace production
  condition: >
    spawned_process
    and container
    and k8s.ns.name = "production"
    and proc.pname = "runc:[2:INIT]"
  output: >
    Shell creado en pod de producción
    (user=%ka.user.name pod=%k8s.pod.name ns=%k8s.ns.name
     container=%container.name command=%proc.cmdline)
  priority: WARNING
  tags: [security, shell, production]

# Detectar lectura de archivos sensibles
- rule: Lectura de archivo sensible en contenedor
  desc: Detectar lectura de archivos sensibles como /etc/shadow o claves privadas
  condition: >
    open_read
    and container
    and (fd.name startswith /etc/shadow
      or fd.name startswith /etc/gshadow
      or fd.name contains id_rsa
      or fd.name contains id_ed25519
      or fd.name endswith .pem
      or fd.name endswith .key)
  output: >
    Archivo sensible leído en contenedor
    (user=%user.name file=%fd.name pod=%k8s.pod.name
     ns=%k8s.ns.name container=%container.name)
  priority: WARNING
  tags: [security, filesystem, sensitive]

# Detectar conexiones salientes inesperadas
- rule: Conexión saliente inesperada desde producción
  desc: Detectar conexiones salientes a IPs que no están en la lista permitida
  condition: >
    outbound
    and container
    and k8s.ns.name = "production"
    and not (fd.sip in (allowed_outbound_ips))
    and not (fd.sport in (53, 443, 5432))
  output: >
    Conexión saliente inesperada desde producción
    (pod=%k8s.pod.name ns=%k8s.ns.name ip=%fd.sip port=%fd.sport
     command=%proc.cmdline container=%container.name)
  priority: NOTICE
  tags: [security, network, production]

# Detectar drift de contenedor (nuevos ejecutables escritos y ejecutados)
- rule: Drift de contenedor detectado
  desc: Detectar cuando nuevos ejecutables son escritos en el filesystem de un contenedor y luego ejecutados
  condition: >
    spawned_process
    and container
    and proc.is_exe_upper_layer = true
  output: >
    Drift detectado: nuevo ejecutable corrido en contenedor
    (user=%user.name command=%proc.cmdline pod=%k8s.pod.name
     ns=%k8s.ns.name container=%container.name image=%container.image.repository)
  priority: ERROR
  tags: [security, drift]

# Detectar minería de criptomonedas
- rule: Detectar actividad de minería de criptomonedas
  desc: Detectar procesos conocidos asociados con minería de criptomonedas
  condition: >
    spawned_process
    and container
    and (proc.name in (xmrig, minerd, cpuminer, cryptonight)
      or proc.cmdline contains "stratum+tcp"
      or proc.cmdline contains "pool.minexmr")
  output: >
    Posible minería de criptomonedas detectada
    (pod=%k8s.pod.name ns=%k8s.ns.name process=%proc.name
     command=%proc.cmdline container=%container.name)
  priority: CRITICAL
  tags: [security, crypto, mining]
```

<br />

Falco te da visibilidad de lo que realmente está pasando dentro de tus contenedores a nivel de system calls.
Combinado con network policies (que controlan qué tráfico está permitido) y Gatekeeper (que controla qué
configuraciones están permitidas), tenés defensa en profundidad cubriendo tiempo de configuración, capa de red
y runtime.

<br />

##### **Seguridad de la cadena de suministro**
Tus imágenes de contenedores son tan confiables como el proceso que las construyó. Los ataques a la cadena de
suministro, donde un atacante compromete una dependencia o pipeline de build para inyectar código malicioso, se
volvieron cada vez más comunes. La solución es firmar tus imágenes y verificar esas firmas antes de permitir
que corran.

<br />

**Firmando imágenes con Cosign**

Cosign del proyecto Sigstore hace fácil firmar y verificar imágenes de contenedores. Así se integra en tu
pipeline de CI:

<br />

```yaml
# .github/workflows/build-and-sign.yaml
name: Build, Sign, and Push

on:
  push:
    branches: [main]

permissions:
  contents: read
  packages: write
  id-token: write  # Requerido para firma keyless

jobs:
  build-sign-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Cosign
        uses: sigstore/cosign-installer@main

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push image
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ghcr.io/kainlite/tr:${{ github.sha }}

      - name: Sign the image with Cosign (keyless)
        env:
          COSIGN_EXPERIMENTAL: "true"
        run: |
          cosign sign --yes \
            ghcr.io/kainlite/tr@${{ steps.build.outputs.digest }}

      - name: Generate SBOM
        uses: anchore/sbom-action@v0
        with:
          image: ghcr.io/kainlite/tr:${{ github.sha }}
          format: spdx-json
          output-file: sbom.spdx.json

      - name: Attach SBOM to image
        run: |
          cosign attach sbom \
            --sbom sbom.spdx.json \
            ghcr.io/kainlite/tr@${{ steps.build.outputs.digest }}
```

<br />

El flag `--yes` usa firma keyless, lo que significa que Cosign obtiene un certificado de corta duración de la
CA Fulcio de Sigstore vinculado a tu identidad OIDC de GitHub Actions. No hay claves de larga duración para
manejar o rotar.

<br />

**Generación de SBOM**

Un Software Bill of Materials (SBOM) es una lista de cada componente en tu imagen. Es esencial para rastrear
cuáles de tus imágenes se ven afectadas cuando se publica un nuevo CVE. El workflow de arriba genera un SBOM en
formato SPDX y lo adjunta a la imagen en el registry.

<br />

**Verificando firmas con Kyverno**

Ahora que tus imágenes están firmadas, necesitás forzar que solo imágenes firmadas puedan correr en el cluster.
Kyverno es un motor de políticas de Kubernetes que puede verificar firmas de Cosign en el momento de admisión:

<br />

```yaml
# kyverno/verify-image-signature.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signatures
  annotations:
    policies.kyverno.io/title: Verificar Firmas de Imágenes
    policies.kyverno.io/description: >
      Verificar que todas las imágenes de contenedores estén firmadas con Cosign
      usando firma keyless de nuestros workflows de GitHub Actions.
spec:
  validationFailureAction: Enforce
  background: false
  webhookTimeoutSeconds: 30
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - production
                - staging
      verifyImages:
        - imageReferences:
            - "ghcr.io/kainlite/*"
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/kainlite/tr/.github/workflows/*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor:
                      url: https://rekor.sigstore.dev
          mutateDigest: true
          required: true
```

<br />

```yaml
# kyverno/require-sbom.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-sbom-attestation
spec:
  validationFailureAction: Audit
  background: false
  rules:
    - name: check-sbom
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - production
      verifyImages:
        - imageReferences:
            - "ghcr.io/kainlite/*"
          attestations:
            - type: https://spdx.dev/Document
              attestors:
                - entries:
                    - keyless:
                        subject: "https://github.com/kainlite/tr/.github/workflows/*"
                        issuer: "https://token.actions.githubusercontent.com"
              conditions:
                - all:
                    - key: "{{ creationInfo.created }}"
                      operator: NotEquals
                      value: ""
```

<br />

Con este setup, el flujo completo de la cadena de suministro es: GitHub Actions construye la imagen, la firma
con Cosign usando firma keyless, genera y adjunta un SBOM, y Kyverno verifica la firma antes de permitir que la
imagen corra en el cluster. Si alguien pushea una imagen sin firmar o una imagen que no fue construida por tu
pipeline de CI, Kyverno la rechaza.

<br />

##### **SLOs de seguridad**
Si venís siguiendo la serie de SRE, sabés que si no podés medirlo, no podés mejorarlo. La seguridad no es
diferente. Igual que rastreás SLOs de disponibilidad y latencia, deberías rastrear métricas de seguridad como
SLIs.

<br />

**Tiempo de remediación de vulnerabilidades**

¿Cuánto le lleva a tu equipo parchear un CVE crítico después de que se descubre? Esta es una de las métricas
de seguridad más importantes:

<br />

```yaml
# prometheus-rules/security-slis.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: security-slis
  namespace: monitoring
spec:
  groups:
    - name: security.slis
      interval: 1h
      rules:
        # Rastrear conteo de vulnerabilidades críticas a lo largo del tiempo
        - record: security:critical_cves:total
          expr: |
            sum(trivy_vulnerability_count{severity="CRITICAL"})

        # Rastrear conteo de vulnerabilidades altas
        - record: security:high_cves:total
          expr: |
            sum(trivy_vulnerability_count{severity="HIGH"})

        # Rastrear tiempo desde el CVE crítico sin parchear más viejo
        - record: security:oldest_critical_cve_age_days
          expr: |
            (time() - min(trivy_vulnerability_first_seen{severity="CRITICAL"})) / 86400

        # Violaciones de política detectadas por auditoría de Gatekeeper
        - record: security:policy_violations:total
          expr: |
            sum(gatekeeper_violations)

        # Tasa de alertas de Falco
        - record: security:falco_alerts:rate1h
          expr: |
            sum(rate(falco_events_total{priority=~"WARNING|ERROR|CRITICAL"}[1h]))
```

<br />

**Definición de SLOs de seguridad**

Definí SLOs concretos para tu postura de seguridad:

<br />

```yaml
# security-slos.yaml
security_slos:
  vulnerability_remediation:
    description: "Los CVEs críticos deben parchearse en 7 días"
    sli: security:oldest_critical_cve_age_days
    objective: 7
    measurement: "Días desde el CVE crítico sin parchear más viejo"

  policy_compliance:
    description: "Cero violaciones de políticas de Gatekeeper en producción"
    sli: security:policy_violations:total
    objective: 0
    measurement: "Total de violaciones de política activas"

  runtime_security:
    description: "Cero alertas críticas de Falco en producción"
    sli: security:falco_alerts:rate1h
    objective: 0
    measurement: "Alertas críticas y de error de Falco por hora"

  image_signing:
    description: "100% de las imágenes de producción deben estar firmadas"
    sli: kyverno:policy_violations:image_signature
    objective: 0
    measurement: "Imágenes sin firmar bloqueadas o corriendo"
```

<br />

**Alertando sobre SLOs de seguridad**

Configurá alertas que se disparen cuando tus SLOs de seguridad estén en riesgo:

<br />

```yaml
# prometheus-rules/security-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: security-alerts
  namespace: monitoring
spec:
  groups:
    - name: security.alerts
      rules:
        - alert: CriticalCVEUnpatchedTooLong
          expr: security:oldest_critical_cve_age_days > 5
          for: 1h
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "CVE crítico sin parchear por más de 5 días"
            description: "El CVE crítico sin parchear más viejo tiene {{ $value }} días. El objetivo del SLO es 7 días."
            runbook: "https://runbooks.example.com/patch-critical-cve"

        - alert: GatekeeperPolicyViolations
          expr: security:policy_violations:total > 0
          for: 5m
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Violaciones de políticas de Gatekeeper detectadas"
            description: "Se encontraron {{ $value }} violaciones de política en el cluster."

        - alert: FalcoCriticalAlert
          expr: security:falco_alerts:rate1h > 0
          for: 0m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "Falco detectó evento de seguridad crítico"
            description: "Falco está reportando {{ $value }} eventos críticos/error por hora."
```

<br />

Tratar las métricas de seguridad como SLIs te da los mismos beneficios que los SLOs de confiabilidad: podés
medir el progreso, definir objetivos, alertar cuando las cosas se desvían, y tomar decisiones basadas en datos
sobre dónde invertir tus esfuerzos de seguridad.

<br />

##### **Juntando todo**
Acá hay un resumen del stack completo de seguridad como código que construimos:

<br />

> 1. **OPA Gatekeeper**: Políticas de control de admisión que fuerzan labels, bloquean contenedores privilegiados y restringen registries de imágenes
> 2. **Pod Security Standards**: Perfiles de seguridad a nivel de namespace incluidos en Kubernetes (Privileged, Baseline, Restricted)
> 3. **Network policies**: Default deny con reglas de allow explícitas, filtrado L7 con Cilium
> 4. **Escaneo de imágenes con Trivy**: Pipeline de CI que bloquea deployments con vulnerabilidades críticas
> 5. **Hardening de RBAC**: Roles de menor privilegio, aislamiento de service accounts, ClusterRoles agregados
> 6. **Audit logging**: Registrando actividad del API server y enviándola a tu stack de observabilidad
> 7. **Seguridad en runtime con Falco**: Detectando comportamiento sospechoso a nivel de system calls
> 8. **Seguridad de la cadena de suministro**: Firma de imágenes con Cosign, generación de SBOM, verificación con Kyverno
> 9. **SLOs de seguridad**: Midiendo y alertando sobre tiempo de remediación de vulnerabilidades y métricas de compliance

<br />

Cada capa cubre una fase diferente de la superficie de ataque: Gatekeeper y PSS previenen configuraciones malas,
las network policies limitan el radio de explosión, Trivy detecta vulnerabilidades conocidas, RBAC restringe el
acceso, los audit logs proporcionan evidencia forense, Falco detecta ataques en runtime, y la seguridad de la
cadena de suministro asegura la integridad de las imágenes.

<br />

Ninguna capa sola es perfecta, pero juntas crean defensa en profundidad que hace significativamente más difícil
que un atacante tenga éxito y mucho más fácil para vos detectar y responder cuando algo sale mal.

<br />

##### **Notas finales**
Seguridad como código no se trata de comprar herramientas caras o lograr puntajes de compliance perfectos. Se
trata de aplicar la misma disciplina de ingeniería que usamos para confiabilidad a la seguridad: definir políticas
como código, aplicarlas automáticamente, medir el compliance y mejorar continuamente.

<br />

Empezá de a poco. Si no hacés nada más, agregá una network policy de default deny a tu namespace de producción y
habilitá el Pod Security Standard restricted. Esos dos cambios solos van a reducir significativamente tu
superficie de ataque. Después podés ir sumando políticas de Gatekeeper, escaneo de imágenes, Falco y seguridad
de la cadena de suministro a medida que la madurez de tu equipo crece.

<br />

Lo importante es hacer de la seguridad un proceso continuo, no una auditoría de una sola vez. Tratá el tiempo de
remediación de CVEs como tratás los SLOs de latencia. Medilo, alertá sobre eso e invertí en mejorarlo. Tu yo del
futuro durante el próximo incidente de seguridad te lo va a agradecer.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
