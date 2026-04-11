%{
  title: "DevOps from Zero to Hero: CI/CD, The Complete Pipeline",
  author: "Gabriel Garrido",
  description: "We will build a complete end-to-end CI/CD pipeline with GitHub Actions covering lint, test, build, staging deploy, smoke tests, production promotion with manual approval, and rollback strategies...",
  tags: ~w(devops ci-cd github-actions kubernetes beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article sixteen of the DevOps from Zero to Hero series. Over the past fifteen articles we
have covered everything from writing a TypeScript API, to version control, testing, CI, infrastructure
as code, Kubernetes, Helm, secrets, and more. Each piece solved a specific problem, but we have not yet
stitched them all together into one cohesive, end-to-end pipeline.

<br />

That changes now. In this article we are going to build a complete CI/CD pipeline that takes your code
from a pull request all the way to production. Not a toy example. A real, multi-job GitHub Actions
workflow that lints, tests, builds, deploys to staging, runs smoke tests, waits for manual approval,
and then promotes to production. We will also cover deployment strategies, rollback procedures, and best
practices for keeping your pipeline fast and reliable.

<br />

If you have been following the series, think of this article as the glue that connects everything.
If you are jumping in fresh, do not worry. We will explain each piece as we go.

<br />

Let's get into it.

<br />

##### **The pipeline philosophy**
Before we write a single line of YAML, let's establish the principles that drive a good CI/CD pipeline:

<br />

> * **Every commit to main should be deployable**: If something is in main, it has been linted, tested, and built. It is ready to ship. If it is not ready, it should not be in main.
> * **Environments are gates, not destinations**: Staging exists to validate, not to accumulate. Code should flow through staging quickly, not sit there for weeks. Production is the destination.
> * **Fail fast, fail loud**: If something is broken, you want to know in seconds, not minutes. Put the cheapest checks first (lint, format) and the expensive ones later (integration tests, builds).
> * **Automation over manual processes**: Every manual step is a step that can be forgotten, done wrong, or skipped under pressure. Automate everything except the final production approval.
> * **Reproducibility**: Your pipeline should produce the same result whether you run it today or three months from now. Pin your versions, cache your dependencies, and use immutable artifacts.

<br />

These are not abstract ideals. They are engineering decisions that prevent outages, reduce toil, and
let you ship with confidence. Every design choice in the pipeline we are about to build traces back
to one of these principles.

<br />

##### **Pipeline stages overview**
Our pipeline will have seven stages, organized into three phases:

<br />

```plaintext
Phase 1: Validate (on every PR and push to main)
  ├── Lint       -> ESLint, Prettier, type checking
  └── Test       -> Unit tests, integration tests, coverage

Phase 2: Build and Deploy to Staging (on push to main only)
  ├── Build      -> Docker image build and push to registry
  ├── Deploy     -> Deploy to staging namespace via ArgoCD
  └── Smoke Test -> Health check and API tests against staging

Phase 3: Promote to Production (manual approval)
  ├── Approve    -> Manual approval gate via GitHub Environments
  └── Deploy     -> Deploy to production namespace
```

<br />

Phase 1 runs on every pull request and every push to main. It is your safety net. Phase 2 only runs
on pushes to main (merged PRs) because you do not want to deploy feature branches to staging. Phase 3
requires a human to click "Approve" before code reaches production. This is the one manual step we
keep on purpose, because deploying to production should be a conscious decision.

<br />

##### **GitHub Actions environments**
GitHub Actions has a feature called Environments that gives you exactly what we need: environment-specific
secrets, protection rules, and deployment history. Let's set them up.

<br />

Go to your repository on GitHub, then Settings, then Environments. Create two environments:

<br />

> * **staging**: No protection rules needed. Deployments here should be automatic after the build passes.
> * **production**: Add a "Required reviewers" protection rule. Pick one or more team members who must approve before a deployment can proceed.

<br />

You can also add a "Wait timer" to production if you want a mandatory cooldown period between
staging and production deploys. Some teams set this to 15 minutes to give smoke tests extra time
to surface issues.

<br />

##### **Environment-specific secrets and variables**
Each environment can have its own secrets and variables. This is how you handle the fact that staging
and production use different clusters, namespaces, databases, and API keys without littering your
workflow with `if` conditionals.

<br />

Here is what you would typically configure:

<br />

```plaintext
Repository secrets (shared):
  REGISTRY_USERNAME    -> your container registry username
  REGISTRY_PASSWORD    -> your container registry token

Staging environment secrets:
  KUBE_CONFIG          -> kubeconfig for your staging cluster
  DATABASE_URL         -> staging database connection string
  ARGOCD_AUTH_TOKEN    -> ArgoCD token for staging

Staging environment variables:
  KUBE_NAMESPACE       -> staging
  APP_URL              -> https://staging.myapp.example.com

Production environment secrets:
  KUBE_CONFIG          -> kubeconfig for your production cluster
  DATABASE_URL         -> production database connection string
  ARGOCD_AUTH_TOKEN    -> ArgoCD token for production

Production environment variables:
  KUBE_NAMESPACE       -> production
  APP_URL              -> https://myapp.example.com
```

<br />

When a job specifies `environment: staging`, it can only access the staging secrets and variables.
When it specifies `environment: production`, it gets the production ones. This isolation prevents
the worst kind of mistake: accidentally running a production migration against the staging database,
or vice versa.

<br />

To configure these, go to Settings, then Environments, click on the environment, and add your secrets
and variables there. They work exactly like repository-level secrets but are scoped to the environment.

<br />

##### **The complete workflow**
Here is the full pipeline. We will go through each job in detail after, but first, see the big picture:

<br />

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

permissions:
  contents: read
  packages: write

jobs:
  # Phase 1: Validate
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - run: npm ci

      - name: Run ESLint
        run: npx eslint .

      - name: Check formatting
        run: npx prettier --check .

      - name: Type check
        run: npx tsc --noEmit

  test:
    name: Test
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: myapp_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      DATABASE_URL: postgres://test:test@localhost:5432/myapp_test
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - run: npm ci

      - name: Run tests with coverage
        run: npm test -- --coverage

      - name: Upload coverage
        if: github.event_name == 'push'
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
          retention-days: 14

  # Phase 2: Build and Deploy to Staging
  build:
    name: Build and Push Image
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}
      image-digest: ${{ steps.build.outputs.digest }}
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - name: Log in to registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=
            type=raw,value=latest

      - name: Build and push
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    needs: [build]
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - name: Install ArgoCD CLI
        run: |
          curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
          chmod +x argocd
          sudo mv argocd /usr/local/bin/

      - name: Deploy to staging
        env:
          ARGOCD_SERVER: ${{ vars.ARGOCD_SERVER }}
          ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
        run: |
          argocd app set myapp-staging \
            --parameter image.tag=${{ github.sha }} \
            --grpc-web

          argocd app sync myapp-staging \
            --grpc-web \
            --timeout 300

          argocd app wait myapp-staging \
            --grpc-web \
            --timeout 300 \
            --health

  smoke-test:
    name: Smoke Tests
    runs-on: ubuntu-latest
    needs: [deploy-staging]
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - name: Wait for deployment to stabilize
        run: sleep 30

      - name: Health check
        run: |
          for i in $(seq 1 10); do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
              "${{ vars.APP_URL }}/health")
            if [ "$STATUS" = "200" ]; then
              echo "Health check passed on attempt $i"
              exit 0
            fi
            echo "Attempt $i: got $STATUS, retrying in 10s..."
            sleep 10
          done
          echo "Health check failed after 10 attempts"
          exit 1

      - name: API smoke test
        run: |
          RESPONSE=$(curl -s -w "\n%{http_code}" \
            "${{ vars.APP_URL }}/api/v1/status")
          BODY=$(echo "$RESPONSE" | head -n -1)
          STATUS=$(echo "$RESPONSE" | tail -n 1)

          echo "Status: $STATUS"
          echo "Body: $BODY"

          if [ "$STATUS" != "200" ]; then
            echo "API smoke test failed with status $STATUS"
            exit 1
          fi

          echo "API smoke test passed"

      - name: Run E2E tests against staging
        env:
          BASE_URL: ${{ vars.APP_URL }}
        run: |
          npm ci
          npx playwright test tests/e2e/smoke.spec.ts

  # Phase 3: Promote to Production
  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: [smoke-test]
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Install ArgoCD CLI
        run: |
          curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
          chmod +x argocd
          sudo mv argocd /usr/local/bin/

      - name: Deploy to production
        env:
          ARGOCD_SERVER: ${{ vars.ARGOCD_SERVER }}
          ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
        run: |
          argocd app set myapp-production \
            --parameter image.tag=${{ github.sha }} \
            --grpc-web

          argocd app sync myapp-production \
            --grpc-web \
            --timeout 300

          argocd app wait myapp-production \
            --grpc-web \
            --timeout 300 \
            --health

      - name: Verify production deployment
        run: |
          for i in $(seq 1 10); do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
              "${{ vars.APP_URL }}/health")
            if [ "$STATUS" = "200" ]; then
              echo "Production health check passed"
              exit 0
            fi
            echo "Attempt $i: got $STATUS, retrying in 10s..."
            sleep 10
          done
          echo "Production health check failed"
          exit 1
