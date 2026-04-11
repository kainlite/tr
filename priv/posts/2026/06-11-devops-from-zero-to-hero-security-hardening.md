%{
  title: "DevOps from Zero to Hero: Security Hardening",
  author: "Gabriel Garrido",
  description: "A practical security checklist for DevOps beginners covering shift-left security, SAST, dependency scanning, container image scanning with Trivy, OIDC authentication, Kubernetes RBAC, network policies, Pod Security Standards, secrets hygiene, and supply chain security...",
  tags: ~w(devops security kubernetes ci-cd beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article eighteen of the DevOps from Zero to Hero series. Over the past seventeen articles
we have built an application, tested it, containerized it, deployed it to Kubernetes, set up GitOps
with ArgoCD, added observability, and assembled a complete CI/CD pipeline. Everything works. But
there is a question we have been skirting around the whole time: is any of this secure?

<br />

Security is not a feature you bolt on at the end. It is a practice you weave into every layer of
your pipeline, your infrastructure, and your daily habits. The good news is that you do not need to
be a security expert to get the basics right. Most real-world breaches come from simple mistakes:
leaked credentials, unpatched dependencies, containers running as root, overly permissive access.
These are all preventable with a checklist and some automation.

<br />

This article is intentionally a beginner-friendly checklist, not a deep dive. If you want
comprehensive coverage of topics like OPA Gatekeeper, Falco, or policy-as-code frameworks, check out
the [SRE Security as Code](/blog/sre-security-as-code) article. For a thorough walk-through of
Kubernetes RBAC at the API level, see the
[RBAC Deep Dive](/blog/rbac-deep-dive). Here we are going to focus on the practical things every
project should do from day one.

<br />

Let's get into it.

<br />

##### **The shift-left security mindset**
The term "shift left" means moving security checks earlier in the development lifecycle. Instead of
discovering a vulnerability in production (or worse, after a breach), you catch it during development
or in your CI pipeline. The earlier you catch a problem, the cheaper and faster it is to fix.

<br />

Think of it like this. If you find a bug while writing code, it takes you five minutes to fix. If you
find it in code review, it takes thirty minutes because you have to context-switch. If you find it in
staging, it takes hours because now QA is involved. If you find it in production, it takes days and
might involve an incident. Security issues follow the same curve, except the stakes are higher because
a security issue can expose your users' data.

<br />

Shifting left does not mean you stop doing security reviews in production. It means you add automated
checks at every stage so that the obvious stuff never makes it that far. Your CI pipeline becomes your
first line of defense.

<br />

The pipeline stages where security checks belong:

<br />

> * **Code time**: Linters, IDE plugins, pre-commit hooks that catch hardcoded secrets or insecure patterns before you even push
> * **Pull request**: SAST tools, dependency scanners, and secret detection run as CI checks on every PR
> * **Build time**: Container image scanning, SBOM generation, base image verification
> * **Deploy time**: Kubernetes admission controllers, Pod Security Standards, RBAC enforcement
> * **Runtime**: Network policies, audit logging, runtime threat detection (covered in the SRE series)

<br />

The rest of this article walks through each of these stages with practical examples you can add to
your project today.

<br />

##### **SAST: Static Application Security Testing**
SAST tools analyze your source code without running it. They look for patterns that are known to cause
security issues: SQL injection, cross-site scripting (XSS), command injection, insecure cryptography,
hardcoded credentials, and more.

<br />

The key thing to understand is that SAST does not find every bug. It finds common patterns that match
known vulnerability signatures. Think of it as a spell checker for security. It catches the obvious
mistakes so you can focus your manual review time on the subtle ones.

<br />

**Semgrep** is one of the best tools for this. It is open source, supports many languages, and has a
huge library of community rules. You can also write your own rules for patterns specific to your
codebase.

<br />

Here is how to add Semgrep to your GitHub Actions pipeline:

<br />

```yaml
# .github/workflows/security.yml
name: Security Checks

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  sast:
    name: SAST Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run Semgrep
        uses: semgrep/semgrep-action@v1
        with:
          config: >-
            p/security-audit
            p/secrets
            p/owasp-top-ten
        env:
          SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }}
```

<br />

The `p/security-audit`, `p/secrets`, and `p/owasp-top-ten` are rule packs that cover the most
common vulnerability patterns. Semgrep will scan your code and report any matches as comments on your
pull request.

<br />

For JavaScript and TypeScript projects, you should also add ESLint security plugins:

<br />

```bash
npm install --save-dev eslint-plugin-security eslint-plugin-no-secrets
```

<br />

```json
{
  "plugins": ["security", "no-secrets"],
  "extends": ["plugin:security/recommended"],
  "rules": {
    "no-secrets/no-secrets": "error",
    "security/detect-eval-with-expression": "error",
    "security/detect-non-literal-fs-filename": "warn",
    "security/detect-possible-timing-attacks": "warn"
  }
}
```

<br />

These plugins run as part of your normal linting step, so they catch issues before code even gets to
the PR stage.

<br />

##### **Dependency scanning**
Your application code is probably 10% of the code that actually runs. The other 90% comes from
dependencies. And those dependencies have their own dependencies (transitive dependencies). A
vulnerability in a deeply nested transitive dependency can be just as dangerous as one in your own
code.

<br />

This is not theoretical. The Log4Shell vulnerability (CVE-2021-44228) was in a logging library that
was a transitive dependency in thousands of Java applications. Most teams did not even know they were
using it until the CVE dropped.

<br />

**npm audit** is the simplest starting point for Node.js projects:

<br />

```bash
# Check for known vulnerabilities
npm audit

# Fix automatically where possible
npm audit fix

# Fail CI if there are high or critical vulnerabilities
npm audit --audit-level=high
```

<br />

Add this to your CI pipeline:

<br />

```yaml
  dependency-scan:
    name: Dependency Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: npm ci

      - name: Run npm audit
        run: npm audit --audit-level=high
```

<br />

**Dependabot** is built into GitHub and automatically creates pull requests when new vulnerability
patches are available. Enable it by adding a configuration file:

<br />

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    reviewers:
      - "your-team"

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

<br />

Notice that we are scanning three ecosystems: npm packages, Docker base images, and GitHub Actions
versions. Each one is a potential attack surface.

<br />

**Snyk** is another popular option that provides deeper analysis than npm audit, including fix
suggestions and prioritization based on exploitability. It has a free tier for open source projects.

<br />

The key habit here is: treat dependency updates as security maintenance, not optional chores. When
Dependabot opens a PR, review it and merge it promptly. Stale dependencies are one of the most
common attack vectors.

<br />

##### **Container image scanning with Trivy**
Your Docker images contain an entire operating system plus your application and its dependencies.
Every package in that OS is a potential vulnerability. Trivy is an open-source scanner that checks
your container images (and your Dockerfiles, and your Kubernetes manifests) for known vulnerabilities.

<br />

First, scan your Dockerfile for misconfigurations:

<br />

```bash
# Install Trivy
brew install trivy  # macOS
# or: sudo apt-get install trivy  # Ubuntu

# Scan a Dockerfile for misconfigurations
trivy config Dockerfile

# Scan a built image for vulnerabilities
trivy image myapp:latest

# Only show high and critical vulnerabilities
trivy image --severity HIGH,CRITICAL myapp:latest

# Fail if any critical vulnerabilities are found (useful for CI)
trivy image --severity CRITICAL --exit-code 1 myapp:latest
```

<br />

Common issues Trivy catches in Dockerfiles:

<br />

> * **Running as root**: Your container should use a non-root user. Add `USER nonroot` to your Dockerfile.
> * **Using latest tag**: Always pin your base image to a specific version or digest.
> * **Missing health checks**: Add a `HEALTHCHECK` instruction so orchestrators know when your app is unhealthy.
> * **Sensitive data in layers**: Never `COPY` secrets into your image. Use build args or mount secrets at runtime.

<br />

Here is a CI job that scans your image after building it:

<br />

```yaml
  image-scan:
    name: Container Image Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: docker build -t myapp:${{ github.sha }} .

      - name: Run Trivy scan
        uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: myapp:${{ github.sha }}
          format: table
          exit-code: 1
          severity: HIGH,CRITICAL
          ignore-unfixed: true
```

<br />

The `ignore-unfixed: true` flag skips vulnerabilities that do not have a fix available yet. This
prevents your pipeline from blocking on issues you cannot actually resolve. You should still track
unfixed vulnerabilities, but they should not break your build.

<br />

##### **OIDC for CI/CD authentication**
If your GitHub Actions workflows deploy to AWS (or any cloud provider), you need credentials. The
old way was to store long-lived access keys as GitHub Secrets. The problem is that those keys never
expire, they exist in multiple places, and if they leak, an attacker has persistent access to your
AWS account.

<br />

OIDC (OpenID Connect) solves this by letting GitHub Actions request short-lived credentials directly
from AWS. No long-lived keys stored anywhere. The credentials last for the duration of the workflow
run and then they expire.

<br />

Here is how to set it up:

<br />

**Step 1: Create an OIDC identity provider in AWS**

<br />

```bash
# Create the OIDC provider (one-time setup)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  --client-id-list "sts.amazonaws.com"
```

<br />

**Step 2: Create an IAM role with a trust policy**

<br />

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID::oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

<br />

The `Condition` block is important. It restricts which repository and branch can assume this role.
Without it, any GitHub repository could use your AWS credentials.

<br />

**Step 3: Use OIDC in your workflow**

<br />

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # Required for OIDC
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID::role/github-actions-deploy
          aws-region: us-east-1

      - name: Deploy
        run: |
          # These credentials are short-lived and scoped to this workflow run
          aws sts get-caller-identity
          # ... your deployment commands
```

<br />

The `permissions.id-token: write` line is what enables OIDC. Without it, the workflow cannot request
a token from GitHub's OIDC provider.

<br />

This pattern works with AWS, GCP, Azure, and any cloud provider that supports OIDC. If your provider
supports it, there is no reason to use long-lived keys.

<br />

##### **Kubernetes RBAC basics**
RBAC (Role-Based Access Control) controls who can do what in your Kubernetes cluster. The principle
is simple: every user, service, and automation should have the minimum permissions it needs to do its
job, and nothing more.

<br />

RBAC has four key resources:

<br />

> * **Role**: Defines a set of permissions within a namespace. For example, "can read pods and services in the staging namespace."
> * **ClusterRole**: Same as Role but applies across the entire cluster. Use this for cluster-wide resources like nodes or namespaces.
> * **RoleBinding**: Connects a Role to a user, group, or ServiceAccount within a namespace.
> * **ClusterRoleBinding**: Connects a ClusterRole to a subject across the entire cluster.

<br />

Here is a basic example that gives a CI/CD ServiceAccount permission to manage deployments in a
specific namespace:

<br />

```yaml
# Create a ServiceAccount for your CI/CD pipeline
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ci-deployer
  namespace: production
---
# Define what it can do
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployer-role
  namespace: production
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
# Bind the role to the ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-deployer-binding
  namespace: production
subjects:
  - kind: ServiceAccount
    name: ci-deployer
    namespace: production
roleRef:
  kind: Role
  name: deployer-role
  apiGroup: rbac.authorization.k8s.io
```

<br />

Notice that the Role only grants `get`, `list`, `update`, and `patch` on deployments. It does not
grant `create` or `delete`. It also does not grant access to secrets, configmaps, or any other
resource. This is the principle of least privilege in action.

<br />

Common mistakes to avoid:

<br />

> * **Using cluster-admin for everything**: The `cluster-admin` ClusterRole gives full access to everything. Never bind it to service accounts used by applications or CI pipelines.
> * **Using default ServiceAccounts**: Every namespace has a `default` ServiceAccount. If you do not create specific ones, all your pods share the same identity. Create dedicated ServiceAccounts for each application.
> * **Not auditing RBAC**: Run `kubectl auth can-i --list --as=system:serviceaccount:production:ci-deployer` to verify what a ServiceAccount can actually do.

<br />

For a much deeper exploration of RBAC, including how it works at the HTTP API level with raw curl
calls, check out the [RBAC Deep Dive](/blog/rbac-deep-dive).

<br />

##### **Network Policies**
By default, every pod in a Kubernetes cluster can talk to every other pod. This is convenient for
development but terrible for security. If an attacker compromises one pod, they can reach every
other service in the cluster.

<br />

Network Policies let you control which pods can communicate with which other pods. Think of them as
firewall rules for your cluster's internal network.

<br />

**Step 1: Start with a default deny policy**

<br />

This blocks all ingress traffic to pods in the namespace. Nothing can talk to anything unless you
explicitly allow it.

<br />

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}    # Applies to all pods in the namespace
  policyTypes:
    - Ingress
```

<br />

**Step 2: Allow specific traffic paths**

<br />

Now you poke holes for the traffic that needs to flow. For example, let the API receive traffic from
the ingress controller:

<br />

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-system
        - podSelector:
            matchLabels:
              app: ingress-controller
      ports:
        - port: 3000
          protocol: TCP
```

<br />

And let the API talk to the database:

<br />

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - port: 5432
          protocol: TCP
```

<br />

The pattern is always the same: deny everything by default, then allow only the specific paths your
application needs. Document these paths. If you cannot explain why a network policy exists, it
probably should not.

<br />

Important note: Network Policies require a CNI plugin that supports them. If you are using EKS, the
default VPC CNI does not enforce Network Policies. You need to enable the Network Policy feature or
use a CNI like Calico. Check your cluster's CNI documentation.

<br />

##### **Pod Security Standards**
Pod Security Standards (PSS) define three profiles that control what pods are allowed to do at the
security level:

<br />

> * **Privileged**: No restrictions. Use this only for system-level pods like CNI plugins or storage drivers that genuinely need host access.
> * **Baseline**: Prevents the most dangerous configurations like running as privileged, using host networking, or mounting the host filesystem. This is a reasonable default for most workloads.
> * **Restricted**: The strictest profile. Requires running as non-root, drops all Linux capabilities, sets a read-only root filesystem, and more. This is what production applications should target.

<br />

The simplest way to enforce these is with namespace labels. Kubernetes has a built-in admission
controller called Pod Security Admission that reads these labels and enforces the corresponding
profile.

<br />

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    # Enforce: reject pods that violate the restricted profile
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest

    # Warn: log a warning for pods that violate restricted
    # (useful during migration to see what would break)
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest

    # Audit: add an audit annotation for baseline violations
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
```

<br />

When you apply the `enforce: restricted` label, Kubernetes will reject any pod that does not meet the
restricted profile. For example, if your pod spec does not include `runAsNonRoot: true`, the pod will
be rejected at admission time.

<br />

Here is what a pod spec looks like when it meets the restricted profile:

<br />

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  namespace: production
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: myapp:1.0.0@sha256:abc123...
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
      resources:
        limits:
          memory: "128Mi"
          cpu: "500m"
        requests:
          memory: "64Mi"
          cpu: "250m"
```

<br />

If you are migrating existing workloads, start with `warn` mode to see what would fail, fix the
violations, and then switch to `enforce`. Do not jump straight to enforce on a production namespace
unless you have tested every workload.

<br />

##### **Secrets hygiene**
Secrets management is covered in depth in the [Secrets and Config](/blog/devops-from-zero-to-hero-secrets-and-config)
article from this series. Here we are going to focus on the hygiene practices that prevent secrets
from leaking in the first place.

<br />

**Never log secrets**. This sounds obvious, but it happens all the time. A debug log statement
prints the entire request object, which includes the Authorization header. A startup script echoes
environment variables to verify configuration. An error handler dumps the full context, including
database connection strings. All of these end up in your logging system, which is usually accessible
to far more people than should have access to your secrets.

<br />

Practical rules:

<br />

> * **Redact sensitive fields in logging**: Configure your logging library to redact fields like `password`, `token`, `secret`, `authorization`, and `cookie`. Most logging libraries support this.
> * **Never echo secrets in CI logs**: If your CI pipeline needs a secret, use masked variables. GitHub Actions masks secrets automatically, but only if you reference them through `${{ secrets.NAME }}`. If you copy the value to a regular variable and echo it, the masking does not apply.
> * **Rotate secrets regularly**: Set a rotation schedule. At minimum, rotate every 90 days. Rotate immediately if someone leaves the team or if you suspect a leak.
> * **Audit who has access**: Periodically review who can read your secrets. In Kubernetes, check which ServiceAccounts have `get` or `list` on secrets. In GitHub, review who has access to repository secrets.
> * **Use short-lived tokens**: Whenever possible, use tokens that expire. OIDC tokens, JWTs with short expiry, temporary AWS credentials. Long-lived tokens are a liability.

<br />

A quick way to check for hardcoded secrets in your codebase before they get committed:

<br />

```bash
# Install gitleaks
brew install gitleaks  # macOS

# Scan the current repo
gitleaks detect --source . --verbose

# Add as a pre-commit hook
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

<br />

##### **Supply chain security**
Supply chain attacks target the tools and dependencies you use rather than your code directly. The
SolarWinds attack, the Codecov breach, and the ua-parser-js npm hijack are all examples. You cannot
eliminate supply chain risk entirely, but you can reduce your exposure significantly.

<br />

**Pin action versions by SHA, not tag**

<br />

GitHub Actions tags are mutable. A malicious actor who compromises a popular action's repository can
update the `v4` tag to point to malicious code, and every workflow using `actions/checkout@v4` would
run it. Pinning by SHA makes your workflow reproducible and tamper-resistant:

<br />

```yaml
# Instead of this (tag can be moved):
- uses: actions/checkout@v4

# Use this (SHA is immutable):
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
```

<br />

Yes, it is less readable. Add a comment with the version number. Security is worth the trade-off.

<br />

**Verify base images**

<br />

Use official images from trusted registries. Pin them by digest, not just by tag:

<br />

```dockerfile
# Instead of this (tag can be overwritten):
FROM node:20-alpine

# Use this (digest is content-addressable and immutable):
FROM node:20-alpine@sha256:abcdef1234567890...
```

<br />

You can find the digest on Docker Hub or by running `docker inspect --format='{{index .RepoDigests 0}}' node:20-alpine`.

<br />

**SBOM (Software Bill of Materials)**

<br />

An SBOM is an inventory of every component in your application. When a new CVE drops, an SBOM tells
you immediately whether you are affected. You do not have to go digging through `node_modules` or
Docker layers.

<br />

Trivy can generate SBOMs:

<br />

```bash
# Generate an SBOM in SPDX format
trivy image --format spdx-json --output sbom.json myapp:latest

# Generate in CycloneDX format
trivy image --format cyclonedx --output sbom.xml myapp:latest
```

<br />

Store your SBOM as a build artifact in your CI pipeline so you can reference it later when new
vulnerabilities are disclosed.

<br />

For a more comprehensive treatment of supply chain security including Cosign image signing and
Kyverno policies, see the [SRE Security as Code](/blog/sre-security-as-code) article.

<br />

##### **The practical security checklist**
Here is a top-10 list of things every project should implement. These are ordered roughly by impact
and effort, so start from the top and work your way down.

<br />

> * **1. Enable Dependabot or equivalent**: Turn on automated dependency updates for all your ecosystems (npm, Docker, GitHub Actions). This takes five minutes and catches most known vulnerabilities automatically.
> * **2. Add secret scanning to your repo**: Enable GitHub secret scanning or add gitleaks as a pre-commit hook. This prevents accidental credential leaks, which are the number one cause of breaches in small teams.
> * **3. Scan container images in CI**: Add Trivy or a similar scanner to your build pipeline. Fail the build on critical vulnerabilities. This catches OS-level vulnerabilities that your language-level scanners miss.
> * **4. Use OIDC instead of long-lived keys**: If your CI deploys to a cloud provider, switch to OIDC authentication. Remove any long-lived access keys from your GitHub Secrets.
> * **5. Run containers as non-root**: Update your Dockerfiles to use a non-root user. Apply Pod Security Standards at the namespace level to enforce this cluster-wide.
> * **6. Implement network policies**: Start with default-deny and explicitly allow the traffic your application needs. This limits blast radius if a pod gets compromised.
> * **7. Create dedicated RBAC roles**: Stop using cluster-admin and default ServiceAccounts. Create specific Roles with minimum permissions for each workload and CI pipeline.
> * **8. Add SAST to your CI pipeline**: Add Semgrep or equivalent SAST tooling. Even the default rule packs catch a surprising number of real issues.
> * **9. Pin your dependencies**: Pin action versions by SHA, pin base images by digest, and use lock files for package managers. This protects against supply chain attacks.
> * **10. Rotate secrets on a schedule**: Set calendar reminders to rotate API keys, database passwords, and service account tokens every 90 days. Automate rotation where possible.

<br />

You do not need to do all ten in one sprint. Start with items 1 through 4. They are quick wins with
high impact. Then work through the rest as you mature your security posture.

<br />

##### **Putting it all together in CI**
Here is a complete security workflow that combines several of the checks we discussed. You can add
this alongside your existing CI pipeline:

<br />

```yaml
# .github/workflows/security.yml
name: Security

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  schedule:
    # Run weekly even without code changes to catch new CVEs
    - cron: "0 8 * * 1"

jobs:
  sast:
    name: SAST
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Semgrep
        uses: semgrep/semgrep-action@v1
        with:
          config: >-
            p/security-audit
            p/secrets
            p/owasp-top-ten

  dependencies:
    name: Dependency Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Install dependencies
        run: npm ci

      - name: npm audit
        run: npm audit --audit-level=high

  image-scan:
    name: Image Scan
    runs-on: ubuntu-latest
    needs: [sast, dependencies]  # Only scan if code checks pass
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Build image
        run: docker build -t myapp:${{ github.sha }} .

      - name: Trivy scan
        uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: myapp:${{ github.sha }}
          format: table
          exit-code: 1
          severity: HIGH,CRITICAL
          ignore-unfixed: true

      - name: Generate SBOM
        if: github.ref == 'refs/heads/main'
        run: |
          trivy image --format spdx-json \
            --output sbom.json myapp:${{ github.sha }}

      - name: Upload SBOM
        if: github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json
```

<br />

A few things to notice:

<br />

> * **Scheduled runs**: The `cron` trigger runs the scan weekly even if no code changes. New CVEs are published constantly, and a dependency that was clean last week might have a critical vulnerability today.
> * **Actions pinned by SHA**: We practice what we preach. The checkout action is pinned to a specific commit.
> * **SBOM as artifact**: On main branch builds, we generate and store an SBOM so we have a record of exactly what went into each release.
> * **Fail fast**: The image scan only runs if SAST and dependency checks pass. No point scanning an image if the code itself has issues.

<br />

##### **Closing notes**
Security is not a project with a finish date. It is a practice, like testing or code review. The
goal is not to make your system impenetrable (nothing is), but to make it hard enough that attackers
move on to easier targets, and to limit the damage when something does get through.

<br />

In this article we covered the shift-left security mindset, SAST with Semgrep and ESLint plugins,
dependency scanning with npm audit and Dependabot, container image scanning with Trivy, OIDC
authentication for CI/CD, Kubernetes RBAC basics, network policies with default deny, Pod Security
Standards and namespace enforcement, secrets hygiene practices, supply chain security with pinned
versions and SBOMs, and a practical top-10 security checklist.

<br />

Every topic here was covered at the checklist level. If you want to go deeper, the
[SRE Security as Code](/blog/sre-security-as-code) article covers OPA Gatekeeper, Falco runtime
security, Cosign image signing, and policy-as-code frameworks. The
[RBAC Deep Dive](/blog/rbac-deep-dive) article walks through RBAC at the Kubernetes API level with
raw HTTP calls.

<br />

Start with the checklist. Pick the top three or four items that your project is missing and implement
them this week. Security is one of those things where doing something is infinitely better than
doing nothing.

<br />

In the next article we will cover disaster recovery and backup strategies, the final layer of
protection when everything else fails.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: Seguridad y Hardening",
  author: "Gabriel Garrido",
  description: "Una checklist practica de seguridad para principiantes en DevOps cubriendo shift-left security, SAST, escaneo de dependencias, escaneo de imagenes de contenedores con Trivy, autenticacion OIDC, RBAC de Kubernetes, network policies, Pod Security Standards, higiene de secretos y seguridad de la cadena de suministro...",
  tags: ~w(devops security kubernetes ci-cd beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo dieciocho de la serie DevOps desde Cero. Durante los ultimos diecisiete
articulos construimos una aplicacion, la testeamos, la containerizamos, la deployeamos a Kubernetes,
configuramos GitOps con ArgoCD, agregamos observabilidad y armamos un pipeline CI/CD completo. Todo
funciona. Pero hay una pregunta que estuvimos esquivando todo este tiempo: algo de esto es seguro?

<br />

La seguridad no es una feature que agregas al final. Es una practica que tejes en cada capa de tu
pipeline, tu infraestructura y tus habitos diarios. La buena noticia es que no necesitas ser un
experto en seguridad para hacer bien lo basico. La mayoria de las brechas reales vienen de errores
simples: credenciales filtradas, dependencias sin parchear, contenedores corriendo como root, accesos
demasiado permisivos. Todo esto se puede prevenir con una checklist y algo de automatizacion.

<br />

Este articulo es intencionalmente una checklist para principiantes, no un deep dive. Si queres
cobertura completa de temas como OPA Gatekeeper, Falco, o frameworks de policy-as-code, mira el
articulo de [SRE Security as Code](/blog/sre-security-as-code). Para un recorrido detallado de RBAC
de Kubernetes a nivel de API, consulta el
[RBAC Deep Dive](/blog/rbac-deep-dive). Aca nos vamos a enfocar en las cosas practicas que todo
proyecto deberia hacer desde el dia uno.

<br />

Vamos a meternos de lleno.

<br />

##### **La mentalidad shift-left en seguridad**
El termino "shift left" significa mover los chequeos de seguridad mas temprano en el ciclo de
desarrollo. En vez de descubrir una vulnerabilidad en produccion (o peor, despues de una brecha),
la detectas durante el desarrollo o en tu pipeline de CI. Cuanto antes encontras un problema, mas
barato y rapido es arreglarlo.

<br />

Pensalo asi. Si encontras un bug mientras escribis codigo, te toma cinco minutos arreglarlo. Si lo
encontras en code review, te toma treinta minutos porque tenes que cambiar de contexto. Si lo
encontras en staging, toma horas porque ahora QA esta involucrado. Si lo encontras en produccion,
toma dias y puede involucrar un incidente. Los problemas de seguridad siguen la misma curva, excepto
que las consecuencias son mas altas porque un problema de seguridad puede exponer los datos de tus
usuarios.

<br />

Shift left no significa que dejas de hacer revisiones de seguridad en produccion. Significa que
agregas chequeos automatizados en cada etapa para que las cosas obvias nunca lleguen tan lejos. Tu
pipeline de CI se convierte en tu primera linea de defensa.

<br />

Las etapas del pipeline donde pertenecen los chequeos de seguridad:

<br />

> * **En el codigo**: Linters, plugins de IDE, pre-commit hooks que detectan secretos hardcodeados o patrones inseguros antes de que hagas push
> * **Pull request**: Herramientas SAST, scanners de dependencias y deteccion de secretos corren como checks de CI en cada PR
> * **Build time**: Escaneo de imagenes de contenedores, generacion de SBOM, verificacion de imagenes base
> * **Deploy time**: Admission controllers de Kubernetes, Pod Security Standards, enforcement de RBAC
> * **Runtime**: Network policies, audit logging, deteccion de amenazas en runtime (cubierto en la serie SRE)

<br />

El resto de este articulo recorre cada una de estas etapas con ejemplos practicos que podes agregar
a tu proyecto hoy.

<br />

##### **SAST: Static Application Security Testing**
Las herramientas SAST analizan tu codigo fuente sin ejecutarlo. Buscan patrones que se sabe que
causan problemas de seguridad: inyeccion SQL, cross-site scripting (XSS), inyeccion de comandos,
criptografia insegura, credenciales hardcodeadas y mas.

<br />

Lo clave que tenes que entender es que SAST no encuentra todos los bugs. Encuentra patrones comunes
que matchean con firmas de vulnerabilidades conocidas. Pensalo como un corrector ortografico para
seguridad. Atrapa los errores obvios para que puedas enfocar tu tiempo de revision manual en los
sutiles.

<br />

**Semgrep** es una de las mejores herramientas para esto. Es open source, soporta muchos lenguajes,
y tiene una biblioteca enorme de reglas de la comunidad. Tambien podes escribir tus propias reglas
para patrones especificos de tu codebase.

<br />

Asi se agrega Semgrep a tu pipeline de GitHub Actions:

<br />

```yaml
# .github/workflows/security.yml
name: Security Checks

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  sast:
    name: SAST Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run Semgrep
        uses: semgrep/semgrep-action@v1
        with:
          config: >-
            p/security-audit
            p/secrets
            p/owasp-top-ten
        env:
          SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }}
