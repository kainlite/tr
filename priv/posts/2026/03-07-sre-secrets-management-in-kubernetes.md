%{
  title: "SRE: Secrets Management in Kubernetes",
  author: "Gabriel Garrido",
  description: "We will explore secrets management in Kubernetes, from Sealed Secrets and External Secrets Operator to HashiCorp Vault integration, secret rotation strategies, and SOPS for encrypting secrets in Git...",
  tags: ~w(sre kubernetes security secrets vault),
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
[capacity planning](/blog/sre-capacity-planning-autoscaling-and-load-testing), and
[GitOps](/blog/sre-gitops-with-argocd). We have built a solid foundation for running reliable services in
Kubernetes, but there is one topic we have not touched yet that can make or break your security posture:
secrets management.

<br />

If you have ever committed a database password to a Git repository, hard-coded an API key in a deployment
manifest, or relied on Kubernetes Secrets thinking they were "encrypted", you know the pain. Secrets are
everywhere in modern infrastructure, and managing them poorly is one of the fastest ways to end up in the
news for all the wrong reasons.

<br />

In this article we will cover why Kubernetes Secrets are not enough on their own, and then walk through the
tools and strategies that actually solve the problem: Sealed Secrets, External Secrets Operator, HashiCorp
Vault, secret rotation, SOPS, RBAC policies, and audit logging. By the end you should have a clear picture
of which approach fits your situation and how to implement it.

<br />

Let's get into it.

<br />

##### **The problem with Kubernetes secrets**
Kubernetes has a built-in Secret resource, and at first glance it looks like it solves the problem. You create
a Secret, reference it in your Pod spec, and your application gets the value as an environment variable or a
mounted file. Simple enough.

<br />

But there is a catch. Kubernetes Secrets are base64 encoded, not encrypted. Base64 is a reversible encoding,
not a security mechanism. Anyone with access to the manifest or the API server can decode your secrets
trivially:

<br />

```yaml
# Creating a "secret" in Kubernetes
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secrets
  namespace: default
type: Opaque
data:
  # This is just base64, NOT encryption
  database-password: cGFzc3dvcmQxMjM=
  api-key: c3VwZXItc2VjcmV0LWtleQ==
```

<br />

```bash
# Anyone can decode this instantly
$ echo "cGFzc3dvcmQxMjM=" | base64 -d
password123

$ echo "c3VwZXItc2VjcmV0LWtleQ==" | base64 -d
super-secret-key
```

<br />

The problems go deeper than encoding:

<br />

> * **etcd storage**: By default, secrets are stored unencrypted in etcd. Anyone with access to the etcd datastore can read every secret in the cluster
> * **RBAC gaps**: The default RBAC configuration in many clusters is too permissive. If a service account can list secrets in a namespace, it can read all of them
> * **Git exposure**: You cannot commit Secret manifests to Git without exposing the values, which breaks GitOps workflows
> * **No audit trail**: Kubernetes does not log who accessed a secret value by default, only who listed or watched the resource
> * **No rotation**: There is no built-in mechanism for rotating secrets. You change the value, restart the pods, and hope nothing breaks
> * **No encryption at rest**: Unless you explicitly configure encryption at rest for etcd, secrets sit there in plain text

<br />

You can enable encryption at rest in the API server with an EncryptionConfiguration:

<br />

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>
      - identity: {}
```

<br />

This helps with data at rest in etcd, but it does not solve the Git problem, the rotation problem, or the
audit problem. For those, we need dedicated tools.

<br />

##### **Sealed Secrets**
Bitnami Sealed Secrets is one of the simplest solutions for the "I need to store secrets in Git" problem.
The idea is elegant: you encrypt your secrets with a public key that only the cluster controller can decrypt.
The encrypted version (a SealedSecret) is safe to commit to Git because only the controller running in your
cluster has the private key to unseal it.

<br />

First, install the Sealed Secrets controller in your cluster:

<br />

```sql
# Install the controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set-string fullnameOverride=sealed-secrets-controller
```

<br />

Then install the `kubeseal` CLI on your workstation:

<br />

```bash
# Install kubeseal
brew install kubeseal

# Or download directly
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.3/kubeseal-0.27.3-linux-amd64.tar.gz
tar -xvf kubeseal-0.27.3-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

<br />

Now the workflow looks like this. You create a regular Kubernetes Secret, then seal it:

<br />

```sql
# Create the regular secret (do NOT commit this file)
kubectl create secret generic my-app-secrets \
  --namespace default \
  --from-literal=database-password=password123 \
  --from-literal=api-key=super-secret-key \
  --dry-run=client -o yaml > my-secret.yaml

# Seal it with the cluster's public key
kubeseal --format yaml < my-secret.yaml > my-sealed-secret.yaml

# Delete the unencrypted version
rm my-secret.yaml
```

<br />

The resulting SealedSecret is safe to commit:

<br />

```yaml
# my-sealed-secret.yaml - this is safe to commit to Git
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-app-secrets
  namespace: default
spec:
  encryptedData:
    database-password: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq...
    api-key: AgCtr8HZFBOGZ9Nk+HrKPHRf7A6WkXN0...
  template:
    metadata:
      name: my-app-secrets
      namespace: default
    type: Opaque
```

<br />

When the Sealed Secrets controller sees this resource in the cluster, it decrypts it and creates a regular
Kubernetes Secret that your pods can use as normal.

<br />

A few important things to know about Sealed Secrets:

<br />

> * **Scope**: By default, a SealedSecret is bound to a specific name and namespace. You cannot change the name or namespace without re-sealing
> * **Key rotation**: The controller rotates its encryption keys every 30 days by default. Old keys are kept so existing SealedSecrets can still be decrypted
> * **Backup the keys**: If you lose the controller's private key (for example, by deleting the namespace without backing up), you lose the ability to decrypt all your SealedSecrets. Back up the keys
> * **Re-encryption**: After key rotation, existing SealedSecrets still work but use the old key. You should periodically re-seal them with the new key

<br />

Here is how you back up and restore the controller keys:

<br />

```bash
# Back up the sealing keys
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-keys-backup.yaml

# Store this backup securely (not in Git!)
# Use a password manager, cloud KMS, or a safe

# Restore keys to a new cluster
kubectl apply -f sealed-secrets-keys-backup.yaml
# Restart the controller to pick up the restored keys
kubectl rollout restart deployment/sealed-secrets-controller -n kube-system
```

<br />

Sealed Secrets is a great fit when you want a simple, self-contained solution that does not depend on
external services. It works perfectly with GitOps because the encrypted manifests live in your repo.
The main downside is that it only solves the "secrets in Git" problem. It does not help with rotation,
centralized management, or dynamic secrets.

<br />

##### **External Secrets Operator**
The External Secrets Operator (ESO) takes a different approach. Instead of encrypting secrets and storing
them in Git, it syncs secrets from an external secret store (like AWS Secrets Manager, HashiCorp Vault,
Google Secret Manager, or Azure Key Vault) into Kubernetes Secrets. Your Git repository only contains the
reference to the secret, not the value itself.

<br />

Install ESO with Helm:

<br />

```sql
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

<br />

The architecture has three main components:

<br />

> * **SecretStore / ClusterSecretStore**: Configures the connection to your external secret provider
> * **ExternalSecret**: Declares which secrets to fetch and how to map them to Kubernetes Secrets
> * **The operator**: Watches for ExternalSecret resources and creates/updates Kubernetes Secrets

<br />

Here is an example using AWS Secrets Manager as the backend. First, configure the SecretStore:

<br />

```yaml
# cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

<br />

Then create an ExternalSecret that references a secret stored in AWS:

<br />

```yaml
# external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secrets
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: my-app-secrets
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        database-password: "{{ .database_password }}"
        api-key: "{{ .api_key }}"
  data:
    - secretKey: database_password
      remoteRef:
        key: production/my-app
        property: database_password
    - secretKey: api_key
      remoteRef:
        key: production/my-app
        property: api_key
```

<br />

This ExternalSecret manifest is perfectly safe to commit to Git because it only contains references, not
values. The operator fetches the actual values from AWS Secrets Manager and creates a Kubernetes Secret.

<br />

You can also use ESO with HashiCorp Vault as the backend:

<br />

```yaml
# vault-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

<br />

```yaml
# vault-external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-vault-secrets
  namespace: default
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-app-secrets
    creationPolicy: Owner
  data:
    - secretKey: database-password
      remoteRef:
        key: secret/data/production/my-app
        property: database_password
    - secretKey: api-key
      remoteRef:
        key: secret/data/production/my-app
        property: api_key
```

<br />

The `refreshInterval` is one of ESO's killer features. The operator periodically checks the external store
and updates the Kubernetes Secret if the upstream value has changed. This is the foundation for automated
secret rotation, which we will cover later.

<br />

ESO is a great choice when you already have a centralized secret store and want to bring those secrets into
Kubernetes without manual steps. It works well with GitOps because only the references live in Git, and
it supports virtually every major cloud provider and secret management tool.

<br />

##### **HashiCorp Vault integration**
HashiCorp Vault is the heavyweight champion of secrets management. It provides centralized secret storage,
dynamic secret generation, encryption as a service, and detailed audit logging. While ESO can sync secrets
from Vault into Kubernetes, Vault also offers native Kubernetes integration through the Vault Agent Injector
and the CSI provider.

<br />

**Vault Agent Injector**

The Vault Agent Injector uses a mutating webhook to inject a Vault Agent sidecar into your pods. The agent
handles authentication, fetches secrets from Vault, and writes them to a shared volume that your application
can read.

<br />

Install the Vault Helm chart with the injector enabled:

<br />

```sql
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "injector.enabled=true" \
  --set "server.dev.enabled=false" \
  --set "server.ha.enabled=true" \
  --set "server.ha.replicas=3"
```

<br />

Configure Vault's Kubernetes auth method so pods can authenticate:

<br />

```bash
# Enable Kubernetes auth in Vault
vault auth enable kubernetes

# Configure it to talk to the Kubernetes API
vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Create a policy for the app
vault policy write my-app-policy - <<EOF
path "secret/data/production/my-app" {
  capabilities = ["read"]
}
EOF

# Create a role that binds the policy to a Kubernetes service account
vault write auth/kubernetes/role/my-app \
  bound_service_account_names=my-app-sa \
  bound_service_account_namespaces=default \
  policies=my-app-policy \
  ttl=1h
```

<br />

Now annotate your deployment to use the injector:

<br />

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "my-app"
        vault.hashicorp.com/agent-inject-secret-db-password: "secret/data/production/my-app"
        vault.hashicorp.com/agent-inject-template-db-password: |
          {{- with secret "secret/data/production/my-app" -}}
          {{ .Data.data.database_password }}
          {{- end -}}
        vault.hashicorp.com/agent-inject-secret-api-key: "secret/data/production/my-app"
        vault.hashicorp.com/agent-inject-template-api-key: |
          {{- with secret "secret/data/production/my-app" -}}
          {{ .Data.data.api_key }}
          {{- end -}}
    spec:
      serviceAccountName: my-app-sa
      containers:
        - name: my-app
          image: my-app:latest
          # Secrets are available at /vault/secrets/db-password and /vault/secrets/api-key
```

<br />

**Vault CSI Provider**

The CSI (Container Storage Interface) provider mounts secrets as volumes using the Secrets Store CSI driver.
This approach is lighter weight than the Agent Injector because it does not require a sidecar:

<br />

```hcl
# Install the Secrets Store CSI driver
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system

# Install the Vault CSI provider
helm install vault hashicorp/vault \
  --namespace vault \
  --set "injector.enabled=false" \
  --set "csi.enabled=true"
```

<br />

```yaml
# secret-provider-class.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-my-app
  namespace: default
spec:
  provider: vault
  parameters:
    vaultAddress: "https://vault.vault.svc:8200"
    roleName: "my-app"
    objects: |
      - objectName: "database-password"
        secretPath: "secret/data/production/my-app"
        secretKey: "database_password"
      - objectName: "api-key"
        secretPath: "secret/data/production/my-app"
        secretKey: "api_key"
  # Optionally sync to a Kubernetes Secret as well
  secretObjects:
    - secretName: my-app-secrets
      type: Opaque
      data:
        - objectName: database-password
          key: database-password
        - objectName: api-key
          key: api-key
```

<br />

```yaml
# pod-with-csi.yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  namespace: default
spec:
  serviceAccountName: my-app-sa
  containers:
    - name: my-app
      image: my-app:latest
      volumeMounts:
        - name: secrets
          mountPath: "/mnt/secrets"
          readOnly: true
  volumes:
    - name: secrets
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "vault-my-app"
```

<br />

Vault is the right choice when you need dynamic secrets (like database credentials that are generated on
the fly and automatically expire), fine-grained access policies, comprehensive audit logging, or encryption
as a service. The tradeoff is complexity. Vault is a distributed system that needs to be deployed, managed,
unsealed, and backed up. For smaller teams, ESO with a cloud-managed secret store might be a better fit.

<br />

##### **Secret rotation strategies**
Static secrets are a liability. The longer a secret exists without being changed, the more time an attacker
has to find and exploit it. Secret rotation is the practice of regularly replacing secrets with new values,
and it is one of the most impactful things you can do for your security posture.

<br />

**Why rotate secrets?**

<br />

> * **Limit blast radius**: If a secret is compromised, rotation limits how long the attacker can use it
> * **Compliance**: Many compliance frameworks (SOC2, PCI-DSS, HIPAA) require regular secret rotation
> * **Reduce stale access**: When people leave the team or services are decommissioned, their credentials should stop working
> * **Defense in depth**: Even if your other controls fail, rotation limits the damage window

<br />

**Automated rotation with External Secrets Operator**

ESO's `refreshInterval` is the simplest way to implement rotation. If you update the secret in your
external store, ESO will pick up the new value on the next refresh cycle:

<br />

```yaml
# external-secret-with-rotation.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rotating-secret
  namespace: default
spec:
  # Check for new values every 15 minutes
  refreshInterval: 15m
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: rotating-secret
    creationPolicy: Owner
  data:
    - secretKey: database-password
      remoteRef:
        key: production/my-app/database
        property: password
```

<br />

On the AWS side, you can set up automatic rotation with a Lambda function:

<br />

```hcl
# terraform for AWS Secrets Manager rotation
resource "aws_secretsmanager_secret" "db_password" {
  name = "production/my-app/database"
}

resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id           = aws_secretsmanager_secret.db_password.id
  rotation_lambda_arn = aws_lambda_function.secret_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_lambda_function" "secret_rotation" {
  function_name = "secret-rotation-db"
  handler       = "rotation.handler"
  runtime       = "python3.12"
  filename      = "rotation-lambda.zip"

  environment {
    variables = {
      DB_HOST = "mydb.cluster-xyz.us-east-1.rds.amazonaws.com"
    }
  }
}
```

<br />

**Dynamic secrets with Vault**

Vault takes rotation a step further with dynamic secrets. Instead of rotating a static credential, Vault
generates a unique, short-lived credential on every request. When the lease expires, Vault automatically
revokes it:

<br />

```bash
# Enable the database secrets engine
vault secrets enable database

# Configure a PostgreSQL connection
vault write database/config/my-postgres \
  plugin_name=postgresql-database-plugin \
  allowed_roles="my-app-role" \
  connection_url="postgresql://{{username}}:{{password}}@postgres.default.svc:5432/mydb?sslmode=disable" \
  username="vault_admin" \
  password="admin_password"

# Create a role that generates credentials with a 1-hour TTL
vault write database/roles/my-app-role \
  db_name=my-postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

<br />

```bash
# Now any request to this path generates a fresh credential
$ vault read database/creds/my-app-role
Key                Value
---                -----
lease_id           database/creds/my-app-role/abcd1234
lease_duration     1h
lease_renewable    true
password           A1B2-C3D4-E5F6-G7H8
username           v-my-app-role-xyz123
```

<br />

With dynamic secrets, there is nothing to rotate in the traditional sense. Every pod gets its own unique
credential that expires automatically. If a credential is compromised, it only works for a short window,
and it only gives access to what that specific role allows.

<br />

The main challenge with rotation (both traditional and dynamic) is making sure your application handles
credential changes gracefully. Your app needs to either re-read the secret file periodically, reconnect
with new credentials when the old ones are revoked, or use a connection pool that handles credential
rotation transparently.

<br />

##### **SOPS with age/GPG**
Mozilla SOPS (Secrets OPerationS) takes yet another approach. Instead of using a separate controller or
operator, SOPS encrypts specific values in your YAML or JSON files while leaving the structure and keys
in plain text. This means you can see what secrets a file contains without being able to read the values,
which is great for code review and diffing.

<br />

Install SOPS and age (a modern encryption tool that is simpler than GPG):

<br />

```bash
# Install sops
brew install sops

# Install age
brew install age

# Generate an age key pair
age-keygen -o keys.txt
# Output: public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

<br />

Create a `.sops.yaml` configuration file in your repository root:

<br />

```yaml
# .sops.yaml
creation_rules:
  # Encrypt secrets in the production directory
  - path_regex: secrets/production/.*\.yaml$
    encrypted_regex: "^(data|stringData)$"
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p

  # Encrypt secrets in the staging directory with a different key
  - path_regex: secrets/staging/.*\.yaml$
    encrypted_regex: "^(data|stringData)$"
    age: age1wrg9q5p84t03edh09vqnqv60xfmxqxfaslfcm2yln95jwzxqntrse2x8fq

  # You can also use AWS KMS, GCP KMS, or Azure Key Vault
  - path_regex: secrets/production-aws/.*\.yaml$
    encrypted_regex: "^(data|stringData)$"
    kms: "arn:aws:kms:us-east-1:123456789:key/abcd-1234-efgh-5678"
```

<br />

Now create a secret file and encrypt it:

<br />

```yaml
# secrets/production/my-app.yaml (before encryption)
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secrets
  namespace: default
type: Opaque
stringData:
  database-password: password123
  api-key: super-secret-key
```

<br />

```bash
# Encrypt the file in place
sops --encrypt --in-place secrets/production/my-app.yaml
```

<br />

After encryption, the file looks like this:

<br />

```yaml
# secrets/production/my-app.yaml (after encryption)
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secrets
  namespace: default
type: Opaque
stringData:
  database-password: ENC[AES256_GCM,data:kJH7x9mN...,iv:abc...,tag:xyz...,type:str]
  api-key: ENC[AES256_GCM,data:pQR8y0oP...,iv:def...,tag:uvw...,type:str]
sops:
  age:
    - recipient: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+...
        -----END AGE ENCRYPTED FILE-----
  lastmodified: "2026-03-07T10:30:00Z"
  version: 3.9.0
```

<br />

Notice that the keys and structure are visible, but the values are encrypted. This is perfect for code
review because you can see that someone changed the `database-password` without seeing the actual value.

<br />

To decrypt and apply:

<br />

```bash
# Decrypt and apply to the cluster
sops --decrypt secrets/production/my-app.yaml | kubectl apply -f -

# Or edit the encrypted file directly (decrypts in your editor, re-encrypts on save)
sops secrets/production/my-app.yaml
```

<br />

**Integrating SOPS with ArgoCD**

ArgoCD has native SOPS support through plugins. You can use the `argocd-vault-plugin` or the built-in
Kustomize SOPS support:

<br />

```yaml
# argocd-repo-server with SOPS support
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-repo-server
  namespace: argocd
spec:
  template:
    spec:
      containers:
        - name: argocd-repo-server
          env:
            # Age private key for decryption
            - name: SOPS_AGE_KEY_FILE
              value: /sops/age/keys.txt
          volumeMounts:
            - name: sops-age
              mountPath: /sops/age
      volumes:
        - name: sops-age
          secret:
            secretName: sops-age-key
```

<br />

```yaml
# Using kustomize-sops with ArgoCD
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

generators:
  - secret-generator.yaml

# secret-generator.yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: my-app-secrets
files:
  - secrets/production/my-app.yaml
```

<br />

SOPS is a great fit when you want to keep everything in Git (true GitOps), you have a small to medium
number of secrets, and you do not need dynamic secrets or complex rotation. It works well for teams that
are already comfortable with Git workflows and want minimal additional infrastructure.

<br />

##### **RBAC for secrets**
No matter which tool you use to manage secrets, the Kubernetes RBAC layer is your last line of defense.
If your RBAC is too permissive, an attacker who compromises any service account can read every secret
in the namespace or even the entire cluster.

<br />

Here are the key principles:

<br />

> * **Least privilege**: Only grant access to the specific secrets a service needs
> * **Namespace isolation**: Use separate namespaces for different environments and teams
> * **No wildcard access**: Avoid `resources: ["*"]` in RBAC rules for secrets
> * **Separate read and write**: Most services only need to read secrets, not create or modify them

<br />

Here is a restrictive Role that only allows reading a specific secret:

<br />

```yaml
# role-secret-reader.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: my-app-secret-reader
  namespace: default
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["my-app-secrets"]  # Only this specific secret
    verbs: ["get"]  # Only get, not list or watch
```

<br />

```yaml
# rolebinding-secret-reader.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-app-secret-reader
  namespace: default
subjects:
  - kind: ServiceAccount
    name: my-app-sa
    namespace: default
roleRef:
  kind: Role
  name: my-app-secret-reader
  apiGroup: rbac.authorization.k8s.io
```

<br />

For namespace isolation, create a NetworkPolicy that prevents pods in one namespace from communicating
with pods in other namespaces, combined with RBAC that restricts service accounts to their own namespace:

<br />

```yaml
# namespace-isolation.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-payments
  labels:
    team: payments
    environment: production
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace
  namespace: team-payments
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}  # Only allow traffic from same namespace
  egress:
    - to:
        - podSelector: {}  # Only allow traffic to same namespace
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - port: 53
          protocol: UDP  # Allow DNS resolution
```

<br />

You should also restrict who can create or modify Roles and RoleBindings, because an attacker who can
create a RoleBinding can grant themselves access to any secret:

<br />

```yaml
# restrict-rbac-management.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: rbac-manager
rules:
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
# Only bind this to cluster administrators, not regular service accounts
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: rbac-manager-binding
subjects:
  - kind: Group
    name: cluster-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: rbac-manager
  apiGroup: rbac.authorization.k8s.io
```

<br />

A common mistake is giving the `edit` or `admin` ClusterRole to service accounts or developers. These
built-in roles include the ability to read all secrets in a namespace. Instead, create custom roles with
only the permissions that are actually needed.

<br />

##### **Auditing secret access**
Even with strong RBAC, you need to know who is accessing your secrets and when. Kubernetes audit logging
gives you this visibility, but it needs to be configured explicitly because it is not enabled by default
in most distributions.

<br />

The audit policy defines which events to log and at what level:

<br />

```yaml
# audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log all secret access at the RequestResponse level
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Log token requests (service account tokens)
  - level: Metadata
    resources:
      - group: ""
        resources: ["serviceaccounts/token"]
    verbs: ["create"]

  # Log RBAC changes
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs: ["create", "update", "patch", "delete"]

  # Log everything else at the metadata level
  - level: Metadata
    omitStages:
      - "RequestReceived"
```

<br />

Configure the API server to use this policy:

<br />

```bash
# kube-apiserver flags
--audit-policy-file=/etc/kubernetes/audit-policy.yaml
--audit-log-path=/var/log/kubernetes/audit.log
--audit-log-maxage=30
--audit-log-maxbackup=10
--audit-log-maxsize=100

# Or send audit logs to a webhook (like Elasticsearch or Loki)
--audit-webhook-config-file=/etc/kubernetes/audit-webhook.yaml
```

<br />

An audit log entry for a secret access looks like this:

<br />

```json
{
  "kind": "Event",
  "apiVersion": "audit.k8s.io/v1",
  "level": "RequestResponse",
  "auditID": "abc-123-def-456",
  "stage": "ResponseComplete",
  "requestURI": "/api/v1/namespaces/default/secrets/my-app-secrets",
  "verb": "get",
  "user": {
    "username": "system:serviceaccount:default:my-app-sa",
    "groups": ["system:serviceaccounts", "system:serviceaccounts:default"]
  },
  "sourceIPs": ["10.244.0.15"],
  "objectRef": {
    "resource": "secrets",
    "namespace": "default",
    "name": "my-app-secrets",
    "apiVersion": "v1"
  },
  "responseStatus": {
    "metadata": {},
    "code": 200
  },
  "requestReceivedTimestamp": "2026-03-07T10:30:00.000000Z",
  "stageTimestamp": "2026-03-07T10:30:00.005000Z"
}
```

<br />

You can build alerts on top of audit logs to detect suspicious activity:

<br />

```yaml
# Falco rule for detecting secret access from unexpected service accounts
- rule: Unexpected Secret Access
  desc: Detect when a service account that is not in the allowlist accesses a secret
  condition: >
    ka.verb in (get, list) and
    ka.target.resource = secrets and
    not ka.user.name in (allowed_secret_readers)
  output: >
    Unexpected secret access
    (user=%ka.user.name verb=%ka.verb
     secret=%ka.target.name ns=%ka.target.namespace
     source=%ka.sourceips)
  priority: WARNING
  source: k8s_audit
  tags: [security, secrets]
```

<br />

```yaml
# Prometheus alerting rule based on audit log metrics
# (requires audit log metrics exporter)
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: secret-access-alerts
  namespace: monitoring
spec:
  groups:
    - name: secret.access
      rules:
        - alert: UnusualSecretAccessRate
          expr: |
            sum(rate(apiserver_audit_event_total{
              resource="secrets",
              verb="get"
            }[5m])) by (user) > 10
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Unusual rate of secret access by {{ $labels.user }}"
            description: "Service account {{ $labels.user }} is accessing secrets at an unusually high rate"
```

<br />

Combining audit logging with alerting gives you the ability to detect and respond to unauthorized secret
access in near real time. This is critical for compliance and for catching compromised service accounts
before they can do serious damage.

<br />

##### **Putting it all together**
With all these tools and approaches, how do you decide what to use? Here is a decision matrix based on
your team's needs and maturity level:

<br />

> 1. **Just starting out, small team**: Use Sealed Secrets. It is the simplest to set up, requires no external infrastructure, and solves the biggest problem (secrets in Git). Add RBAC restrictions and basic audit logging.
> 2. **Growing team, cloud-native**: Use External Secrets Operator with your cloud provider's secret store (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault). This gives you centralized management, automatic rotation through the cloud provider, and a clean GitOps workflow.
> 3. **Large organization, strict compliance**: Use HashiCorp Vault with the Agent Injector or CSI provider. Vault gives you dynamic secrets, detailed audit logging, policy as code, and integrations with everything. Combine with ESO for a hybrid approach.
> 4. **GitOps purists**: Use SOPS with age or KMS. Everything stays in Git, encrypted at the value level, with clear diffs in pull requests.
> 5. **Maximum security**: Combine Vault for secret storage and dynamic credentials, ESO for Kubernetes integration, RBAC with least-privilege policies, audit logging with alerting, and automatic rotation with short TTLs.

<br />

Here is a maturity model to guide your journey:

<br />

> * **Level 0**: Secrets hardcoded in code or committed to Git in plain text. Stop everything and fix this first.
> * **Level 1**: Kubernetes Secrets with encryption at rest enabled in etcd. Better, but secrets are still in manifests and not audited.
> * **Level 2**: Sealed Secrets or SOPS for encrypted secrets in Git. RBAC restricted to least privilege. This is a solid baseline.
> * **Level 3**: External Secrets Operator with a centralized secret store. Automated rotation. Audit logging enabled.
> * **Level 4**: Vault with dynamic secrets, short-lived credentials, and comprehensive audit logging. Secret access alerts. Regular rotation. Compliance controls in place.

<br />

Most teams will find that Level 2 or Level 3 covers their needs. Level 4 is for organizations with
strict compliance requirements or high-value targets. The important thing is to be honest about where
you are and take incremental steps to improve.

<br />

##### **Closing notes**
Secrets management is one of those topics that seems simple on the surface but gets complex fast. The good
news is that the Kubernetes ecosystem has mature, battle-tested tools for every level of complexity, from
Sealed Secrets for small teams to Vault for enterprise-grade dynamic secrets.

<br />

The most important takeaway is this: base64 is not encryption, and Kubernetes Secrets alone are not
sufficient. Pick a tool that fits your team's size and needs, enforce least-privilege RBAC, enable audit
logging, and rotate your secrets regularly. You do not need to implement everything at once, but you should
know where you are on the maturity ladder and have a plan to move up.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Gestión de Secretos en Kubernetes",
  author: "Gabriel Garrido",
  description: "Vamos a explorar la gestión de secretos en Kubernetes, desde Sealed Secrets y External Secrets Operator hasta la integración con HashiCorp Vault, estrategias de rotación de secretos, y SOPS para encriptar secretos en Git...",
  tags: ~w(sre kubernetes security secrets vault),
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
[planificación de capacidad](/blog/sre-capacity-planning-autoscaling-and-load-testing) y
[GitOps](/blog/sre-gitops-with-argocd). Construimos una base sólida para correr servicios confiables en
Kubernetes, pero hay un tema que todavía no tocamos y que puede hacer o romper tu postura de seguridad:
la gestión de secretos.

<br />

Si alguna vez commiteaste una contraseña de base de datos a un repositorio Git, hardcodeaste una API key
en un manifiesto de deployment, o confiaste en los Secrets de Kubernetes pensando que estaban "encriptados",
conocés el dolor. Los secretos están en todos lados en la infraestructura moderna, y gestionarlos mal es
una de las formas más rápidas de terminar en las noticias por las razones equivocadas.

<br />

En este artículo vamos a cubrir por qué los Secrets de Kubernetes no son suficientes por sí solos, y después
recorrer las herramientas y estrategias que realmente resuelven el problema: Sealed Secrets, External Secrets
Operator, HashiCorp Vault, rotación de secretos, SOPS, políticas de RBAC, y logging de auditoría. Al final
vas a tener una imagen clara de qué enfoque se ajusta a tu situación y cómo implementarlo.

<br />

Vamos al tema.

<br />

##### **El problema con los secrets de Kubernetes**
Kubernetes tiene un recurso Secret incorporado, y a primera vista parece que resuelve el problema. Creás
un Secret, lo referenciás en tu spec de Pod, y tu aplicación recibe el valor como variable de entorno o
archivo montado. Bastante simple.

<br />

Pero hay un detalle. Los Secrets de Kubernetes están codificados en base64, no encriptados. Base64 es una
codificación reversible, no un mecanismo de seguridad. Cualquiera con acceso al manifiesto o al API server
puede decodificar tus secretos de manera trivial:

<br />

```yaml
# Creando un "secret" en Kubernetes
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secrets
  namespace: default
type: Opaque
data:
  # Esto es solo base64, NO encriptación
  database-password: cGFzc3dvcmQxMjM=
  api-key: c3VwZXItc2VjcmV0LWtleQ==
```

<br />

```bash
# Cualquiera puede decodificar esto al instante
$ echo "cGFzc3dvcmQxMjM=" | base64 -d
password123

$ echo "c3VwZXItc2VjcmV0LWtleQ==" | base64 -d
super-secret-key
```

<br />

Los problemas van más allá de la codificación:

<br />

> * **Almacenamiento en etcd**: Por defecto, los secrets se guardan sin encriptar en etcd. Cualquiera con acceso al datastore de etcd puede leer todos los secrets del cluster
> * **Brechas de RBAC**: La configuración de RBAC por defecto en muchos clusters es demasiado permisiva. Si una service account puede listar secrets en un namespace, puede leer todos
> * **Exposición en Git**: No podés commitear manifiestos de Secret a Git sin exponer los valores, lo que rompe los flujos de trabajo GitOps
> * **Sin registro de auditoría**: Kubernetes no registra quién accedió al valor de un secret por defecto, solo quién listó o watcheó el recurso
> * **Sin rotación**: No hay mecanismo incorporado para rotar secretos. Cambiás el valor, reiniciás los pods, y esperás que nada se rompa
> * **Sin encriptación en reposo**: A menos que configures explícitamente encriptación en reposo para etcd, los secrets están ahí en texto plano

<br />

Podés habilitar la encriptación en reposo en el API server con una EncryptionConfiguration:

<br />

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <clave-de-32-bytes-en-base64>
      - identity: {}
```

<br />

Esto ayuda con los datos en reposo en etcd, pero no resuelve el problema de Git, el problema de rotación,
ni el problema de auditoría. Para esos necesitamos herramientas dedicadas.

<br />

##### **Sealed Secrets**
Bitnami Sealed Secrets es una de las soluciones más simples para el problema de "necesito guardar secretos
en Git". La idea es elegante: encriptás tus secretos con una clave pública que solo el controlador del
cluster puede desencriptar. La versión encriptada (un SealedSecret) es segura para commitear a Git porque
solo el controlador corriendo en tu cluster tiene la clave privada para desellarlo.

<br />

Primero, instalá el controlador de Sealed Secrets en tu cluster:

<br />

```sql
# Instalar el controlador
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set-string fullnameOverride=sealed-secrets-controller
```

<br />

Después instalá el CLI `kubeseal` en tu estación de trabajo:

<br />

```bash
# Instalar kubeseal
brew install kubeseal

# O descargar directamente
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.3/kubeseal-0.27.3-linux-amd64.tar.gz
tar -xvf kubeseal-0.27.3-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

<br />

Ahora el flujo de trabajo se ve así. Creás un Secret regular de Kubernetes y después lo sellás:

<br />

```bash
# Crear el secret regular (NO commitear este archivo)
kubectl create secret generic my-app-secrets \
  --namespace default \
  --from-literal=database-password=password123 \
  --from-literal=api-key=super-secret-key \
  --dry-run=client -o yaml > my-secret.yaml

# Sellarlo con la clave pública del cluster
kubeseal --format yaml < my-secret.yaml > my-sealed-secret.yaml

# Eliminar la versión sin encriptar
rm my-secret.yaml
```

<br />

El SealedSecret resultante es seguro para commitear:

<br />

```yaml
# my-sealed-secret.yaml - esto es seguro para commitear a Git
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-app-secrets
  namespace: default
spec:
  encryptedData:
    database-password: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq...
    api-key: AgCtr8HZFBOGZ9Nk+HrKPHRf7A6WkXN0...
  template:
    metadata:
      name: my-app-secrets
      namespace: default
    type: Opaque
```

<br />

Cuando el controlador de Sealed Secrets ve este recurso en el cluster, lo desencripta y crea un Secret
regular de Kubernetes que tus pods pueden usar normalmente.

<br />

Algunas cosas importantes sobre Sealed Secrets:

<br />

> * **Alcance**: Por defecto, un SealedSecret está vinculado a un nombre y namespace específico. No podés cambiar el nombre o namespace sin volver a sellar
> * **Rotación de claves**: El controlador rota sus claves de encriptación cada 30 días por defecto. Las claves viejas se mantienen para que los SealedSecrets existentes puedan seguir siendo desencriptados
> * **Respaldá las claves**: Si perdés la clave privada del controlador (por ejemplo, eliminando el namespace sin respaldar), perdés la capacidad de desencriptar todos tus SealedSecrets. Respaldá las claves
> * **Re-encriptación**: Después de la rotación de claves, los SealedSecrets existentes siguen funcionando pero usan la clave vieja. Deberías re-sellarlos periódicamente con la nueva clave

<br />

Así es como respaldás y restaurás las claves del controlador:

<br />

```bash
# Respaldar las claves de sellado
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-keys-backup.yaml

# Guardá este respaldo de forma segura (no en Git!)
# Usá un password manager, cloud KMS, o una caja fuerte

# Restaurar claves en un cluster nuevo
kubectl apply -f sealed-secrets-keys-backup.yaml
# Reiniciar el controlador para que levante las claves restauradas
kubectl rollout restart deployment/sealed-secrets-controller -n kube-system
```

<br />

Sealed Secrets es una excelente opción cuando querés una solución simple y autocontenida que no dependa
de servicios externos. Funciona perfecto con GitOps porque los manifiestos encriptados viven en tu repo.
La desventaja principal es que solo resuelve el problema de "secretos en Git". No ayuda con rotación,
gestión centralizada, o secretos dinámicos.

<br />

##### **External Secrets Operator**
El External Secrets Operator (ESO) toma un enfoque diferente. En vez de encriptar secretos y guardarlos
en Git, sincroniza secretos desde un almacén de secretos externo (como AWS Secrets Manager, HashiCorp
Vault, Google Secret Manager, o Azure Key Vault) hacia Secrets de Kubernetes. Tu repositorio Git solo
contiene la referencia al secreto, no el valor en sí.

<br />

Instalá ESO con Helm:

<br />

```sql
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

<br />

La arquitectura tiene tres componentes principales:

<br />

> * **SecretStore / ClusterSecretStore**: Configura la conexión a tu proveedor de secretos externo
> * **ExternalSecret**: Declara qué secretos traer y cómo mapearlos a Secrets de Kubernetes
> * **El operador**: Observa los recursos ExternalSecret y crea/actualiza Secrets de Kubernetes

<br />

Acá hay un ejemplo usando AWS Secrets Manager como backend. Primero, configurá el SecretStore:

<br />

```yaml
# cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

<br />

Después creá un ExternalSecret que referencia un secreto almacenado en AWS:

<br />

```yaml
# external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secrets
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: my-app-secrets
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        database-password: "{{ .database_password }}"
        api-key: "{{ .api_key }}"
  data:
    - secretKey: database_password
      remoteRef:
        key: production/my-app
        property: database_password
    - secretKey: api_key
      remoteRef:
        key: production/my-app
        property: api_key
```

<br />

Este manifiesto ExternalSecret es perfectamente seguro para commitear a Git porque solo contiene
referencias, no valores. El operador trae los valores reales de AWS Secrets Manager y crea un
Secret de Kubernetes.

<br />

También podés usar ESO con HashiCorp Vault como backend:

<br />

```yaml
# vault-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

<br />

```yaml
# vault-external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-vault-secrets
  namespace: default
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-app-secrets
    creationPolicy: Owner
  data:
    - secretKey: database-password
      remoteRef:
        key: secret/data/production/my-app
        property: database_password
    - secretKey: api-key
      remoteRef:
        key: secret/data/production/my-app
        property: api_key
```

<br />

El `refreshInterval` es una de las funcionalidades estrella de ESO. El operador chequea periódicamente
el almacén externo y actualiza el Secret de Kubernetes si el valor upstream cambió. Esta es la base para
la rotación automatizada de secretos, que vamos a cubrir más adelante.

<br />

ESO es una excelente opción cuando ya tenés un almacén de secretos centralizado y querés traer esos
secretos a Kubernetes sin pasos manuales. Funciona bien con GitOps porque solo las referencias viven
en Git, y soporta prácticamente todos los proveedores de nube y herramientas de gestión de secretos.

<br />

##### **Integración con HashiCorp Vault**
HashiCorp Vault es el peso pesado de la gestión de secretos. Provee almacenamiento centralizado de
secretos, generación de secretos dinámicos, encriptación como servicio, y logging de auditoría detallado.
Mientras que ESO puede sincronizar secretos desde Vault hacia Kubernetes, Vault también ofrece integración
nativa con Kubernetes a través del Vault Agent Injector y el proveedor CSI.

<br />

**Vault Agent Injector**

El Vault Agent Injector usa un mutating webhook para inyectar un sidecar de Vault Agent en tus pods.
El agente se encarga de la autenticación, trae los secretos de Vault, y los escribe en un volumen
compartido que tu aplicación puede leer.

<br />

Instalá el chart de Helm de Vault con el injector habilitado:

<br />

```sql
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "injector.enabled=true" \
  --set "server.dev.enabled=false" \
  --set "server.ha.enabled=true" \
  --set "server.ha.replicas=3"
```

<br />

Configurá el método de autenticación Kubernetes de Vault para que los pods puedan autenticarse:

<br />

```bash
# Habilitar auth de Kubernetes en Vault
vault auth enable kubernetes

# Configurarlo para hablar con el API de Kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Crear una política para la app
vault policy write my-app-policy - <<EOF
path "secret/data/production/my-app" {
  capabilities = ["read"]
}
EOF

# Crear un rol que vincule la política a una service account de Kubernetes
vault write auth/kubernetes/role/my-app \
  bound_service_account_names=my-app-sa \
  bound_service_account_namespaces=default \
  policies=my-app-policy \
  ttl=1h
```

<br />

Ahora anotá tu deployment para usar el injector:

<br />

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "my-app"
        vault.hashicorp.com/agent-inject-secret-db-password: "secret/data/production/my-app"
        vault.hashicorp.com/agent-inject-template-db-password: |
          {{- with secret "secret/data/production/my-app" -}}
          {{ .Data.data.database_password }}
          {{- end -}}
        vault.hashicorp.com/agent-inject-secret-api-key: "secret/data/production/my-app"
        vault.hashicorp.com/agent-inject-template-api-key: |
          {{- with secret "secret/data/production/my-app" -}}
          {{ .Data.data.api_key }}
          {{- end -}}
    spec:
      serviceAccountName: my-app-sa
      containers:
        - name: my-app
          image: my-app:latest
          # Los secretos están disponibles en /vault/secrets/db-password y /vault/secrets/api-key
```

<br />

**Proveedor CSI de Vault**

El proveedor CSI (Container Storage Interface) monta secretos como volúmenes usando el driver Secrets
Store CSI. Este enfoque es más liviano que el Agent Injector porque no requiere un sidecar:

<br />

```bash
# Instalar el driver Secrets Store CSI
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system

# Instalar el proveedor CSI de Vault
helm install vault hashicorp/vault \
  --namespace vault \
  --set "injector.enabled=false" \
  --set "csi.enabled=true"
```

<br />

```yaml
# secret-provider-class.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-my-app
  namespace: default
spec:
  provider: vault
  parameters:
    vaultAddress: "https://vault.vault.svc:8200"
    roleName: "my-app"
    objects: |
      - objectName: "database-password"
        secretPath: "secret/data/production/my-app"
        secretKey: "database_password"
      - objectName: "api-key"
        secretPath: "secret/data/production/my-app"
        secretKey: "api_key"
  secretObjects:
    - secretName: my-app-secrets
      type: Opaque
      data:
        - objectName: database-password
          key: database-password
        - objectName: api-key
          key: api-key
```

<br />

```yaml
# pod-with-csi.yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  namespace: default
spec:
  serviceAccountName: my-app-sa
  containers:
    - name: my-app
      image: my-app:latest
      volumeMounts:
        - name: secrets
          mountPath: "/mnt/secrets"
          readOnly: true
  volumes:
    - name: secrets
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "vault-my-app"
```

<br />

Vault es la opción correcta cuando necesitás secretos dinámicos (como credenciales de base de datos que
se generan al vuelo y expiran automáticamente), políticas de acceso granulares, logging de auditoría
integral, o encriptación como servicio. La contrapartida es la complejidad. Vault es un sistema distribuido
que necesita ser desplegado, gestionado, desellado, y respaldado. Para equipos más chicos, ESO con un
almacén de secretos gestionado en la nube puede ser mejor opción.

<br />

##### **Estrategias de rotación de secretos**
Los secretos estáticos son un riesgo. Cuanto más tiempo existe un secreto sin ser cambiado, más tiempo
tiene un atacante para encontrarlo y explotarlo. La rotación de secretos es la práctica de reemplazar
secretos con valores nuevos regularmente, y es una de las cosas más impactantes que podés hacer por
tu postura de seguridad.

<br />

**¿Por qué rotar secretos?**

<br />

> * **Limitar radio de impacto**: Si un secreto es comprometido, la rotación limita cuánto tiempo puede usarlo el atacante
> * **Cumplimiento**: Muchos marcos de cumplimiento (SOC2, PCI-DSS, HIPAA) requieren rotación regular de secretos
> * **Reducir acceso obsoleto**: Cuando la gente se va del equipo o los servicios se decomisionan, sus credenciales deberían dejar de funcionar
> * **Defensa en profundidad**: Incluso si tus otros controles fallan, la rotación limita la ventana de daño

<br />

**Rotación automatizada con External Secrets Operator**

El `refreshInterval` de ESO es la forma más simple de implementar rotación. Si actualizás el secreto
en tu almacén externo, ESO levanta el nuevo valor en el siguiente ciclo de refresco:

<br />

```yaml
# external-secret-with-rotation.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rotating-secret
  namespace: default
spec:
  # Chequear nuevos valores cada 15 minutos
  refreshInterval: 15m
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: rotating-secret
    creationPolicy: Owner
  data:
    - secretKey: database-password
      remoteRef:
        key: production/my-app/database
        property: password
```

<br />

Del lado de AWS, podés configurar rotación automática con una función Lambda:

<br />

```hcl
# terraform para rotación de AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name = "production/my-app/database"
}

resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id           = aws_secretsmanager_secret.db_password.id
  rotation_lambda_arn = aws_lambda_function.secret_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_lambda_function" "secret_rotation" {
  function_name = "secret-rotation-db"
  handler       = "rotation.handler"
  runtime       = "python3.12"
  filename      = "rotation-lambda.zip"

  environment {
    variables = {
      DB_HOST = "mydb.cluster-xyz.us-east-1.rds.amazonaws.com"
    }
  }
}
```

<br />

**Secretos dinámicos con Vault**

Vault lleva la rotación un paso más allá con secretos dinámicos. En vez de rotar una credencial estática,
Vault genera una credencial única y de corta vida en cada solicitud. Cuando el lease expira, Vault la
revoca automáticamente:

<br />

```bash
# Habilitar el motor de secretos de base de datos
vault secrets enable database

# Configurar una conexión PostgreSQL
vault write database/config/my-postgres \
  plugin_name=postgresql-database-plugin \
  allowed_roles="my-app-role" \
  connection_url="postgresql://{{username}}:{{password}}@postgres.default.svc:5432/mydb?sslmode=disable" \
  username="vault_admin" \
  password="admin_password"

# Crear un rol que genera credenciales con TTL de 1 hora
vault write database/roles/my-app-role \
  db_name=my-postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

<br />

```bash
# Ahora cada solicitud a este path genera una credencial nueva
$ vault read database/creds/my-app-role
Key                Value
---                -----
lease_id           database/creds/my-app-role/abcd1234
lease_duration     1h
lease_renewable    true
password           A1B2-C3D4-E5F6-G7H8
username           v-my-app-role-xyz123
```

<br />

Con secretos dinámicos, no hay nada que rotar en el sentido tradicional. Cada pod recibe su propia
credencial única que expira automáticamente. Si una credencial es comprometida, solo funciona por una
ventana corta, y solo da acceso a lo que ese rol específico permite.

<br />

El desafío principal con la rotación (tanto tradicional como dinámica) es asegurarte de que tu aplicación
maneje los cambios de credenciales de forma elegante. Tu app necesita re-leer el archivo de secretos
periódicamente, reconectarse con nuevas credenciales cuando las viejas se revocan, o usar un pool de
conexiones que maneje la rotación de credenciales de forma transparente.

<br />

##### **SOPS con age/GPG**
Mozilla SOPS (Secrets OPerationS) toma otro enfoque. En vez de usar un controlador u operador separado,
SOPS encripta valores específicos en tus archivos YAML o JSON mientras deja la estructura y las claves
en texto plano. Esto significa que podés ver qué secretos contiene un archivo sin poder leer los valores,
lo cual es genial para code review y para ver diffs.

<br />

Instalá SOPS y age (una herramienta de encriptación moderna que es más simple que GPG):

<br />

```bash
# Instalar sops
brew install sops

# Instalar age
brew install age

# Generar un par de claves age
age-keygen -o keys.txt
# Output: public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

<br />

Creá un archivo de configuración `.sops.yaml` en la raíz de tu repositorio:

<br />

```yaml
# .sops.yaml
creation_rules:
  # Encriptar secretos en el directorio de producción
  - path_regex: secrets/production/.*\.yaml$
    encrypted_regex: "^(data|stringData)$"
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p

  # Encriptar secretos en el directorio de staging con otra clave
  - path_regex: secrets/staging/.*\.yaml$
    encrypted_regex: "^(data|stringData)$"
    age: age1wrg9q5p84t03edh09vqnqv60xfmxqxfaslfcm2yln95jwzxqntrse2x8fq

  # También podés usar AWS KMS, GCP KMS, o Azure Key Vault
  - path_regex: secrets/production-aws/.*\.yaml$
    encrypted_regex: "^(data|stringData)$"
    kms: "arn:aws:kms:us-east-1:123456789:key/abcd-1234-efgh-5678"
```

<br />

Ahora creá un archivo de secreto y encriptalo:

<br />

```yaml
# secrets/production/my-app.yaml (antes de encriptar)
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secrets
  namespace: default
type: Opaque
stringData:
  database-password: password123
  api-key: super-secret-key
```

<br />

```bash
# Encriptar el archivo in place
sops --encrypt --in-place secrets/production/my-app.yaml
```

<br />

Después de la encriptación, el archivo se ve así:

<br />

```yaml
# secrets/production/my-app.yaml (después de encriptar)
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secrets
  namespace: default
type: Opaque
stringData:
  database-password: ENC[AES256_GCM,data:kJH7x9mN...,iv:abc...,tag:xyz...,type:str]
  api-key: ENC[AES256_GCM,data:pQR8y0oP...,iv:def...,tag:uvw...,type:str]
sops:
  age:
    - recipient: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+...
        -----END AGE ENCRYPTED FILE-----
  lastmodified: "2026-03-07T10:30:00Z"
  version: 3.9.0
```

<br />

Notá que las claves y la estructura son visibles, pero los valores están encriptados. Esto es perfecto
para code review porque podés ver que alguien cambió el `database-password` sin ver el valor real.

<br />

Para desencriptar y aplicar:

<br />

```bash
# Desencriptar y aplicar al cluster
sops --decrypt secrets/production/my-app.yaml | kubectl apply -f -

# O editar el archivo encriptado directamente (desencripta en tu editor, re-encripta al guardar)
sops secrets/production/my-app.yaml
```

<br />

**Integrando SOPS con ArgoCD**

ArgoCD tiene soporte nativo para SOPS a través de plugins. Podés usar el `argocd-vault-plugin` o el
soporte incorporado de Kustomize SOPS:

<br />

```yaml
# argocd-repo-server con soporte SOPS
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-repo-server
  namespace: argocd
spec:
  template:
    spec:
      containers:
        - name: argocd-repo-server
          env:
            # Clave privada age para desencriptación
            - name: SOPS_AGE_KEY_FILE
              value: /sops/age/keys.txt
          volumeMounts:
            - name: sops-age
              mountPath: /sops/age
      volumes:
        - name: sops-age
          secret:
            secretName: sops-age-key
```

<br />

```yaml
# Usando kustomize-sops con ArgoCD
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

generators:
  - secret-generator.yaml

# secret-generator.yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: my-app-secrets
files:
  - secrets/production/my-app.yaml
```

<br />

SOPS es una gran opción cuando querés mantener todo en Git (GitOps puro), tenés una cantidad chica a
mediana de secretos, y no necesitás secretos dinámicos ni rotación compleja. Funciona bien para equipos
que ya están cómodos con flujos de trabajo de Git y quieren mínima infraestructura adicional.

<br />

##### **RBAC para secretos**
Sin importar qué herramienta uses para gestionar secretos, la capa de RBAC de Kubernetes es tu última
línea de defensa. Si tu RBAC es demasiado permisivo, un atacante que comprometa cualquier service account
puede leer todos los secretos en el namespace o incluso en todo el cluster.

<br />

Estos son los principios clave:

<br />

> * **Mínimo privilegio**: Solo otorgá acceso a los secretos específicos que un servicio necesita
> * **Aislamiento por namespace**: Usá namespaces separados para diferentes ambientes y equipos
> * **Sin acceso wildcard**: Evitá `resources: ["*"]` en las reglas de RBAC para secretos
> * **Separar lectura y escritura**: La mayoría de los servicios solo necesitan leer secretos, no crearlos o modificarlos

<br />

Acá hay un Role restrictivo que solo permite leer un secreto específico:

<br />

```yaml
# role-secret-reader.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: my-app-secret-reader
  namespace: default
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["my-app-secrets"]  # Solo este secreto específico
    verbs: ["get"]  # Solo get, no list ni watch
```

<br />

```yaml
# rolebinding-secret-reader.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-app-secret-reader
  namespace: default
subjects:
  - kind: ServiceAccount
    name: my-app-sa
    namespace: default
roleRef:
  kind: Role
  name: my-app-secret-reader
  apiGroup: rbac.authorization.k8s.io
```

<br />

Para aislamiento de namespaces, creá una NetworkPolicy que evite que pods en un namespace se comuniquen
con pods en otros namespaces, combinada con RBAC que restrinja las service accounts a su propio namespace:

<br />

```yaml
# namespace-isolation.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-payments
  labels:
    team: payments
    environment: production
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace
  namespace: team-payments
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}  # Solo permitir tráfico del mismo namespace
  egress:
    - to:
        - podSelector: {}  # Solo permitir tráfico al mismo namespace
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - port: 53
          protocol: UDP  # Permitir resolución DNS
```

<br />

También deberías restringir quién puede crear o modificar Roles y RoleBindings, porque un atacante que
puede crear un RoleBinding puede darse acceso a cualquier secreto:

<br />

```yaml
# restrict-rbac-management.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: rbac-manager
rules:
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
# Solo vincular esto a administradores del cluster, no a service accounts regulares
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: rbac-manager-binding
subjects:
  - kind: Group
    name: cluster-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: rbac-manager
  apiGroup: rbac.authorization.k8s.io
```

<br />

Un error común es darle el ClusterRole `edit` o `admin` a service accounts o desarrolladores. Estos roles
incorporados incluyen la capacidad de leer todos los secretos en un namespace. En vez de eso, creá roles
personalizados con solo los permisos que realmente se necesitan.

<br />

##### **Auditoría de acceso a secretos**
Incluso con RBAC fuerte, necesitás saber quién está accediendo a tus secretos y cuándo. El logging de
auditoría de Kubernetes te da esta visibilidad, pero necesita ser configurado explícitamente porque no
está habilitado por defecto en la mayoría de las distribuciones.

<br />

La política de auditoría define qué eventos registrar y a qué nivel:

<br />

```yaml
# audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Registrar todo acceso a secretos a nivel RequestResponse
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Registrar solicitudes de tokens (tokens de service account)
  - level: Metadata
    resources:
      - group: ""
        resources: ["serviceaccounts/token"]
    verbs: ["create"]

  # Registrar cambios de RBAC
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs: ["create", "update", "patch", "delete"]

  # Registrar todo lo demás a nivel metadata
  - level: Metadata
    omitStages:
      - "RequestReceived"
```

<br />

Configurá el API server para usar esta política:

<br />

```bash
# flags del kube-apiserver
--audit-policy-file=/etc/kubernetes/audit-policy.yaml
--audit-log-path=/var/log/kubernetes/audit.log
--audit-log-maxage=30
--audit-log-maxbackup=10
--audit-log-maxsize=100

# O enviá logs de auditoría a un webhook (como Elasticsearch o Loki)
--audit-webhook-config-file=/etc/kubernetes/audit-webhook.yaml
```

<br />

Una entrada de log de auditoría para acceso a secretos se ve así:

<br />

```json
{
  "kind": "Event",
  "apiVersion": "audit.k8s.io/v1",
  "level": "RequestResponse",
  "auditID": "abc-123-def-456",
  "stage": "ResponseComplete",
  "requestURI": "/api/v1/namespaces/default/secrets/my-app-secrets",
  "verb": "get",
  "user": {
    "username": "system:serviceaccount:default:my-app-sa",
    "groups": ["system:serviceaccounts", "system:serviceaccounts:default"]
  },
  "sourceIPs": ["10.244.0.15"],
  "objectRef": {
    "resource": "secrets",
    "namespace": "default",
    "name": "my-app-secrets",
    "apiVersion": "v1"
  },
  "responseStatus": {
    "metadata": {},
    "code": 200
  },
  "requestReceivedTimestamp": "2026-03-07T10:30:00.000000Z",
  "stageTimestamp": "2026-03-07T10:30:00.005000Z"
}
```

<br />

Podés construir alertas sobre los logs de auditoría para detectar actividad sospechosa:

<br />

```yaml
# Regla de Falco para detectar acceso a secretos desde service accounts inesperadas
- rule: Unexpected Secret Access
  desc: Detectar cuando una service account que no está en la lista permitida accede a un secreto
  condition: >
    ka.verb in (get, list) and
    ka.target.resource = secrets and
    not ka.user.name in (allowed_secret_readers)
  output: >
    Acceso inesperado a secreto
    (user=%ka.user.name verb=%ka.verb
     secret=%ka.target.name ns=%ka.target.namespace
     source=%ka.sourceips)
  priority: WARNING
  source: k8s_audit
  tags: [security, secrets]
```

<br />

```yaml
# Regla de alertas de Prometheus basada en métricas de logs de auditoría
# (requiere exportador de métricas de logs de auditoría)
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: secret-access-alerts
  namespace: monitoring
spec:
  groups:
    - name: secret.access
      rules:
        - alert: UnusualSecretAccessRate
          expr: |
            sum(rate(apiserver_audit_event_total{
              resource="secrets",
              verb="get"
            }[5m])) by (user) > 10
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Tasa inusual de acceso a secretos por {{ $labels.user }}"
            description: "La service account {{ $labels.user }} está accediendo a secretos a una tasa inusualmente alta"
```

<br />

Combinar logging de auditoría con alertas te da la capacidad de detectar y responder a acceso no
autorizado a secretos en casi tiempo real. Esto es crítico para cumplimiento y para atrapar service
accounts comprometidas antes de que puedan hacer daño serio.

<br />

##### **Juntando todo**
Con todas estas herramientas y enfoques, ¿cómo decidís qué usar? Acá hay una matriz de decisión basada
en las necesidades y nivel de madurez de tu equipo:

<br />

> 1. **Recién empezando, equipo chico**: Usá Sealed Secrets. Es lo más simple de configurar, no requiere infraestructura externa, y resuelve el problema más grande (secretos en Git). Agregá restricciones de RBAC y logging de auditoría básico.
> 2. **Equipo en crecimiento, cloud-native**: Usá External Secrets Operator con el almacén de secretos de tu proveedor de nube (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault). Te da gestión centralizada, rotación automática a través del proveedor de nube, y un flujo GitOps limpio.
> 3. **Organización grande, cumplimiento estricto**: Usá HashiCorp Vault con el Agent Injector o proveedor CSI. Vault te da secretos dinámicos, logging de auditoría detallado, política como código, e integraciones con todo. Combinalo con ESO para un enfoque híbrido.
> 4. **Puristas de GitOps**: Usá SOPS con age o KMS. Todo se queda en Git, encriptado a nivel de valor, con diffs claros en pull requests.
> 5. **Máxima seguridad**: Combiná Vault para almacenamiento de secretos y credenciales dinámicas, ESO para integración con Kubernetes, RBAC con políticas de mínimo privilegio, logging de auditoría con alertas, y rotación automática con TTLs cortos.

<br />

Acá hay un modelo de madurez para guiar tu camino:

<br />

> * **Nivel 0**: Secretos hardcodeados en código o commiteados a Git en texto plano. Pará todo y arreglá esto primero.
> * **Nivel 1**: Kubernetes Secrets con encriptación en reposo habilitada en etcd. Mejor, pero los secretos siguen en manifiestos y no se auditan.
> * **Nivel 2**: Sealed Secrets o SOPS para secretos encriptados en Git. RBAC restringido a mínimo privilegio. Esta es una base sólida.
> * **Nivel 3**: External Secrets Operator con almacén de secretos centralizado. Rotación automatizada. Logging de auditoría habilitado.
> * **Nivel 4**: Vault con secretos dinámicos, credenciales de corta vida, y logging de auditoría integral. Alertas de acceso a secretos. Rotación regular. Controles de cumplimiento implementados.

<br />

La mayoría de los equipos van a encontrar que el Nivel 2 o Nivel 3 cubre sus necesidades. El Nivel 4 es
para organizaciones con requerimientos estrictos de cumplimiento o blancos de alto valor. Lo importante
es ser honesto sobre dónde estás y dar pasos incrementales para mejorar.

<br />

##### **Notas finales**
La gestión de secretos es uno de esos temas que parece simple en la superficie pero se vuelve complejo
rápido. La buena noticia es que el ecosistema de Kubernetes tiene herramientas maduras y probadas en
batalla para cada nivel de complejidad, desde Sealed Secrets para equipos chicos hasta Vault para
secretos dinámicos de grado empresarial.

<br />

La conclusión más importante es esta: base64 no es encriptación, y los Secrets de Kubernetes solos no
son suficientes. Elegí una herramienta que se ajuste al tamaño y necesidades de tu equipo, aplicá RBAC
de mínimo privilegio, habilitá logging de auditoría, y rotá tus secretos regularmente. No necesitás
implementar todo de una, pero deberías saber dónde estás en la escalera de madurez y tener un plan
para subir.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