```

<br />

That is a lot of YAML, so let's break it down piece by piece.

<br />

##### **Phase 1: Validate**
The lint and test jobs run in parallel on every push and pull request. They are the cheapest and fastest
checks, so they go first.

<br />

The lint job runs three checks: ESLint for code quality, Prettier for formatting, and the TypeScript
compiler for type safety. If any of these fail, the pipeline stops. There is no point building a Docker
image for code that does not compile.

<br />

The test job spins up a PostgreSQL service container. GitHub Actions lets you define services alongside
your job, and they are available on `localhost` just like a local database. The tests run with coverage
enabled, and the coverage report is uploaded as an artifact for later review.

<br />

Notice that lint and test have no dependency on each other. They run in parallel by default, which
means the validate phase takes as long as the slower of the two, not the sum of both.

<br />

##### **Phase 2: Build and deploy to staging**
The build job only runs on pushes to main (not on pull requests) and only after both lint and test
pass. This is controlled by the `needs: [lint, test]` dependency and the `if` conditional.

<br />

We use Docker Buildx with GitHub Actions cache (`cache-from: type=gha`). This means subsequent
builds reuse cached layers, which can cut build time from minutes to seconds. The image is tagged
with the Git SHA and pushed to GitHub Container Registry (GHCR).

<br />

The deploy-staging job uses the ArgoCD CLI to update the image tag and sync the application. ArgoCD
then handles the actual Kubernetes deployment: it updates the deployment manifest, waits for the new
pods to be healthy, and reports back. The `argocd app wait` command blocks until the deployment is
fully rolled out and healthy, so the pipeline knows whether the deploy succeeded or failed.

<br />

If you are not using ArgoCD, you can replace this with `kubectl` commands:

<br />

```yaml
      - name: Deploy to staging with kubectl
        run: |
          echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > kubeconfig
          export KUBECONFIG=kubeconfig

          kubectl set image deployment/myapp \
            myapp=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
            -n staging

          kubectl rollout status deployment/myapp \
            -n staging \
            --timeout=300s

          rm kubeconfig
```

<br />

The key point is the same: update the image, then wait for the rollout to finish before moving on.

<br />

##### **Smoke tests in detail**
The smoke test job is the gatekeeper between staging and production. It answers one question: is the
thing we just deployed actually working?

<br />

We run three levels of smoke tests:

<br />

> * **Health check**: A simple HTTP request to `/health`. If the server is not responding, everything else is irrelevant. We retry up to 10 times with 10-second intervals because deployments can take a moment to stabilize.
> * **API smoke test**: A request to a real API endpoint. This validates that the application is not just running but actually serving requests correctly. We check both the status code and that the response body is valid.
> * **E2E smoke test**: A Playwright test that loads the application in a browser and performs a few critical user flows. This catches issues that API-level tests miss, like broken JavaScript bundles or misconfigured CDN paths.

<br />

You do not need all three levels on day one. Start with just the health check. Add the API test when
you have an API. Add the E2E test when you have Playwright set up. The important thing is to have
something that validates the deployment before you promote to production.

<br />

Here is a minimal Playwright smoke test:

<br />

```typescript
import { test, expect } from "@playwright/test";

const BASE_URL = process.env.BASE_URL || "http://localhost:3000";