```

<br />

Los `p/security-audit`, `p/secrets` y `p/owasp-top-ten` son paquetes de reglas que cubren los
patrones de vulnerabilidades mas comunes. Semgrep va a escanear tu codigo y reportar cualquier
coincidencia como comentarios en tu pull request.

<br />

Para proyectos JavaScript y TypeScript, tambien deberias agregar plugins de seguridad de ESLint:

<br />

```bash
npm install --save-dev eslint-plugin-security eslint-plugin-no-secrets
```

<br />

```json
{
  "plugins": ["security", "no-secrets"],
  "extends": ["plugin:security/recommended"],
  "rules": {
    "no-secrets/no-secrets": "error",
    "security/detect-eval-with-expression": "error",
    "security/detect-non-literal-fs-filename": "warn",
    "security/detect-possible-timing-attacks": "warn"
  }
}
```

<br />

Estos plugins corren como parte de tu paso normal de linting, asi que detectan problemas antes de
que el codigo llegue al PR.

<br />

##### **Escaneo de dependencias**
Tu codigo de aplicacion es probablemente el 10% del codigo que realmente se ejecuta. El otro 90%
viene de las dependencias. Y esas dependencias tienen sus propias dependencias (dependencias
transitivas). Una vulnerabilidad en una dependencia transitiva profundamente anidada puede ser tan
peligrosa como una en tu propio codigo.

<br />

Esto no es teorico. La vulnerabilidad Log4Shell (CVE-2021-44228) estaba en una libreria de logging
que era una dependencia transitiva en miles de aplicaciones Java. La mayoria de los equipos ni sabian
que la estaban usando hasta que salio el CVE.

<br />

**npm audit** es el punto de partida mas simple para proyectos Node.js:

<br />

```bash
# Chequear vulnerabilidades conocidas
npm audit

