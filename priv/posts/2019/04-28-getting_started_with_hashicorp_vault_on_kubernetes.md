%{
  title: "Getting started with HashiCorp Vault on Kubernetes",
  author: "Gabriel Garrido",
  description: "Exploring how to install and use Vault on Kubernetes...",
  tags: ~w(kubernetes vault linux security),
  published: true,
  image: "vault.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![vault](/images/vault.webp){:class="mx-auto"}

##### **Introduction**
Vault secures, stores, and tightly controls access to tokens, passwords, certificates, API keys, and other secrets in modern computing. What this means is that you can safely store all your App secrets in Vault without having to worry anymore how to store, provide, and use those secrets, we will see how to install it on a running kubernetes cluster and save and read a secret by our application, in this page we will be using Vault version 1.1.1, we will be using dynamic secrets, that means that each pod will have a different secret and that secret will expire once the pod is killed.
<br />

Before you start you will need [Consul](https://www.consul.io/docs/install/index.html), [Vault](https://www.vaultproject.io/docs/install/) client binaries and [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/) or any running cluster, you can find the files used here in [this repo](https://github.com/kainlite/vault-consul-tls).
<br />

This is the part one of [two](/blog/actually_using_vault_on_kubernetes)
<br />

##### **Preparing the cluster**
Let's start minikube and validate that we can reach our cluster with `minikube start` and then with `kubectl get nodes`, also the dashboard can become handy you can invoke it like this `minikube dashboard`
```elixir
$ minikube start
😄  minikube v1.0.0 on linux (amd64)
🤹  Downloading Kubernetes v1.14.0 images in the background ...
💡  Tip: Use 'minikube start -p <name>' to create a new cluster, or 'minikube delete' to delete this one.
🔄  Restarting existing virtualbox VM for "minikube" ...
⌛  Waiting for SSH access ...
📶  "minikube" IP address is 192.168.99.102
🐳  Configuring Docker as the container runtime ...
🐳  Version of container runtime is 18.06.2-ce
⌛  Waiting for image downloads to complete ...
✨  Preparing Kubernetes environment ...
🚜  Pulling images required by Kubernetes v1.14.0 ...
🔄  Relaunching Kubernetes v1.14.0 using kubeadm ... 
⌛  Waiting for pods: apiserver proxy etcd scheduler controller dns
📯  Updating kube-proxy configuration ...
🤔  Verifying component health ......
💗  kubectl is now configured to use "minikube"
🏄  Done! Thank you for using minikube!

$ kubectl get nodes
NAME       STATUS   ROLES    AGE     VERSION
minikube   Ready    master   4d20h   v1.14.0
```
<br />

##### **Creating certificates for Consul and Vault**
Vault needs a backend to store data, this backend can be consul, etcd, postgres, and [many more](https://www.vaultproject.io/docs/configuration/storage/index.html), so the first thing that we are going to do is create a certificate so consul and vault can speak to each other securely.
```elixir
$ consul tls ca create
==> Saved consul-agent-ca.pem
==> Saved consul-agent-ca-key.pem

$ consul tls cert create -server -additional-dnsname server.dc1.cluster.local
==> WARNING: Server Certificates grants authority to become a
    server and access all state in the cluster including root keys
    and all ACL tokens. Do not distribute them to production hosts
    that are not server nodes. Store them as securely as CA keys.
==> Using consul-agent-ca.pem and consul-agent-ca-key.pem
==> Saved dc1-server-consul-0.pem
==> Saved dc1-server-consul-0-key.pem

$ consul tls cert create -client
==> Using consul-agent-ca.pem and consul-agent-ca-key.pem
==> Saved dc1-client-consul-0.pem
==> Saved dc1-client-consul-0-key.pem
```
<br />

##### **Consul**
The next steps would be to create an encryption key for the consul cluster and to create all the kubernetes resources associated with it
```elixir
# Create secret for the gossip protocol
$ export GOSSIP_ENCRYPTION_KEY=$(consul keygen)

# Create kubernetes secret with the certificates and the gossip encryption key
# This will be used by all consul servers to make them able to communicate
# And also join the cluster.
$ kubectl create secret generic consul \
  --from-literal="gossip-encryption-key=${GOSSIP_ENCRYPTION_KEY}" \
  --from-file=certs/consul-agent-ca.pem \
  --from-file=certs/dc1-server-consul-0.pem \
  --from-file=certs/dc1-server-consul-0-key.pem
secret/consul created

# Store the configuration as a configmap
$ kubectl create configmap consul --from-file=consul/config.json
configmap/consul created

# Create a service so the pods can see each other
$ kubectl create -f consul/01-service.yaml
service/consul created

# Create the consul pods
$ kubectl create -f consul/02-statefulset.yaml
statefulset.apps/consul created

# To be test consul we need to port-forward the port 8500 to our computer
$ kubectl port-forward consul-1 8500:8500

# Then we can validate that all the consul members are alive and well
$ consul members
Node      Address          Status  Type    Build  Protocol  DC   Segment
consul-0  172.17.0.5:8301  alive   server  1.4.4  2         dc1  <all>
consul-1  172.17.0.6:8301  alive   server  1.4.4  2         dc1  <all>
consul-2  172.17.0.7:8301  alive   server  1.4.4  2         dc1  <all>
```
<br />

##### **Vault**
Once we have Consul running starting vault should be straight forward, we need to create all kubernetes resources associated with it and then initialize and unseal the vault.
```elixir
# Store the certs for vault
$ kubectl create secret generic vault \
    --from-file=certs/consul-agent-ca.pem \
    --from-file=certs/dc1-client-consul-0.pem \
    --from-file=certs/dc1-client-consul-0-key.pem
secret/vault created

# Store the config as a configmap
$ kubectl create configmap vault --from-file=vault/config.json
configmap/vault created

# Create the service
$ kubectl create -f vault/01-service.yaml
service/vault created

# And the deployment
$ kubectl create -f vault/02-deployment.yaml
deployment.extensions/vault created

# To be able to initialize and use the vault we need to use that port-forward.
$ kubectl port-forward vault-6d78b6df7c-z7chq 8200:8200
$ export VAULT_ADDR=https://127.0.0.1:8200
$ export VAULT_CACERT="certs/consul-agent-ca.pem"

# Initialize the vault, here we define that we need 3 shares and 3 keys to unseal
# In a production environment those keys should be separated and only known by the
# responsibles of vault.
$ vault operator init -key-shares=3 -key-threshold=3

vault operator init -key-shares=3 -key-threshold=3
Unseal Key 1: 8I3HkpLoujn+fAdXHCRJYGJEw0WpvamnzTNu5IGyTcWB
Unseal Key 2: I65GU6xRt+ZX+QigBjCHRyht8pvIOShpU5TL8iLGhr6g
Unseal Key 3: n+Kv2qrDNiIELEy3dEMfUpD/c8EtnwpJCYIn88TrS3Pg

Initial Root Token: s.3pEYBZqlzvDpImB988GyAsuf

Vault initialized with 3 key shares and a key threshold of 3. Please securely
distribute the key shares printed above. When the Vault is re-sealed,
restarted, or stopped, you must supply at least 3 of these keys to unseal it
before it can start servicing requests.

Vault does not store the generated master key. Without at least 3 key to
reconstruct the master key, Vault will remain permanently sealed!

It is possible to generate new unseal keys, provided you have a quorum of
existing unseal keys shares. See "vault operator rekey" for more information.

# To unseal the vault we need to repeat this process with the 3 keys that we got in the previous step
$ vault operator unseal
Unseal Key (will be hidden):
Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             true
Total Shares       3
Threshold          3
Unseal Progress    1/3
Unseal Nonce       e9bb1681-ba71-b90d-95f6-8e68389e934b
Version            1.1.1
HA Enabled         true

# Then we login with the initial root token 
$ vault login
Token (will be hidden):
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.3pEYBZqlzvDpImB988GyAsuf
token_accessor       w3W3Kw2GWflF9L59C4Itn6cZ
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]

# We enable the /secrets path with the plugin kv
$ vault secrets enable -path=secrets kv
Success! Enabled the kv secrets engine at: secrets/

# And finally test storing a secret there
$ vault kv put secrets/hello foo=world
Success! Data written to: secrets/hello

# Then we validate that we can read it as well
$ vault kv get secrets/hello
=== Data ===
Key    Value
---    -----
foo    world
```
<br />

##### **Closing notes**
As you can see it takes a while to configure a Vault server but I really like the pattern that renders for the apps using it, in the next post we will see how to unlock it automatically with kubernetes and also how to mount the secrets automatically to our pods so our applications can use it :), this post was heavily inspired by [this one](https://testdriven.io/blog/running-vault-and-consul-on-kubernetes/) and [this one](https://learn.hashicorp.com/consul/advanced/day-1-operations/certificates#configuring-agents).
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Probando HashiCorp Vault en Kubernetes",
  author: "Gabriel Garrido",
  description: "En este articulo vemos como instalar y usar Vault en kubernetes...",
  tags: ~w(kubernetes vault linux security),
  published: true,
  image: "vault.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![vault](/images/vault.webp){:class="mx-auto"}

##### **Introducción**
Vault asegura, almacena y controla de manera estricta el acceso a tokens, contraseñas, certificados, claves API y otros secretos en la informática moderna. Esto significa que podés almacenar de forma segura todos los secretos de tu aplicación en Vault sin preocuparte más por cómo almacenarlos, proporcionarlos y utilizarlos. Vamos a ver cómo instalar Vault en un clúster de Kubernetes en ejecución, y cómo guardar y leer un secreto por parte de nuestra aplicación. En esta guía, usaremos Vault versión 1.1.1 con **secretos dinámicos**, lo que significa que cada pod tendrá un secreto diferente, y ese secreto expirará cuando se elimine el pod.
<br />

Antes de comenzar, necesitás los binarios cliente de [Consul](https://www.consul.io/docs/install/index.html) y [Vault](https://www.vaultproject.io/docs/install/), así como [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/) o cualquier clúster en funcionamiento. Los archivos utilizados se encuentran en [este repo](https://github.com/kainlite/vault-consul-tls).
<br />

Este es el primer artículo de dos en la serie [Uso de Vault en Kubernetes](/blog/actually_using_vault_on_kubernetes).
<br />

##### **Preparando el clúster**
Primero, iniciamos Minikube y validamos que podemos acceder al clúster con `minikube start` y `kubectl get nodes`. También puede ser útil iniciar el dashboard de Minikube con `minikube dashboard`.
```elixir
$ minikube start
$ kubectl get nodes
```
<br />

##### **Creando certificados para Consul y Vault**
Vault necesita un backend para almacenar datos, que puede ser Consul, etcd, Postgres, y [muchos otros](https://www.vaultproject.io/docs/configuration/storage/index.html). Lo primero que vamos a hacer es crear un certificado para que Consul y Vault se comuniquen de forma segura.
```elixir
$ consul tls ca create
$ consul tls cert create -server -additional-dnsname server.dc1.cluster.local
$ consul tls cert create -client
```
<br />

##### **Consul**
Los siguientes pasos son crear una clave de cifrado para el clúster de Consul y luego crear los recursos de Kubernetes asociados.
```elixir
$ export GOSSIP_ENCRYPTION_KEY=$(consul keygen)
$ kubectl create secret generic consul \
  --from-literal="gossip-encryption-key=${GOSSIP_ENCRYPTION_KEY}" \
  --from-file=certs/consul-agent-ca.pem \
  --from-file=certs/dc1-server-consul-0.pem \
  --from-file=certs/dc1-server-consul-0-key.pem

$ kubectl create configmap consul --from-file=consul/config.json
$ kubectl create -f consul/01-service.yaml
$ kubectl create -f consul/02-statefulset.yaml
$ kubectl port-forward consul-1 8500:8500
$ consul members
```
<br />

##### **Vault**
Con Consul en funcionamiento, ahora podemos desplegar Vault, crear los recursos necesarios en Kubernetes y luego inicializar y desbloquear Vault.
```elixir
$ kubectl create secret generic vault \
    --from-file=certs/consul-agent-ca.pem \
    --from-file=certs/dc1-client-consul-0.pem \
    --from-file=certs/dc1-client-consul-0-key.pem

$ kubectl create configmap vault --from-file=vault/config.json
$ kubectl create -f vault/01-service.yaml
$ kubectl create -f vault/02-deployment.yaml
$ kubectl port-forward vault-6d78b6df7c-z7chq 8200:8200
$ export VAULT_ADDR=https://127.0.0.1:8200
$ export VAULT_CACERT="certs/consul-agent-ca.pem"
$ vault operator init -key-shares=3 -key-threshold=3
```
Luego de inicializar, debemos desbloquear Vault:
```elixir
$ vault operator unseal
```
Iniciar sesión con el token raíz inicial:
```elixir
$ vault login
```
Habilitamos el camino `/secrets` con el plugin `kv` y luego probamos guardar y leer un secreto:
```elixir
$ vault secrets enable -path=secrets kv
$ vault kv put secrets/hello foo=world
$ vault kv get secrets/hello
```
<br />

##### **Conclusión**
Como se puede ver, lleva un tiempo configurar un servidor Vault, pero me gusta mucho el patrón que permite para las aplicaciones que lo utilizan. En el próximo artículo, veremos cómo desbloquearlo automáticamente con Kubernetes y cómo montar los secretos automáticamente en nuestros pods para que nuestras aplicaciones puedan usarlos.

Este artículo fue fuertemente inspirado por [este](https://testdriven.io/blog/running-vault-and-consul-on-kubernetes/) y [este](https://learn.hashicorp.com/consul/advanced/day-1-operations/certificates#configuring-agents).
<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo corrija.

<br />