test.describe("Smoke Tests", () => {
  test("homepage loads successfully", async ({ page }) => {
    const response = await page.goto(BASE_URL);
    expect(response?.status()).toBe(200);
    await expect(page.locator("h1")).toBeVisible();
  });

  test("API returns valid response", async ({ request }) => {
    const response = await request.get(`${BASE_URL}/api/v1/status`);
    expect(response.status()).toBe(200);

    const body = await response.json();
    expect(body).toHaveProperty("status", "ok");
  });

  test("login page renders", async ({ page }) => {
    await page.goto(`${BASE_URL}/login`);
    await expect(page.locator('input[name="email"]')).toBeVisible();
    await expect(page.locator('button[type="submit"]')).toBeVisible();
  });
});
```

<br />

Keep smoke tests fast. They should run in under a minute. If you need comprehensive E2E coverage,
run that in a separate workflow. Smoke tests are about confidence, not completeness.

<br />

##### **Production promotion and manual approval**
The deploy-production job has `environment: production`, which triggers the protection rules you
configured earlier. When the pipeline reaches this job, it pauses and shows a "Review deployments"
button in the GitHub Actions UI. The required reviewers you configured get a notification, and
the pipeline waits until one of them clicks "Approve."

<br />

This is intentional. Production deployments should be a deliberate decision. The approval step gives
your team a moment to ask: did the smoke tests look good? Are there any known issues? Is this a good
time to deploy (not Friday afternoon)?

<br />

Once approved, the production deploy follows the same pattern as staging: update the image tag, sync
with ArgoCD, wait for the rollout, and verify with a health check.

<br />

You might be wondering why we do not run the full smoke test suite against production. Some teams do,
and that is fine. But there is a tradeoff: running tests against production means your tests can fail
due to production-specific issues (rate limiting, real data edge cases), and a test failure after
deploy can cause confusion about whether the deploy itself failed. A simple health check is usually
enough for the production verification step.

<br />

##### **Deployment strategies**
The pipeline we built uses the default Kubernetes deployment strategy: rolling update. But it is
worth understanding the alternatives and when to use them.

<br />

**Rolling update (default)**

<br />

This is what Kubernetes does out of the box. It gradually replaces old pods with new pods, one at a
time (or in batches). At any point during the rollout, some pods are running the old version and some
are running the new version.

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  replicas: 3
  template:
    spec:
      containers:
        - name: myapp
          image: ghcr.io/myorg/myapp:abc123
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 10
```

<br />

> * **maxSurge: 1** means Kubernetes can create one extra pod above the desired replica count during the rollout.
> * **maxUnavailable: 0** means no pod is removed until its replacement is ready. This ensures zero downtime.
> * **readinessProbe** tells Kubernetes when a new pod is ready to receive traffic. Without this, Kubernetes might send requests to a pod that is still starting up.

<br />

Rolling updates are the right choice for most applications. They are simple, zero-downtime, and
well-supported by every Kubernetes distribution.

<br />

**Blue-green deployment**

<br />

In a blue-green deployment, you run two identical environments: blue (current production) and green
(the new version). Traffic goes to blue while green is being deployed and tested. Once green is
verified, you switch traffic from blue to green in one shot.

<br />

The advantage is that the switch is instantaneous and you can roll back by switching back to blue.
The disadvantage is that you need double the resources during the deployment. In Kubernetes, you can
implement blue-green by maintaining two deployments and switching the service selector:

<br />

```bash
# Deploy the new version as "green"
kubectl set image deployment/myapp-green \
  myapp=ghcr.io/myorg/myapp:new-version -n production

kubectl rollout status deployment/myapp-green -n production

# Switch traffic from blue to green
kubectl patch service myapp \
  -p '{"spec":{"selector":{"version":"green"}}}' -n production
```

<br />

**Canary deployment**

<br />

A canary deployment routes a small percentage of traffic (say 5%) to the new version while the
majority continues hitting the old version. You monitor error rates and latency for the canary, and
if everything looks good, you gradually increase the traffic split until 100% goes to the new version.

<br />

Canary deployments are powerful but require a service mesh (like Istio or Linkerd) or an ingress
controller that supports traffic splitting. They are more complex to set up but give you the safest
possible production rollout for high-traffic applications.

<br />

For this series, we will stick with rolling updates. They cover the vast majority of use cases, and
you can always adopt blue-green or canary later when your needs grow.

<br />

##### **Rollback strategies**
Things go wrong. A deploy passes all tests but a subtle bug appears under real traffic. You need to
get back to a known-good state fast. Here are your options:

<br />

**Option 1: Git revert and push**

<br />

This is the simplest and most reliable approach. You revert the commit that caused the problem, push
to main, and the pipeline redeploys the previous version automatically.

<br />

```bash
# Find the commit that caused the issue
git log --oneline -5

# Revert it
git revert HEAD

# Push to main, which triggers the pipeline
git push origin main
```

<br />

The advantage of this approach is that it goes through the full pipeline: lint, test, build, staging,
smoke test, production. You know the reverted version works because it was validated at every stage.
The downside is that it takes as long as a normal deployment (5-15 minutes depending on your pipeline).

<br />

**Option 2: ArgoCD rollback**

<br />

If you are using ArgoCD, you can roll back to a previous sync directly:

<br />

```bash
# List the sync history
argocd app history myapp-production

# Roll back to a specific revision
argocd app rollback myapp-production <revision-number>
```

<br />

This is faster than a git revert because it skips the build step. ArgoCD simply redeploys the previous
manifests. However, it creates a drift between your Git state and what is running in the cluster.
You should still create a git revert afterwards to keep Git as the source of truth.

<br />

**Option 3: kubectl rollout undo**

<br />

Kubernetes keeps a history of deployments, and you can roll back with a single command:

<br />

```bash
# Roll back to the previous version
kubectl rollout undo deployment/myapp -n production

# Or roll back to a specific revision
kubectl rollout history deployment/myapp -n production
kubectl rollout undo deployment/myapp -n production --to-revision=3
```

<br />

Like the ArgoCD rollback, this is fast but creates drift from Git. Use it for emergencies, then
follow up with a proper git revert.

<br />

The recommendation is: for planned rollbacks, use git revert. For emergencies, use kubectl rollout
undo or ArgoCD rollback, then git revert as a follow-up. Either way, Git should always reflect
what is actually running in production.

<br />

##### **Pipeline best practices**
Now that you have a working pipeline, here are the practices that keep it fast, reliable, and
maintainable over time:

<br />

**Fail early**

<br />

Order your jobs from fastest to slowest. Lint takes seconds, tests take a minute, Docker builds take
several minutes. If the code does not pass lint, there is no point waiting for a Docker build to
finish. The `needs` keyword enforces this ordering.

<br />

**Parallelize where possible**

<br />

Lint and test do not depend on each other. Run them in parallel. If you have multiple test suites
(unit, integration, E2E), split them into separate jobs that run simultaneously. Every minute you
shave off the pipeline is a minute your team gets back on every single commit.

<br />

**Cache aggressively**

<br />

Cache everything that does not change between builds:

<br />

> * **npm dependencies**: Use `actions/setup-node` with `cache: "npm"`. This caches the npm global store and restores it based on `package-lock.json`.
> * **Docker layers**: Use BuildKit with `cache-from: type=gha` and `cache-to: type=gha,mode=max`. This stores and restores layer caches using GitHub's cache backend.
> * **Test fixtures**: If your tests download large fixtures, cache them with `actions/cache`.

<br />

Without caching, a typical pipeline takes 8-12 minutes. With caching, it can drop to 3-5 minutes.

<br />

**Keep it DRY**

<br />

If you have multiple repositories with similar pipelines, extract common steps into reusable workflows
or composite actions:

<br />