# Arreglar automaticamente donde sea posible
npm audit fix

# Fallar en CI si hay vulnerabilidades altas o criticas
npm audit --audit-level=high
```

<br />

Agrega esto a tu pipeline de CI:

<br />

```yaml
  dependency-scan:
    name: Dependency Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: npm ci

      - name: Run npm audit
        run: npm audit --audit-level=high
```

<br />

**Dependabot** viene integrado en GitHub y crea pull requests automaticamente cuando hay parches de
vulnerabilidades disponibles. Activalo agregando un archivo de configuracion:

<br />

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    reviewers:
      - "your-team"

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

<br />

Fijate que estamos escaneando tres ecosistemas: paquetes npm, imagenes base de Docker y versiones
de GitHub Actions. Cada uno es una superficie de ataque potencial.

<br />

**Snyk** es otra opcion popular que provee analisis mas profundo que npm audit, incluyendo
sugerencias de arreglo y priorizacion basada en explotabilidad. Tiene un tier gratuito para proyectos
open source.

<br />

El habito clave aca es: trata las actualizaciones de dependencias como mantenimiento de seguridad,
no como tareas opcionales. Cuando Dependabot abre un PR, revisalo y mergealo rapido. Las
dependencias desactualizadas son uno de los vectores de ataque mas comunes.

<br />

##### **Escaneo de imagenes de contenedores con Trivy**
Tus imagenes Docker contienen un sistema operativo entero mas tu aplicacion y sus dependencias. Cada
paquete en ese SO es una vulnerabilidad potencial. Trivy es un scanner open-source que chequea tus
imagenes de contenedores (y tus Dockerfiles, y tus manifiestos de Kubernetes) buscando
vulnerabilidades conocidas.

<br />

Primero, escanea tu Dockerfile buscando misconfiguraciones:

<br />

```bash
# Instalar Trivy
brew install trivy  # macOS
# o: sudo apt-get install trivy  # Ubuntu

