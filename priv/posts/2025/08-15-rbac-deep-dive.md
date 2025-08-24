%{
  title: "Kubernetes RBAC deep dive: Understanding authorization with kubectl and curl",
  author: "Gabriel Garrido", 
  description: "In this article we will explore how RBAC works in kubernetes at the API level, using both kubectl and raw HTTP calls to understand what's happening under the hood",
  tags: ~w(kubernetes linux security rbac api),
  published: true,
  image: "kubernetes-cluster-architecture.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![kubernetes](/images/kubernetes-cluster-architecture.png){:class="mx-auto"}

#### Introduction
In this article we will explore how RBAC (Role-Based Access Control) works in Kubernetes, not just from the kubectl perspective, but by diving deep into the actual HTTP API calls that happen behind the scenes. We'll see what kubectl is really doing when you create roles, role bindings, and check permissions.

This post aims to demistify the Kubernetes API and also give you a better understanding of how to interact with it by using RBAC. This not only will give us a very good understanding of how Kubernetes APIs work, but it will also open the possibility to build any tool or process that you need using the Kubernetes APIs.

<br />

If you read my previous article on [Kubernetes authentication and authorization](/blog/kubernetes_authentication_and_authorization), you know that authentication is about proving who you are, while authorization is about what you're allowed to do. RBAC is Kubernetes' primary authorization mechanism, and understanding how it works at the API level will make you much more effective at debugging permission issues.

<br />

**RBAC Basics**:

RBAC in Kubernetes consists of three main components:
* **Roles/ClusterRoles**: Define what actions can be performed on which resources
* **Subjects**: Users, groups, or service accounts that need permissions  
* **RoleBindings/ClusterRoleBindings**: Connect roles to subjects

<br />

The key difference between Role/RoleBinding and ClusterRole/ClusterRoleBinding is scope:
* Role/RoleBinding: Namespaced (permissions within a specific namespace)
* ClusterRole/ClusterRoleBinding: Cluster-wide (permissions across all namespaces or cluster-scoped resources)

<br />

So we are going to create some RBAC resources, test them with kubectl, and then see exactly what HTTP requests are being made to the Kubernetes API server. This will give you a much deeper understanding of how RBAC actually works.

<br />

#### Let's get to it
Let's start by setting up our testing environment. I'll create a namespace, some roles, and users, then show you both the kubectl commands and the equivalent curl calls, either use kubectl or curl as both will be equivalent.

<br />

**Setup our environment**:

First, we need to find out the public ip of our API server:
```
kubectl get ep -A
NAMESPACE     NAME         ENDPOINTS                                               AGE
default       kubernetes   172.19.0.2:6443                                         78m
kube-system   kube-dns     10.244.0.3:53,10.244.0.4:53,10.244.0.3:53 + 3 more...   78m
```
if you instead use kubectl proxy, that will use your current credentials and will sort-of bypass the authentication when using curl, so stick to hitting the URL directly for all the examples to work as expected.

First, let's create a namespace for our experiments:
```elixir
kubectl create namespace rbac-demo
```

<br />

Now let's see what this actually does at the API level. Enable kubectl verbose mode to see the HTTP calls:
```elixir
kubectl create namespace rbac-demo -v=8
```

<br />

You'll see output like this (truncated for readability):
```elixir
I0110 10:30:15.123456 POST https://127.0.0.1:6443/api/v1/namespaces
I0110 10:30:15.123456 Request Body: {"apiVersion":"v1","kind":"Namespace","metadata":{"name":"rbac-demo"}}
I0110 10:30:15.123456 Response Status: 201 Created
```

<br />

Now let's do the same thing with curl to understand the raw API call:
```elixir
# Get your cluster info
kubectl cluster-info

# Get your token (this will vary based on your setup)
TOKEN=$(kubectl get secret $(kubectl get serviceaccount default -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 -d)

# Make the API call
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/api/v1/namespaces \
  -d '{
    "apiVersion": "v1",
    "kind": "Namespace", 
    "metadata": {
      "name": "rbac-demo-curl"
    }
  }'
```

<br />

The response will be a JSON representation of the created namespace. This is exactly what kubectl does behind the scenes!

<br />

#### Creating RBAC Resources

Now let's create a Role that allows reading pods in our namespace:

```elixir
kubectl create role pod-reader \
  --namespace=rbac-demo \
  --verb=get,list,watch \
  --resource=pods
```

<br />

Let's see the actual YAML that was created:
```elixir
kubectl get role pod-reader -n rbac-demo -o yaml
```

<br />

The output should look like this:
```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: rbac-demo
  resourceVersion: "12345"
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
  - watch
```

<br />

Now let's make the same call with curl to see the raw HTTP request:
```elixir
# First, let's see what kubectl would send
kubectl create role pod-reader-curl \
  --namespace=rbac-demo \
  --verb=get,list,watch \
  --resource=pods \
  --dry-run=client -o json
```

<br />

This shows us the exact JSON payload. Now let's send it via curl:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "pod-reader-curl",
      "namespace": "rbac-demo"
    },
    "rules": [
      {
        "apiGroups": [""],
        "resources": ["pods"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

<br />

Notice the API path: `/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles`. This tells us:
* We're using the RBAC API group (`rbac.authorization.k8s.io`)
* Version v1
* It's namespaced (includes `/namespaces/rbac-demo`)
* We're working with roles

<br />

#### Creating a RoleBinding

Now let's create a RoleBinding to give a user the pod-reader role:
```elixir
kubectl create rolebinding pod-reader-binding \
  --namespace=rbac-demo \
  --role=pod-reader \
  --user=john.doe@example.com
```

NOTE: creating users can be a bit tricky as we need a certificate and so on, you can read more [here](https://kubernetes.io/docs/reference/access-authn-authz/authentication/), there are plenty of examples in how to create one manually out there, this is also a bit different with cloud offerings, but the Kubernetes mechanics are basically the same.

<br />

Let's inspect what was created:
```elixir
kubectl get rolebinding pod-reader-binding -n rbac-demo -o yaml
```

<br />

The output shows:
```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: rbac-demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: john.doe@example.com
```

<br />

Now the curl equivalent:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/rolebindings \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "RoleBinding",
    "metadata": {
      "name": "pod-reader-binding-curl",
      "namespace": "rbac-demo"
    },
    "roleRef": {
      "apiGroup": "rbac.authorization.k8s.io",
      "kind": "Role",
      "name": "pod-reader"
    },
    "subjects": [
      {
        "apiGroup": "rbac.authorization.k8s.io",
        "kind": "User",
        "name": "john.doe@example.com"
      }
    ]
  }'
```

<br />

#### Checking Permissions

Now let's test permissions. Kubernetes provides a handy API for this - the SubjectAccessReview:
```elixir
kubectl auth can-i get pods --namespace=rbac-demo --as=john.doe@example.com
```

<br />

This should return `yes` since we just gave john.doe@example.com the pod-reader role. But what's happening behind the scenes? Let's use curl to make the same check:

```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/authorization.k8s.io/v1/subjectaccessreviews \
  -d '{
    "apiVersion": "authorization.k8s.io/v1",
    "kind": "SubjectAccessReview",
    "spec": {
      "resourceAttributes": {
        "namespace": "rbac-demo",
        "verb": "get",
        "resource": "pods"
      },
      "user": "john.doe@example.com"
    }
  }'
```

<br />

The response will look like:
```elixir
{
  "apiVersion": "authorization.k8s.io/v1",
  "kind": "SubjectAccessReview",
  "metadata": {
  },
  "spec": {
    "resourceAttributes": {
      "namespace": "rbac-demo",
      "resource": "pods",
      "verb": "get"
    },
    "user": "john.doe@example.com"
  },
  "status": {
    "allowed": true,
    "reason": "RBAC: allowed by RoleBinding \"pod-reader-binding/rbac-demo\" of Role \"pod-reader\" to User \"john.doe@example.com\""
  }
}
```

<br />

This is incredibly useful! The response not only tells us if the action is allowed (`"allowed": true`) but also explains exactly why (`reason` field).

<br />

Let's test a permission that should be denied:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/authorization.k8s.io/v1/subjectaccessreviews \
  -d '{
    "apiVersion": "authorization.k8s.io/v1",
    "kind": "SubjectAccessReview",
    "spec": {
      "resourceAttributes": {
        "namespace": "rbac-demo",
        "verb": "delete",
        "resource": "pods"
      },
      "user": "john.doe@example.com"
    }
  }'
```

<br />

The response will show:
```elixir
{
  "status": {
    "allowed": false,
    "reason": "RBAC: access denied"
  }
}
```

<br />

#### ClusterRole and ClusterRoleBinding Example

Let's create a ClusterRole that can read nodes (a cluster-scoped resource):
```elixir
kubectl create clusterrole node-reader --verb=get,list,watch --resource=nodes
```

<br />

The curl equivalent (notice no namespace in the URL since it's cluster-scoped):
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/clusterroles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "ClusterRole",
    "metadata": {
      "name": "node-reader-curl"
    },
    "rules": [
      {
        "apiGroups": [""],
        "resources": ["nodes"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

<br />

Now bind it to a user:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/clusterrolebindings \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "ClusterRoleBinding",
    "metadata": {
      "name": "node-reader-binding-curl"
    },
    "roleRef": {
      "apiGroup": "rbac.authorization.k8s.io",
      "kind": "ClusterRole",
      "name": "node-reader-curl"
    },
    "subjects": [
      {
        "apiGroup": "rbac.authorization.k8s.io",
        "kind": "User",
        "name": "admin@example.com"
      }
    ]
  }'
```

<br />

#### Debugging RBAC Issues

One of the most powerful features for debugging RBAC is the ability to check permissions for any user. Let's create a comprehensive script to audit permissions:

```elixir
#!/bin/bash
# rbac-check.sh

USER=$1
NAMESPACE=${2:-"default"}

if [ -z "$USER" ]; then
  echo "Usage: $0 <user> [namespace]"
  exit 1
fi

echo "Checking permissions for user: $USER in namespace: $NAMESPACE"
echo "=================================================="

# Common resources to check
RESOURCES=("pods" "services" "deployments" "configmaps" "secrets")
VERBS=("get" "list" "watch" "create" "update" "patch" "delete")

for resource in "${RESOURCES[@]}"; do
  echo "Resource: $resource"
  for verb in "${VERBS[@]}"; do
    result=$(kubectl auth can-i $verb $resource --namespace=$NAMESPACE --as=$USER)
    printf "  %-8s: %s\n" "$verb" "$result"
  done
  echo ""
done
```

<br />

#### Advanced RBAC Features

Let's explore some advanced RBAC features using both kubectl and curl:

**Resource Names**: You can restrict access to specific named resources:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "specific-pod-reader",
      "namespace": "rbac-demo"
    },
    "rules": [
      {
        "apiGroups": [""],
        "resources": ["pods"],
        "resourceNames": ["my-specific-pod"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

<br />

**API Groups**: Different resources belong to different API groups:
```elixir
# Core API group (empty string) - pods, services, etc.
# apps API group - deployments, replicasets, etc.
# extensions API group - ingresses, etc.

curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "deployment-manager",
      "namespace": "rbac-demo"
    },
    "rules": [
      {
        "apiGroups": ["apps"],
        "resources": ["deployments"],
        "verbs": ["get", "list", "watch", "create", "update", "patch", "delete"]
      }
    ]
  }'
```

<br />

#### Inspecting Existing RBAC

To understand what permissions exist in your cluster, you can query the API directly:

```elixir
# List all roles in a namespace
curl -k -H "Authorization: Bearer $TOKEN" \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles

# List all rolebindings in a namespace
curl -k -H "Authorization: Bearer $TOKEN" \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/rolebindings

# List all clusterroles
curl -k -H "Authorization: Bearer $TOKEN" \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/clusterroles

# List all clusterrolebindings
curl -k -H "Authorization: Bearer $TOKEN" \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/clusterrolebindings
```

<br />

You can also use jq to filter and format the output:
```elixir
# Get all rolebindings and show which users have which roles
curl -s -k -H "Authorization: Bearer $TOKEN" \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/rolebindings | \
  jq -r '.items[] | "\(.metadata.name): \(.subjects[]?.name) -> \(.roleRef.name)"'
```

<br />

#### Testing with a Real User

Let's create a service account and test our RBAC rules:
```elixir
kubectl create serviceaccount test-user -n rbac-demo

# Bind our pod-reader role to this service account
kubectl create rolebinding test-user-binding \
  --namespace=rbac-demo \
  --role=pod-reader \
  --serviceaccount=rbac-demo:test-user

# Special secret to generate a token for the service account
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: test-user-sa-secret
  namespace: rbac-demo
  annotations:
    kubernetes.io/service-account.name: test-user
type: kubernetes.io/service-account-token
EOF
```

<br />

Now let's get the service account token and test permissions:
```elixir
# Get the service account token
SA_TOKEN=$(kubectl get secret test-user-sa-secret -n rbac-demo -o jsonpath='{.data.token}' | base64 -d)

# Test if we can list pods using the service account token
curl -k -H "Authorization: Bearer $SA_TOKEN" \
  https://172.19.0.2:6443/api/v1/namespaces/rbac-demo/pods
```

<br />

This should work since we gave the service account the pod-reader role. Now let's try something it shouldn't be able to do:
```elixir
# Try to create a pod (should fail)
curl -k -H "Authorization: Bearer $SA_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/api/v1/namespaces/rbac-demo/pods \
  -d '{
    "apiVersion": "v1",
    "kind": "Pod",
    "metadata": {
      "name": "test-pod"
    },
    "spec": {
      "containers": [
        {
          "name": "test",
          "image": "nginx"
        }
      ]
    }
  }'
```

<br />

This should return a 403 Forbidden error with a message like:
```elixir
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "pods is forbidden: User \"system:serviceaccount:rbac-demo:test-user\" cannot create resource \"pods\" in API group \"\" in the namespace \"rbac-demo\"",
  "reason": "Forbidden",
  "details": {
    "kind": "pods"
  },
  "code": 403
}
```

<br />

Perfect! The RBAC is working as expected.

<br />

#### Common RBAC Patterns

Here are some common RBAC patterns you'll encounter:

**Read-only access to everything in a namespace**:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "namespace-reader",
      "namespace": "rbac-demo"
    },
    "rules": [
      {
        "apiGroups": ["*"],
        "resources": ["*"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

<br />

**Access to create and manage deployments**:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "deployment-manager",
      "namespace": "rbac-demo"
    },
    "rules": [
      {
        "apiGroups": ["apps"],
        "resources": ["deployments"],
        "verbs": ["*"]
      },
      {
        "apiGroups": [""],
        "resources": ["pods"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

<br />

#### Troubleshooting RBAC

When RBAC isn't working as expected, here's a systematic approach to debug:

1. **Check if the user/service account exists**:
```elixir
kubectl get serviceaccount test-user -n rbac-demo
```

2. **Check what roles are bound to the user**:
```elixir
kubectl get rolebindings -n rbac-demo -o wide
kubectl get clusterrolebindings -o wide
```

3. **Use SubjectAccessReview to test specific permissions**:
```elixir
kubectl auth can-i create pods --namespace=rbac-demo --as=system:serviceaccount:rbac-demo:test-user
```

4. **Check the exact error message from the API**:
The error messages are usually very specific about what's missing.

5. **Verify the role rules**:
```elixir
kubectl describe role pod-reader -n rbac-demo
```

<br />

#### Clean up
Always remember to clean up your testing resources:
```elixir
kubectl delete namespace rbac-demo
```

<br />

Or with curl:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -X DELETE \
  https://172.19.0.2:6443/api/v1/namespaces/rbac-demo
```

<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

<br />

You can read more about RBAC [here](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) and about the Kubernetes API [here](https://kubernetes.io/docs/concepts/overview/kubernetes-api/).

<br />
---lang---
%{
  title: "Kubernetes RBAC a fondo: Entendiendo autorización con kubectl y curl",
  author: "Gabriel Garrido", 
  description: "En este artículo exploraremos cómo funciona RBAC en kubernetes a nivel de API, usando tanto kubectl como llamadas HTTP directas para entender qué pasa por debajo",
  tags: ~w(kubernetes linux security rbac api),
  published: true,
  image: "kubernetes-cluster-architecture.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![kubernetes](/images/kubernetes-cluster-architecture.png){:class="mx-auto"}

#### Introducción
En este artículo vamos a explorar cómo funciona RBAC (Control de Acceso Basado en Roles) en Kubernetes, no solo desde la perspectiva de kubectl, sino profundizando en las llamadas HTTP reales que suceden detrás de escena. Vamos a ver qué hace realmente kubectl cuando creás roles, role bindings y verificás permisos.

La idea de este articulo es desmitificar la API de Kubernetes mientras vemos como funciona RBAC, esto no solo nos va a dar la posibilidad de entender y manejar mejor los permisos en el cluster si no que construir cualquier herramienta o interaccion que necesitemos en Kubernetes usando sus APIs.

<br />

Si leíste mi artículo anterior sobre [autenticación y autorización en Kubernetes](/blog/kubernetes_authentication_and_authorization), ya sabés que la autenticación es sobre probar quién sos, mientras que la autorización es sobre qué se te permite hacer. RBAC es el mecanismo principal de autorización de Kubernetes, y entender cómo funciona a nivel de API te va a hacer mucho más efectivo para debugear problemas de permisos.

<br />

**RBAC Básico**:

RBAC en Kubernetes consiste de tres componentes principales:
* **Roles/ClusterRoles**: Definen qué acciones se pueden realizar en qué recursos
* **Subjects**: Usuarios, grupos o service accounts que necesitan permisos
* **RoleBindings/ClusterRoleBindings**: Conectan roles con subjects

<br />

La diferencia clave entre Role/RoleBinding y ClusterRole/ClusterRoleBinding es el alcance:
* Role/RoleBinding: Con namespace (permisos dentro de un namespace específico)
* ClusterRole/ClusterRoleBinding: A nivel de cluster (permisos en todos los namespaces o recursos de nivel cluster)

<br />

Así que vamos a crear algunos recursos RBAC, probarlos con kubectl, y después ver exactamente qué requests HTTP se están haciendo al servidor de API de Kubernetes. Esto te va a dar un entendimiento mucho más profundo de cómo realmente funciona RBAC.

<br />

#### Vamos al grano
Empecemos configurando nuestro entorno de testing. Voy a crear un namespace, algunos roles y usuarios, después te muestro tanto los comandos kubectl como las llamadas curl equivalentes.

<br />

**Configurando nuestro entorno**:

Primero necesitamos encontrar la direccion publica de nuestro API server:
```
kubectl get ep -A
NAMESPACE     NAME         ENDPOINTS                                               AGE
default       kubernetes   172.19.0.2:6443                                         78m
kube-system   kube-dns     10.244.0.3:53,10.244.0.4:53,10.244.0.3:53 + 3 more...   78m
```
Si en vez usamos kubectl proxy, va a usar las credenciales que usa kubectl e ignorar las que le pasemos con curl, asi que para que todos los ejemplos funcionen como se muestra hay que usar la direccion directa del API server.

Primero, vamos a crear un namespace para nuestros experimentos:
```elixir
kubectl create namespace rbac-demo
```

<br />

Ahora veamos qué hace esto realmente a nivel de API. Habilitá el modo verbose de kubectl para ver las llamadas HTTP:
```elixir
kubectl create namespace rbac-demo -v=8
```

<br />

Vas a ver output como este (truncado para legibilidad):
```elixir
I0110 10:30:15.123456 POST https://127.0.0.1:6443/api/v1/namespaces
I0110 10:30:15.123456 Request Body: {"apiVersion":"v1","kind":"Namespace","metadata":{"name":"rbac-demo"}}
I0110 10:30:15.123456 Response Status: 201 Created
```

<br />

Ahora hagamos lo mismo con curl para entender la llamada de API cruda:
```elixir
# Obtener info del cluster
kubectl cluster-info

# Obtener tu token (esto va a variar según tu configuración)
TOKEN=$(kubectl get secret $(kubectl get serviceaccount default -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 -d)

# Hacer la llamada de API
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/api/v1/namespaces \
  -d '{
    "apiVersion": "v1",
    "kind": "Namespace", 
    "metadata": {
      "name": "rbac-demo-curl"
    }
  }'
```

<br />

La respuesta va a ser una representación JSON del namespace creado. ¡Esto es exactamente lo que hace kubectl por detrás!

<br />

#### Creando Recursos RBAC

Ahora vamos a crear un Role que permita leer pods en nuestro namespace:

```elixir
kubectl create role pod-reader \
  --namespace=rbac-demo \
  --verb=get,list,watch \
  --resource=pods
```

<br />

Veamos el YAML real que se creó:
```elixir
kubectl get role pod-reader -n rbac-demo -o yaml
```

<br />

El output debería verse así:
```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: rbac-demo
  resourceVersion: "12345"
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
  - watch
```

<br />

Ahora hagamos la misma llamada con curl para ver el request HTTP crudo:
```elixir
# Primero, veamos qué enviaría kubectl
kubectl create role pod-reader-curl \
  --namespace=rbac-demo \
  --verb=get,list,watch \
  --resource=pods \
  --dry-run=client -o json
```

<br />

Esto nos muestra el payload JSON exacto. Ahora enviémoslo vía curl:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "pod-reader-curl",
      "namespace": "rbac-demo"
    },
    "rules": [
      {
        "apiGroups": [""],
        "resources": ["pods"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

<br />

Notá el path de API: `/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles`. Esto nos dice:
* Estamos usando el API group de RBAC (`rbac.authorization.k8s.io`)
* Versión v1
* Está namespacead (incluye `/namespaces/rbac-demo`)
* Estamos trabajando con roles

<br />

#### Creando un RoleBinding

Ahora vamos a crear un RoleBinding para darle a un usuario el role pod-reader:
```elixir
kubectl create rolebinding pod-reader-binding \
  --namespace=rbac-demo \
  --role=pod-reader \
  --user=john.doe@example.com
```

NOTA: Crear usuarios es un poco complicado por que necesitamos un certificado, etc, podes leer mas [aca](https://kubernetes.io/docs/reference/access-authn-authz/authentication/), hay muchos ejemplos de como crear un usuario manualmente, esto tambien funciona un poco distinto en los proveedores cloud pero las mecanicas de Kubernetes son basicamente las mismas.

<br />

Inspeccionemos qué se creó:
```elixir
kubectl get rolebinding pod-reader-binding -n rbac-demo -o yaml
```

<br />

El output muestra:
```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: rbac-demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: john.doe@example.com
```

<br />

Ahora el equivalente en curl:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/rolebindings \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "RoleBinding",
    "metadata": {
      "name": "pod-reader-binding-curl",
      "namespace": "rbac-demo"
    },
    "roleRef": {
      "apiGroup": "rbac.authorization.k8s.io",
      "kind": "Role",
      "name": "pod-reader"
    },
    "subjects": [
      {
        "apiGroup": "rbac.authorization.k8s.io",
        "kind": "User",
        "name": "john.doe@example.com"
      }
    ]
  }'
```

<br />

#### Verificando Permisos

Ahora testeemos permisos. Kubernetes proporciona una API muy útil para esto - el SubjectAccessReview:
```elixir
kubectl auth can-i get pods --namespace=rbac-demo --as=john.doe@example.com
```

<br />

Esto debería retornar `yes` ya que recién le dimos a john.doe@example.com el role pod-reader. ¿Pero qué está pasando por detrás? Usemos curl para hacer la misma verificación:

```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/authorization.k8s.io/v1/subjectaccessreviews \
  -d '{
    "apiVersion": "authorization.k8s.io/v1",
    "kind": "SubjectAccessReview",
    "spec": {
      "resourceAttributes": {
        "namespace": "rbac-demo",
        "verb": "get",
        "resource": "pods"
      },
      "user": "john.doe@example.com"
    }
  }'
```

<br />

La respuesta se va a ver así:
```elixir
{
  "apiVersion": "authorization.k8s.io/v1",
  "kind": "SubjectAccessReview",
  "metadata": {
  },
  "spec": {
    "resourceAttributes": {
      "namespace": "rbac-demo",
      "resource": "pods",
      "verb": "get"
    },
    "user": "john.doe@example.com"
  },
  "status": {
    "allowed": true,
    "reason": "RBAC: allowed by RoleBinding \"pod-reader-binding/rbac-demo\" of Role \"pod-reader\" to User \"john.doe@example.com\""
  }
}
```

<br />

¡Esto es increíblemente útil! La respuesta no solo nos dice si la acción está permitida (`"allowed": true`) sino que también explica exactamente por qué (campo `reason`).

<br />

Testeemos un permiso que debería ser denegado:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/authorization.k8s.io/v1/subjectaccessreviews \
  -d '{
    "apiVersion": "authorization.k8s.io/v1",
    "kind": "SubjectAccessReview",
    "spec": {
      "resourceAttributes": {
        "namespace": "rbac-demo",
        "verb": "delete",
        "resource": "pods"
      },
      "user": "john.doe@example.com"
    }
  }'
```

<br />

La respuesta va a mostrar:
```elixir
{
  "status": {
    "allowed": false,
    "reason": "RBAC: access denied"
  }
}
```

<br />

#### Ejemplo de ClusterRole y ClusterRoleBinding

Vamos a crear un ClusterRole que pueda leer nodes (un recurso de nivel cluster):
```elixir
kubectl create clusterrole node-reader --verb=get,list,watch --resource=nodes
```

<br />

El equivalente en curl (notá que no hay namespace en la URL ya que es de nivel cluster):
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/clusterroles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "ClusterRole",
    "metadata": {
      "name": "node-reader-curl"
    },
    "rules": [
      {
        "apiGroups": [""],
        "resources": ["nodes"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

<br />

Ahora vinculémoslo a un usuario:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/clusterrolebindings \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "ClusterRoleBinding",
    "metadata": {
      "name": "node-reader-binding-curl"
    },
    "roleRef": {
      "apiGroup": "rbac.authorization.k8s.io",
      "kind": "ClusterRole",
      "name": "node-reader-curl"
    },
    "subjects": [
      {
        "apiGroup": "rbac.authorization.k8s.io",
        "kind": "User",
        "name": "admin@example.com"
      }
    ]
  }'
```

<br />

#### Debugeando Problemas de RBAC

Una de las características más poderosas para debugear RBAC es la habilidad de verificar permisos para cualquier usuario. Creemos un script comprensivo para auditar permisos:

```elixir
#!/bin/bash
# rbac-check.sh

USER=$1
NAMESPACE=${2:-"default"}

if [ -z "$USER" ]; then
  echo "Usage: $0 <user> [namespace]"
  exit 1
fi

echo "Verificando permisos para usuario: $USER en namespace: $NAMESPACE"
echo "=================================================="

# Recursos comunes para verificar
RESOURCES=("pods" "services" "deployments" "configmaps" "secrets")
VERBS=("get" "list" "watch" "create" "update" "patch" "delete")

for resource in "${RESOURCES[@]}"; do
  echo "Recurso: $resource"
  for verb in "${VERBS[@]}"; do
    result=$(kubectl auth can-i $verb $resource --namespace=$NAMESPACE --as=$USER)
    printf "  %-8s: %s\n" "$verb" "$result"
  done
  echo ""
done
```

<br />

#### Características Avanzadas de RBAC

Exploremos algunas características avanzadas de RBAC usando tanto kubectl como curl:

**Resource Names**: Podés restringir acceso a recursos nombrados específicos:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "specific-pod-reader",
      "namespace": "rbac-demo"
    },
    "rules": [
      {
        "apiGroups": [""],
        "resources": ["pods"],
        "resourceNames": ["my-specific-pod"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

<br />

**API Groups**: Diferentes recursos pertenecen a diferentes API groups:
```elixir
# Core API group (string vacío) - pods, services, etc.
# apps API group - deployments, replicasets, etc.
# extensions API group - ingresses, etc.

curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "deployment-manager",
      "namespace": "rbac-demo"
    },
    "rules": [
      {
        "apiGroups": ["apps"],
        "resources": ["deployments"],
        "verbs": ["get", "list", "watch", "create", "update", "patch", "delete"]
      }
    ]
  }'
```

<br />

#### Inspeccionando RBAC Existente

Para entender qué permisos existen en tu cluster, podés consultar la API directamente:

```elixir
# Listar todos los roles en un namespace
curl -k -H "Authorization: Bearer $TOKEN" \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles

# Listar todos los rolebindings en un namespace
curl -k -H "Authorization: Bearer $TOKEN" \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/rolebindings

# Listar todos los clusterroles
curl -k -H "Authorization: Bearer $TOKEN" \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/clusterroles

# Listar todos los clusterrolebindings
curl -k -H "Authorization: Bearer $TOKEN" \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/clusterrolebindings
```

<br />

También podés usar jq para filtrar y formatear el output:
```elixir
# Obtener todos los rolebindings y mostrar qué usuarios tienen qué roles
curl -s -k -H "Authorization: Bearer $TOKEN" \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/rolebindings | \
  jq -r '.items[] | "\(.metadata.name): \(.subjects[]?.name) -> \(.roleRef.name)"'
```

<br />

#### Testeando con un Usuario Real

Vamos a crear un service account y testear nuestras reglas RBAC:
```elixir
kubectl create serviceaccount test-user -n rbac-demo

# Vincular nuestro role pod-reader a este service account
kubectl create rolebinding test-user-binding \
  --namespace=rbac-demo \
  --role=pod-reader \
  --serviceaccount=rbac-demo:test-user

# Secreto especial que se usa para crear el token de este service account
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: test-user-sa-secret
  namespace: rbac-demo
  annotations:
    kubernetes.io/service-account.name: test-user
type: kubernetes.io/service-account-token
EOF

```

<br />

Ahora obtengamos el token del service account y testeemos permisos:
```elixir
# Obtener el token del service account
SA_TOKEN=$(kubectl get secret $(kubectl get serviceaccount test-user -n rbac-demo -o jsonpath='{.secrets[0].name}') -n rbac-demo -o jsonpath='{.data.token}' | base64 -d)

# Testear si podemos listar pods usando el token del service account
curl -k -H "Authorization: Bearer $SA_TOKEN" \
  https://172.19.0.2:6443/api/v1/namespaces/rbac-demo/pods
```

<br />

Esto debería funcionar ya que le dimos al service account el role pod-reader. Ahora probemos algo que no debería poder hacer:
```elixir
# Intentar crear un pod (debería fallar)
curl -k -H "Authorization: Bearer $SA_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/api/v1/namespaces/rbac-demo/pods \
  -d '{
    "apiVersion": "v1",
    "kind": "Pod",
    "metadata": {
      "name": "test-pod"
    },
    "spec": {
      "containers": [
        {
          "name": "test",
          "image": "nginx"
        }
      ]
    }
  }'
```

<br />

Esto debería retornar un error 403 Forbidden con un mensaje como:
```elixir
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "pods is forbidden: User \"system:serviceaccount:rbac-demo:test-user\" cannot create resource \"pods\" in API group \"\" in the namespace \"rbac-demo\"",
  "reason": "Forbidden",
  "details": {
    "kind": "pods"
  },
  "code": 403
}
```

<br />

¡Perfecto! El RBAC está funcionando como esperábamos.

<br />

#### Patrones Comunes de RBAC

Acá hay algunos patrones comunes de RBAC que vas a encontrar:

**Acceso de solo lectura a todo en un namespace**:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "namespace-reader",
      "namespace": "rbac-demo"
    },
    "rules": [
      {
        "apiGroups": ["*"],
        "resources": ["*"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

<br />

**Acceso para crear y manejar deployments**:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://172.19.0.2:6443/apis/rbac.authorization.k8s.io/v1/namespaces/rbac-demo/roles \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "deployment-manager",
      "namespace": "rbac-demo"
    },
    "rules": [
      {
        "apiGroups": ["apps"],
        "resources": ["deployments"],
        "verbs": ["*"]
      },
      {
        "apiGroups": [""],
        "resources": ["pods"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

<br />

#### Troubleshooting RBAC

Cuando RBAC no está funcionando como esperás, acá hay un enfoque sistemático para debugear:

1. **Verificar si el usuario/service account existe**:
```elixir
kubectl get serviceaccount test-user -n rbac-demo
```

2. **Verificar qué roles están vinculados al usuario**:
```elixir
kubectl get rolebindings -n rbac-demo -o wide
kubectl get clusterrolebindings -o wide
```

3. **Usar SubjectAccessReview para testear permisos específicos**:
```elixir
kubectl auth can-i create pods --namespace=rbac-demo --as=system:serviceaccount:rbac-demo:test-user
```

4. **Verificar el mensaje de error exacto de la API**:
Los mensajes de error usualmente son muy específicos sobre qué está faltando.

5. **Verificar las reglas del role**:
```elixir
kubectl describe role pod-reader -n rbac-demo
```

<br />

#### Clean up
Siempre recordá limpiar tus recursos de testing:
```elixir
kubectl delete namespace rbac-demo
```

<br />

O con curl:
```elixir
curl -k -H "Authorization: Bearer $TOKEN" \
  -X DELETE \
  https://172.19.0.2:6443/api/v1/namespaces/rbac-demo
```

<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, mandame un mensaje para que lo corrija.

<br />

Podés leer más sobre RBAC [acá](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) y sobre la API de Kubernetes [acá](https://kubernetes.io/docs/concepts/overview/kubernetes-api/).

<br />