```yaml
# .github/workflows/reusable-deploy.yml
name: Deploy
on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
      argocd-app:
        required: true
        type: string
    secrets:
      ARGOCD_AUTH_TOKEN:
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - name: Install ArgoCD CLI
        run: |
          curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
          chmod +x argocd
          sudo mv argocd /usr/local/bin/

      - name: Deploy
        env:
          ARGOCD_SERVER: ${{ vars.ARGOCD_SERVER }}
          ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
        run: |
          argocd app set ${{ inputs.argocd-app }} \
            --parameter image.tag=${{ github.sha }} \
            --grpc-web
          argocd app sync ${{ inputs.argocd-app }} \
            --grpc-web --timeout 300
          argocd app wait ${{ inputs.argocd-app }} \
            --grpc-web --timeout 300 --health
```

<br />

Then call it from your main pipeline:

<br />

```yaml
  deploy-staging:
    needs: [build]
    uses: ./.github/workflows/reusable-deploy.yml
    with:
      environment: staging
      argocd-app: myapp-staging
    secrets:
      ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
```

<br />

This avoids duplicating deployment logic across staging and production jobs. When you need to change
how deployments work, you change it in one place.

<br />

**Pin your action versions**

<br />

Always use specific versions (or commit SHAs) for actions, not `@main` or `@latest`. Third-party
actions can change without warning, and a broken action version can break your pipeline across all
repositories at once:

<br />

```yaml
# Good: pinned to a specific version
- uses: actions/checkout@v4
- uses: docker/build-push-action@v6

# Bad: unpinned, can break without warning
- uses: actions/checkout@main
- uses: some-org/some-action@latest
```

<br />

##### **Monitoring your pipeline**
A pipeline is only useful if you know how it is performing. GitHub Actions gives you several ways to
monitor pipeline health:

<br />

> * **Workflow run history**: Go to the Actions tab in your repository. You can see every run, filter by workflow, branch, or status, and drill into individual jobs and steps.
> * **Build time trends**: Track how long your pipeline takes over time. If builds are getting slower, it usually means your test suite is growing without corresponding optimization, or your Docker cache is not working correctly.
> * **Failure rate**: If your pipeline fails more than 10% of the time on legitimate code changes, something is flaky. Common culprits are network-dependent tests, race conditions, and service container startup timing.
> * **Status badges**: Add a workflow status badge to your README so the team can see pipeline health at a glance.

<br />

You can add a status badge to your README with this markdown:

<br />

```bash
![CI/CD](https://github.com/myorg/myapp/actions/workflows/ci-cd.yml/badge.svg)
```

<br />

For more advanced monitoring, consider integrating with tools like Datadog CI Visibility or
Grafana with the GitHub Actions exporter. These give you dashboards with build time percentiles,
failure breakdowns by job, and alerts when build times exceed a threshold.

<br />

##### **Putting it all together**
Let's recap what happens when a developer pushes a change through this pipeline:

<br />

> * **Developer opens a PR**: Lint and test run automatically. The PR gets a green checkmark or a red X. Code review happens in parallel.
> * **PR is merged to main**: Lint and test run again on the merged code. Then the build job creates a Docker image tagged with the commit SHA and pushes it to GHCR.
> * **Staging deploy**: ArgoCD updates the staging deployment with the new image tag. The pipeline waits until the rollout is healthy.
> * **Smoke tests**: Health check, API test, and E2E test run against staging. If any fail, the pipeline stops and the team is notified.
> * **Manual approval**: A reviewer checks the staging deployment, confirms it looks good, and clicks "Approve" in the GitHub Actions UI.
> * **Production deploy**: ArgoCD updates the production deployment. A final health check confirms the deployment is live.

<br />

The entire process, from merge to production, takes about 10-15 minutes. Most of that time is in the
build and test stages. The actual deployment steps take less than a minute each.

<br />

If anything goes wrong, the pipeline stops at the failed step. No code reaches production unless it
has passed every gate. And if something slips through, you can roll back with a git revert in under
a minute.

<br />