# Escanear un Dockerfile buscando misconfiguraciones
trivy config Dockerfile

# Escanear una imagen construida buscando vulnerabilidades
trivy image myapp:latest

# Mostrar solo vulnerabilidades altas y criticas
trivy image --severity HIGH,CRITICAL myapp:latest

# Fallar si se encuentran vulnerabilidades criticas (util para CI)
trivy image --severity CRITICAL --exit-code 1 myapp:latest
```

<br />

Problemas comunes que Trivy detecta en Dockerfiles:

<br />

> * **Corriendo como root**: Tu contenedor deberia usar un usuario no-root. Agrega `USER nonroot` a tu Dockerfile.
> * **Usando el tag latest**: Siempre fija tu imagen base a una version o digest especifico.
> * **Sin health checks**: Agrega una instruccion `HEALTHCHECK` para que los orquestadores sepan cuando tu app no esta sana.
> * **Datos sensibles en las capas**: Nunca hagas `COPY` de secretos a tu imagen. Usa build args o monta secretos en runtime.

<br />

Aca hay un job de CI que escanea tu imagen despues de construirla:

<br />

```yaml
  image-scan:
    name: Container Image Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: docker build -t myapp:${{ github.sha }} .

      - name: Run Trivy scan
        uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: myapp:${{ github.sha }}
          format: table
          exit-code: 1
          severity: HIGH,CRITICAL
          ignore-unfixed: true
