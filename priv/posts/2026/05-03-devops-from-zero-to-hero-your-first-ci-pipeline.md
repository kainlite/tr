%{
  title: "DevOps from Zero to Hero: Your First CI Pipeline with GitHub Actions",
  author: "Gabriel Garrido",
  description: "We will build a complete CI pipeline with GitHub Actions covering linting, testing, Docker builds, caching, matrix builds, and reusable workflows...",
  tags: ~w(devops github-actions ci-cd beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article five of the DevOps from Zero to Hero series. In the previous article we wrote unit
and integration tests for a TypeScript project. Tests are great, but they only help if someone
actually runs them. That someone should not be you, manually, right before a deploy. It should be a
machine that runs them every single time code changes.

<br />

That is what Continuous Integration (CI) is about: automating the boring, repetitive, critical stuff
so humans can focus on writing code. In this article we are going to build a complete CI pipeline with
GitHub Actions from scratch. By the end, every push and pull request to your repository will
automatically lint the code, run tests, build a Docker image, and push it to a container registry.

<br />

Let's get into it.

<br />

##### **What is CI and why it matters**
Continuous Integration is the practice of automatically building and testing code every time someone
pushes a change. The word "continuous" is important: this is not something you do once a week or
before a release. It happens on every commit, every pull request, every time.

<br />

Why does this matter? Three reasons:

<br />

> * **Catch bugs early**: A bug found in CI costs minutes to fix. A bug found in production costs hours, customer trust, and sometimes money. The earlier you catch it, the cheaper it is.
> * **Enforce standards**: Linting, formatting, and type checking should not depend on developers remembering to run them. CI enforces these standards automatically, every time.
> * **Automate repetitive tasks**: Building Docker images, running test suites, generating artifacts. These are things a machine should do, not a person.

<br />

Without CI, your workflow looks like this: a developer writes code, forgets to run the linter,
pushes to main, breaks the build, and the whole team notices an hour later. With CI, the linter
runs automatically, the push is blocked, and the developer fixes it in five minutes before anyone
else is affected.

<br />

CI is the first real automation layer in a DevOps pipeline. Everything else, continuous delivery,
continuous deployment, infrastructure as code, all of it builds on top of CI.

<br />

##### **GitHub Actions fundamentals**
GitHub Actions is a CI/CD platform built into GitHub. You define workflows as YAML files in a
`.github/workflows/` directory, and GitHub runs them for you on hosted virtual machines. There is no
separate service to set up, no webhooks to configure, and no servers to manage.

<br />

Before we write any YAML, let's understand the key concepts:

<br />

> * **Workflow**: A YAML file that defines an automated process. Each workflow lives in `.github/workflows/` and is triggered by events.
> * **Event (trigger)**: What causes the workflow to run. Common triggers are `push`, `pull_request`, and `schedule`.
> * **Job**: A set of steps that run on the same virtual machine (called a "runner"). A workflow can have multiple jobs, and by default they run in parallel.
> * **Step**: A single task within a job. A step can run a shell command or use a pre-built action.
> * **Action**: A reusable unit of code that performs a common task. For example, `actions/checkout@v4` clones your repository, and `actions/setup-node@v4` installs Node.js.
> * **Runner**: The virtual machine that executes your job. GitHub provides hosted runners with Ubuntu, Windows, and macOS.

<br />

Here is the hierarchy visualized:

<br />

```
Workflow (.github/workflows/ci.yml)
  ├── Event: push to main, pull_request
  ├── Job: lint
  │     ├── Step: Checkout code
  │     ├── Step: Setup Node.js
  │     └── Step: Run ESLint
  ├── Job: test
  │     ├── Step: Checkout code
  │     ├── Step: Setup Node.js
  │     ├── Step: Install dependencies
  │     └── Step: Run Vitest
  └── Job: build
        ├── Step: Checkout code
        ├── Step: Setup Docker Buildx
        └── Step: Build and push image
```

<br />

##### **Triggers: when does CI run?**
The `on` key in your workflow file defines when it runs. Here are the triggers you will use most
often:

<br />

```yaml
# Run on every push to main
on:
  push:
    branches: [main]

# Run on every pull request targeting main
on:
  pull_request:
    branches: [main]

# Run on both push and pull request
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# Run on a schedule (cron syntax, every day at 6 AM UTC)
on:
  schedule:
    - cron: "0 6 * * *"

# Run manually from the GitHub UI
on:
  workflow_dispatch:
```

<br />

For a typical project, you want CI to run on both `push` and `pull_request` to the main branch. The
push trigger catches anything that lands on main directly, and the pull request trigger gives you
feedback before merging.

<br />

##### **Building the pipeline step by step**
Let's build a real CI pipeline for a TypeScript project. We will start simple and add features
incrementally. Create the file `.github/workflows/ci.yml` in your repository:

<br />

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Run ESLint
        run: npx eslint . --max-warnings 0

  test:
    name: Test
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

      - name: Run tests with coverage
        run: npm run test:coverage

      - name: Upload coverage report
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
```

<br />

Let's break down what is happening here:

<br />

> * **`actions/checkout@v4`**: Clones your repository into the runner. Without this, the runner has no code to work with.
> * **`actions/setup-node@v4`**: Installs the specified Node.js version and configures npm caching.
> * **`npm ci`**: Installs dependencies from `package-lock.json` exactly as specified. Unlike `npm install`, it does not modify the lockfile and is faster and more reliable in CI.
> * **`npx eslint . --max-warnings 0`**: Runs ESLint and fails if there are any warnings. This is stricter than the default, which only fails on errors. Treating warnings as errors in CI prevents them from piling up.
> * **Lint and test jobs run in parallel**: Since they do not depend on each other, GitHub runs them at the same time, making your pipeline faster.

<br />

##### **Adding the Docker build**
Now let's add a job that builds a Docker image and pushes it to GitHub Container Registry (GHCR).
This job should only run after linting and tests pass, so we use the `needs` keyword to create a
dependency:

<br />

```yaml
  build:
    name: Build and Push Docker Image
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha,prefix=
            type=raw,value=latest

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

<br />

There is a lot going on here, so let's unpack it:

<br />

> * **`needs: [lint, test]`**: This job waits for both lint and test to pass before running. If either fails, the build is skipped entirely.
> * **`if: github.event_name == 'push' && github.ref == 'refs/heads/main'`**: Only build images on pushes to main, not on pull requests. You do not want to push a Docker image for every PR.
> * **`permissions`**: GitHub Actions uses a `GITHUB_TOKEN` that is automatically created for each workflow run. We need `packages: write` to push to GHCR.
> * **`docker/setup-buildx-action@v3`**: Sets up Docker Buildx, which is an extended build tool that supports advanced features like caching and multi-platform builds.
> * **`docker/login-action@v3`**: Logs into GHCR using the built-in `GITHUB_TOKEN`. No need to create a personal access token.
> * **`docker/metadata-action@v5`**: Generates tags and labels automatically. We tag with both the Git SHA (for traceability) and `latest` (for convenience).
> * **`docker/build-push-action@v6`**: Builds the Dockerfile and pushes the image. The `cache-from` and `cache-to` lines enable GitHub Actions cache for Docker layers, which we will explain next.

<br />

##### **Caching: making CI fast**
CI pipelines that take 10 minutes quickly become a bottleneck. Developers stop waiting for them,
start merging without checking results, and the whole point of CI breaks down. Caching is how you
keep things fast.

<br />

There are two things worth caching in a Node.js project: npm packages and Docker layers.

<br />

**npm cache** is the easier one. The `actions/setup-node@v4` action handles it for you when you add
`cache: "npm"`:

<br />

```yaml
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"
```

<br />

This caches the npm download cache (not `node_modules`), so `npm ci` still runs but does not need
to download packages from the registry. The first run populates the cache, and subsequent runs reuse
it. On a project with many dependencies, this can save 30 to 60 seconds per run.

<br />

**Docker layer cache** is more impactful. Building a Docker image from scratch every time is wasteful
because most layers (like the base image and installed system packages) rarely change. Docker Buildx
with the GitHub Actions cache backend stores layers between runs:

<br />

```yaml
      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

<br />

> * **`cache-from: type=gha`**: Pull cached layers from the GitHub Actions cache.
> * **`cache-to: type=gha,mode=max`**: Push all layers to the cache after building. The `mode=max` option caches intermediate layers too, not just the final image layers.

<br />

A well-structured Dockerfile benefits enormously from this. If your dependency installation layer
has not changed, Docker reuses the cached layer instead of running `npm ci` again inside the
container. This can cut build times from minutes to seconds.

<br />

##### **Matrix builds: testing across versions**
Sometimes you need to test your code against multiple Node.js versions, or multiple operating
systems, or both. Matrix builds let you define a set of variables and run the job once for each
combination.

<br />

```yaml
  test:
    name: Test (Node ${{ matrix.node-version }})
    runs-on: ubuntu-latest

    strategy:
      matrix:
        node-version: ["20", "22"]
      fail-fast: false

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js ${{ matrix.node-version }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test
```

<br />

This runs the test job twice: once with Node 20 and once with Node 22. Both runs happen in parallel
on separate runners, so it does not slow down your pipeline.

<br />

Key settings:

<br />

> * **`strategy.matrix`**: Defines the variables and their values. You can add more dimensions, like `os: [ubuntu-latest, windows-latest]`, and GitHub will run every combination.
> * **`fail-fast: false`**: By default, if one matrix job fails, GitHub cancels the others. Setting this to `false` lets all jobs complete, so you can see all failures at once.

<br />

Matrix builds are especially useful for libraries that need to support multiple runtimes. For
application code where you control the runtime, testing a single version is usually enough.

<br />

##### **Secrets and environment variables**
Your CI pipeline will often need credentials: API keys for external services, tokens for registries,
or database passwords for integration tests. GitHub provides two mechanisms for this.

<br />

**Environment variables** are for non-sensitive values:

<br />

```yaml
    env:
      NODE_ENV: test
      API_URL: https://api.staging.example.com

    steps:
      - name: Run tests
        run: npm test
        env:
          DATABASE_URL: postgres://localhost:5432/testdb
```

<br />

You can set environment variables at the workflow level, job level, or step level. Step-level
variables override job-level variables, which override workflow-level variables.

<br />

**Secrets** are for sensitive values like API keys and tokens:

<br />

```yaml
      - name: Deploy to staging
        run: ./deploy.sh
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

<br />

To add secrets, go to your repository's Settings, then Secrets and variables, then Actions. Secrets
are encrypted at rest and masked in logs. GitHub will replace the secret value with `***` if it
accidentally appears in the output.

<br />

Important rules about secrets:

<br />

> * **Never hardcode secrets in your workflow files**. They are committed to the repository and visible to anyone with read access.
> * **`GITHUB_TOKEN` is automatic**. You do not need to create it. GitHub generates one for every workflow run with permissions scoped to the repository.
> * **Secrets are not available in pull requests from forks**. This is a security feature. If your tests need secrets, they will fail on fork PRs, which is expected.
> * **Use environments for deployment secrets**. GitHub environments let you require approvals and restrict which branches can use certain secrets.

<br />

##### **Reusable workflows: keeping things DRY**
As your organization grows, you will have multiple repositories that need similar CI pipelines. Copy
pasting YAML files between repositories is a maintenance nightmare. Reusable workflows let you define
a workflow once and call it from other workflows.

<br />

First, create the reusable workflow in a shared repository. The key difference is the
`workflow_call` trigger:

<br />

```yaml
# .github/workflows/node-ci.yml (in your shared repo)
name: Node.js CI

on:
  workflow_call:
    inputs:
      node-version:
        description: "Node.js version to use"
        required: false
        type: string
        default: "22"
      run-lint:
        description: "Whether to run linting"
        required: false
        type: boolean
        default: true

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    if: ${{ inputs.run-lint }}

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: "npm"

      - run: npm ci

      - run: npx eslint . --max-warnings 0

  test:
    name: Test
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: "npm"

      - run: npm ci

      - run: npm test
```

<br />

Then call it from any repository:

<br />

```yaml
# .github/workflows/ci.yml (in your project repo)
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    uses: your-org/shared-workflows/.github/workflows/node-ci.yml@main
    with:
      node-version: "22"
      run-lint: true
```

<br />

The benefits are significant:

<br />

> * **Single source of truth**: Update the shared workflow and every repository that uses it gets the update.
> * **Consistency**: Every project follows the same CI process, same actions versions, same caching strategy.
> * **Less maintenance**: Fix a bug or upgrade an action in one place, not in fifty repositories.
> * **Inputs make it flexible**: Each project can customize behavior (Node version, whether to lint, etc.) without forking the workflow.

<br />

##### **Status badges: show your pipeline health**
Once your CI pipeline is working, you want everyone to see its status at a glance. GitHub provides
status badges that you can add to your README:

<br />

```markdown
![CI](https://github.com/your-org/your-repo/actions/workflows/ci.yml/badge.svg)
```

<br />

This renders as a small badge that shows "passing" (green) or "failing" (red) based on the latest
run of the workflow. Add it to the top of your README so contributors immediately know the project's
health.

<br />

You can also make badges branch-specific:

<br />

```markdown
![CI](https://github.com/your-org/your-repo/actions/workflows/ci.yml/badge.svg?branch=main)
```

<br />

This only reflects the status of the workflow on the main branch, ignoring feature branches.

<br />

##### **Branch protection: require CI to pass before merge**
A CI pipeline is only useful if people cannot bypass it. Branch protection rules ensure that code
cannot be merged into main unless CI passes. Here is how to set it up:

<br />

> 1. Go to your repository's Settings, then Branches.
> 2. Click "Add branch protection rule" (or "Add classic branch protection rule").
> 3. Set the branch name pattern to `main`.
> 4. Check "Require status checks to pass before merging."
> 5. Search for and select your CI job names (e.g., "Lint", "Test").
> 6. Optionally check "Require branches to be up to date before merging" to prevent merging stale branches.

<br />

With this in place, the merge button on a pull request is disabled until all required checks pass.
No one can bypass CI, not even repository admins (unless they explicitly override it, which leaves an
audit trail).

<br />

Additional protections worth enabling:

<br />

> * **Require pull request reviews**: At least one team member must approve before merging.
> * **Require linear history**: Force squash or rebase merges for a clean git history.
> * **Do not allow bypassing the above settings**: Even admins must follow the rules.

<br />

##### **The complete workflow file**
Here is the full CI pipeline combining everything we covered. This is a production-ready starting
point for any TypeScript project:

<br />

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  NODE_ENV: test
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Check formatting
        run: npx prettier --check .

      - name: Run ESLint
        run: npx eslint . --max-warnings 0

      - name: Type check
        run: npx tsc --noEmit

  test:
    name: Test (Node ${{ matrix.node-version }})
    runs-on: ubuntu-latest

    strategy:
      matrix:
        node-version: ["20", "22"]
      fail-fast: false

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js ${{ matrix.node-version }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

      - name: Run tests with coverage
        run: npm run test:coverage

      - name: Upload coverage report
        if: matrix.node-version == '22'
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
          retention-days: 14

  build:
    name: Build and Push Docker Image
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
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
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

<br />

Notice a few things about this complete workflow:

<br />

> * **Three stages**: Lint, test, and build. They form a pipeline where each stage gates the next.
> * **Type checking in lint**: We added `tsc --noEmit` to catch TypeScript errors. This is a cheap check that catches a whole class of bugs.
> * **Prettier check**: `prettier --check` verifies formatting without modifying files. If a developer forgot to format, CI catches it.
> * **Coverage only uploaded once**: When running a matrix build, you only need one coverage report, not one per Node version. The `if: matrix.node-version == '22'` conditional handles this.
> * **Retention days**: Artifacts do not need to live forever. Setting `retention-days: 14` keeps things tidy.
> * **Environment variables at the top**: `REGISTRY` and `IMAGE_NAME` are defined once and reused, making the workflow easier to adapt to other registries.

<br />

##### **Debugging failed workflows**
When your CI pipeline fails (and it will), here is how to debug it:

<br />

> * **Read the logs**: Click on the failed job in the GitHub Actions UI. Each step shows its output. The error is usually in the last few lines of the failed step.
> * **Run locally first**: Before pushing, run the same commands locally. `npm ci && npx eslint . && npm test` should produce the same result as CI.
> * **Check the runner environment**: CI runs on a clean Ubuntu machine. If something works locally but fails in CI, the difference is usually in environment variables, installed tools, or file paths.
> * **Use `act` for local testing**: The `act` tool (https://github.com/nektos/act) lets you run GitHub Actions workflows on your local machine using Docker. It is not perfect, but it catches most issues.
> * **Enable debug logging**: Re-run the workflow with debug logging enabled by going to the failed run, clicking "Re-run all jobs", and checking "Enable debug logging." This adds verbose output from every action.

<br />

##### **Common pitfalls and how to avoid them**
A few things that trip people up when setting up CI for the first time:

<br />

> * **Not using `npm ci`**: Using `npm install` in CI can produce different dependency trees than your local machine. Always use `npm ci`, which installs exactly what is in `package-lock.json`.
> * **Missing `package-lock.json` in the repository**: If you gitignored it, `npm ci` will fail. The lockfile should always be committed.
> * **Tests that depend on order**: If your tests pass locally but fail in CI, they might depend on execution order. Vitest runs tests in parallel by default, which can expose this.
> * **Hardcoded paths**: Tests that reference `/Users/yourname/project/` will fail on a Linux runner. Use relative paths or environment variables.
> * **Forgetting the Docker context**: If your Dockerfile copies files with `COPY . .`, make sure your `.dockerignore` excludes `node_modules`, `.git`, and other large directories.
> * **Overly broad triggers**: Running CI on every push to every branch wastes runner minutes. Limit triggers to `main` and pull requests targeting `main`.

<br />

##### **What comes next**
We now have a CI pipeline that lints, tests, and builds our code automatically. But CI is only half
the story. Getting code into a container is useful, but that container needs to go somewhere.

<br />

In the next article, we will tackle Continuous Deployment (CD): taking the Docker image we just built
and deploying it to a real environment. We will cover deployment strategies, rollbacks, and how to
make deployments boring (which is exactly what you want them to be).

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps from Zero to Hero: Tu Primer Pipeline de CI con GitHub Actions",
  author: "Gabriel Garrido",
  description: "Vamos a construir un pipeline de CI completo con GitHub Actions cubriendo linting, testing, builds de Docker, caching, matrix builds y workflows reutilizables...",
  tags: ~w(devops github-actions ci-cd beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al quinto articulo de la serie DevOps from Zero to Hero. En el articulo anterior escribimos
tests unitarios y de integracion para un proyecto TypeScript. Los tests son geniales, pero solo sirven
si alguien los corre. Ese alguien no deberias ser vos, manualmente, justo antes de un deploy. Deberia
ser una maquina que los corre cada vez que el codigo cambia.

<br />

De eso se trata la Integracion Continua (CI): automatizar las tareas aburridas, repetitivas y criticas
para que los humanos puedan enfocarse en escribir codigo. En este articulo vamos a construir un pipeline
de CI completo con GitHub Actions desde cero. Al final, cada push y pull request a tu repositorio va
a hacer lint del codigo automaticamente, correr tests, construir una imagen Docker y pushearla a un
registro de contenedores.

<br />

Vamos a meternos de lleno.

<br />

##### **Que es CI y por que importa**
Integracion Continua es la practica de construir y testear codigo automaticamente cada vez que alguien
pushea un cambio. La palabra "continua" es importante: esto no es algo que haces una vez por semana o
antes de un release. Pasa en cada commit, cada pull request, cada vez.

<br />

Por que importa? Tres razones:

<br />

> * **Atrapar bugs temprano**: Un bug encontrado en CI cuesta minutos en arreglar. Un bug encontrado en produccion cuesta horas, confianza de los clientes y a veces plata. Cuanto antes lo atrapes, mas barato es.
> * **Aplicar estandares**: Linting, formateo y type checking no deberian depender de que los desarrolladores se acuerden de correrlos. CI aplica estos estandares automaticamente, cada vez.
> * **Automatizar tareas repetitivas**: Construir imagenes Docker, correr suites de tests, generar artefactos. Estas son cosas que deberia hacer una maquina, no una persona.

<br />

Sin CI, tu workflow se ve asi: un desarrollador escribe codigo, se olvida de correr el linter, pushea
a main, rompe el build y todo el equipo se entera una hora despues. Con CI, el linter corre
automaticamente, el push se bloquea y el desarrollador lo arregla en cinco minutos antes de que afecte
a alguien mas.

<br />

CI es la primera capa real de automatizacion en un pipeline de DevOps. Todo lo demas, delivery continuo,
deployment continuo, infraestructura como codigo, todo se construye arriba de CI.

<br />

##### **Fundamentos de GitHub Actions**
GitHub Actions es una plataforma de CI/CD integrada en GitHub. Definis workflows como archivos YAML en
un directorio `.github/workflows/`, y GitHub los ejecuta por vos en maquinas virtuales hosteadas. No
hay un servicio separado que configurar, no hay webhooks que armar y no hay servidores que administrar.

<br />

Antes de escribir YAML, entendamos los conceptos clave:

<br />

> * **Workflow**: Un archivo YAML que define un proceso automatizado. Cada workflow vive en `.github/workflows/` y se dispara por eventos.
> * **Evento (trigger)**: Lo que causa que el workflow se ejecute. Triggers comunes son `push`, `pull_request` y `schedule`.
> * **Job**: Un conjunto de pasos que corren en la misma maquina virtual (llamada "runner"). Un workflow puede tener multiples jobs, y por defecto corren en paralelo.
> * **Step**: Una tarea individual dentro de un job. Un step puede ejecutar un comando de shell o usar una action pre-construida.
> * **Action**: Una unidad reutilizable de codigo que realiza una tarea comun. Por ejemplo, `actions/checkout@v4` clona tu repositorio, y `actions/setup-node@v4` instala Node.js.
> * **Runner**: La maquina virtual que ejecuta tu job. GitHub provee runners hosteados con Ubuntu, Windows y macOS.

<br />

Aca esta la jerarquia visualizada:

<br />

```
Workflow (.github/workflows/ci.yml)
  ├── Evento: push a main, pull_request
  ├── Job: lint
  │     ├── Step: Checkout codigo
  │     ├── Step: Setup Node.js
  │     └── Step: Correr ESLint
  ├── Job: test
  │     ├── Step: Checkout codigo
  │     ├── Step: Setup Node.js
  │     ├── Step: Instalar dependencias
  │     └── Step: Correr Vitest
  └── Job: build
        ├── Step: Checkout codigo
        ├── Step: Setup Docker Buildx
        └── Step: Build y push imagen
```

<br />

##### **Triggers: cuando corre CI?**
La key `on` en tu archivo de workflow define cuando se ejecuta. Estos son los triggers que vas a usar
con mas frecuencia:

<br />

```yaml
# Correr en cada push a main
on:
  push:
    branches: [main]

# Correr en cada pull request apuntando a main
on:
  pull_request:
    branches: [main]

# Correr en push y pull request
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# Correr en un schedule (sintaxis cron, todos los dias a las 6 AM UTC)
on:
  schedule:
    - cron: "0 6 * * *"

# Correr manualmente desde la UI de GitHub
on:
  workflow_dispatch:
```

<br />

Para un proyecto tipico, queres que CI corra tanto en `push` como en `pull_request` a la rama main.
El trigger de push atrapa cualquier cosa que llegue a main directamente, y el trigger de pull request
te da feedback antes de mergear.

<br />

##### **Construyendo el pipeline paso a paso**
Vamos a construir un pipeline de CI real para un proyecto TypeScript. Empezamos simple y vamos
agregando funcionalidades de forma incremental. Crea el archivo `.github/workflows/ci.yml` en tu
repositorio:

<br />

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Run ESLint
        run: npx eslint . --max-warnings 0

  test:
    name: Test
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

      - name: Run tests with coverage
        run: npm run test:coverage

      - name: Upload coverage report
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
```

<br />

Veamos que esta pasando aca:

<br />

> * **`actions/checkout@v4`**: Clona tu repositorio en el runner. Sin esto, el runner no tiene codigo con el que trabajar.
> * **`actions/setup-node@v4`**: Instala la version especificada de Node.js y configura el caching de npm.
> * **`npm ci`**: Instala las dependencias de `package-lock.json` exactamente como se especifican. A diferencia de `npm install`, no modifica el lockfile y es mas rapido y confiable en CI.
> * **`npx eslint . --max-warnings 0`**: Corre ESLint y falla si hay algun warning. Esto es mas estricto que el comportamiento por defecto, que solo falla por errores. Tratar los warnings como errores en CI evita que se acumulen.
> * **Los jobs de lint y test corren en paralelo**: Como no dependen uno del otro, GitHub los corre al mismo tiempo, haciendo tu pipeline mas rapido.

<br />

##### **Agregando el build de Docker**
Ahora agreguemos un job que construya una imagen Docker y la pushee a GitHub Container Registry (GHCR).
Este job solo deberia correr despues de que lint y tests pasen, asi que usamos la keyword `needs` para
crear una dependencia:

<br />

```yaml
  build:
    name: Build and Push Docker Image
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha,prefix=
            type=raw,value=latest

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

<br />

Hay mucho pasando aca, asi que vamos a desarmarlo:

<br />

> * **`needs: [lint, test]`**: Este job espera a que tanto lint como test pasen antes de correr. Si alguno falla, el build se saltea completamente.
> * **`if: github.event_name == 'push' && github.ref == 'refs/heads/main'`**: Solo construye imagenes en pushes a main, no en pull requests. No queres pushear una imagen Docker por cada PR.
> * **`permissions`**: GitHub Actions usa un `GITHUB_TOKEN` que se crea automaticamente para cada ejecucion de workflow. Necesitamos `packages: write` para pushear a GHCR.
> * **`docker/setup-buildx-action@v3`**: Configura Docker Buildx, que es una herramienta de build extendida que soporta funcionalidades avanzadas como caching y builds multi-plataforma.
> * **`docker/login-action@v3`**: Se loguea a GHCR usando el `GITHUB_TOKEN` integrado. No necesitas crear un token de acceso personal.
> * **`docker/metadata-action@v5`**: Genera tags y labels automaticamente. Tagueamos con el SHA de Git (para trazabilidad) y `latest` (por conveniencia).
> * **`docker/build-push-action@v6`**: Construye el Dockerfile y pushea la imagen. Las lineas `cache-from` y `cache-to` habilitan el cache de GitHub Actions para las capas de Docker, que explicamos a continuacion.

<br />

##### **Caching: haciendo CI rapido**
Los pipelines de CI que tardan 10 minutos se convierten rapidamente en un cuello de botella. Los
desarrolladores dejan de esperar los resultados, empiezan a mergear sin verificar y se pierde todo
el sentido de CI. El caching es como mantenes las cosas rapidas.

<br />

Hay dos cosas que vale la pena cachear en un proyecto Node.js: paquetes npm y capas de Docker.

<br />

**npm cache** es lo mas facil. La action `actions/setup-node@v4` lo maneja por vos cuando agregas
`cache: "npm"`:

<br />

```yaml
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"
```

<br />

Esto cachea el cache de descarga de npm (no `node_modules`), asi que `npm ci` todavia corre pero no
necesita descargar paquetes del registry. La primera ejecucion llena el cache y las siguientes lo
reutilizan. En un proyecto con muchas dependencias, esto puede ahorrar 30 a 60 segundos por ejecucion.

<br />

**Docker layer cache** tiene mas impacto. Construir una imagen Docker desde cero cada vez es un
desperdicio porque la mayoria de las capas (como la imagen base y los paquetes del sistema instalados)
rara vez cambian. Docker Buildx con el backend de cache de GitHub Actions guarda las capas entre
ejecuciones:

<br />

```yaml
      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

<br />

> * **`cache-from: type=gha`**: Trae capas cacheadas del cache de GitHub Actions.
> * **`cache-to: type=gha,mode=max`**: Pushea todas las capas al cache despues de construir. La opcion `mode=max` cachea las capas intermedias tambien, no solo las capas de la imagen final.

<br />

Un Dockerfile bien estructurado se beneficia enormemente de esto. Si tu capa de instalacion de
dependencias no cambio, Docker reutiliza la capa cacheada en vez de correr `npm ci` de nuevo
dentro del contenedor. Esto puede reducir los tiempos de build de minutos a segundos.

<br />

##### **Matrix builds: testeando entre versiones**
A veces necesitas testear tu codigo contra multiples versiones de Node.js, o multiples sistemas
operativos, o ambos. Los matrix builds te permiten definir un conjunto de variables y correr el
job una vez por cada combinacion.

<br />

```yaml
  test:
    name: Test (Node ${{ matrix.node-version }})
    runs-on: ubuntu-latest

    strategy:
      matrix:
        node-version: ["20", "22"]
      fail-fast: false

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js ${{ matrix.node-version }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test
```

<br />

Esto corre el job de test dos veces: una con Node 20 y otra con Node 22. Ambas ejecuciones pasan en
paralelo en runners separados, asi que no ralentiza tu pipeline.

<br />

Configuraciones clave:

<br />

> * **`strategy.matrix`**: Define las variables y sus valores. Podes agregar mas dimensiones, como `os: [ubuntu-latest, windows-latest]`, y GitHub va a correr cada combinacion.
> * **`fail-fast: false`**: Por defecto, si un job de la matrix falla, GitHub cancela los demas. Poner esto en `false` deja que todos los jobs terminen, asi podes ver todas las fallas a la vez.

<br />

Los matrix builds son especialmente utiles para librerias que necesitan soportar multiples runtimes.
Para codigo de aplicacion donde vos controlas el runtime, testear una sola version suele ser
suficiente.

<br />

##### **Secrets y variables de entorno**
Tu pipeline de CI va a necesitar credenciales frecuentemente: API keys para servicios externos,
tokens para registries o passwords de bases de datos para tests de integracion. GitHub provee dos
mecanismos para esto.

<br />

**Variables de entorno** son para valores no sensibles:

<br />

```yaml
    env:
      NODE_ENV: test
      API_URL: https://api.staging.example.com

    steps:
      - name: Run tests
        run: npm test
        env:
          DATABASE_URL: postgres://localhost:5432/testdb
```

<br />

Podes definir variables de entorno a nivel de workflow, de job o de step. Las variables a nivel de
step sobreescriben las de nivel de job, que sobreescriben las de nivel de workflow.

<br />

**Secrets** son para valores sensibles como API keys y tokens:

<br />

```yaml
      - name: Deploy to staging
        run: ./deploy.sh
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

<br />

Para agregar secrets, anda a Settings de tu repositorio, despues Secrets and variables, despues
Actions. Los secrets se encriptan en reposo y se enmascaran en los logs. GitHub va a reemplazar
el valor del secret con `***` si accidentalmente aparece en la salida.

<br />

Reglas importantes sobre secrets:

<br />

> * **Nunca hardcodees secrets en tus archivos de workflow**. Estan commiteados al repositorio y son visibles para cualquiera con acceso de lectura.
> * **`GITHUB_TOKEN` es automatico**. No necesitas crearlo. GitHub genera uno para cada ejecucion de workflow con permisos limitados al repositorio.
> * **Los secrets no estan disponibles en pull requests de forks**. Esta es una funcionalidad de seguridad. Si tus tests necesitan secrets, van a fallar en PRs de forks, lo cual es esperado.
> * **Usa environments para secrets de deployment**. Los environments de GitHub te permiten requerir aprobaciones y restringir que ramas pueden usar ciertos secrets.

<br />

##### **Workflows reutilizables: manteniendo las cosas DRY**
A medida que tu organizacion crece, vas a tener multiples repositorios que necesitan pipelines de CI
similares. Copiar y pegar archivos YAML entre repositorios es una pesadilla de mantenimiento. Los
workflows reutilizables te permiten definir un workflow una vez y llamarlo desde otros workflows.

<br />

Primero, crea el workflow reutilizable en un repositorio compartido. La diferencia clave es el
trigger `workflow_call`:

<br />

```yaml
# .github/workflows/node-ci.yml (en tu repo compartido)
name: Node.js CI

on:
  workflow_call:
    inputs:
      node-version:
        description: "Version de Node.js a usar"
        required: false
        type: string
        default: "22"
      run-lint:
        description: "Si correr linting o no"
        required: false
        type: boolean
        default: true

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    if: ${{ inputs.run-lint }}

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: "npm"

      - run: npm ci

      - run: npx eslint . --max-warnings 0

  test:
    name: Test
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: "npm"

      - run: npm ci

      - run: npm test
```

<br />

Despues lo llamas desde cualquier repositorio:

<br />

```yaml
# .github/workflows/ci.yml (en tu repo del proyecto)
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    uses: your-org/shared-workflows/.github/workflows/node-ci.yml@main
    with:
      node-version: "22"
      run-lint: true
```

<br />

Los beneficios son significativos:

<br />

> * **Unica fuente de verdad**: Actualiza el workflow compartido y cada repositorio que lo usa recibe la actualizacion.
> * **Consistencia**: Cada proyecto sigue el mismo proceso de CI, mismas versiones de actions, misma estrategia de caching.
> * **Menos mantenimiento**: Arregla un bug o actualiza una action en un lugar, no en cincuenta repositorios.
> * **Los inputs lo hacen flexible**: Cada proyecto puede personalizar el comportamiento (version de Node, si hacer lint o no, etc.) sin forkear el workflow.

<br />

##### **Status badges: mostra la salud de tu pipeline**
Una vez que tu pipeline de CI esta funcionando, queres que todos vean su estado de un vistazo. GitHub
provee badges de estado que podes agregar a tu README:

<br />

```markdown
![CI](https://github.com/your-org/your-repo/actions/workflows/ci.yml/badge.svg)
```

<br />

Esto se renderiza como un badge chiquito que muestra "passing" (verde) o "failing" (rojo) basado en
la ultima ejecucion del workflow. Agregalo al principio de tu README para que los colaboradores
sepan inmediatamente la salud del proyecto.

<br />

Tambien podes hacer badges especificos por rama:

<br />

```markdown
![CI](https://github.com/your-org/your-repo/actions/workflows/ci.yml/badge.svg?branch=main)
```

<br />

Esto solo refleja el estado del workflow en la rama main, ignorando las feature branches.

<br />

##### **Branch protection: requerir que CI pase antes de mergear**
Un pipeline de CI solo es util si la gente no puede saltearselo. Las reglas de branch protection
aseguran que el codigo no se pueda mergear a main a menos que CI pase. Aca te explico como
configurarlo:

<br />

> 1. Anda a Settings de tu repositorio, despues Branches.
> 2. Clickea "Add branch protection rule" (o "Add classic branch protection rule").
> 3. Pone el patron de nombre de rama en `main`.
> 4. Marca "Require status checks to pass before merging."
> 5. Busca y selecciona los nombres de tus jobs de CI (por ejemplo, "Lint", "Test").
> 6. Opcionalmente marca "Require branches to be up to date before merging" para evitar mergear ramas desactualizadas.

<br />

Con esto configurado, el boton de merge en un pull request esta deshabilitado hasta que todas las
verificaciones requeridas pasen. Nadie puede saltear CI, ni siquiera los admins del repositorio (a
menos que lo sobreescriban explicitamente, lo cual deja un registro de auditoria).

<br />

Protecciones adicionales que vale la pena habilitar:

<br />

> * **Requerir reviews de pull request**: Al menos un miembro del equipo debe aprobar antes de mergear.
> * **Requerir historia lineal**: Forzar squash o rebase merges para una historia de git limpia.
> * **No permitir saltear las configuraciones anteriores**: Incluso los admins deben seguir las reglas.

<br />

##### **El archivo de workflow completo**
Aca esta el pipeline de CI completo combinando todo lo que cubrimos. Este es un punto de partida listo
para produccion para cualquier proyecto TypeScript:

<br />

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  NODE_ENV: test
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Check formatting
        run: npx prettier --check .

      - name: Run ESLint
        run: npx eslint . --max-warnings 0

      - name: Type check
        run: npx tsc --noEmit

  test:
    name: Test (Node ${{ matrix.node-version }})
    runs-on: ubuntu-latest

    strategy:
      matrix:
        node-version: ["20", "22"]
      fail-fast: false

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js ${{ matrix.node-version }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

      - name: Run tests with coverage
        run: npm run test:coverage

      - name: Upload coverage report
        if: matrix.node-version == '22'
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
          retention-days: 14

  build:
    name: Build and Push Docker Image
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
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
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

<br />

Fijate en algunas cosas de este workflow completo:

<br />

> * **Tres etapas**: Lint, test y build. Forman un pipeline donde cada etapa filtra la siguiente.
> * **Type checking en lint**: Agregamos `tsc --noEmit` para atrapar errores de TypeScript. Este es un chequeo barato que atrapa toda una clase de bugs.
> * **Prettier check**: `prettier --check` verifica el formato sin modificar archivos. Si un desarrollador se olvido de formatear, CI lo atrapa.
> * **Coverage solo se sube una vez**: Cuando corres un matrix build, solo necesitas un reporte de coverage, no uno por version de Node. El condicional `if: matrix.node-version == '22'` maneja esto.
> * **Dias de retencion**: Los artefactos no necesitan existir para siempre. Poner `retention-days: 14` mantiene las cosas ordenadas.
> * **Variables de entorno arriba**: `REGISTRY` e `IMAGE_NAME` se definen una vez y se reutilizan, haciendo que el workflow sea mas facil de adaptar a otros registries.

<br />

##### **Debuggeando workflows fallidos**
Cuando tu pipeline de CI falle (y va a fallar), aca tenes como debuggearlo:

<br />

> * **Lee los logs**: Clickea en el job fallido en la UI de GitHub Actions. Cada step muestra su salida. El error generalmente esta en las ultimas lineas del step fallido.
> * **Corre localmente primero**: Antes de pushear, corre los mismos comandos localmente. `npm ci && npx eslint . && npm test` deberia producir el mismo resultado que CI.
> * **Verifica el entorno del runner**: CI corre en una maquina Ubuntu limpia. Si algo funciona localmente pero falla en CI, la diferencia suele estar en variables de entorno, herramientas instaladas o rutas de archivos.
> * **Usa `act` para testing local**: La herramienta `act` (https://github.com/nektos/act) te permite correr workflows de GitHub Actions en tu maquina local usando Docker. No es perfecto, pero atrapa la mayoria de los problemas.
> * **Habilita el logging de debug**: Re-ejecuta el workflow con logging de debug habilitado yendo a la ejecucion fallida, clickeando "Re-run all jobs" y marcando "Enable debug logging." Esto agrega salida verbosa de cada action.

<br />

##### **Errores comunes y como evitarlos**
Algunas cosas que complican a la gente cuando configura CI por primera vez:

<br />

> * **No usar `npm ci`**: Usar `npm install` en CI puede producir arboles de dependencias diferentes a tu maquina local. Siempre usa `npm ci`, que instala exactamente lo que esta en `package-lock.json`.
> * **Falta `package-lock.json` en el repositorio**: Si lo pusiste en el gitignore, `npm ci` va a fallar. El lockfile siempre deberia estar commiteado.
> * **Tests que dependen del orden**: Si tus tests pasan localmente pero fallan en CI, podrian depender del orden de ejecucion. Vitest corre tests en paralelo por defecto, lo que puede exponer esto.
> * **Paths hardcodeados**: Tests que referencian `/Users/tunombre/proyecto/` van a fallar en un runner Linux. Usa paths relativos o variables de entorno.
> * **Olvidarse del contexto de Docker**: Si tu Dockerfile copia archivos con `COPY . .`, asegurate de que tu `.dockerignore` excluya `node_modules`, `.git` y otros directorios grandes.
> * **Triggers demasiado amplios**: Correr CI en cada push a cada rama desperdicia minutos de runner. Limita los triggers a `main` y pull requests apuntando a `main`.

<br />

##### **Que viene despues**
Ahora tenemos un pipeline de CI que hace lint, testea y construye nuestro codigo automaticamente. Pero
CI es solo la mitad de la historia. Meter codigo en un contenedor es util, pero ese contenedor necesita
ir a algun lado.

<br />

En el proximo articulo, vamos a abordar Continuous Deployment (CD): tomar la imagen Docker que acabamos
de construir y deployarla a un entorno real. Vamos a cubrir estrategias de deployment, rollbacks y como
hacer que los deployments sean aburridos (que es exactamente lo que queres que sean).

<br />

Espero que te haya resultado util y que lo hayas disfrutado, hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en los [fuentes aca](https://github.com/kainlite/tr)

<br />