##### **What comes next**
We now have a complete, end-to-end CI/CD pipeline that takes code from a pull request to production
with automated validation at every stage. In the next article, we will look at monitoring and
observability: how to know what your application is doing once it is running in production.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps from Zero to Hero: CI/CD, El Pipeline Completo",
  author: "Gabriel Garrido",
  description: "Vamos a construir un pipeline completo de CI/CD de punta a punta con GitHub Actions cubriendo lint, test, build, deploy a staging, smoke tests, promocion a produccion con aprobacion manual, y estrategias de rollback...",
  tags: ~w(devops ci-cd github-actions kubernetes beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo dieciseis de la serie DevOps from Zero to Hero. A lo largo de los quince
articulos anteriores cubrimos todo, desde escribir una API en TypeScript, pasando por control de
versiones, testing, CI, infraestructura como codigo, Kubernetes, Helm, secretos, y mas. Cada pieza
resolvio un problema especifico, pero todavia no las cosimos todas juntas en un pipeline cohesivo de
punta a punta.

<br />

Eso cambia ahora. En este articulo vamos a construir un pipeline completo de CI/CD que lleva tu codigo
desde un pull request hasta produccion. No un ejemplo de juguete. Un workflow real de GitHub Actions
con multiples jobs que hace lint, testea, construye, despliega a staging, corre smoke tests, espera
aprobacion manual, y despues promueve a produccion. Tambien vamos a cubrir estrategias de deploy,
procedimientos de rollback, y buenas practicas para mantener tu pipeline rapido y confiable.

<br />

Si venias siguiendo la serie, pensa en este articulo como el pegamento que conecta todo. Si estas
arrancando de cero, no te preocupes. Vamos a explicar cada parte a medida que avancemos.

<br />

Vamos a meternos de lleno.

<br />

##### **La filosofia del pipeline**
Antes de escribir una sola linea de YAML, establezcamos los principios que guian un buen pipeline
de CI/CD:

<br />

> * **Cada commit a main deberia ser desplegable**: Si algo esta en main, fue linteado, testeado y construido. Esta listo para salir. Si no esta listo, no deberia estar en main.
> * **Los ambientes son puertas, no destinos**: Staging existe para validar, no para acumular. El codigo deberia fluir por staging rapido, no quedarse ahi semanas. Produccion es el destino.
> * **Fallar rapido, fallar fuerte**: Si algo esta roto, queres saberlo en segundos, no en minutos. Pone los checks mas baratos primero (lint, formato) y los caros despues (tests de integracion, builds).
> * **Automatizacion sobre procesos manuales**: Cada paso manual es un paso que se puede olvidar, hacer mal, o saltear bajo presion. Automatiza todo excepto la aprobacion final a produccion.
> * **Reproducibilidad**: Tu pipeline deberia producir el mismo resultado ya sea que lo corras hoy o dentro de tres meses. Fija tus versiones, cachea tus dependencias, y usa artefactos inmutables.

<br />

Estos no son ideales abstractos. Son decisiones de ingenieria que previenen caidas, reducen el toil,
y te dejan deployar con confianza. Cada decision de diseno en el pipeline que vamos a construir se
remonta a uno de estos principios.

<br />

##### **Vista general de las etapas del pipeline**
Nuestro pipeline va a tener siete etapas, organizadas en tres fases:

<br />

```plaintext
Fase 1: Validar (en cada PR y push a main)
  ├── Lint       -> ESLint, Prettier, type checking
  └── Test       -> Tests unitarios, de integracion, coverage

Fase 2: Build y Deploy a Staging (solo en push a main)
  ├── Build      -> Build de imagen Docker y push al registry
  ├── Deploy     -> Deploy al namespace de staging via ArgoCD
  └── Smoke Test -> Health check y tests de API contra staging

Fase 3: Promover a Produccion (aprobacion manual)
  ├── Aprobar    -> Gate de aprobacion manual via GitHub Environments
  └── Deploy     -> Deploy al namespace de produccion
```

<br />

La Fase 1 corre en cada pull request y cada push a main. Es tu red de seguridad. La Fase 2 solo corre
en pushes a main (PRs mergeados) porque no queres deployar feature branches a staging. La Fase 3
requiere que un humano haga click en "Approve" antes de que el codigo llegue a produccion. Este es
el unico paso manual que mantenemos a proposito, porque deployar a produccion deberia ser una decision
consciente.

<br />

##### **Environments de GitHub Actions**
GitHub Actions tiene una funcionalidad llamada Environments que te da exactamente lo que necesitamos:
secretos especificos por ambiente, reglas de proteccion, y historial de deploys. Vamos a configurarlos.

<br />

Anda a tu repositorio en GitHub, despues Settings, despues Environments. Crea dos environments:

<br />

> * **staging**: No necesita reglas de proteccion. Los deploys aca deberian ser automaticos despues de que pase el build.
> * **production**: Agrega una regla de proteccion "Required reviewers". Elegi uno o mas miembros del equipo que tienen que aprobar antes de que un deploy pueda proceder.

<br />

Tambien podes agregar un "Wait timer" a production si queres un periodo de enfriamiento obligatorio
entre deploys a staging y produccion. Algunos equipos lo ponen en 15 minutos para darle tiempo extra
a los smoke tests de encontrar problemas.

<br />

##### **Secretos y variables especificos por ambiente**
Cada environment puede tener sus propios secretos y variables. Asi es como manejas el hecho de que
staging y produccion usan clusters, namespaces, bases de datos y API keys diferentes sin llenar tu
workflow de condicionales `if`.

<br />

Esto es lo que tipicamente configurarias:

<br />

```plaintext
Secretos del repositorio (compartidos):
  REGISTRY_USERNAME    -> tu usuario del registry de contenedores
  REGISTRY_PASSWORD    -> tu token del registry de contenedores

Secretos del environment staging:
  KUBE_CONFIG          -> kubeconfig para tu cluster de staging
  DATABASE_URL         -> connection string de la base de datos de staging
  ARGOCD_AUTH_TOKEN    -> token de ArgoCD para staging

Variables del environment staging:
  KUBE_NAMESPACE       -> staging
  APP_URL              -> https://staging.myapp.example.com

Secretos del environment production:
  KUBE_CONFIG          -> kubeconfig para tu cluster de produccion
  DATABASE_URL         -> connection string de la base de datos de produccion
  ARGOCD_AUTH_TOKEN    -> token de ArgoCD para produccion

Variables del environment production:
  KUBE_NAMESPACE       -> production
  APP_URL              -> https://myapp.example.com
```

<br />

Cuando un job especifica `environment: staging`, solo puede acceder a los secretos y variables de
staging. Cuando especifica `environment: production`, obtiene los de produccion. Este aislamiento
previene el peor tipo de error: correr accidentalmente una migracion de produccion contra la base de
datos de staging, o viceversa.

<br />

Para configurar estos, anda a Settings, despues Environments, hace click en el environment, y agrega
tus secretos y variables ahi. Funcionan exactamente como los secretos a nivel repositorio pero estan
limitados al environment.

<br />

##### **El workflow completo**
Aca esta el pipeline completo. Vamos a repasar cada job en detalle despues, pero primero, mira el
panorama general:

<br />

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

permissions:
  contents: read
  packages: write

jobs:
  # Fase 1: Validar
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - run: npm ci

      - name: Run ESLint
        run: npx eslint .

      - name: Check formatting
        run: npx prettier --check .

      - name: Type check
        run: npx tsc --noEmit

  test:
    name: Test
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: myapp_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      DATABASE_URL: postgres://test:test@localhost:5432/myapp_test
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - run: npm ci

      - name: Run tests with coverage
        run: npm test -- --coverage

      - name: Upload coverage
        if: github.event_name == 'push'
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
          retention-days: 14

  # Fase 2: Build y Deploy a Staging
  build:
    name: Build and Push Image
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}
      image-digest: ${{ steps.build.outputs.digest }}
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - name: Log in to registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=
            type=raw,value=latest

      - name: Build and push
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    needs: [build]
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - name: Install ArgoCD CLI
        run: |
          curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
          chmod +x argocd
          sudo mv argocd /usr/local/bin/

      - name: Deploy to staging
        env:
          ARGOCD_SERVER: ${{ vars.ARGOCD_SERVER }}
          ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
        run: |
          argocd app set myapp-staging \
            --parameter image.tag=${{ github.sha }} \
            --grpc-web

          argocd app sync myapp-staging \
            --grpc-web \
            --timeout 300

          argocd app wait myapp-staging \
            --grpc-web \
            --timeout 300 \
            --health

  smoke-test:
    name: Smoke Tests
    runs-on: ubuntu-latest
    needs: [deploy-staging]
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - name: Wait for deployment to stabilize
        run: sleep 30

      - name: Health check
        run: |
          for i in $(seq 1 10); do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
              "${{ vars.APP_URL }}/health")
            if [ "$STATUS" = "200" ]; then
              echo "Health check passed on attempt $i"
              exit 0
            fi
            echo "Attempt $i: got $STATUS, retrying in 10s..."
            sleep 10
          done
          echo "Health check failed after 10 attempts"
          exit 1

      - name: API smoke test
        run: |
          RESPONSE=$(curl -s -w "\n%{http_code}" \
            "${{ vars.APP_URL }}/api/v1/status")
          BODY=$(echo "$RESPONSE" | head -n -1)
          STATUS=$(echo "$RESPONSE" | tail -n 1)

          echo "Status: $STATUS"
          echo "Body: $BODY"

          if [ "$STATUS" != "200" ]; then
            echo "API smoke test failed with status $STATUS"
            exit 1
          fi

          echo "API smoke test passed"

      - name: Run E2E tests against staging
        env:
          BASE_URL: ${{ vars.APP_URL }}
        run: |
          npm ci
          npx playwright test tests/e2e/smoke.spec.ts

  # Fase 3: Promover a Produccion
  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: [smoke-test]
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Install ArgoCD CLI
        run: |
          curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
          chmod +x argocd
          sudo mv argocd /usr/local/bin/

      - name: Deploy to production
        env:
          ARGOCD_SERVER: ${{ vars.ARGOCD_SERVER }}
          ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
        run: |
          argocd app set myapp-production \
            --parameter image.tag=${{ github.sha }} \
            --grpc-web

          argocd app sync myapp-production \
            --grpc-web \
            --timeout 300

          argocd app wait myapp-production \
            --grpc-web \
            --timeout 300 \
            --health

      - name: Verify production deployment
        run: |
          for i in $(seq 1 10); do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
              "${{ vars.APP_URL }}/health")
            if [ "$STATUS" = "200" ]; then
              echo "Production health check passed"
              exit 0
            fi
            echo "Attempt $i: got $STATUS, retrying in 10s..."
            sleep 10
          done
          echo "Production health check failed"
          exit 1