```

<br />

El flag `ignore-unfixed: true` omite vulnerabilidades que no tienen un fix disponible todavia. Esto
evita que tu pipeline se bloquee por problemas que no podes resolver. Igual deberias trackear las
vulnerabilidades sin fix, pero no deberian romper tu build.

<br />

##### **OIDC para autenticacion de CI/CD**
Si tus workflows de GitHub Actions deployean a AWS (o cualquier proveedor cloud), necesitas
credenciales. La forma vieja era guardar access keys de larga duracion como GitHub Secrets. El
problema es que esas keys nunca expiran, existen en multiples lugares, y si se filtran, un atacante
tiene acceso persistente a tu cuenta de AWS.

<br />

OIDC (OpenID Connect) resuelve esto permitiendo que GitHub Actions solicite credenciales de corta
duracion directamente de AWS. No hay keys de larga duracion guardadas en ningun lado. Las
credenciales duran lo que dura la ejecucion del workflow y despues expiran.

<br />

Asi se configura:

<br />

**Paso 1: Crear un proveedor de identidad OIDC en AWS**

<br />

```bash
# Crear el proveedor OIDC (configuracion unica)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  --client-id-list "sts.amazonaws.com"
```

<br />

**Paso 2: Crear un rol IAM con una politica de confianza**

<br />

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID::oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

<br />

El bloque `Condition` es importante. Restringe que repositorio y rama pueden asumir este rol. Sin
el, cualquier repositorio de GitHub podria usar tus credenciales de AWS.

<br />

**Paso 3: Usar OIDC en tu workflow**

<br />

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # Requerido para OIDC
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID::role/github-actions-deploy
          aws-region: us-east-1

      - name: Deploy
        run: |
          # Estas credenciales son de corta duracion y con scope a esta ejecucion
          aws sts get-caller-identity
          # ... tus comandos de deployment
```

