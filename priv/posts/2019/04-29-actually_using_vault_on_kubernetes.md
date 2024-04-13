%{
  title: "Actually using Vault on Kubernetes",
  author: "Gabriel Garrido",
  description: "In the previous article we configured Vault with Consul on our cluster, now it's time to go ahead and use it to provision secrets to our pods/applications...",
  tags: ~w(kubernetes vault security),
  published: true,
  image: "vault-kubernetes.png"
}
---

![vault](/images/vault-kubernetes.png){:class="mx-auto"}

##### **Introduction**
In the previous article we configured Vault with Consul on our cluster, now it's time to go ahead and use it to provision secrets to our pods/applications. If you don't remember about it or don't have your Vault already configured you can go to [Getting started with HashiCorp Vault on Kubernetes](/blog/getting_started_with_hashicorp_vault_on_kubernetes).

In this article we will actually create an example using mutual TLS and provision some secrets to our app, You can find the files used here in [this repo](https://github.com/kainlite/vault-kubernetes).

##### **Creating a cert for our new client**
As we see here we need to enable kv version 1 on `/secret` for this to work, then we just create a secret and store it as a kubernetes secret for myapp, note that the CA was created in the previous article and we rely on these certificates so we can keep building on that.
```elixir
# For this to work we need to enable the path /secret with kv version 1
vault secrets enable -path=secret -version=1 kv

# Then create a separate certificate for our client (Important in case we need or want to revoke it later)
$ consul tls cert create -client -additional-dnsname vault
==> Using consul-agent-ca.pem and consul-agent-ca-key.pem
==> Saved dc1-client-consul-1.pem
==> Saved dc1-client-consul-1-key.pem

# And store the certs as a kubernetes secrets so our pod can use them
$ kubectl create secret generic myapp \
  --from-file=certs/consul-agent-ca.pem \
  --from-file=certs/dc1-client-consul-1.pem \
  --from-file=certs/dc1-client-consul-1-key.pem

```

##### **Service account for kubernetes**
In Kubernetes, a service account provides an identity for processes that run in a Pod so that the processes can contact the API server.
```elixir
$ cat vault-auth-service-account.yml
  ---
  apiVersion: rbac.authorization.k8s.io/v1beta1
  kind: ClusterRoleBinding
  metadata:
    name: role-tokenreview-binding
    namespace: default
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: system:auth-delegator
  subjects:
  - kind: ServiceAccount
    name: vault-auth
    namespace: default

# Create the 'vault-auth' service account
$ kubectl apply --filename vault-auth-service-account.yml

```

##### **Vault policy**
Then we need to set a read-only policy for our secrets, we don't want or app to be able to write or rewrite secrets.
```elixir
# Create a policy file, myapp-kv-ro.hcl
$ tee myapp-kv-ro.hcl <<EOF
# If working with K/V v1
path "secret/myapp/*" {
    capabilities = ["read", "list"]
}

# If working with K/V v2
path "secret/data/myapp/*" {
    capabilities = ["read", "list"]
}
EOF

# Create a policy named myapp-kv-ro
$ vault policy write myapp-kv-ro myapp-kv-ro.hcl

$ vault kv put secret/myapp/config username='appuser' \
        password='suP3rsec(et!' \
        ttl='30s'

```

##### **Kubernetes configuration**
Set the environment variables to point to the running Minikube environment and enable the [kubernetes authentication method](https://www.vaultproject.io/docs/auth/kubernetes.html#configuration) and then validate it from a temporal Pod.
```elixir
# Set VAULT_SA_NAME to the service account you created earlier
$ export VAULT_SA_NAME=$(kubectl get sa vault-auth -o jsonpath="{.secrets[*]['name']}")

# Set SA_JWT_TOKEN value to the service account JWT used to access the TokenReview API
$ export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)

# Set SA_CA_CRT to the PEM encoded CA cert used to talk to Kubernetes API
$ export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)

# Set K8S_HOST to minikube IP address
$ export K8S_HOST=$(minikube ip)

# Enable the Kubernetes auth method at the default path ("auth/kubernetes")
$ vault auth enable kubernetes

# Tell Vault how to communicate with the Kubernetes (Minikube) cluster
$ vault write auth/kubernetes/config \
        token_reviewer_jwt="$SA_JWT_TOKEN" \
        kubernetes_host="https://$K8S_HOST:8443" \
        kubernetes_ca_cert="$SA_CA_CRT"

# Create a role named, 'example' to map Kubernetes Service Account to
# Vault policies and default token TTL
$ vault write auth/kubernetes/role/example \
        bound_service_account_names=vault-auth \
        bound_service_account_namespaces=default \
        policies=myapp-kv-ro \
        ttl=24h

# Run a temp pod to test that we can reach vault
$ kubectl run --generator=run-pod/v1 tmp --rm -i --tty --serviceaccount=vault-auth --image alpine:3.7
$ apk add curl jq
$ curl -k https://vault/v1/sys/health | jq
{
  "initialized": true,
  "sealed": false,
  "standby": false,
  "performance_standby": false,
  "replication_performance_mode": "disabled",
  "replication_dr_mode": "disabled",
  "server_time_utc": 1556488210,
  "version": "1.1.1",
  "cluster_name": "vault-cluster-1677ba10",
  "cluster_id": "fa706969-085b-91ac-36de-de6fcf2328c5"
}

# Then we can test the login
$ curl --request POST \
        --data '{"jwt": "'"$KUBE_TOKEN"'", "role": "example"}' \
        https://vault:8200/v1/auth/kubernetes/login | jq
{
  ...
  "auth": {
    "client_token": "s.7cH83AFIdmXXYKsPsSbeESpp",
    "accessor": "8bmYWFW5HtwDHLAoxSiuMZRh",
    "policies": [
      "default",
      "myapp-kv-ro"
    ],
    "token_policies": [
      "default",
      "myapp-kv-ro"
    ],
    "metadata": {
      "role": "example",
      "service_account_name": "vault-auth",
      "service_account_namespace": "default",
      "service_account_secret_name": "vault-auth-token-vqqlp",
      "service_account_uid": "adaca842-f2a7-11e8-831e-080027b85b6a"
    },
    "lease_duration": 86400,
    "renewable": true,
    "entity_id": "2c4624f1-29d6-972a-fb27-729b50dd05e2",
    "token_type": "service"
  }
}

```

##### **The deployment and the consul-template configuration**
If you check the volume mounts and the secrets we load the certificates we created initially and use them to fetch the secret from vault
```elixir
---
apiVersion: v1
kind: Pod
metadata:
  name: vault-agent-example
spec:
  serviceAccountName: vault-auth

  restartPolicy: Never

  volumes:
    - name: vault-token
      emptyDir:
        medium: Memory
    - name: vault-tls
      secret:
        secretName: myapp

    - name: config
      configMap:
        name: example-vault-agent-config
        items:
          - key: vault-agent-config.hcl
            path: vault-agent-config.hcl

          - key: consul-template-config.hcl
            path: consul-template-config.hcl


    - name: shared-data
      emptyDir: {}

  initContainers:
    # Vault container
    - name: vault-agent-auth
      image: vault

      volumeMounts:
        - name: config
          mountPath: /etc/vault
        - name: vault-token
          mountPath: /home/vault
        - name: vault-tls
          mountPath: /etc/tls

      # This assumes Vault running on a pod in the K8s cluster and that the service name is vault
      env:
        - name: VAULT_ADDR
          value: https://vault:8200
        - name: VAULT_CACERT
          value: /etc/tls/consul-agent-ca.pem
        - name: VAULT_CLIENT_CERT
          value: /etc/tls/dc1-client-consul-1.pem
        - name: VAULT_CLIENT_KEY
          value: /etc/tls/dc1-client-consul-1-key.pem
        - name: VAULT_TLS_SERVER_NAME
          value: client.dc1.consul

      # Run the Vault agent
      args:
        [
          "agent",
          "-config=/etc/vault/vault-agent-config.hcl",
          #"-log-level=debug",
        ]

  containers:
    # Consul Template container
    - name: consul-template
      image: hashicorp/consul-template:alpine
      imagePullPolicy: Always

      volumeMounts:
        - name: vault-token
          mountPath: /home/vault

        - name: config
          mountPath: /etc/consul-template

        - name: shared-data
          mountPath: /etc/secrets

        - name: vault-tls
          mountPath: /etc/tls

      env:
        - name: HOME
          value: /home/vault

        - name: VAULT_ADDR
          value: https://vault:8200

        - name: VAULT_CACERT
          value: /etc/tls/consul-agent-ca.pem

        - name: VAULT_CLIENT_CERT
          value: /etc/tls/dc1-client-consul-1.pem

        - name: VAULT_CLIENT_KEY
          value: /etc/tls/dc1-client-consul-1-key.pem

        - name: VAULT_TLS_SERVER_NAME
          value: client.dc1.consul

      # Consul-Template looks in $HOME/.vault-token, $VAULT_TOKEN, or -vault-token (via CLI)
      args:
        [
          "-config=/etc/consul-template/consul-template-config.hcl",
          #"-log-level=debug",
        ]

    # Nginx container
    - name: nginx-container
      image: nginx

      ports:
        - containerPort: 80

      volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html

```

This is where the magic happens so we're able to fetch secrets (thanks to that role and the token that then will be stored there)
```elixir
# Uncomment this to have Agent run once (e.g. when running as an initContainer)
exit_after_auth = true
pid_file = "/home/vault/pidfile"

auto_auth {
    method "kubernetes" {
        mount_path = "auth/kubernetes"
        config = {
            role = "example"
        }
    }

    sink "file" {
        config = {
            path = "/home/vault/.vault-token"
        }
    }
}

```

And last but not least we create a file based in the template provided which our nginx container will render on the screen later, this is done using Consul Template.
```elixir
vault {
  renew_token = false
  vault_agent_token_file = "/home/vault/.vault-token"
  retry {
    backoff = "1s"
  }
}

template {
  destination = "/etc/secrets/index.html"
  contents = <<EOH
  <html>
  <body>
  <p>Some secrets:</p>
  {{- with secret "secret/myapp/config" }}
  <ul>
  <li><pre>username: {{ .Data.username }}</pre></li>
  <li><pre>password: {{ .Data.password }}</pre></li>
  </ul>
  {{ end }}
  </body>
  </html>
  EOH
}

```

##### **Test it!**
The last step would be to test all that, so after having deployed the files to kubernetes we should see something like this
```elixir
# Finally let's create our app and see if we can fetch secrets from Vault
$ kubectl apply -f example-k8s-spec.yml

# The init container log should look something like this if everything went well.
$ kubectl logs vault-agent-example vault-agent-auth -f
Couldn't start vault with IPC_LOCK. Disabling IPC_LOCK, please use --privileged or --cap-add IPC_LOCK
==> Vault server started! Log data will stream in below:

==> Vault agent configuration:

                     Cgo: disabled
               Log Level: info
                 Version: Vault v1.1.2
             Version Sha: 0082501623c0b704b87b1fbc84c2d725994bac54

2019-04-28T20:37:46.328Z [INFO]  sink.file: creating file sink
2019-04-28T20:37:46.328Z [INFO]  sink.file: file sink configured: path=/home/vault/.vault-token
2019-04-28T20:37:46.329Z [INFO]  auth.handler: starting auth handler
2019-04-28T20:37:46.329Z [INFO]  auth.handler: authenticating
2019-04-28T20:37:46.334Z [INFO]  sink.server: starting sink server
2019-04-28T20:37:46.456Z [INFO]  auth.handler: authentication successful, sending token to sinks
2019-04-28T20:37:46.456Z [INFO]  auth.handler: starting renewal process
2019-04-28T20:37:46.456Z [INFO]  sink.file: token written: path=/home/vault/.vault-token
2019-04-28T20:37:46.456Z [INFO]  sink.server: sink server stopped
2019-04-28T20:37:46.456Z [INFO]  sinks finished, exiting

# Then we use a port-forward to test if the template created the files with our secrets correctly
$ kubectl port-forward pod/vault-agent-example 8080:80

# As we can see here we were able to fetch our secrets
$ curl -v localhost:8080
*   Trying 127.0.0.1...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8080 (#0)
> GET / HTTP/1.1
> Host: localhost:8080
> User-Agent: curl/7.64.1
> Accept: */*
>
< HTTP/1.1 200 OK
< Server: nginx/1.15.12
< Date: Sun, 28 Apr 2019 20:47:02 GMT
< Content-Type: text/html
< Content-Length: 166
< Last-Modified: Sun, 28 Apr 2019 20:37:53 GMT
< Connection: keep-alive
< ETag: "5cc60f21-a6"
< Accept-Ranges: bytes
<
  <html>
  <body>
  <p>Some secrets:</p>
  <ul>
  <li><pre>username: appuser</pre></li>
  <li><pre>password: suP3rsec(et!</pre></li>
  </ul>

  </body>
  </html>
* Connection #0 to host localhost left intact
* Closing connection 0

```

##### **Closing notes**
This post was heavily inspired by [this doc page](https://learn.hashicorp.com/vault/identity-access-management/vault-agent-k8s), the main difference is that we have mutual TLS on, the only thing left would be to auto unseal our Vault, but we will left that for a future article or as an exercise for the reader.

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)