```

<br />

Es mucho YAML, asi que vamos a desarmarlo pieza por pieza.

<br />

##### **Fase 1: Validar**
Los jobs de lint y test corren en paralelo en cada push y pull request. Son los checks mas baratos y
rapidos, asi que van primero.

<br />

El job de lint corre tres checks: ESLint para calidad de codigo, Prettier para formato, y el
compilador de TypeScript para seguridad de tipos. Si cualquiera de estos falla, el pipeline se
detiene. No tiene sentido construir una imagen Docker para codigo que no compila.

<br />

El job de test levanta un contenedor de servicio de PostgreSQL. GitHub Actions te deja definir
servicios junto a tu job, y estan disponibles en `localhost` como una base de datos local. Los tests
corren con coverage habilitado, y el reporte de coverage se sube como artefacto para revision
posterior.

<br />

Nota que lint y test no dependen uno del otro. Corren en paralelo por defecto, lo que significa que
la fase de validacion toma lo que dure el mas lento de los dos, no la suma de ambos.

<br />

##### **Fase 2: Build y deploy a staging**
El job de build solo corre en pushes a main (no en pull requests) y solo despues de que pasen tanto
lint como test. Esto se controla con la dependencia `needs: [lint, test]` y el condicional `if`.

<br />

Usamos Docker Buildx con cache de GitHub Actions (`cache-from: type=gha`). Esto significa que los
builds subsiguientes reusan capas cacheadas, lo que puede reducir el tiempo de build de minutos a
segundos. La imagen se tagea con el SHA de Git y se pushea a GitHub Container Registry (GHCR).

<br />

El job deploy-staging usa el CLI de ArgoCD para actualizar el tag de la imagen y sincronizar la
aplicacion. ArgoCD entonces maneja el deploy real a Kubernetes: actualiza el manifest del deployment,
espera a que los nuevos pods esten healthy, y reporta. El comando `argocd app wait` bloquea hasta
que el deploy este completamente rolleado y healthy, asi el pipeline sabe si el deploy fue exitoso
o fallo.

<br />

Si no estas usando ArgoCD, podes reemplazar esto con comandos `kubectl`:

<br />

```yaml
      - name: Deploy to staging with kubectl
        run: |
          echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > kubeconfig
          export KUBECONFIG=kubeconfig

          kubectl set image deployment/myapp \
            myapp=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
            -n staging

          kubectl rollout status deployment/myapp \
            -n staging \
            --timeout=300s

          rm kubeconfig
```

<br />

El punto clave es el mismo: actualizar la imagen, despues esperar a que el rollout termine antes de
seguir adelante.

<br />

##### **Smoke tests en detalle**
El job de smoke test es el guardian entre staging y produccion. Responde una pregunta: lo que acabamos
de deployar, esta funcionando?

<br />

Corremos tres niveles de smoke tests:

<br />

> * **Health check**: Un request HTTP simple a `/health`. Si el servidor no responde, todo lo demas es irrelevante. Reintentamos hasta 10 veces con intervalos de 10 segundos porque los deploys pueden tardar un momento en estabilizarse.
> * **API smoke test**: Un request a un endpoint real de la API. Esto valida que la aplicacion no solo esta corriendo sino que realmente esta sirviendo requests correctamente. Chequeamos tanto el status code como que el cuerpo de la respuesta sea valido.
> * **E2E smoke test**: Un test de Playwright que carga la aplicacion en un navegador y ejecuta algunos flujos criticos de usuario. Esto atrapa problemas que los tests a nivel API no ven, como bundles de JavaScript rotos o paths de CDN mal configurados.

<br />

No necesitas los tres niveles desde el dia uno. Arranca solo con el health check. Agrega el test de
API cuando tengas una API. Agrega el test E2E cuando tengas Playwright configurado. Lo importante es
tener algo que valide el deploy antes de promover a produccion.

<br />

Aca hay un smoke test minimo con Playwright:

<br />

```typescript
import { test, expect } from "@playwright/test";

const BASE_URL = process.env.BASE_URL || "http://localhost:3000";