<br />

La linea `permissions.id-token: write` es lo que habilita OIDC. Sin ella, el workflow no puede
solicitar un token del proveedor OIDC de GitHub.

<br />

Este patron funciona con AWS, GCP, Azure y cualquier proveedor cloud que soporte OIDC. Si tu
proveedor lo soporta, no hay razon para usar keys de larga duracion.

<br />

##### **Conceptos basicos de RBAC en Kubernetes**
RBAC (Role-Based Access Control) controla quien puede hacer que en tu cluster de Kubernetes. El
principio es simple: cada usuario, servicio y automatizacion deberia tener los permisos minimos que
necesita para hacer su trabajo, y nada mas.

<br />

RBAC tiene cuatro recursos clave:

<br />

> * **Role**: Define un conjunto de permisos dentro de un namespace. Por ejemplo, "puede leer pods y services en el namespace staging."
> * **ClusterRole**: Igual que Role pero aplica en todo el cluster. Usalo para recursos cluster-wide como nodos o namespaces.
> * **RoleBinding**: Conecta un Role a un usuario, grupo o ServiceAccount dentro de un namespace.
> * **ClusterRoleBinding**: Conecta un ClusterRole a un sujeto en todo el cluster.

<br />

Aca hay un ejemplo basico que le da a un ServiceAccount de CI/CD permisos para manejar deployments
en un namespace especifico:

<br />

```yaml
# Crear un ServiceAccount para tu pipeline CI/CD
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ci-deployer
  namespace: production
---
# Definir que puede hacer
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployer-role
  namespace: production
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
# Vincular el role al ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-deployer-binding
  namespace: production
subjects:
  - kind: ServiceAccount
    name: ci-deployer
    namespace: production
roleRef:
  kind: Role
  name: deployer-role
  apiGroup: rbac.authorization.k8s.io
```

<br />

Fijate que el Role solo otorga `get`, `list`, `update` y `patch` sobre deployments. No otorga
`create` ni `delete`. Tampoco otorga acceso a secrets, configmaps ni ningun otro recurso. Este es
el principio de minimo privilegio en accion.

<br />

Errores comunes a evitar:

<br />

> * **Usar cluster-admin para todo**: El ClusterRole `cluster-admin` da acceso total a todo. Nunca lo vincules a service accounts usados por aplicaciones o pipelines de CI.
> * **Usar ServiceAccounts default**: Cada namespace tiene un ServiceAccount `default`. Si no creas especificos, todos tus pods comparten la misma identidad. Crea ServiceAccounts dedicados para cada aplicacion.
> * **No auditar RBAC**: Ejecuta `kubectl auth can-i --list --as=system:serviceaccount:production:ci-deployer` para verificar que puede hacer realmente un ServiceAccount.

<br />

Para una exploracion mucho mas profunda de RBAC, incluyendo como funciona a nivel de API HTTP con
llamadas curl crudas, mira el [RBAC Deep Dive](/blog/rbac-deep-dive).

<br />

##### **Network Policies**
Por defecto, cada pod en un cluster de Kubernetes puede hablar con cada otro pod. Esto es conveniente
para desarrollo pero terrible para seguridad. Si un atacante compromete un pod, puede alcanzar todos
los demas servicios en el cluster.

<br />

Las Network Policies te permiten controlar que pods se pueden comunicar con cuales otros. Pensalas
como reglas de firewall para la red interna de tu cluster.

<br />

**Paso 1: Empezar con una politica de deny por defecto**

<br />

Esto bloquea todo el trafico ingress hacia los pods en el namespace. Nada puede hablar con nada
a menos que lo permitas explicitamente.

<br />

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}    # Aplica a todos los pods en el namespace
  policyTypes:
    - Ingress
```

<br />

**Paso 2: Permitir rutas de trafico especificas**

<br />

Ahora abris agujeros para el trafico que necesita fluir. Por ejemplo, dejar que la API reciba
trafico del ingress controller:

<br />

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-system
        - podSelector:
            matchLabels:
              app: ingress-controller
      ports:
        - port: 3000
          protocol: TCP
```

<br />

Y dejar que la API se comunique con la base de datos:

<br />

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - port: 5432
          protocol: TCP
