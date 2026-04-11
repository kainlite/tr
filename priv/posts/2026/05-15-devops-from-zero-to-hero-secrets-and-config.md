%{
  title: "DevOps from Zero to Hero: Secrets, Config, and Environment Management",
  author: "Gabriel Garrido",
  description: "We will explore the 12-factor app config methodology, environment variables, AWS Secrets Manager, Parameter Store, and how to manage configuration across environments...",
  tags: ~w(devops aws secrets configuration beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article nine of the DevOps from Zero to Hero series. In the previous article we deployed
our TypeScript API to ECS with Fargate, and everything is running in the cloud. But we skipped over
something important: how does your application get its database URL, API keys, and other configuration
values? If you hard-coded them into your source code, you have a problem.

<br />

Configuration and secrets management is one of those topics that seems simple until you get it wrong.
A leaked API key can cost you thousands of dollars. A misconfigured database URL can point your
production app at the staging database. A checked-in `.env` file can expose credentials to anyone who
clones your repository. These are not hypothetical scenarios, they happen all the time.

<br />

In this article we will cover the foundational practices for handling configuration and secrets: the
12-factor methodology, environment variables, `.env` files, secret scanning, AWS Secrets Manager,
AWS Systems Manager Parameter Store, and how to structure configuration across dev, staging, and
production environments. By the end you will have a clear, practical approach to keeping your config
clean and your secrets safe.

<br />

Let's get into it.

<br />

##### **The 12-factor app: config belongs in the environment**
The [Twelve-Factor App](https://12factor.net/) is a methodology for building modern applications that
was published by the team at Heroku back in 2012. It describes twelve principles for building software
that is easy to deploy, scale, and maintain. Factor number three is about configuration, and it says
something very clear: store config in the environment.

<br />

What does "config" mean here? It is anything that is likely to change between environments (dev,
staging, production). Database URLs, API keys, feature flags, external service endpoints, log levels.
These values should not live in your source code. They should not be baked into your Docker image.
They should come from the environment where your application is running.

<br />

The reasoning is simple:

<br />

> * **Security**: Secrets in source code end up in version control, in CI logs, in Docker layers, and in the hands of anyone who has access to your repository.
> * **Portability**: If your database URL is hard-coded, you cannot run the same code against a staging database without changing the code. If it comes from the environment, you just change the environment variable.
> * **Simplicity**: One build artifact (your Docker image) works in every environment. The only thing that changes is the configuration injected at runtime.

<br />

Here is the anti-pattern versus the correct approach:

<br />

```typescript
// BAD: hard-coded config
const dbUrl = "postgresql://admin:supersecret@prod-db.example.com:5432/myapp";

// GOOD: read from the environment
const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  throw new Error("DATABASE_URL environment variable is required");
}
```

<br />

That second example follows the 12-factor principle. The application does not know or care which
environment it is running in. It just reads the value from the environment and uses it.

<br />

##### **Environment variables: how they work**
Environment variables are key-value pairs that exist in the operating system's process environment.
Every process inherits the environment of its parent process, and you can set additional variables
when launching a process.

<br />

Setting and reading environment variables in the shell:

<br />

```bash
# Set a variable for the current shell session
export DATABASE_URL="postgresql://localhost:5432/myapp"

# Read it
echo $DATABASE_URL

# Set a variable only for a single command
DATABASE_URL="postgresql://localhost:5432/myapp" node app.js

# List all environment variables
env

# Unset a variable
unset DATABASE_URL
```

<br />

In Node.js/TypeScript, you access them through `process.env`:

<br />

```typescript
// Read an environment variable
const port = process.env.PORT || "3000";
const dbUrl = process.env.DATABASE_URL;
const logLevel = process.env.LOG_LEVEL || "info";

// Check for required variables at startup
const required = ["DATABASE_URL", "API_KEY", "JWT_SECRET"];
for (const key of required) {
  if (!process.env[key]) {
    console.error(`Missing required environment variable: ${key}`);
    process.exit(1);
  }
}
```

<br />

This pattern of checking for required variables at startup is important. You want your application to
fail fast and loud if it is missing configuration, not silently break at some random point later.

<br />

##### **Dotenv files: local development convenience**
Typing `export DATABASE_URL=...` every time you open a terminal gets old fast. That is where `.env`
files come in. A `.env` file is a simple text file that lists environment variables, one per line:

<br />

```bash
# .env
DATABASE_URL=postgresql://localhost:5432/myapp_dev
API_KEY=dev-api-key-not-real
JWT_SECRET=local-dev-secret
LOG_LEVEL=debug
PORT=3000
```

<br />

Libraries like [dotenv](https://www.npmjs.com/package/dotenv) for Node.js automatically read this file
and load the variables into `process.env` when your application starts:

<br />

```typescript
// Load .env file at the very top of your entry point
import "dotenv/config";

// Now process.env.DATABASE_URL is available
console.log(process.env.DATABASE_URL);
```

<br />

The critical rule with `.env` files is: **never commit them to Git**. They contain secrets, and your
Git repository is not a secure place to store secrets. Add `.env` to your `.gitignore` immediately:

<br />

```bash
# .gitignore

# Environment files with secrets
.env
.env.local
.env.*.local

# Keep the example file (no real secrets)
!.env.example
```

<br />

Instead of committing your actual `.env` file, commit a `.env.example` file with placeholder values.
This tells your teammates what variables they need without exposing real secrets:

<br />

```bash
# .env.example
DATABASE_URL=postgresql://localhost:5432/myapp_dev
API_KEY=your-api-key-here
JWT_SECRET=generate-a-random-string
LOG_LEVEL=debug
PORT=3000
```

<br />

When a new developer joins the team, they copy `.env.example` to `.env` and fill in their own values.
Simple, safe, effective.

<br />

##### **Why you should never commit secrets to Git**
This deserves its own section because it is that important. When you commit a secret to Git, it does
not just exist in the current version of the file. It exists in the Git history forever. Even if you
delete the file or overwrite the value in a later commit, anyone who clones the repository can find
it by looking at the commit history.

<br />

```bash
# Oops, I committed my .env file
git log --all --full-history -- .env

# Anyone can see the contents of that file at that commit
git show abc123:.env
```

<br />

If this happens, the secret is compromised. You need to rotate it immediately, meaning generate a new
key and revoke the old one. Rewriting Git history with `git filter-branch` or BFG Repo-Cleaner is
possible but painful, especially in a shared repository.

<br />

The better approach is prevention. Use tools that scan your repository for secrets before they ever
get committed:

<br />

> * **[git-secrets](https://github.com/awslabs/git-secrets)**: An AWS tool that installs Git hooks to prevent committing secrets. It scans for AWS access keys, secret keys, and custom patterns you define.
> * **[gitleaks](https://github.com/gitleaks/gitleaks)**: A faster, more comprehensive scanner that detects a wide range of secret patterns (API keys, tokens, passwords) across your entire repository history.
> * **[pre-commit](https://pre-commit.com/)**: A framework for managing Git pre-commit hooks. You can add gitleaks or git-secrets as a hook that runs automatically on every commit.

<br />

Here is how to set up gitleaks as a pre-commit hook:

<br />

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

<br />

```bash
# Install pre-commit and set up the hooks
pip install pre-commit
pre-commit install

# Now every commit will be scanned for secrets automatically
git commit -m "add new feature"
# gitleaks runs and blocks the commit if it finds a secret
```

<br />

You should also run gitleaks in your CI pipeline as a safety net. We covered CI pipelines in article
five, so adding a gitleaks step is straightforward:

<br />

```yaml
# In your GitHub Actions workflow
- name: Scan for secrets
  uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

<br />

##### **Config hierarchy: how values get resolved**
In a real application, configuration can come from multiple sources. When the same key is defined in
more than one place, you need a clear precedence order. The standard hierarchy, from lowest to highest
priority, looks like this:

<br />

```plaintext
1. Application defaults (hard-coded fallbacks in your code)
2. Config files (JSON, YAML, TOML files loaded at startup)
3. Environment variables (set by the OS, container runtime, or .env file)
4. CLI flags (passed when starting the application)
5. Remote config (fetched from Secrets Manager, Parameter Store, etc.)
```

<br />

Each level overrides the one below it. So if your code has a default `LOG_LEVEL=info`, your config
file sets it to `warn`, and your environment variable sets it to `debug`, the environment variable
wins. If you also pass `--log-level=error` as a CLI flag, that wins over everything.

<br />

Here is a practical example showing this hierarchy in TypeScript:

<br />

```typescript
import { readFileSync, existsSync } from "fs";

interface AppConfig {
  port: number;
  logLevel: string;
  dbUrl: string;
}

function loadConfig(): AppConfig {
  // Level 1: Application defaults
  let config: AppConfig = {
    port: 3000,
    logLevel: "info",
    dbUrl: "postgresql://localhost:5432/myapp",
  };

  // Level 2: Config file (if it exists)
  const configPath = "./config.json";
  if (existsSync(configPath)) {
    const fileConfig = JSON.parse(readFileSync(configPath, "utf-8"));
    config = { ...config, ...fileConfig };
  }

  // Level 3: Environment variables (override file config)
  if (process.env.PORT) config.port = parseInt(process.env.PORT, 10);
  if (process.env.LOG_LEVEL) config.logLevel = process.env.LOG_LEVEL;
  if (process.env.DATABASE_URL) config.dbUrl = process.env.DATABASE_URL;

  return config;
}

const config = loadConfig();
console.log("Config loaded:", config);
```

<br />

This pattern gives you flexibility. Developers can use a config file locally, the CI environment can
set environment variables, and production can pull secrets from AWS Secrets Manager (which we will
cover next).

<br />

##### **AWS Secrets Manager: storing and retrieving secrets**
AWS Secrets Manager is a managed service for storing, retrieving, and rotating secrets. Unlike
environment variables, which are visible in ECS task definitions, CloudFormation templates, and
potentially in logs, Secrets Manager stores values encrypted at rest and provides fine-grained
access control through IAM policies.

<br />

When should you use Secrets Manager instead of plain environment variables?

<br />

> * **Database credentials**: Secrets Manager can automatically rotate database passwords on a schedule, updating both the secret value and the database itself.
> * **API keys for third-party services**: Stripe, Twilio, SendGrid, anything where a leaked key means real money.
> * **TLS certificates and private keys**: Anything cryptographic that should never appear in plain text.
> * **Shared secrets across services**: When multiple services need the same credentials, Secrets Manager is a single source of truth.

<br />

Creating a secret with the AWS CLI:

<br />

```bash
# Create a simple string secret
aws secretsmanager create-secret \
  --name "prod/task-api/database-url" \
  --description "Production database connection string" \
  --secret-string "postgresql://admin:s3cur3P@ss@prod-db.example.com:5432/myapp"

# Create a JSON secret (multiple key-value pairs in one secret)
aws secretsmanager create-secret \
  --name "prod/task-api/credentials" \
  --description "Production API credentials" \
  --secret-string '{
    "DB_URL": "postgresql://admin:s3cur3P@ss@prod-db.example.com:5432/myapp",
    "API_KEY": "sk_live_abc123",
    "JWT_SECRET": "a-very-long-random-string"
  }'
```

<br />

Notice the naming convention: `environment/service/secret-name`. This hierarchical naming makes it
easy to organize secrets and write IAM policies that restrict access by environment or service.

<br />

Retrieving a secret:

<br />

```bash
# Get the secret value
aws secretsmanager get-secret-value \
  --secret-id "prod/task-api/database-url" \
  --query SecretString \
  --output text
```

<br />

##### **Secrets Manager: rotation basics**
One of the most powerful features of Secrets Manager is automatic rotation. Instead of using the same
database password forever (and hoping nobody leaks it), you can configure Secrets Manager to rotate
the password on a schedule, for example every 30 days.

<br />

For Amazon RDS databases, AWS provides built-in rotation Lambda functions. The rotation process works
like this:

<br />

```plaintext
1. Secrets Manager invokes a Lambda function on a schedule
2. The Lambda generates a new password
3. It updates the password in the RDS database
4. It stores the new password in Secrets Manager
5. Your application fetches the new value next time it reads the secret
```

<br />

Setting up rotation with the CLI:

<br />

```bash
# Enable rotation for an RDS secret
aws secretsmanager rotate-secret \
  --secret-id "prod/task-api/database-url" \
  --rotation-lambda-arn "arn:aws:lambda:us-east-1:123456789012:function:SecretsManagerRDSRotation" \
  --rotation-rules '{"AutomaticallyAfterDays": 30}'
```

<br />

The important thing to understand about rotation is that your application needs to handle it
gracefully. If your app caches the database connection string at startup and never re-reads it, a
rotated password will break your connection. The solution is to either re-fetch the secret
periodically or use a connection library that can handle credential refresh.

<br />

##### **Secrets Manager: IAM access policies**
You control who and what can access your secrets through IAM policies. Here is a policy that allows
an ECS task role to read only the secrets for a specific environment and service:

<br />

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/task-api/*"
    }
  ]
}
```

<br />

This policy follows the principle of least privilege. The ECS task can only read secrets under the
`prod/task-api/` prefix. It cannot list all secrets in the account, it cannot read secrets from other
services, and it cannot modify or delete any secrets. If someone compromises your task-api service, they
still cannot access the secrets belonging to your user-service or payment-service.

<br />

You attach this policy to the ECS task execution role that we set up in the previous article:

<br />

```bash
# Create the policy
aws iam create-policy \
  --policy-name task-api-secrets-read \
  --policy-document file://secrets-policy.json

# Attach it to the ECS task role
aws iam attach-role-policy \
  --role-name task-api-task-role \
  --policy-arn "arn:aws:iam::123456789012:policy/task-api-secrets-read"
```

<br />

##### **AWS Systems Manager Parameter Store**
Parameter Store is another AWS service for storing configuration, and it serves a different purpose
than Secrets Manager. Think of it this way:

<br />

> * **Secrets Manager**: For sensitive values that need encryption, rotation, and fine-grained access control. It costs $0.40 per secret per month.
> * **Parameter Store**: For non-sensitive or less-sensitive configuration values. The standard tier is free for up to 10,000 parameters.

<br />

Parameter Store supports three types of parameters:

<br />

> * **String**: A plain text value. Good for configuration like log levels, feature flags, or endpoint URLs.
> * **StringList**: A comma-separated list of values.
> * **SecureString**: An encrypted value using AWS KMS. This provides similar encryption to Secrets Manager but without the rotation features.

<br />

Creating parameters with the CLI:

<br />

```bash
# Plain string parameter
aws ssm put-parameter \
  --name "/prod/task-api/log-level" \
  --type "String" \
  --value "info"

# Encrypted parameter
aws ssm put-parameter \
  --name "/prod/task-api/api-key" \
  --type "SecureString" \
  --value "sk_live_abc123"

# Get a parameter
aws ssm get-parameter \
  --name "/prod/task-api/log-level" \
  --query "Parameter.Value" \
  --output text

# Get an encrypted parameter (decrypt it)
aws ssm get-parameter \
  --name "/prod/task-api/api-key" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text

# Get all parameters under a path
aws ssm get-parameters-by-path \
  --path "/prod/task-api/" \
  --with-decryption
```

<br />

The hierarchical path naming (`/environment/service/parameter`) is the same convention we used with
Secrets Manager, and it makes IAM policies straightforward:

<br />

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:us-east-1:123456789012:parameter/prod/task-api/*"
    }
  ]
}
```

<br />

A common pattern is to use Parameter Store for non-sensitive config (log level, feature flags,
service URLs) and Secrets Manager for truly sensitive values (database passwords, API keys). This
keeps costs down and gives you the best of both services.

<br />

##### **Practical example: loading config from env vars and Secrets Manager**
Let's bring everything together. Here is a realistic example of loading configuration in a TypeScript
application that reads from environment variables first, then falls back to AWS Secrets Manager for
sensitive values.

<br />

First, install the AWS SDK:

<br />

```bash
npm install @aws-sdk/client-secrets-manager @aws-sdk/client-ssm
```

<br />

Now the configuration loader:

<br />

```typescript
// src/config.ts
import {
  SecretsManagerClient,
  GetSecretValueCommand,
} from "@aws-sdk/client-secrets-manager";
import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";

const smClient = new SecretsManagerClient({ region: "us-east-1" });
const ssmClient = new SSMClient({ region: "us-east-1" });

interface AppConfig {
  port: number;
  logLevel: string;
  dbUrl: string;
  apiKey: string;
  jwtSecret: string;
}

async function getSecret(secretId: string): Promise<string> {
  const command = new GetSecretValueCommand({ SecretId: secretId });
  const response = await smClient.send(command);
  if (!response.SecretString) {
    throw new Error(`Secret ${secretId} has no string value`);
  }
  return response.SecretString;
}

async function getParameter(name: string): Promise<string> {
  const command = new GetParameterCommand({
    Name: name,
    WithDecryption: true,
  });
  const response = await ssmClient.send(command);
  if (!response.Parameter?.Value) {
    throw new Error(`Parameter ${name} not found`);
  }
  return response.Parameter.Value;
}

export async function loadConfig(): Promise<AppConfig> {
  const env = process.env.APP_ENV || "dev";

  // Non-sensitive config: prefer env vars, fall back to Parameter Store
  const port = process.env.PORT
    ? parseInt(process.env.PORT, 10)
    : 3000;

  const logLevel = process.env.LOG_LEVEL
    || await getParameter(`/${env}/task-api/log-level`).catch(() => "info");

  // Sensitive config: prefer env vars (for local dev), fall back to Secrets Manager
  let dbUrl = process.env.DATABASE_URL;
  let apiKey = process.env.API_KEY;
  let jwtSecret = process.env.JWT_SECRET;

  if (!dbUrl || !apiKey || !jwtSecret) {
    console.log(`Fetching secrets from AWS Secrets Manager for env: ${env}`);
    const secretString = await getSecret(`${env}/task-api/credentials`);
    const secrets = JSON.parse(secretString);

    dbUrl = dbUrl || secrets.DB_URL;
    apiKey = apiKey || secrets.API_KEY;
    jwtSecret = jwtSecret || secrets.JWT_SECRET;
  }

  if (!dbUrl || !apiKey || !jwtSecret) {
    throw new Error("Missing required configuration. Check env vars or Secrets Manager.");
  }

  return { port, logLevel, dbUrl, apiKey, jwtSecret };
}
```

<br />

And here is how you use it in your application entry point:

<br />

```typescript
// src/index.ts
import "dotenv/config";
import { loadConfig } from "./config";
import { createApp } from "./app";

async function main() {
  const config = await loadConfig();
  console.log(`Starting server on port ${config.port} (log level: ${config.logLevel})`);

  const app = createApp(config);
  app.listen(config.port, () => {
    console.log(`Server running at http://localhost:${config.port}`);
  });
}

main().catch((err) => {
  console.error("Failed to start:", err);
  process.exit(1);
});
```

<br />

This setup works for both local development and production:

<br />

> * **Local development**: Developers set values in their `.env` file. The app reads from `process.env` and never hits AWS.
> * **Production**: The `.env` file does not exist. The app detects the missing env vars and fetches from Secrets Manager. The ECS task role provides the necessary IAM permissions.

<br />

##### **Environment promotion: dev, staging, and production**
When you have multiple environments, you need a clear strategy for what changes between them and
what stays the same. The general principle is: your code and Docker image should be identical across
all environments. Only the configuration should differ.

<br />

Things that should differ between environments:

<br />

> * **Database connection strings**: Each environment has its own database.
> * **API keys and secrets**: Separate keys for each environment, so a compromised dev key does not affect production.
> * **Log levels**: Usually `debug` in dev, `info` in staging, `warn` or `error` in production.
> * **Feature flags**: Test new features in staging before enabling them in production.
> * **Scaling parameters**: Dev runs one instance, production runs three or more.
> * **External service endpoints**: Dev might point to sandbox APIs, production to live ones.

<br />

Things that should NOT differ between environments:

<br />

> * **Application code**: The same Docker image runs everywhere. No environment-specific code paths.
> * **Business logic**: If your app behaves differently in staging and production, you are going to have a bad time.
> * **Configuration structure**: The same keys exist in all environments, just with different values.

<br />

Here is a practical structure using Parameter Store and Secrets Manager:

<br />

```plaintext
Parameter Store:
  /dev/task-api/log-level       = "debug"
  /staging/task-api/log-level   = "info"
  /prod/task-api/log-level      = "warn"

  /dev/task-api/feature-new-ui  = "true"
  /staging/task-api/feature-new-ui = "true"
  /prod/task-api/feature-new-ui = "false"

Secrets Manager:
  dev/task-api/credentials      = { DB_URL: "...", API_KEY: "...", JWT_SECRET: "..." }
  staging/task-api/credentials  = { DB_URL: "...", API_KEY: "...", JWT_SECRET: "..." }
  prod/task-api/credentials     = { DB_URL: "...", API_KEY: "...", JWT_SECRET: "..." }
```

<br />

Your ECS task definition sets a single environment variable, `APP_ENV`, to tell the application which
environment it is running in. The config loader (like the one we built above) uses that value to
fetch the right secrets:

<br />

```json
{
  "containerDefinitions": [
    {
      "name": "task-api",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:v1.2.3",
      "environment": [
        { "name": "APP_ENV", "value": "prod" },
        { "name": "PORT", "value": "3000" }
      ]
    }
  ]
}
```

<br />

Notice that the only values in the task definition are non-sensitive. The database URL and API keys
are fetched from Secrets Manager at runtime, so they never appear in your Terraform code, CloudFormation
templates, or ECS console.

<br />

##### **ECS integration with Secrets Manager**
ECS also has native integration with Secrets Manager, where it can inject secret values directly
as environment variables when starting a container. This means your application does not need to
call the Secrets Manager API at all:

<br />

```json
{
  "containerDefinitions": [
    {
      "name": "task-api",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:v1.2.3",
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/task-api/credentials:DB_URL::"
        },
        {
          "name": "API_KEY",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/task-api/credentials:API_KEY::"
        }
      ],
      "environment": [
        { "name": "APP_ENV", "value": "prod" },
        { "name": "PORT", "value": "3000" }
      ]
    }
  ]
}
```

<br />

The `valueFrom` field uses the format `secret-arn:json-key:version-stage:version-id`. The double
colon at the end means "use the latest version". This approach is simpler because your application
just reads `process.env.DATABASE_URL` like normal, and ECS handles the Secrets Manager integration.

<br />

The trade-off is that the secret values are only fetched when the container starts. If a secret
rotates, you need to restart the container to pick up the new value. The SDK-based approach from
the previous section lets you re-fetch secrets without restarting.

<br />

##### **Advanced tools: Vault, SOPS, and Sealed Secrets**
Everything we have covered so far handles the most common scenarios well. But as your infrastructure
grows, you might need more specialized tools. I covered these in depth in the
[SRE: Secrets Management in Kubernetes](/blog/sre-secrets-management-in-kubernetes) article, so here
is a quick overview with links:

<br />

> * **[HashiCorp Vault](https://www.vaultproject.io/)**: A full-featured secrets management platform. It supports dynamic secrets (generate a fresh database credential for each request), encryption as a service, and audit logging. Ideal for large organizations with complex compliance requirements.
> * **[SOPS](https://github.com/getsops/sops)**: Mozilla's tool for encrypting secrets in files. You can store encrypted YAML, JSON, or .env files directly in Git. SOPS encrypts only the values, not the keys, so diffs are still readable. Great for GitOps workflows.
> * **[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)**: A Kubernetes-specific solution. You encrypt secrets locally with a public key, commit the encrypted version to Git, and the Sealed Secrets controller in your cluster decrypts them. Perfect for GitOps with Kubernetes.

<br />

For the scope of this series, AWS Secrets Manager and Parameter Store will cover everything you need.
If you are working with Kubernetes and want the deep dive into these tools, check out the SRE
article linked above.

<br />

##### **Quick reference: choosing the right approach**
Here is a simple decision guide:

<br />

```plaintext
Is it sensitive (password, API key, token)?
  YES --> Use AWS Secrets Manager
    - Needs rotation? --> Enable Secrets Manager rotation
    - Multiple services need it? --> Use resource-based policy
  NO --> Is it environment-specific config?
    YES --> Use Parameter Store (free tier)
    NO --> Hard-code it as an application default
```

<br />

And here is a comparison table:

<br />

```plaintext
Feature                  | Env Vars      | Parameter Store | Secrets Manager
-------------------------|---------------|-----------------|----------------
Cost                     | Free          | Free (std tier) | $0.40/secret/mo
Encryption               | No            | Optional (KMS)  | Always (KMS)
Rotation                 | Manual        | Manual          | Automatic
Audit logging            | No            | CloudTrail      | CloudTrail
Version history          | No            | Yes             | Yes
Cross-account access     | No            | Yes             | Yes
Best for                 | Local dev     | Non-sensitive    | Sensitive data
```

<br />

##### **Closing notes**
You now have a solid understanding of how to manage configuration and secrets in a real application.
The key takeaways are: follow the 12-factor methodology and keep config out of your code, use `.env`
files for local development but never commit them, scan your repositories for leaked secrets with
tools like gitleaks, use AWS Secrets Manager for sensitive values and Parameter Store for everything
else, and structure your configuration so that the same Docker image works in every environment.

<br />

These are the fundamentals that will serve you well regardless of which cloud provider or
orchestration platform you end up using. In the next article, we will tackle DNS, TLS, and making
your application reachable from the internet with a proper domain name and HTTPS. See you there.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: Secretos, Configuracion y Manejo de Entornos",
  author: "Gabriel Garrido",
  description: "Vamos a explorar la metodologia 12-factor app para configuracion, variables de entorno, AWS Secrets Manager, Parameter Store, y como manejar la configuracion entre entornos...",
  tags: ~w(devops aws secrets configuration beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo nueve de la serie DevOps desde Cero. En el articulo anterior deployeamos
nuestra API TypeScript a ECS con Fargate, y todo esta corriendo en la nube. Pero nos salteamos algo
importante: como obtiene tu aplicacion su URL de base de datos, API keys, y otros valores de
configuracion? Si los dejaste hard-codeados en tu codigo fuente, tenes un problema.

<br />

El manejo de configuracion y secretos es uno de esos temas que parece simple hasta que lo haces mal.
Una API key filtrada te puede costar miles de dolares. Una URL de base de datos mal configurada puede
apuntar tu app de produccion a la base de datos de staging. Un archivo `.env` commiteado puede exponer
credenciales a cualquiera que clone tu repositorio. Estos no son escenarios hipoteticos, pasan todo
el tiempo.

<br />

En este articulo vamos a cubrir las practicas fundamentales para manejar configuracion y secretos: la
metodologia 12-factor, variables de entorno, archivos `.env`, escaneo de secretos, AWS Secrets Manager,
AWS Systems Manager Parameter Store, y como estructurar la configuracion entre entornos de dev, staging
y produccion. Al final vas a tener un enfoque claro y practico para mantener tu config limpia y tus
secretos seguros.

<br />

Vamos a meternos de lleno.

<br />

##### **La 12-factor app: la config pertenece al entorno**
La [Twelve-Factor App](https://12factor.net/) es una metodologia para construir aplicaciones modernas
que fue publicada por el equipo de Heroku alla por 2012. Describe doce principios para construir
software que sea facil de deployear, escalar y mantener. El factor numero tres es sobre configuracion,
y dice algo muy claro: guarda la config en el entorno.

<br />

Que significa "config" aca? Es cualquier cosa que probablemente cambie entre entornos (dev, staging,
produccion). URLs de base de datos, API keys, feature flags, endpoints de servicios externos, niveles
de log. Estos valores no deberian vivir en tu codigo fuente. No deberian estar horneados en tu imagen
Docker. Deberian venir del entorno donde tu aplicacion esta corriendo.

<br />

El razonamiento es simple:

<br />

> * **Seguridad**: Los secretos en el codigo fuente terminan en control de versiones, en logs de CI, en capas de Docker, y en las manos de cualquiera que tenga acceso a tu repositorio.
> * **Portabilidad**: Si tu URL de base de datos esta hard-codeada, no podes correr el mismo codigo contra una base de datos de staging sin cambiar el codigo. Si viene del entorno, simplemente cambias la variable de entorno.
> * **Simplicidad**: Un solo artefacto de build (tu imagen Docker) funciona en cada entorno. Lo unico que cambia es la configuracion inyectada en runtime.

<br />

Aca esta el anti-patron versus el enfoque correcto:

<br />

```typescript
// MAL: config hard-codeada
const dbUrl = "postgresql://admin:supersecret@prod-db.example.com:5432/myapp";

// BIEN: leer del entorno
const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  throw new Error("La variable de entorno DATABASE_URL es requerida");
}
```

<br />

El segundo ejemplo sigue el principio 12-factor. La aplicacion no sabe ni le importa en que entorno
esta corriendo. Simplemente lee el valor del entorno y lo usa.

<br />

##### **Variables de entorno: como funcionan**
Las variables de entorno son pares clave-valor que existen en el entorno de proceso del sistema
operativo. Cada proceso hereda el entorno de su proceso padre, y podes setear variables adicionales
cuando lanzas un proceso.

<br />

Seteando y leyendo variables de entorno en la shell:

<br />

```bash
# Setear una variable para la sesion actual de la shell
export DATABASE_URL="postgresql://localhost:5432/myapp"

# Leerla
echo $DATABASE_URL

# Setear una variable solo para un unico comando
DATABASE_URL="postgresql://localhost:5432/myapp" node app.js

# Listar todas las variables de entorno
env

# Borrar una variable
unset DATABASE_URL
```

<br />

En Node.js/TypeScript, las accedes a traves de `process.env`:

<br />

```typescript
// Leer una variable de entorno
const port = process.env.PORT || "3000";
const dbUrl = process.env.DATABASE_URL;
const logLevel = process.env.LOG_LEVEL || "info";

// Verificar variables requeridas al inicio
const required = ["DATABASE_URL", "API_KEY", "JWT_SECRET"];
for (const key of required) {
  if (!process.env[key]) {
    console.error(`Falta la variable de entorno requerida: ${key}`);
    process.exit(1);
  }
}
```

<br />

Este patron de verificar variables requeridas al inicio es importante. Queres que tu aplicacion falle
rapido y ruidosamente si le falta configuracion, no que se rompa silenciosamente en algun punto
aleatorio despues.

<br />

##### **Archivos dotenv: conveniencia para desarrollo local**
Tipear `export DATABASE_URL=...` cada vez que abris una terminal se vuelve tedioso rapido. Para eso
estan los archivos `.env`. Un archivo `.env` es un archivo de texto simple que lista variables de
entorno, una por linea:

<br />

```bash
# .env
DATABASE_URL=postgresql://localhost:5432/myapp_dev
API_KEY=dev-api-key-not-real
JWT_SECRET=local-dev-secret
LOG_LEVEL=debug
PORT=3000
```

<br />

Librerias como [dotenv](https://www.npmjs.com/package/dotenv) para Node.js leen automaticamente este
archivo y cargan las variables en `process.env` cuando tu aplicacion inicia:

<br />

```typescript
// Cargar el archivo .env al principio de tu entry point
import "dotenv/config";

// Ahora process.env.DATABASE_URL esta disponible
console.log(process.env.DATABASE_URL);
```

<br />

La regla critica con los archivos `.env` es: **nunca los commitees a Git**. Contienen secretos, y tu
repositorio Git no es un lugar seguro para guardar secretos. Agrega `.env` a tu `.gitignore`
inmediatamente:

<br />

```bash
# .gitignore

# Archivos de entorno con secretos
.env
.env.local
.env.*.local

# Mantener el archivo de ejemplo (sin secretos reales)
!.env.example
```

<br />

En lugar de commitear tu archivo `.env` real, commitea un archivo `.env.example` con valores de
placeholder. Esto le dice a tus companeros de equipo que variables necesitan sin exponer secretos
reales:

<br />

```bash
# .env.example
DATABASE_URL=postgresql://localhost:5432/myapp_dev
API_KEY=tu-api-key-aca
JWT_SECRET=genera-un-string-aleatorio
LOG_LEVEL=debug
PORT=3000
```

<br />

Cuando un nuevo desarrollador se suma al equipo, copia `.env.example` a `.env` y completa con sus
propios valores. Simple, seguro, efectivo.

<br />

##### **Por que nunca deberias commitear secretos a Git**
Esto merece su propia seccion porque es asi de importante. Cuando commiteas un secreto a Git, no
existe solo en la version actual del archivo. Existe en el historial de Git para siempre. Incluso si
borras el archivo o sobreescribis el valor en un commit posterior, cualquiera que clone el repositorio
puede encontrarlo mirando el historial de commits.

<br />

```bash
# Ups, commitee mi archivo .env
git log --all --full-history -- .env

# Cualquiera puede ver el contenido de ese archivo en ese commit
git show abc123:.env
```

<br />

Si esto pasa, el secreto esta comprometido. Necesitas rotarlo inmediatamente, o sea generar una clave
nueva y revocar la vieja. Reescribir el historial de Git con `git filter-branch` o BFG Repo-Cleaner
es posible pero doloroso, especialmente en un repositorio compartido.

<br />

El mejor enfoque es la prevencion. Usa herramientas que escaneen tu repositorio buscando secretos
antes de que se commiteen:

<br />

> * **[git-secrets](https://github.com/awslabs/git-secrets)**: Una herramienta de AWS que instala hooks de Git para prevenir commitear secretos. Escanea buscando access keys de AWS, secret keys, y patrones personalizados que vos definas.
> * **[gitleaks](https://github.com/gitleaks/gitleaks)**: Un scanner mas rapido y completo que detecta un amplio rango de patrones de secretos (API keys, tokens, passwords) en todo el historial de tu repositorio.
> * **[pre-commit](https://pre-commit.com/)**: Un framework para gestionar hooks de pre-commit de Git. Podes agregar gitleaks o git-secrets como un hook que corre automaticamente en cada commit.

<br />

Asi se configura gitleaks como un hook de pre-commit:

<br />

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

<br />

```bash
# Instalar pre-commit y configurar los hooks
pip install pre-commit
pre-commit install

# Ahora cada commit va a ser escaneado buscando secretos automaticamente
git commit -m "agregar nueva funcionalidad"
# gitleaks corre y bloquea el commit si encuentra un secreto
```

<br />

Tambien deberias correr gitleaks en tu pipeline de CI como red de seguridad. Cubrimos pipelines de
CI en el articulo cinco, asi que agregar un paso de gitleaks es directo:

<br />

```yaml
# En tu workflow de GitHub Actions
- name: Escanear secretos
  uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

<br />

##### **Jerarquia de configuracion: como se resuelven los valores**
En una aplicacion real, la configuracion puede venir de multiples fuentes. Cuando la misma clave esta
definida en mas de un lugar, necesitas un orden de precedencia claro. La jerarquia estandar, de menor
a mayor prioridad, se ve asi:

<br />

```plaintext
1. Defaults de la aplicacion (fallbacks hard-codeados en tu codigo)
2. Archivos de config (archivos JSON, YAML, TOML cargados al inicio)
3. Variables de entorno (seteadas por el SO, container runtime, o archivo .env)
4. Flags de CLI (pasados al iniciar la aplicacion)
5. Config remota (obtenida de Secrets Manager, Parameter Store, etc.)
```

<br />

Cada nivel sobreescribe al de abajo. Asi que si tu codigo tiene un default `LOG_LEVEL=info`, tu
archivo de config lo setea a `warn`, y tu variable de entorno lo setea a `debug`, la variable de
entorno gana. Si ademas pasas `--log-level=error` como flag de CLI, eso gana sobre todo lo demas.

<br />

Aca hay un ejemplo practico mostrando esta jerarquia en TypeScript:

<br />

```typescript
import { readFileSync, existsSync } from "fs";

interface AppConfig {
  port: number;
  logLevel: string;
  dbUrl: string;
}

function loadConfig(): AppConfig {
  // Nivel 1: Defaults de la aplicacion
  let config: AppConfig = {
    port: 3000,
    logLevel: "info",
    dbUrl: "postgresql://localhost:5432/myapp",
  };

  // Nivel 2: Archivo de config (si existe)
  const configPath = "./config.json";
  if (existsSync(configPath)) {
    const fileConfig = JSON.parse(readFileSync(configPath, "utf-8"));
    config = { ...config, ...fileConfig };
  }

  // Nivel 3: Variables de entorno (sobreescriben la config del archivo)
  if (process.env.PORT) config.port = parseInt(process.env.PORT, 10);
  if (process.env.LOG_LEVEL) config.logLevel = process.env.LOG_LEVEL;
  if (process.env.DATABASE_URL) config.dbUrl = process.env.DATABASE_URL;

  return config;
}

const config = loadConfig();
console.log("Config cargada:", config);
```

<br />

Este patron te da flexibilidad. Los desarrolladores pueden usar un archivo de config localmente, el
entorno de CI puede setear variables de entorno, y produccion puede obtener secretos de AWS Secrets
Manager (que vamos a cubrir a continuacion).

<br />

##### **AWS Secrets Manager: almacenando y obteniendo secretos**
AWS Secrets Manager es un servicio gestionado para almacenar, obtener y rotar secretos. A diferencia
de las variables de entorno, que son visibles en las definiciones de task de ECS, templates de
CloudFormation, y potencialmente en logs, Secrets Manager almacena valores encriptados en reposo y
provee control de acceso granular a traves de politicas de IAM.

<br />

Cuando deberias usar Secrets Manager en lugar de variables de entorno planas?

<br />

> * **Credenciales de base de datos**: Secrets Manager puede rotar automaticamente passwords de base de datos en un cronograma, actualizando tanto el valor del secreto como la base de datos misma.
> * **API keys de servicios terceros**: Stripe, Twilio, SendGrid, cualquier cosa donde una key filtrada significa plata real.
> * **Certificados TLS y claves privadas**: Cualquier cosa criptografica que nunca deberia aparecer en texto plano.
> * **Secretos compartidos entre servicios**: Cuando multiples servicios necesitan las mismas credenciales, Secrets Manager es una unica fuente de verdad.

<br />

Creando un secreto con la CLI de AWS:

<br />

```bash
# Crear un secreto de string simple
aws secretsmanager create-secret \
  --name "prod/task-api/database-url" \
  --description "String de conexion a base de datos de produccion" \
  --secret-string "postgresql://admin:s3cur3P@ss@prod-db.example.com:5432/myapp"

# Crear un secreto JSON (multiples pares clave-valor en un secreto)
aws secretsmanager create-secret \
  --name "prod/task-api/credentials" \
  --description "Credenciales de API de produccion" \
  --secret-string '{
    "DB_URL": "postgresql://admin:s3cur3P@ss@prod-db.example.com:5432/myapp",
    "API_KEY": "sk_live_abc123",
    "JWT_SECRET": "un-string-aleatorio-muy-largo"
  }'
```

<br />

Nota la convencion de nombres: `entorno/servicio/nombre-del-secreto`. Este naming jerarquico hace
que sea facil organizar secretos y escribir politicas de IAM que restrinjan acceso por entorno o
servicio.

<br />

Obteniendo un secreto:

<br />

```bash
# Obtener el valor del secreto
aws secretsmanager get-secret-value \
  --secret-id "prod/task-api/database-url" \
  --query SecretString \
  --output text
```

<br />

##### **Secrets Manager: basicos de rotacion**
Una de las funcionalidades mas poderosas de Secrets Manager es la rotacion automatica. En lugar de
usar el mismo password de base de datos para siempre (y rezar que nadie lo filtre), podes configurar
Secrets Manager para rotar el password en un cronograma, por ejemplo cada 30 dias.

<br />

Para bases de datos Amazon RDS, AWS provee funciones Lambda de rotacion incorporadas. El proceso de
rotacion funciona asi:

<br />

```plaintext
1. Secrets Manager invoca una funcion Lambda en un cronograma
2. La Lambda genera un nuevo password
3. Actualiza el password en la base de datos RDS
4. Almacena el nuevo password en Secrets Manager
5. Tu aplicacion obtiene el nuevo valor la proxima vez que lee el secreto
```

<br />

Configurando la rotacion con la CLI:

<br />

```bash
# Habilitar rotacion para un secreto de RDS
aws secretsmanager rotate-secret \
  --secret-id "prod/task-api/database-url" \
  --rotation-lambda-arn "arn:aws:lambda:us-east-1:123456789012:function:SecretsManagerRDSRotation" \
  --rotation-rules '{"AutomaticallyAfterDays": 30}'
```

<br />

Lo importante que tenes que entender sobre la rotacion es que tu aplicacion necesita manejarla de
forma elegante. Si tu app cachea el string de conexion a la base de datos al inicio y nunca lo
relee, un password rotado va a romper tu conexion. La solucion es o re-obtener el secreto
periodicamente o usar una libreria de conexion que pueda manejar el refresco de credenciales.

<br />

##### **Secrets Manager: politicas de acceso IAM**
Controlas quien y que puede acceder a tus secretos a traves de politicas IAM. Aca hay una politica
que permite a un rol de task de ECS leer solo los secretos de un entorno y servicio especificos:

<br />

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/task-api/*"
    }
  ]
}
```

<br />

Esta politica sigue el principio de menor privilegio. El task de ECS solo puede leer secretos bajo el
prefijo `prod/task-api/`. No puede listar todos los secretos de la cuenta, no puede leer secretos de
otros servicios, y no puede modificar ni borrar ningun secreto. Si alguien compromete tu servicio
task-api, igual no puede acceder a los secretos pertenecientes a tu user-service o payment-service.

<br />

Adjuntas esta politica al rol de ejecucion del task de ECS que configuramos en el articulo anterior:

<br />

```bash
# Crear la politica
aws iam create-policy \
  --policy-name task-api-secrets-read \
  --policy-document file://secrets-policy.json

# Adjuntarla al rol del task de ECS
aws iam attach-role-policy \
  --role-name task-api-task-role \
  --policy-arn "arn:aws:iam::123456789012:policy/task-api-secrets-read"
```

<br />

##### **AWS Systems Manager Parameter Store**
Parameter Store es otro servicio de AWS para almacenar configuracion, y sirve un proposito diferente
al de Secrets Manager. Pensalo de esta manera:

<br />

> * **Secrets Manager**: Para valores sensibles que necesitan encriptacion, rotacion, y control de acceso granular. Cuesta $0.40 por secreto por mes.
> * **Parameter Store**: Para valores de configuracion no sensibles o menos sensibles. El tier estandar es gratis para hasta 10,000 parametros.

<br />

Parameter Store soporta tres tipos de parametros:

<br />

> * **String**: Un valor de texto plano. Bueno para configuracion como niveles de log, feature flags, o URLs de endpoints.
> * **StringList**: Una lista de valores separados por coma.
> * **SecureString**: Un valor encriptado usando AWS KMS. Esto provee encriptacion similar a Secrets Manager pero sin las funcionalidades de rotacion.

<br />

Creando parametros con la CLI:

<br />

```bash
# Parametro de string plano
aws ssm put-parameter \
  --name "/prod/task-api/log-level" \
  --type "String" \
  --value "info"

# Parametro encriptado
aws ssm put-parameter \
  --name "/prod/task-api/api-key" \
  --type "SecureString" \
  --value "sk_live_abc123"

# Obtener un parametro
aws ssm get-parameter \
  --name "/prod/task-api/log-level" \
  --query "Parameter.Value" \
  --output text

# Obtener un parametro encriptado (desencriptarlo)
aws ssm get-parameter \
  --name "/prod/task-api/api-key" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text

# Obtener todos los parametros bajo un path
aws ssm get-parameters-by-path \
  --path "/prod/task-api/" \
  --with-decryption
```

<br />

El naming jerarquico por path (`/entorno/servicio/parametro`) es la misma convencion que usamos con
Secrets Manager, y hace que las politicas de IAM sean directas:

<br />

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:us-east-1:123456789012:parameter/prod/task-api/*"
    }
  ]
}
```

<br />

Un patron comun es usar Parameter Store para config no sensible (nivel de log, feature flags, URLs
de servicios) y Secrets Manager para valores verdaderamente sensibles (passwords de base de datos,
API keys). Esto mantiene los costos bajos y te da lo mejor de ambos servicios.

<br />

##### **Ejemplo practico: cargando config de env vars y Secrets Manager**
Juntemos todo. Aca hay un ejemplo realista de carga de configuracion en una aplicacion TypeScript que
lee de variables de entorno primero, y despues recurre a AWS Secrets Manager para valores sensibles.

<br />

Primero, instala el SDK de AWS:

<br />

```bash
npm install @aws-sdk/client-secrets-manager @aws-sdk/client-ssm
```

<br />

Ahora el cargador de configuracion:

<br />

```typescript
// src/config.ts
import {
  SecretsManagerClient,
  GetSecretValueCommand,
} from "@aws-sdk/client-secrets-manager";
import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";

const smClient = new SecretsManagerClient({ region: "us-east-1" });
const ssmClient = new SSMClient({ region: "us-east-1" });

interface AppConfig {
  port: number;
  logLevel: string;
  dbUrl: string;
  apiKey: string;
  jwtSecret: string;
}

async function getSecret(secretId: string): Promise<string> {
  const command = new GetSecretValueCommand({ SecretId: secretId });
  const response = await smClient.send(command);
  if (!response.SecretString) {
    throw new Error(`El secreto ${secretId} no tiene valor string`);
  }
  return response.SecretString;
}

async function getParameter(name: string): Promise<string> {
  const command = new GetParameterCommand({
    Name: name,
    WithDecryption: true,
  });
  const response = await ssmClient.send(command);
  if (!response.Parameter?.Value) {
    throw new Error(`Parametro ${name} no encontrado`);
  }
  return response.Parameter.Value;
}

export async function loadConfig(): Promise<AppConfig> {
  const env = process.env.APP_ENV || "dev";

  // Config no sensible: preferir env vars, recurrir a Parameter Store
  const port = process.env.PORT
    ? parseInt(process.env.PORT, 10)
    : 3000;

  const logLevel = process.env.LOG_LEVEL
    || await getParameter(`/${env}/task-api/log-level`).catch(() => "info");

  // Config sensible: preferir env vars (para dev local), recurrir a Secrets Manager
  let dbUrl = process.env.DATABASE_URL;
  let apiKey = process.env.API_KEY;
  let jwtSecret = process.env.JWT_SECRET;

  if (!dbUrl || !apiKey || !jwtSecret) {
    console.log(`Obteniendo secretos de AWS Secrets Manager para env: ${env}`);
    const secretString = await getSecret(`${env}/task-api/credentials`);
    const secrets = JSON.parse(secretString);

    dbUrl = dbUrl || secrets.DB_URL;
    apiKey = apiKey || secrets.API_KEY;
    jwtSecret = jwtSecret || secrets.JWT_SECRET;
  }

  if (!dbUrl || !apiKey || !jwtSecret) {
    throw new Error("Falta configuracion requerida. Revisa env vars o Secrets Manager.");
  }

  return { port, logLevel, dbUrl, apiKey, jwtSecret };
}
```

<br />

Y aca esta como lo usas en el entry point de tu aplicacion:

<br />

```typescript
// src/index.ts
import "dotenv/config";
import { loadConfig } from "./config";
import { createApp } from "./app";

async function main() {
  const config = await loadConfig();
  console.log(`Iniciando servidor en puerto ${config.port} (log level: ${config.logLevel})`);

  const app = createApp(config);
  app.listen(config.port, () => {
    console.log(`Servidor corriendo en http://localhost:${config.port}`);
  });
}

main().catch((err) => {
  console.error("Error al iniciar:", err);
  process.exit(1);
});
```

<br />

Este setup funciona tanto para desarrollo local como para produccion:

<br />

> * **Desarrollo local**: Los desarrolladores setean valores en su archivo `.env`. La app lee de `process.env` y nunca le pega a AWS.
> * **Produccion**: El archivo `.env` no existe. La app detecta las env vars faltantes y las busca en Secrets Manager. El rol del task de ECS provee los permisos IAM necesarios.

<br />

##### **Promocion de entornos: dev, staging y produccion**
Cuando tenes multiples entornos, necesitas una estrategia clara sobre que cambia entre ellos y que se
mantiene igual. El principio general es: tu codigo e imagen Docker deberian ser identicos en todos los
entornos. Solo la configuracion deberia diferir.

<br />

Cosas que deberian diferir entre entornos:

<br />

> * **Strings de conexion a base de datos**: Cada entorno tiene su propia base de datos.
> * **API keys y secretos**: Claves separadas para cada entorno, asi una clave de dev comprometida no afecta produccion.
> * **Niveles de log**: Usualmente `debug` en dev, `info` en staging, `warn` o `error` en produccion.
> * **Feature flags**: Probar funcionalidades nuevas en staging antes de habilitarlas en produccion.
> * **Parametros de escalado**: Dev corre una instancia, produccion corre tres o mas.
> * **Endpoints de servicios externos**: Dev podria apuntar a APIs sandbox, produccion a las live.

<br />

Cosas que NO deberian diferir entre entornos:

<br />

> * **Codigo de la aplicacion**: La misma imagen Docker corre en todos lados. Sin code paths especificos por entorno.
> * **Logica de negocio**: Si tu app se comporta diferente en staging y produccion, la vas a pasar mal.
> * **Estructura de configuracion**: Las mismas claves existen en todos los entornos, solo con valores diferentes.

<br />

Aca hay una estructura practica usando Parameter Store y Secrets Manager:

<br />

```plaintext
Parameter Store:
  /dev/task-api/log-level       = "debug"
  /staging/task-api/log-level   = "info"
  /prod/task-api/log-level      = "warn"

  /dev/task-api/feature-new-ui  = "true"
  /staging/task-api/feature-new-ui = "true"
  /prod/task-api/feature-new-ui = "false"

Secrets Manager:
  dev/task-api/credentials      = { DB_URL: "...", API_KEY: "...", JWT_SECRET: "..." }
  staging/task-api/credentials  = { DB_URL: "...", API_KEY: "...", JWT_SECRET: "..." }
  prod/task-api/credentials     = { DB_URL: "...", API_KEY: "...", JWT_SECRET: "..." }
```

<br />

Tu task definition de ECS setea una unica variable de entorno, `APP_ENV`, para decirle a la
aplicacion en que entorno esta corriendo. El cargador de config (como el que construimos arriba) usa
ese valor para buscar los secretos correctos:

<br />

```json
{
  "containerDefinitions": [
    {
      "name": "task-api",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:v1.2.3",
      "environment": [
        { "name": "APP_ENV", "value": "prod" },
        { "name": "PORT", "value": "3000" }
      ]
    }
  ]
}
```

<br />

Nota que los unicos valores en el task definition son no sensibles. La URL de base de datos y API
keys se obtienen de Secrets Manager en runtime, asi que nunca aparecen en tu codigo Terraform,
templates de CloudFormation, ni en la consola de ECS.

<br />

##### **Integracion de ECS con Secrets Manager**
ECS tambien tiene integracion nativa con Secrets Manager, donde puede inyectar valores de secretos
directamente como variables de entorno al iniciar un container. Esto significa que tu aplicacion no
necesita llamar a la API de Secrets Manager para nada:

<br />

```json
{
  "containerDefinitions": [
    {
      "name": "task-api",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:v1.2.3",
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/task-api/credentials:DB_URL::"
        },
        {
          "name": "API_KEY",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/task-api/credentials:API_KEY::"
        }
      ],
      "environment": [
        { "name": "APP_ENV", "value": "prod" },
        { "name": "PORT", "value": "3000" }
      ]
    }
  ]
}
```

<br />

El campo `valueFrom` usa el formato `secret-arn:json-key:version-stage:version-id`. El doble dos
puntos al final significa "usar la ultima version". Este enfoque es mas simple porque tu aplicacion
simplemente lee `process.env.DATABASE_URL` como siempre, y ECS maneja la integracion con Secrets
Manager.

<br />

El trade-off es que los valores del secreto solo se obtienen cuando el container inicia. Si un
secreto se rota, necesitas reiniciar el container para obtener el nuevo valor. El enfoque basado en
SDK de la seccion anterior te permite re-obtener secretos sin reiniciar.

<br />

##### **Herramientas avanzadas: Vault, SOPS y Sealed Secrets**
Todo lo que cubrimos hasta ahora maneja los escenarios mas comunes bien. Pero a medida que tu
infraestructura crece, podrias necesitar herramientas mas especializadas. Las cubri en profundidad
en el articulo [SRE: Secrets Management in Kubernetes](/blog/sre-secrets-management-in-kubernetes),
asi que aca va un resumen rapido con links:

<br />

> * **[HashiCorp Vault](https://www.vaultproject.io/)**: Una plataforma de gestion de secretos completa. Soporta secretos dinamicos (generar una credencial de base de datos fresca para cada request), encriptacion como servicio, y logging de auditoria. Ideal para organizaciones grandes con requerimientos de compliance complejos.
> * **[SOPS](https://github.com/getsops/sops)**: La herramienta de Mozilla para encriptar secretos en archivos. Podes guardar archivos YAML, JSON, o .env encriptados directamente en Git. SOPS encripta solo los valores, no las claves, asi que los diffs siguen siendo legibles. Genial para workflows de GitOps.
> * **[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)**: Una solucion especifica de Kubernetes. Encriptas secretos localmente con una clave publica, commiteas la version encriptada a Git, y el controller de Sealed Secrets en tu cluster los desencripta. Perfecto para GitOps con Kubernetes.

<br />

Para el alcance de esta serie, AWS Secrets Manager y Parameter Store van a cubrir todo lo que
necesitas. Si estas trabajando con Kubernetes y queres el deep dive en estas herramientas, revisa
el articulo de SRE linkeado arriba.

<br />

##### **Referencia rapida: eligiendo el enfoque correcto**
Aca hay una guia de decision simple:

<br />

```plaintext
Es sensible (password, API key, token)?
  SI --> Usar AWS Secrets Manager
    - Necesita rotacion? --> Habilitar rotacion de Secrets Manager
    - Multiples servicios lo necesitan? --> Usar resource-based policy
  NO --> Es config especifica por entorno?
    SI --> Usar Parameter Store (tier gratis)
    NO --> Hard-codearlo como default de la aplicacion
```

<br />

Y aca hay una tabla comparativa:

<br />

```plaintext
Funcionalidad            | Env Vars      | Parameter Store | Secrets Manager
-------------------------|---------------|-----------------|----------------
Costo                    | Gratis        | Gratis (std)    | $0.40/secreto/mes
Encriptacion             | No            | Opcional (KMS)  | Siempre (KMS)
Rotacion                 | Manual        | Manual          | Automatica
Logging de auditoria     | No            | CloudTrail      | CloudTrail
Historial de versiones   | No            | Si              | Si
Acceso cross-account     | No            | Si              | Si
Mejor para               | Dev local     | No sensible     | Datos sensibles
```

<br />

##### **Notas de cierre**
Ahora tenes un entendimiento solido de como manejar configuracion y secretos en una aplicacion real.
Los puntos clave son: segui la metodologia 12-factor y mantene la config fuera de tu codigo, usa
archivos `.env` para desarrollo local pero nunca los commitees, escanea tus repositorios buscando
secretos filtrados con herramientas como gitleaks, usa AWS Secrets Manager para valores sensibles y
Parameter Store para todo lo demas, y estructura tu configuracion para que la misma imagen Docker
funcione en cada entorno.

<br />

Estos son los fundamentos que te van a servir bien sin importar que proveedor de cloud o plataforma
de orquestacion termines usando. En el proximo articulo, vamos a abordar DNS, TLS, y hacer que tu
aplicacion sea alcanzable desde internet con un nombre de dominio propio y HTTPS. Nos vemos ahi.

<br />

Espero que te haya resultado util y que lo hayas disfrutado, hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se
corrija.

Tambien, podes revisar el codigo fuente y los cambios en los [fuentes aca](https://github.com/kainlite/tr)

<br />