test.describe("Smoke Tests", () => {
  test("homepage loads successfully", async ({ page }) => {
    const response = await page.goto(BASE_URL);
    expect(response?.status()).toBe(200);
    await expect(page.locator("h1")).toBeVisible();
  });

  test("API returns valid response", async ({ request }) => {
    const response = await request.get(`${BASE_URL}/api/v1/status`);
    expect(response.status()).toBe(200);

    const body = await response.json();
    expect(body).toHaveProperty("status", "ok");
  });

  test("login page renders", async ({ page }) => {
    await page.goto(`${BASE_URL}/login`);
    await expect(page.locator('input[name="email"]')).toBeVisible();
    await expect(page.locator('button[type="submit"]')).toBeVisible();
  });
});
```

<br />

Mantene los smoke tests rapidos. Deberian correr en menos de un minuto. Si necesitas cobertura E2E
completa, corré eso en un workflow separado. Los smoke tests son sobre confianza, no completitud.

<br />

##### **Promocion a produccion y aprobacion manual**
El job deploy-production tiene `environment: production`, lo que activa las reglas de proteccion que
configuraste antes. Cuando el pipeline llega a este job, se pausa y muestra un boton "Review
deployments" en la UI de GitHub Actions. Los reviewers requeridos que configuraste reciben una
notificacion, y el pipeline espera hasta que uno de ellos haga click en "Approve."

<br />

Esto es intencional. Los deploys a produccion deberian ser una decision deliberada. El paso de
aprobacion le da a tu equipo un momento para preguntarse: los smoke tests se vieron bien? Hay algun
problema conocido? Es un buen momento para deployar (no un viernes a la tarde)?

<br />

Una vez aprobado, el deploy a produccion sigue el mismo patron que staging: actualizar el tag de la
imagen, sincronizar con ArgoCD, esperar el rollout, y verificar con un health check.

<br />

Te podrias preguntar por que no corremos la suite completa de smoke tests contra produccion. Algunos
equipos lo hacen, y esta bien. Pero hay un tradeoff: correr tests contra produccion significa que tus
tests pueden fallar por problemas especificos de produccion (rate limiting, edge cases de datos
reales), y un test que falla despues del deploy puede causar confusion sobre si fue el deploy el que
fallo. Un health check simple suele alcanzar para la verificacion de produccion.

<br />

##### **Estrategias de deployment**
El pipeline que construimos usa la estrategia de deployment por defecto de Kubernetes: rolling update.
Pero vale la pena entender las alternativas y cuando usarlas.

<br />

**Rolling update (por defecto)**

<br />

Esto es lo que Kubernetes hace out of the box. Gradualmente reemplaza pods viejos con pods nuevos,
uno a la vez (o en batches). En cualquier punto durante el rollout, algunos pods corren la version
vieja y otros la nueva.

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  replicas: 3
  template:
    spec:
      containers:
        - name: myapp
          image: ghcr.io/myorg/myapp:abc123
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 10
```

<br />

> * **maxSurge: 1** significa que Kubernetes puede crear un pod extra por encima del conteo de replicas deseado durante el rollout.
> * **maxUnavailable: 0** significa que ningun pod se remueve hasta que su reemplazo este listo. Esto garantiza zero downtime.
> * **readinessProbe** le dice a Kubernetes cuando un pod nuevo esta listo para recibir trafico. Sin esto, Kubernetes podria enviar requests a un pod que todavia esta arrancando.

<br />

Los rolling updates son la eleccion correcta para la mayoria de las aplicaciones. Son simples, sin
downtime, y bien soportados por todas las distribuciones de Kubernetes.

<br />

**Blue-green deployment**

<br />

En un deploy blue-green, tenes dos ambientes identicos corriendo: blue (produccion actual) y green
(la version nueva). El trafico va a blue mientras green se esta deployando y testeando. Una vez que
green esta verificado, switcheas el trafico de blue a green de una sola vez.

<br />

La ventaja es que el switch es instantaneo y podes rollbackear switcheando de vuelta a blue. La
desventaja es que necesitas el doble de recursos durante el deploy. En Kubernetes, podes implementar
blue-green manteniendo dos deployments y switcheando el selector del service:

<br />

```bash
# Deployar la nueva version como "green"
kubectl set image deployment/myapp-green \
  myapp=ghcr.io/myorg/myapp:new-version -n production

kubectl rollout status deployment/myapp-green -n production

# Switchear trafico de blue a green
kubectl patch service myapp \
  -p '{"spec":{"selector":{"version":"green"}}}' -n production
```

<br />

**Canary deployment**

<br />

Un canary deployment rutea un porcentaje chico de trafico (digamos 5%) a la version nueva mientras
la mayoria sigue pegandole a la version vieja. Monitoreas las tasas de error y latencia del canary,
y si todo se ve bien, gradualmente incrementas el split de trafico hasta que el 100% va a la version
nueva.

<br />

Los canary deployments son poderosos pero requieren un service mesh (como Istio o Linkerd) o un
ingress controller que soporte traffic splitting. Son mas complejos de configurar pero te dan el
rollout a produccion mas seguro posible para aplicaciones de alto trafico.

<br />

Para esta serie, nos quedamos con rolling updates. Cubren la gran mayoria de los casos de uso, y
siempre podes adoptar blue-green o canary mas adelante cuando tus necesidades crezcan.

<br />

##### **Estrategias de rollback**
Las cosas salen mal. Un deploy pasa todos los tests pero aparece un bug sutil bajo trafico real.
Necesitas volver a un estado bueno conocido rapido. Aca estan tus opciones:

<br />

**Opcion 1: Git revert y push**

<br />

Este es el enfoque mas simple y confiable. Revertis el commit que causo el problema, pusheas a main,
y el pipeline redeploya la version anterior automaticamente.

<br />

```bash
# Encontrar el commit que causo el problema
git log --oneline -5

# Revertirlo
git revert HEAD

# Pushear a main, lo que dispara el pipeline
git push origin main
```

<br />

La ventaja de este enfoque es que pasa por el pipeline completo: lint, test, build, staging, smoke
test, produccion. Sabes que la version revertida funciona porque fue validada en cada etapa. La
desventaja es que tarda lo mismo que un deploy normal (5-15 minutos dependiendo de tu pipeline).

<br />

**Opcion 2: Rollback con ArgoCD**

<br />

Si estas usando ArgoCD, podes hacer rollback a un sync anterior directamente:

<br />

```bash
# Listar el historial de syncs
argocd app history myapp-production

# Rollback a una revision especifica
argocd app rollback myapp-production <numero-de-revision>
```

<br />

Esto es mas rapido que un git revert porque saltea el paso de build. ArgoCD simplemente redeploya los
manifests anteriores. Sin embargo, crea un drift entre tu estado de Git y lo que esta corriendo en el
cluster. Igual deberias crear un git revert despues para mantener Git como la fuente de verdad.

<br />

**Opcion 3: kubectl rollout undo**

<br />

Kubernetes guarda un historial de deployments, y podes hacer rollback con un solo comando:

<br />

```bash
# Rollback a la version anterior
kubectl rollout undo deployment/myapp -n production

# O rollback a una revision especifica
kubectl rollout history deployment/myapp -n production
kubectl rollout undo deployment/myapp -n production --to-revision=3
```

<br />

Como el rollback de ArgoCD, esto es rapido pero crea drift con Git. Usalo para emergencias, despues
segui con un git revert apropiado.

<br />

La recomendacion es: para rollbacks planificados, usa git revert. Para emergencias, usa kubectl
rollout undo o rollback de ArgoCD, despues git revert como follow-up. De cualquier manera, Git
siempre deberia reflejar lo que esta corriendo realmente en produccion.

<br />

##### **Buenas practicas del pipeline**
Ahora que tenes un pipeline funcionando, aca estan las practicas que lo mantienen rapido, confiable
y mantenible a lo largo del tiempo:

<br />

**Fallar temprano**

<br />

Ordena tus jobs del mas rapido al mas lento. Lint tarda segundos, tests un minuto, builds de Docker
varios minutos. Si el codigo no pasa lint, no tiene sentido esperar a que termine un build de Docker.
La keyword `needs` impone este orden.