```

<br />

El patron es siempre el mismo: negar todo por defecto, y despues permitir solo las rutas especificas
que tu aplicacion necesita. Documenta estas rutas. Si no podes explicar por que existe una network
policy, probablemente no deberia existir.

<br />

Nota importante: las Network Policies requieren un plugin CNI que las soporte. Si estas usando EKS,
el VPC CNI por defecto no aplica Network Policies. Necesitas habilitar la funcionalidad de Network
Policy o usar un CNI como Calico. Revisa la documentacion del CNI de tu cluster.

<br />

##### **Pod Security Standards**
Los Pod Security Standards (PSS) definen tres perfiles que controlan que pueden hacer los pods a
nivel de seguridad:

<br />

> * **Privileged**: Sin restricciones. Usalo solo para pods a nivel de sistema como plugins CNI o drivers de almacenamiento que genuinamente necesitan acceso al host.
> * **Baseline**: Previene las configuraciones mas peligrosas como correr como privilegiado, usar networking del host, o montar el filesystem del host. Este es un default razonable para la mayoria de los workloads.
> * **Restricted**: El perfil mas estricto. Requiere correr como non-root, eliminar todas las capabilities de Linux, configurar un root filesystem de solo lectura, y mas. Esto es lo que las aplicaciones de produccion deberian apuntar.

<br />

La forma mas simple de aplicar estos es con labels de namespace. Kubernetes tiene un admission
controller integrado llamado Pod Security Admission que lee estos labels y aplica el perfil
correspondiente.

<br />

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    # Enforce: rechazar pods que violen el perfil restricted
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest

    # Warn: loguear un warning para pods que violen restricted
    # (util durante la migracion para ver que se romperia)
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest

    # Audit: agregar una anotacion de auditoria para violaciones de baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
```

<br />

Cuando aplicas el label `enforce: restricted`, Kubernetes va a rechazar cualquier pod que no cumpla
con el perfil restricted. Por ejemplo, si tu pod spec no incluye `runAsNonRoot: true`, el pod va a
ser rechazado en el momento de la admision.

<br />

Aca esta como se ve un pod spec que cumple con el perfil restricted:

<br />

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  namespace: production
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: myapp:1.0.0@sha256:abc123...
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
      resources:
        limits:
          memory: "128Mi"
          cpu: "500m"
        requests:
          memory: "64Mi"
          cpu: "250m"
```

<br />

Si estas migrando workloads existentes, empeza con modo `warn` para ver que fallaria, arregla las
violaciones y despues cambia a `enforce`. No saltes directo a enforce en un namespace de produccion
a menos que hayas testeado todos los workloads.

<br />

##### **Higiene de secretos**
La gestion de secretos se cubre en profundidad en el articulo de
[Secrets y Configuracion](/blog/devops-from-zero-to-hero-secrets-and-config) de esta serie. Aca nos
vamos a enfocar en las practicas de higiene que previenen que los secretos se filtren en primer lugar.

<br />

**Nunca loguees secretos**. Esto suena obvio, pero pasa todo el tiempo. Un statement de debug log
imprime el objeto request entero, que incluye el header Authorization. Un script de arranque hace
echo de las variables de entorno para verificar la configuracion. Un manejador de errores hace dump
del contexto completo, incluyendo strings de conexion a la base de datos. Todo esto termina en tu
sistema de logging, que generalmente es accesible para mucha mas gente de la que deberia tener acceso
a tus secretos.

<br />

Reglas practicas:

<br />

> * **Redacta campos sensibles en el logging**: Configura tu libreria de logging para redactar campos como `password`, `token`, `secret`, `authorization` y `cookie`. La mayoria de las librerias de logging soportan esto.
> * **Nunca hagas echo de secretos en logs de CI**: Si tu pipeline de CI necesita un secreto, usa variables enmascaradas. GitHub Actions enmascara secretos automaticamente, pero solo si los referenciascon `${{ secrets.NAME }}`. Si copias el valor a una variable regular y haces echo, el enmascaramiento no aplica.
> * **Rota secretos regularmente**: Establece un calendario de rotacion. Como minimo, rota cada 90 dias. Rota inmediatamente si alguien deja el equipo o si sospechas una filtracion.
> * **Audita quien tiene acceso**: Periodicamente revisa quien puede leer tus secretos. En Kubernetes, chequea que ServiceAccounts tienen `get` o `list` sobre secrets. En GitHub, revisa quien tiene acceso a los secrets del repositorio.
> * **Usa tokens de corta duracion**: Siempre que sea posible, usa tokens que expiren. Tokens OIDC, JWTs con expiracion corta, credenciales temporales de AWS. Los tokens de larga duracion son un pasivo.

<br />

Una forma rapida de chequear secretos hardcodeados en tu codebase antes de que se commiteen:

<br />

```bash
# Instalar gitleaks
brew install gitleaks  # macOS

# Escanear el repo actual
gitleaks detect --source . --verbose

# Agregar como pre-commit hook
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

<br />

##### **Seguridad de la cadena de suministro**
Los ataques a la cadena de suministro apuntan a las herramientas y dependencias que usas en vez de
a tu codigo directamente. El ataque de SolarWinds, la brecha de Codecov y el secuestro de ua-parser-js
en npm son todos ejemplos. No podes eliminar el riesgo de cadena de suministro completamente, pero
podes reducir tu exposicion significativamente.

<br />

**Pinear versiones de actions por SHA, no por tag**

<br />

Los tags de GitHub Actions son mutables. Un actor malicioso que comprometa el repositorio de una
action popular puede actualizar el tag `v4` para apuntar a codigo malicioso, y cada workflow usando
`actions/checkout@v4` lo ejecutaria. Pinear por SHA hace tu workflow reproducible y resistente a
manipulacion:

<br />

```yaml
# En vez de esto (el tag se puede mover):
- uses: actions/checkout@v4

# Usa esto (el SHA es inmutable):
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
```

<br />

Si, es menos legible. Agrega un comentario con el numero de version. La seguridad vale el trade-off.

<br />

**Verificar imagenes base**

<br />

Usa imagenes oficiales de registries confiables. Pinealas por digest, no solo por tag:

<br />

```dockerfile
# En vez de esto (el tag se puede sobreescribir):
FROM node:20-alpine

# Usa esto (el digest es content-addressable e inmutable):
FROM node:20-alpine@sha256:abcdef1234567890...
```

<br />

Podes encontrar el digest en Docker Hub o ejecutando `docker inspect --format='{{index .RepoDigests 0}}' node:20-alpine`.

<br />

**SBOM (Software Bill of Materials)**

<br />

Un SBOM es un inventario de cada componente en tu aplicacion. Cuando sale un nuevo CVE, un SBOM te
dice inmediatamente si estas afectado. No tenes que ir a escarbar en `node_modules` o capas de
Docker.

<br />

Trivy puede generar SBOMs:

<br />

```bash
# Generar un SBOM en formato SPDX
trivy image --format spdx-json --output sbom.json myapp:latest

# Generar en formato CycloneDX
trivy image --format cyclonedx --output sbom.xml myapp:latest
```

<br />

Guarda tu SBOM como un artefacto de build en tu pipeline de CI para poder referenciarlo despues
cuando se divulguen nuevas vulnerabilidades.

<br />

Para un tratamiento mas completo de seguridad de la cadena de suministro incluyendo firma de
imagenes con Cosign y politicas de Kyverno, mira el articulo de
[SRE Security as Code](/blog/sre-security-as-code).

<br />

##### **La checklist practica de seguridad**
Aca hay una lista top-10 de cosas que todo proyecto deberia implementar. Estan ordenadas
aproximadamente por impacto y esfuerzo, asi que empeza desde arriba y avanza hacia abajo.

<br />

> * **1. Habilitar Dependabot o equivalente**: Activa actualizaciones automaticas de dependencias para todos tus ecosistemas (npm, Docker, GitHub Actions). Esto toma cinco minutos y detecta la mayoria de las vulnerabilidades conocidas automaticamente.
> * **2. Agregar escaneo de secretos a tu repo**: Habilita GitHub secret scanning o agrega gitleaks como pre-commit hook. Esto previene filtraciones accidentales de credenciales, que son la causa numero uno de brechas en equipos chicos.
> * **3. Escanear imagenes de contenedores en CI**: Agrega Trivy o un scanner similar a tu pipeline de build. Falla el build en vulnerabilidades criticas. Esto detecta vulnerabilidades a nivel de SO que tus scanners a nivel de lenguaje no captan.
> * **4. Usar OIDC en vez de keys de larga duracion**: Si tu CI deployea a un proveedor cloud, cambia a autenticacion OIDC. Elimina cualquier access key de larga duracion de tus GitHub Secrets.
> * **5. Correr contenedores como non-root**: Actualiza tus Dockerfiles para usar un usuario non-root. Aplica Pod Security Standards a nivel de namespace para forzar esto en todo el cluster.
> * **6. Implementar network policies**: Empeza con default-deny y permite explicitamente el trafico que tu aplicacion necesita. Esto limita el radio de explosion si un pod se ve comprometido.
> * **7. Crear roles RBAC dedicados**: Deja de usar cluster-admin y ServiceAccounts default. Crea Roles especificos con permisos minimos para cada workload y pipeline de CI.
> * **8. Agregar SAST a tu pipeline de CI**: Agrega Semgrep o herramientas SAST equivalentes. Incluso los paquetes de reglas por defecto detectan una cantidad sorprendente de problemas reales.
> * **9. Pinear tus dependencias**: Pinea versiones de actions por SHA, pinea imagenes base por digest, y usa lock files para package managers. Esto protege contra ataques a la cadena de suministro.
> * **10. Rotar secretos con un calendario**: Pone recordatorios en el calendario para rotar API keys, passwords de base de datos y tokens de service accounts cada 90 dias. Automatiza la rotacion donde sea posible.

<br />

No necesitas hacer las diez en un sprint. Empeza con los items 1 a 4. Son quick wins con alto
impacto. Despues avanza con el resto a medida que madure tu postura de seguridad.

<br />

##### **Juntando todo en CI**
Aca hay un workflow de seguridad completo que combina varios de los chequeos que discutimos. Podes
agregar esto junto a tu pipeline de CI existente:

<br />

```yaml
# .github/workflows/security.yml
name: Security

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  schedule:
    # Correr semanalmente incluso sin cambios de codigo para detectar nuevos CVEs
    - cron: "0 8 * * 1"

jobs:
  sast:
    name: SAST
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Semgrep
        uses: semgrep/semgrep-action@v1
        with:
          config: >-
            p/security-audit
            p/secrets
            p/owasp-top-ten

  dependencies:
    name: Dependency Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Install dependencies
        run: npm ci

      - name: npm audit
        run: npm audit --audit-level=high

  image-scan:
    name: Image Scan
    runs-on: ubuntu-latest
    needs: [sast, dependencies]  # Solo escanear si los chequeos de codigo pasan
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Build image
        run: docker build -t myapp:${{ github.sha }} .

      - name: Trivy scan
        uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: myapp:${{ github.sha }}
          format: table
          exit-code: 1
          severity: HIGH,CRITICAL
          ignore-unfixed: true

      - name: Generate SBOM
        if: github.ref == 'refs/heads/main'
        run: |
          trivy image --format spdx-json \
            --output sbom.json myapp:${{ github.sha }}

      - name: Upload SBOM
        if: github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json
```

<br />

Algunas cosas para notar:

<br />

> * **Ejecuciones programadas**: El trigger `cron` ejecuta el escaneo semanalmente incluso si no hay cambios de codigo. Nuevos CVEs se publican constantemente, y una dependencia que estaba limpia la semana pasada puede tener una vulnerabilidad critica hoy.
> * **Actions pineadas por SHA**: Practicamos lo que predicamos. La action de checkout esta pineada a un commit especifico.
> * **SBOM como artefacto**: En builds de la rama main, generamos y guardamos un SBOM para tener un registro de exactamente que fue a cada release.
> * **Fallar rapido**: El escaneo de imagen solo corre si los chequeos SAST y de dependencias pasan. No tiene sentido escanear una imagen si el codigo en si tiene problemas.

<br />

##### **Notas finales**
La seguridad no es un proyecto con fecha de finalizacion. Es una practica, como testing o code
review. El objetivo no es hacer tu sistema impenetrable (nada lo es), sino hacerlo lo suficientemente
dificil para que los atacantes se muevan a objetivos mas faciles, y limitar el dano cuando algo
logra pasar.

<br />

En este articulo cubrimos la mentalidad shift-left de seguridad, SAST con Semgrep y plugins de
ESLint, escaneo de dependencias con npm audit y Dependabot, escaneo de imagenes de contenedores con
Trivy, autenticacion OIDC para CI/CD, conceptos basicos de RBAC en Kubernetes, network policies con
default deny, Pod Security Standards y enforcement por namespace, practicas de higiene de secretos,
seguridad de la cadena de suministro con versiones pineadas y SBOMs, y una checklist practica de
seguridad top-10.

<br />

Cada tema aca fue cubierto a nivel de checklist. Si queres ir mas profundo, el articulo de
[SRE Security as Code](/blog/sre-security-as-code) cubre OPA Gatekeeper, seguridad en runtime con
Falco, firma de imagenes con Cosign y frameworks de policy-as-code. El articulo de
[RBAC Deep Dive](/blog/rbac-deep-dive) recorre RBAC a nivel de API de Kubernetes con llamadas HTTP
crudas.

<br />

Empeza con la checklist. Elegí los tres o cuatro items que tu proyecto le faltan e implementalos
esta semana. La seguridad es una de esas cosas donde hacer algo es infinitamente mejor que no hacer
nada.

<br />

En el proximo articulo vamos a cubrir disaster recovery y estrategias de backup, la ultima capa de
proteccion cuando todo lo demas falla.

<br />

Espero que te haya resultado util y que hayas disfrutado la lectura, hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se
corrija.

Tambien, podes ver el codigo fuente y los cambios en los [fuentes aca](https://github.com/kainlite/tr)

<br />