<br />

**Paralelizar donde sea posible**

<br />

Lint y test no dependen uno del otro. Correlos en paralelo. Si tenes multiples suites de test
(unitarios, integracion, E2E), dividilos en jobs separados que corran simultaneamente. Cada minuto
que le recortes al pipeline es un minuto que tu equipo recupera en cada commit.

<br />

**Cachear agresivamente**

<br />

Cachea todo lo que no cambia entre builds:

<br />

> * **Dependencias de npm**: Usa `actions/setup-node` con `cache: "npm"`. Esto cachea el store global de npm y lo restaura basandose en `package-lock.json`.
> * **Capas de Docker**: Usa BuildKit con `cache-from: type=gha` y `cache-to: type=gha,mode=max`. Esto guarda y restaura caches de capas usando el backend de cache de GitHub.
> * **Fixtures de tests**: Si tus tests descargan fixtures grandes, cachealos con `actions/cache`.

<br />

Sin cache, un pipeline tipico tarda 8-12 minutos. Con cache, puede bajar a 3-5 minutos.

<br />

**Mantenerlo DRY**

<br />

Si tenes multiples repositorios con pipelines similares, extraé los pasos comunes en workflows
reutilizables o composite actions:

<br />

```yaml
# .github/workflows/reusable-deploy.yml
name: Deploy
on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
      argocd-app:
        required: true
        type: string
    secrets:
      ARGOCD_AUTH_TOKEN:
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - name: Install ArgoCD CLI
        run: |
          curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
          chmod +x argocd
          sudo mv argocd /usr/local/bin/

      - name: Deploy
        env:
          ARGOCD_SERVER: ${{ vars.ARGOCD_SERVER }}
          ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
        run: |
          argocd app set ${{ inputs.argocd-app }} \
            --parameter image.tag=${{ github.sha }} \
            --grpc-web
          argocd app sync ${{ inputs.argocd-app }} \
            --grpc-web --timeout 300
          argocd app wait ${{ inputs.argocd-app }} \
            --grpc-web --timeout 300 --health
```

<br />

Despues llamalo desde tu pipeline principal:

<br />

```yaml
  deploy-staging:
    needs: [build]
    uses: ./.github/workflows/reusable-deploy.yml
    with:
      environment: staging
      argocd-app: myapp-staging
    secrets:
      ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
```

<br />

Esto evita duplicar logica de deploy entre los jobs de staging y produccion. Cuando necesites cambiar
como funcionan los deploys, lo cambias en un solo lugar.

<br />

**Fijar las versiones de tus actions**

<br />

Siempre usa versiones especificas (o SHAs de commits) para las actions, no `@main` ni `@latest`.
Las actions de terceros pueden cambiar sin aviso, y una version rota puede romper tu pipeline en
todos los repositorios de una:

<br />

```yaml
# Bien: fijado a una version especifica
- uses: actions/checkout@v4
- uses: docker/build-push-action@v6

# Mal: sin fijar, puede romperse sin aviso
- uses: actions/checkout@main
- uses: some-org/some-action@latest
```

<br />

##### **Monitoreando tu pipeline**
Un pipeline solo es util si sabes como esta performando. GitHub Actions te da varias formas de
monitorear la salud del pipeline:

<br />

> * **Historial de runs**: Anda a la tab Actions en tu repositorio. Podes ver cada ejecucion, filtrar por workflow, branch o estado, y profundizar en jobs y pasos individuales.
> * **Tendencias de build time**: Trackea cuanto tarda tu pipeline a lo largo del tiempo. Si los builds se estan poniendo mas lentos, generalmente significa que tu suite de tests esta creciendo sin optimizacion correspondiente, o tu cache de Docker no esta funcionando bien.
> * **Tasa de fallos**: Si tu pipeline falla mas del 10% del tiempo en cambios de codigo legitimos, algo es flaky. Los culpables comunes son tests que dependen de la red, race conditions, y timing de startup de contenedores de servicio.
> * **Badges de estado**: Agrega un badge de estado del workflow a tu README asi el equipo puede ver la salud del pipeline de un vistazo.

<br />

Podes agregar un badge de estado a tu README con este markdown:

<br />

```bash
![CI/CD](https://github.com/myorg/myapp/actions/workflows/ci-cd.yml/badge.svg)
```

<br />

Para monitoreo mas avanzado, considera integrar con herramientas como Datadog CI Visibility o Grafana
con el exporter de GitHub Actions. Estos te dan dashboards con percentiles de build time, breakdowns
de fallas por job, y alertas cuando los tiempos de build superan un umbral.

<br />

##### **Juntando todo**
Recapitulemos lo que pasa cuando un developer pushea un cambio a traves de este pipeline:

<br />

> * **El developer abre un PR**: Lint y test corren automaticamente. El PR recibe una marca verde o una X roja. El code review pasa en paralelo.
> * **El PR se mergea a main**: Lint y test corren de nuevo sobre el codigo mergeado. Despues el job de build crea una imagen Docker tageada con el SHA del commit y la pushea a GHCR.
> * **Deploy a staging**: ArgoCD actualiza el deployment de staging con el nuevo tag de imagen. El pipeline espera hasta que el rollout este healthy.
> * **Smoke tests**: Health check, test de API, y test E2E corren contra staging. Si alguno falla, el pipeline se detiene y se notifica al equipo.
> * **Aprobacion manual**: Un reviewer chequea el deploy de staging, confirma que se ve bien, y hace click en "Approve" en la UI de GitHub Actions.
> * **Deploy a produccion**: ArgoCD actualiza el deployment de produccion. Un health check final confirma que el deploy esta live.

<br />

El proceso completo, desde el merge hasta produccion, tarda unos 10-15 minutos. La mayor parte de
ese tiempo esta en las etapas de build y test. Los pasos de deploy en si tardan menos de un minuto
cada uno.

<br />

Si algo sale mal, el pipeline se detiene en el paso que fallo. Ningun codigo llega a produccion a
menos que haya pasado por cada gate. Y si algo se cuela, podes hacer rollback con un git revert en
menos de un minuto.

<br />

##### **Que viene despues**
Ahora tenemos un pipeline completo de CI/CD de punta a punta que lleva codigo desde un pull request
hasta produccion con validacion automatizada en cada etapa. En el proximo articulo, vamos a ver
monitoreo y observabilidad: como saber que esta haciendo tu aplicacion una vez que esta corriendo en
produccion.

<br />

Espero que te haya resultado util y que lo hayas disfrutado, hasta la proxima!

<br />

##### **Errata**
Si encontras mass algun error o tenes alguna sugerencia, por favor mandame un mensaje para que lo
pueda corregir.

Tambien, podes ver el codigo fuente y los cambios en los [fuentes aca](https://github.com/kainlite/tr)

<br />
