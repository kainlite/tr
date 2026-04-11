%{
  title: "DevOps from Zero to Hero: Kubernetes Fundamentals",
  author: "Gabriel Garrido",
  description: "We will explore Kubernetes from scratch: its architecture, core objects like Pods, Deployments, and Services, how to set up a local cluster with kind, and how to deploy, scale, and update workloads...",
  tags: ~w(devops kubernetes containers beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article eleven of the DevOps from Zero to Hero series. In article eight we deployed our
TypeScript API to AWS ECS with Fargate. ECS is a solid container orchestrator, but it is AWS-specific.
If you want something that runs on any cloud provider, on bare metal, or even on your laptop,
Kubernetes is the answer.

<br />

Kubernetes (often shortened to K8s) is the industry standard for container orchestration. It is what
most teams end up using when they need to run containers at scale. It is also one of those technologies
that looks intimidating from the outside but makes a lot of sense once you understand the core concepts.

<br />

In this article we will cover what Kubernetes is and why it exists, walk through the architecture,
learn about every core object you will use daily, set up a local cluster with kind, and deploy a real
workload step by step. By the end you will be comfortable reading Kubernetes manifests, running kubectl
commands, and understanding what is happening inside a cluster.

<br />

Let's get into it.

<br />

##### **What is Kubernetes and why does it exist?**
Imagine you have ten containers that need to run across five servers. Some containers need to talk to
each other. Some need more CPU than others. If one crashes, you want it restarted automatically. If
traffic spikes, you want to spin up more copies. And you want all of this to happen without you waking
up at 3 AM.

<br />

That is container orchestration, and that is what Kubernetes does. It takes a set of machines, pools
their resources together, and lets you declare what you want running. Kubernetes then figures out where
to place each container, keeps everything healthy, and handles networking so containers can find each
other.

<br />

The key capabilities are:

<br />

> * **Scheduling**: Kubernetes decides which node (server) each container runs on based on available resources.
> * **Scaling**: You tell Kubernetes how many copies of a container you want. It makes it happen. You can also set up auto-scaling based on CPU, memory, or custom metrics.
> * **Self-healing**: If a container crashes, Kubernetes restarts it. If a node goes down, Kubernetes reschedules the containers that were running on it to healthy nodes.
> * **Service discovery and load balancing**: Kubernetes gives each set of containers a stable network identity and balances traffic across them automatically.
> * **Rolling updates and rollbacks**: You can update your application with zero downtime. If something goes wrong, you can roll back to the previous version with a single command.
> * **Declarative configuration**: You describe what you want in YAML files, and Kubernetes continuously works to make reality match your description. This is called the "desired state" model.

<br />

Kubernetes was originally designed by Google, based on their internal system called Borg. It was open
sourced in 2014 and is now maintained by the Cloud Native Computing Foundation (CNCF). Every major cloud
provider offers a managed Kubernetes service: EKS on AWS, GKE on Google Cloud, AKS on Azure.

<br />

##### **Architecture overview**
A Kubernetes cluster has two types of components: the control plane (the brain) and the worker nodes
(the muscle). Here is how they fit together:

<br />

```plaintext
+-----------------------------------------------------------+
|                     Kubernetes Cluster                     |
|                                                           |
|  +-----------------------------------------------------+  |
|  |                   Control Plane                      |  |
|  |                                                     |  |
|  |  +--------------+  +-------+  +-----------+         |  |
|  |  |  API Server  |  | etcd  |  | Scheduler |         |  |
|  |  +--------------+  +-------+  +-----------+         |  |
|  |  +--------------------+                             |  |
|  |  | Controller Manager |                             |  |
|  |  +--------------------+                             |  |
|  +-----------------------------------------------------+  |
|                                                           |
|  +------------------------+  +------------------------+   |
|  |     Worker Node 1      |  |     Worker Node 2      |   |
|  |                        |  |                        |   |
|  |  +--------+ +-------+ |  |  +--------+ +-------+  |   |
|  |  | kubelet| | proxy | |  |  | kubelet| | proxy |  |   |
|  |  +--------+ +-------+ |  |  +--------+ +-------+  |   |
|  |  +------+ +------+    |  |  +------+ +------+     |   |
|  |  | Pod  | | Pod  |    |  |  | Pod  | | Pod  |     |   |
|  |  +------+ +------+    |  |  +------+ +------+     |   |
|  +------------------------+  +------------------------+   |
+-----------------------------------------------------------+
```

<br />

Let's break down each component:

<br />

##### **Control plane components**

<br />

> * **API Server (kube-apiserver)**: The front door to your cluster. Every command you run with kubectl goes through the API server. It validates requests, updates the cluster state, and is the only component that talks directly to etcd. Think of it as the receptionist that handles all incoming requests.
> * **etcd**: A distributed key-value store that holds the entire state of your cluster. Every object you create, every configuration, every secret is stored here. If etcd is lost and you have no backup, your cluster state is gone. It is the single source of truth.
> * **Scheduler (kube-scheduler)**: When you create a new Pod and it does not have a node assigned yet, the scheduler picks one. It looks at resource requirements, constraints, and available capacity to make the best placement decision.
> * **Controller Manager (kube-controller-manager)**: Runs a set of controllers that watch the cluster state and work to make reality match the desired state. For example, the ReplicaSet controller ensures the right number of Pod replicas are running. If you ask for three replicas and only two are running, it creates another one.

<br />

##### **Worker node components**

<br />

> * **kubelet**: An agent that runs on every worker node. It receives Pod specifications from the API server and ensures the containers described in those specs are running and healthy. If a container crashes, kubelet restarts it.
> * **kube-proxy**: Manages network rules on each node. It handles the networking magic that lets you reach any Pod from any node using a Service. It sets up iptables rules (or IPVS, depending on configuration) to route traffic correctly.
> * **Container runtime**: The software that actually runs containers. Kubernetes supports any runtime that implements the Container Runtime Interface (CRI). The most common ones are containerd and CRI-O. Docker used to be the default, but Kubernetes removed direct Docker support in version 1.24 (containerd, which Docker uses under the hood, is still fully supported).

<br />

##### **Core objects: Pods**
A Pod is the smallest deployable unit in Kubernetes. It is not a container. It is a wrapper around one
or more containers that share the same network namespace and storage volumes.

<br />

Most of the time a Pod runs a single container. But sometimes you need a helper container alongside
your main one (for logging, proxying, or injecting configuration). Those are called sidecar containers,
and they live in the same Pod.

<br />

Containers in the same Pod:

<br />

> * **Share the same IP address** and can talk to each other via localhost
> * **Share storage volumes** mounted into the Pod
> * **Are scheduled together** on the same node
> * **Start and stop together** as a unit

<br />

Here is a simple Pod definition:

<br />

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-nginx
  labels:
    app: nginx
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
```

<br />

You almost never create Pods directly in production. Instead, you use a Deployment (which we will cover
next) that manages Pods for you. If you create a Pod directly and it crashes, nothing will restart it.
A Deployment ensures crashed Pods are replaced automatically.

<br />

##### **Core objects: Deployments**
A Deployment is the most common way to run workloads in Kubernetes. It wraps a Pod template and adds
powerful management features on top.

<br />

When you create a Deployment, you tell Kubernetes: "I want three replicas of this container, always
running, and here is how to update them." Kubernetes then creates a ReplicaSet behind the scenes, and
the ReplicaSet creates the Pods. The chain looks like this:

<br />

```plaintext
Deployment
  └── ReplicaSet
        ├── Pod 1
        ├── Pod 2
        └── Pod 3
```

<br />

Here is a Deployment manifest:

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "250m"
```

<br />

Key features of Deployments:

<br />

> * **Desired state**: You declare how many replicas you want. If a Pod dies, the Deployment creates a new one. If you have too many, it terminates the extras.
> * **Rolling updates**: When you change the container image, the Deployment gradually replaces old Pods with new ones, ensuring zero downtime. By default it takes down at most 25% of Pods at a time while bringing up new ones.
> * **Rollback**: Every change to a Deployment creates a new revision. If a new version is broken, you can roll back to any previous revision with `kubectl rollout undo`.
> * **Scaling**: Change the replica count and Kubernetes handles the rest. Scale up or down at any time.

<br />

##### **Core objects: Services**
Pods are ephemeral. They get created, destroyed, and moved around constantly. Each time a Pod is
recreated, it gets a new IP address. So how do other Pods find and talk to your application?

<br />

That is what Services solve. A Service provides a stable network endpoint (a fixed IP and DNS name)
that routes traffic to a set of Pods. Even as Pods come and go, the Service keeps pointing to the
healthy ones.

<br />

There are three main types:

<br />

> * **ClusterIP (default)**: Creates an internal IP address that is only reachable from within the cluster. This is what you use for service-to-service communication. For example, your API talking to your database.
> * **NodePort**: Exposes the service on a static port on every node in the cluster. You can reach it from outside by hitting any node's IP at that port. Useful for development, but not ideal for production.
> * **LoadBalancer**: Provisions an external load balancer (on cloud providers). This is the standard way to expose a service to the internet in production. On AWS it creates an ELB, on GCP a Cloud Load Balancer, and so on.

<br />

Here is a Service that exposes our nginx Deployment:

<br />

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

<br />

The `selector` field is what connects a Service to its Pods. The Service looks for all Pods with the
label `app: nginx` and routes traffic to them. This is the label-selector mechanism and it is
fundamental to how Kubernetes connects objects together.

<br />

##### **Core objects: ConfigMaps and Secrets**
Applications need configuration: database URLs, feature flags, API keys. Hardcoding these values into
your container image is a bad idea because you would need to rebuild the image for every environment.

<br />

Kubernetes solves this with ConfigMaps and Secrets:

<br />

> * **ConfigMap**: Stores non-sensitive configuration as key-value pairs. Things like environment names, log levels, and feature flags.
> * **Secret**: Stores sensitive data like passwords, tokens, and certificates. Secrets are base64-encoded (not encrypted by default, but you can enable encryption at rest). In production, use a secrets manager like HashiCorp Vault or AWS Secrets Manager and sync secrets into Kubernetes with an operator.

<br />

Here is a ConfigMap:

<br />

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: "info"
  APP_ENV: "production"
  MAX_CONNECTIONS: "100"
```

<br />

And a Secret:

<br />

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
data:
  DATABASE_URL: cG9zdGdyZXM6Ly91c2VyOnBhc3NAaG9zdDo1NDMyL2Ri
  API_KEY: c3VwZXItc2VjcmV0LWtleQ==
```

<br />

You can inject these into Pods as environment variables or mount them as files. Here is how to use
both in a Deployment:

<br />

```yaml
spec:
  containers:
    - name: app
      image: my-app:1.0
      envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secrets
```

<br />

##### **Core objects: Namespaces**
Namespaces provide logical isolation within a cluster. They are like folders for your Kubernetes
objects. Different teams, environments, or applications can each have their own namespace.

<br />

Every cluster starts with a few default namespaces:

<br />

> * **default**: Where objects go if you do not specify a namespace.
> * **kube-system**: Where Kubernetes system components run (API server, scheduler, CoreDNS, etc.).
> * **kube-public**: Readable by all users, used for cluster-wide public information.
> * **kube-node-lease**: Holds lease objects for node heartbeats.

<br />

Creating a namespace is simple:

<br />

```bash
kubectl create namespace staging
```

<br />

Or with YAML:

<br />

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: staging
```

<br />

Then deploy resources into that namespace:

<br />

```bash
kubectl apply -f deployment.yaml -n staging
```

<br />

Namespaces are also the boundary for resource quotas and network policies. You can limit how much CPU
and memory a namespace can consume, and you can control which namespaces can talk to each other.

<br />

##### **Labels and selectors**
Labels are key-value pairs attached to any Kubernetes object. They are the glue that connects
different objects together.

<br />

```yaml
metadata:
  labels:
    app: nginx
    environment: production
    team: platform
    version: "1.27"
```

<br />

Selectors filter objects based on their labels. This is how a Service finds its Pods, how a Deployment
knows which Pods it owns, and how you can query specific objects with kubectl:

<br />

```bash
# Get all pods with a specific label
kubectl get pods -l app=nginx

# Get pods matching multiple labels
kubectl get pods -l app=nginx,environment=production

# Get pods where a label exists (any value)
kubectl get pods -l team

# Get pods where a label does NOT exist
kubectl get pods -l '!team'
```

<br />

Labels and selectors are not just a nice-to-have. They are how Kubernetes works internally. If your
Service selector does not match your Pod labels, traffic will not flow. If your Deployment selector
does not match the Pod template labels, the Deployment will reject the configuration.

<br />

##### **Resource requests and limits**
Every container should declare how much CPU and memory it needs. Without this, Kubernetes has no idea
how to schedule Pods efficiently and you risk overloading nodes.

<br />

There are two settings:

<br />

> * **Requests**: The minimum amount of resources guaranteed to the container. The scheduler uses requests to decide which node has enough room for the Pod. If you request 256Mi of memory, Kubernetes will place the Pod on a node with at least that much available.
> * **Limits**: The maximum amount of resources a container can use. If a container exceeds its memory limit, Kubernetes kills it (OOMKilled). If it exceeds its CPU limit, it gets throttled (slowed down but not killed).

<br />

```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "500m"
```

<br />

CPU is measured in millicores. `100m` means 0.1 CPU cores. `1000m` (or just `1`) means one full core.
Memory uses standard units: `Mi` (mebibytes), `Gi` (gibibytes).

<br />

A few rules of thumb:

<br />

> * **Always set requests**. Without them, the scheduler is guessing.
> * **Set memory limits** to prevent runaway containers from crashing the node.
> * **Be careful with CPU limits**. Aggressive CPU limits cause throttling even when the node has spare CPU. Some teams set CPU requests but skip CPU limits to avoid unnecessary throttling.
> * **Monitor actual usage** and adjust requests/limits based on real data, not guesses.

<br />

##### **Setting up a local cluster with kind**
kind (Kubernetes in Docker) is the fastest way to get a local Kubernetes cluster running. It creates
a cluster by running Kubernetes nodes as Docker containers. You need Docker installed and that is it.

<br />

Install kind:

<br />

```bash
# On Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# On macOS (Homebrew)
brew install kind
```

<br />

Create a cluster:

<br />

```bash
kind create cluster --name my-cluster
```

<br />

That is it. kind creates a single-node cluster and configures kubectl to use it. Verify it is
running:

<br />

```bash
kubectl cluster-info --context kind-my-cluster
kubectl get nodes
```

<br />

You should see output like:

<br />

```plaintext
NAME                       STATUS   ROLES           AGE   VERSION
my-cluster-control-plane   Ready    control-plane   45s   v1.32.2
```

<br />

When you are done, delete the cluster:

<br />

```bash
kind delete cluster --name my-cluster
```

<br />

##### **kubectl basics**
kubectl is the command-line tool for interacting with Kubernetes. Here are the commands you will use
every day:

<br />

```bash
# Get resources
kubectl get pods                     # List all pods in current namespace
kubectl get pods -A                  # List pods in ALL namespaces
kubectl get deployments              # List deployments
kubectl get services                 # List services
kubectl get all                      # List common resource types

# Detailed information about a resource
kubectl describe pod my-nginx        # Show events, conditions, containers
kubectl describe deployment nginx-deployment

# View logs
kubectl logs my-nginx                # Logs from a pod
kubectl logs my-nginx -f             # Stream logs (follow)
kubectl logs my-nginx --previous     # Logs from the previous container (after crash)

# Execute commands inside a container
kubectl exec -it my-nginx -- /bin/bash   # Interactive shell
kubectl exec my-nginx -- cat /etc/nginx/nginx.conf  # Run a single command

# Apply and delete resources from files
kubectl apply -f deployment.yaml     # Create or update resources from a file
kubectl apply -f ./manifests/        # Apply all files in a directory
kubectl delete -f deployment.yaml    # Delete resources defined in a file
kubectl delete pod my-nginx          # Delete a specific pod
```

<br />

A few tips that will save you time:

<br />

> * **Use `-o wide`** to see extra columns like node name and IP: `kubectl get pods -o wide`
> * **Use `-o yaml`** to see the full object definition: `kubectl get pod my-nginx -o yaml`
> * **Set a default namespace** so you do not have to type `-n` every time: `kubectl config set-context --current --namespace=staging`
> * **Use aliases**. Most Kubernetes users alias `kubectl` to `k`: `alias k=kubectl`

<br />

##### **Practical walkthrough: deploy, expose, scale, update**
Let's put everything together with a hands-on exercise. Make sure you have a kind cluster running.

<br />

**Step 1: Create a Deployment**

<br />

Create a file called `nginx-deployment.yaml`:

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "100m"
```

<br />

Apply it:

<br />

```bash
kubectl apply -f nginx-deployment.yaml
```

<br />

Check the results:

<br />

```bash
kubectl get deployments
kubectl get pods
```

<br />

You should see two Pods running:

<br />

```plaintext
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-5d8f4d7b9c-abc12   1/1     Running   0          15s
nginx-deployment-5d8f4d7b9c-def34   1/1     Running   0          15s
```

<br />

**Step 2: Expose it with a Service**

<br />

Create a file called `nginx-service.yaml`:

<br />

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30080
```

<br />

Apply it:

<br />

```bash
kubectl apply -f nginx-service.yaml
```

<br />

Verify the Service:

<br />

```bash
kubectl get services
```

<br />

```plaintext
NAME            TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
nginx-service   NodePort   10.96.45.123   <none>        80:30080/TCP   5s
kubernetes      ClusterIP  10.96.0.1      <none>        443/TCP        10m
```

<br />

Test that it works. Since we are using kind, we can port-forward to access the service locally:

<br />

```bash
kubectl port-forward service/nginx-service 8080:80
```

<br />

Now open another terminal and hit it:

<br />

```bash
curl http://localhost:8080
```

<br />

You should see the default nginx welcome page HTML.

<br />

**Step 3: Scale the Deployment**

<br />

Let's go from two replicas to five:

<br />

```bash
kubectl scale deployment nginx-deployment --replicas=5
```

<br />

Watch the Pods come up:

<br />

```bash
kubectl get pods -w
```

<br />

Within seconds you will have five Pods running. Scale back down:

<br />

```bash
kubectl scale deployment nginx-deployment --replicas=2
```

<br />

Kubernetes will terminate three Pods gracefully.

<br />

**Step 4: Do a rolling update**

<br />

Let's update from nginx 1.27 to 1.28. You can edit the YAML file and re-apply, or do it inline:

<br />

```bash
kubectl set image deployment/nginx-deployment nginx=nginx:1.28
```

<br />

Watch the rolling update happen:

<br />

```bash
kubectl rollout status deployment/nginx-deployment
```

<br />

```plaintext
Waiting for deployment "nginx-deployment" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "nginx-deployment" rollout to finish: 1 old replicas are pending termination...
deployment "nginx-deployment" successfully rolled out
```

<br />

Kubernetes created new Pods with nginx 1.28 and terminated the old ones, one at a time, with zero
downtime.

<br />

Check the rollout history:

<br />

```bash
kubectl rollout history deployment/nginx-deployment
```

<br />

If something goes wrong, roll back:

<br />

```bash
kubectl rollout undo deployment/nginx-deployment
```

<br />

This reverts to the previous revision immediately.

<br />

**Step 5: Inspect and debug**

<br />

Get detailed information about a Pod:

<br />

```bash
kubectl describe pod nginx-deployment-<tab-complete-the-name>
```

<br />

Check the container logs:

<br />

```bash
kubectl logs deployment/nginx-deployment
```

<br />

Open a shell inside a running container:

<br />

```bash
kubectl exec -it deployment/nginx-deployment -- /bin/bash
```

<br />

Inside the container you can inspect files, test connectivity, and debug issues directly.

<br />

**Step 6: Clean up**

<br />

```bash
kubectl delete -f nginx-service.yaml
kubectl delete -f nginx-deployment.yaml
```

<br />

Or delete the entire kind cluster:

<br />

```bash
kind delete cluster --name my-cluster
```

<br />

##### **Closing notes**
Kubernetes has a reputation for being complex, and it is true that the ecosystem is massive. But the
core concepts are straightforward. You have Pods that run containers, Deployments that manage Pods,
Services that route traffic, ConfigMaps and Secrets for configuration, and Namespaces for isolation.
Everything connects through labels and selectors.

<br />

The key insight is that Kubernetes is a declarative system. You tell it what you want, and it
continuously works to make that happen. You do not tell it "start three containers." You tell it "I
want three replicas" and it figures out how to get there, whether that means creating new Pods,
restarting crashed ones, or rescheduling them to different nodes.

<br />

We covered a lot of ground in this article. Set up a kind cluster and play around. Break things on
purpose. Delete a Pod and watch the Deployment recreate it. Change resource limits and see what
happens. The best way to learn Kubernetes is by using it.

<br />

In the next articles we will build on this foundation: deploying real applications to Kubernetes,
setting up networking with Ingress controllers, and managing everything with Helm charts.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: Fundamentos de Kubernetes",
  author: "Gabriel Garrido",
  description: "Vamos a explorar Kubernetes desde cero: su arquitectura, objetos principales como Pods, Deployments y Services, como levantar un cluster local con kind, y como desplegar, escalar y actualizar workloads...",
  tags: ~w(devops kubernetes containers beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo once de la serie DevOps from Zero to Hero. En el articulo ocho desplegamos
nuestra API TypeScript en AWS ECS con Fargate. ECS es un buen orquestador de contenedores, pero es
especifico de AWS. Si queres algo que funcione en cualquier proveedor cloud, en bare metal, o incluso
en tu laptop, Kubernetes es la respuesta.

<br />

Kubernetes (abreviado como K8s) es el estandar de la industria para orquestacion de contenedores. Es
lo que la mayoria de los equipos termina usando cuando necesitan correr contenedores a escala. Tambien
es una de esas tecnologias que parecen intimidantes desde afuera, pero tienen mucho sentido una vez que
entendes los conceptos principales.

<br />

En este articulo vamos a cubrir que es Kubernetes y por que existe, recorrer la arquitectura, aprender
cada objeto principal que vas a usar todos los dias, levantar un cluster local con kind, y desplegar un
workload real paso a paso. Al final vas a poder leer manifiestos de Kubernetes, ejecutar comandos de
kubectl y entender que esta pasando dentro de un cluster.

<br />

Vamos a meternos de lleno.

<br />

##### **Que es Kubernetes y por que existe?**
Imaginate que tenes diez contenedores que necesitan correr en cinco servidores. Algunos necesitan
comunicarse entre si. Algunos necesitan mas CPU que otros. Si uno se cae, queres que se reinicie
automaticamente. Si el trafico aumenta, queres levantar mas copias. Y queres que todo esto pase sin
que te despierten a las 3 AM.

<br />

Eso es orquestacion de contenedores, y eso es lo que hace Kubernetes. Toma un conjunto de maquinas,
agrupa sus recursos, y te deja declarar que queres corriendo. Kubernetes despues se encarga de decidir
donde ubicar cada contenedor, mantener todo saludable, y manejar la red para que los contenedores se
encuentren entre si.

<br />

Las capacidades principales son:

<br />

> * **Scheduling**: Kubernetes decide en que nodo (servidor) corre cada contenedor segun los recursos disponibles.
> * **Escalado**: Le decis a Kubernetes cuantas copias de un contenedor queres. Lo hace. Tambien podes configurar auto-escalado basado en CPU, memoria o metricas custom.
> * **Auto-recuperacion**: Si un contenedor se cae, Kubernetes lo reinicia. Si un nodo se muere, Kubernetes reprograma los contenedores que estaban corriendo ahi en nodos saludables.
> * **Descubrimiento de servicios y balanceo de carga**: Kubernetes le da a cada conjunto de contenedores una identidad de red estable y balancea el trafico entre ellos automaticamente.
> * **Rolling updates y rollbacks**: Podes actualizar tu aplicacion con cero downtime. Si algo sale mal, podes volver a la version anterior con un solo comando.
> * **Configuracion declarativa**: Describis lo que queres en archivos YAML, y Kubernetes trabaja continuamente para que la realidad coincida con tu descripcion. Esto se llama el modelo de "estado deseado".

<br />

Kubernetes fue disenado originalmente por Google, basado en su sistema interno llamado Borg. Fue
liberado como open source en 2014 y ahora lo mantiene la Cloud Native Computing Foundation (CNCF).
Todos los proveedores cloud importantes ofrecen un servicio de Kubernetes gestionado: EKS en AWS, GKE
en Google Cloud, AKS en Azure.

<br />

##### **Vision general de la arquitectura**
Un cluster de Kubernetes tiene dos tipos de componentes: el plano de control (el cerebro) y los nodos
worker (el musculo). Asi encajan:

<br />

```plaintext
+-----------------------------------------------------------+
|                     Cluster Kubernetes                     |
|                                                           |
|  +-----------------------------------------------------+  |
|  |                  Plano de Control                    |  |
|  |                                                     |  |
|  |  +--------------+  +-------+  +-----------+         |  |
|  |  |  API Server  |  | etcd  |  | Scheduler |         |  |
|  |  +--------------+  +-------+  +-----------+         |  |
|  |  +--------------------+                             |  |
|  |  | Controller Manager |                             |  |
|  |  +--------------------+                             |  |
|  +-----------------------------------------------------+  |
|                                                           |
|  +------------------------+  +------------------------+   |
|  |     Nodo Worker 1      |  |     Nodo Worker 2      |   |
|  |                        |  |                        |   |
|  |  +--------+ +-------+ |  |  +--------+ +-------+  |   |
|  |  | kubelet| | proxy | |  |  | kubelet| | proxy |  |   |
|  |  +--------+ +-------+ |  |  +--------+ +-------+  |   |
|  |  +------+ +------+    |  |  +------+ +------+     |   |
|  |  | Pod  | | Pod  |    |  |  | Pod  | | Pod  |     |   |
|  |  +------+ +------+    |  |  +------+ +------+     |   |
|  +------------------------+  +------------------------+   |
+-----------------------------------------------------------+
```

<br />

Desglosemos cada componente:

<br />

##### **Componentes del plano de control**

<br />

> * **API Server (kube-apiserver)**: La puerta de entrada a tu cluster. Cada comando que ejecutas con kubectl pasa por el API server. Valida requests, actualiza el estado del cluster, y es el unico componente que habla directamente con etcd. Pensalo como la recepcion que maneja todos los pedidos entrantes.
> * **etcd**: Un almacen distribuido de clave-valor que contiene todo el estado de tu cluster. Cada objeto que creas, cada configuracion, cada secreto se guarda aca. Si se pierde etcd y no tenes backup, se pierde el estado de tu cluster. Es la unica fuente de verdad.
> * **Scheduler (kube-scheduler)**: Cuando creas un Pod nuevo y todavia no tiene un nodo asignado, el scheduler elige uno. Analiza los requerimientos de recursos, restricciones y capacidad disponible para tomar la mejor decision de ubicacion.
> * **Controller Manager (kube-controller-manager)**: Ejecuta un conjunto de controllers que observan el estado del cluster y trabajan para que la realidad coincida con el estado deseado. Por ejemplo, el controller de ReplicaSet asegura que la cantidad correcta de replicas de Pods este corriendo. Si pediste tres replicas y solo hay dos corriendo, crea otra.

<br />

##### **Componentes de los nodos worker**

<br />

> * **kubelet**: Un agente que corre en cada nodo worker. Recibe especificaciones de Pods del API server y se asegura de que los contenedores descritos en esas especificaciones esten corriendo y saludables. Si un contenedor se cae, kubelet lo reinicia.
> * **kube-proxy**: Gestiona reglas de red en cada nodo. Maneja la magia de networking que te permite alcanzar cualquier Pod desde cualquier nodo usando un Service. Configura reglas de iptables (o IPVS, dependiendo de la configuracion) para rutear trafico correctamente.
> * **Container runtime**: El software que realmente corre los contenedores. Kubernetes soporta cualquier runtime que implemente la Container Runtime Interface (CRI). Los mas comunes son containerd y CRI-O. Docker solia ser el default, pero Kubernetes elimino el soporte directo a Docker en la version 1.24 (containerd, que Docker usa internamente, sigue siendo completamente soportado).

<br />

##### **Objetos principales: Pods**
Un Pod es la unidad desplegable mas chica en Kubernetes. No es un contenedor. Es un wrapper alrededor
de uno o mas contenedores que comparten el mismo namespace de red y volumenes de almacenamiento.

<br />

La mayoria de las veces un Pod corre un solo contenedor. Pero a veces necesitas un contenedor auxiliar
al lado del principal (para logging, proxy o inyeccion de configuracion). Esos se llaman contenedores
sidecar, y viven en el mismo Pod.

<br />

Los contenedores en el mismo Pod:

<br />

> * **Comparten la misma direccion IP** y pueden comunicarse entre si via localhost
> * **Comparten volumenes de almacenamiento** montados en el Pod
> * **Se programan juntos** en el mismo nodo
> * **Se inician y detienen juntos** como una unidad

<br />

Aca tenes una definicion simple de Pod:

<br />

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-nginx
  labels:
    app: nginx
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
```

<br />

Casi nunca creas Pods directamente en produccion. En su lugar, usas un Deployment (que vamos a
cubrir a continuacion) que gestiona los Pods por vos. Si creas un Pod directamente y se cae, nada lo
va a reiniciar. Un Deployment asegura que los Pods caidos se reemplacen automaticamente.

<br />

##### **Objetos principales: Deployments**
Un Deployment es la forma mas comun de correr workloads en Kubernetes. Envuelve un template de Pod y
agrega funcionalidades de gestion poderosas encima.

<br />

Cuando creas un Deployment, le decis a Kubernetes: "Quiero tres replicas de este contenedor, siempre
corriendo, y asi es como actualizarlas." Kubernetes entonces crea un ReplicaSet detras de escena, y el
ReplicaSet crea los Pods. La cadena se ve asi:

<br />

```plaintext
Deployment
  └── ReplicaSet
        ├── Pod 1
        ├── Pod 2
        └── Pod 3
```

<br />

Aca tenes un manifiesto de Deployment:

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "250m"
```

<br />

Caracteristicas principales de los Deployments:

<br />

> * **Estado deseado**: Declaras cuantas replicas queres. Si un Pod muere, el Deployment crea uno nuevo. Si hay de mas, termina los extras.
> * **Rolling updates**: Cuando cambias la imagen del contenedor, el Deployment reemplaza gradualmente los Pods viejos con nuevos, asegurando cero downtime. Por defecto da de baja como maximo el 25% de los Pods a la vez mientras levanta nuevos.
> * **Rollback**: Cada cambio a un Deployment crea una nueva revision. Si una version nueva esta rota, podes volver a cualquier revision anterior con `kubectl rollout undo`.
> * **Escalado**: Cambia la cantidad de replicas y Kubernetes se encarga del resto. Escala para arriba o para abajo en cualquier momento.

<br />

##### **Objetos principales: Services**
Los Pods son efimeros. Se crean, se destruyen y se mueven constantemente. Cada vez que un Pod se
recrea, obtiene una nueva direccion IP. Entonces, como hacen otros Pods para encontrar y hablar con tu
aplicacion?

<br />

Eso es lo que resuelven los Services. Un Service provee un endpoint de red estable (una IP fija y un
nombre DNS) que rutea trafico a un conjunto de Pods. Incluso mientras los Pods van y vienen, el Service
sigue apuntando a los saludables.

<br />

Hay tres tipos principales:

<br />

> * **ClusterIP (default)**: Crea una direccion IP interna que solo es alcanzable desde dentro del cluster. Esto es lo que usas para comunicacion servicio-a-servicio. Por ejemplo, tu API hablando con tu base de datos.
> * **NodePort**: Expone el servicio en un puerto estatico en cada nodo del cluster. Podes accederlo desde afuera apuntando a la IP de cualquier nodo en ese puerto. Util para desarrollo, pero no ideal para produccion.
> * **LoadBalancer**: Provisiona un balanceador de carga externo (en proveedores cloud). Esta es la forma estandar de exponer un servicio a internet en produccion. En AWS crea un ELB, en GCP un Cloud Load Balancer, y asi.

<br />

Aca tenes un Service que expone nuestro Deployment de nginx:

<br />

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

<br />

El campo `selector` es lo que conecta un Service con sus Pods. El Service busca todos los Pods con la
etiqueta `app: nginx` y rutea trafico hacia ellos. Este es el mecanismo de label-selector y es
fundamental para como Kubernetes conecta objetos entre si.

<br />

##### **Objetos principales: ConfigMaps y Secrets**
Las aplicaciones necesitan configuracion: URLs de bases de datos, feature flags, API keys. Hardcodear
estos valores en tu imagen de contenedor es mala idea porque tendrias que reconstruir la imagen para
cada entorno.

<br />

Kubernetes resuelve esto con ConfigMaps y Secrets:

<br />

> * **ConfigMap**: Almacena configuracion no sensible como pares clave-valor. Cosas como nombres de entorno, niveles de log y feature flags.
> * **Secret**: Almacena datos sensibles como passwords, tokens y certificados. Los Secrets estan codificados en base64 (no encriptados por defecto, pero podes habilitar encriptacion en reposo). En produccion, usa un gestor de secretos como HashiCorp Vault o AWS Secrets Manager y sincroniza secretos en Kubernetes con un operator.

<br />

Aca tenes un ConfigMap:

<br />

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: "info"
  APP_ENV: "production"
  MAX_CONNECTIONS: "100"
```

<br />

Y un Secret:

<br />

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
data:
  DATABASE_URL: cG9zdGdyZXM6Ly91c2VyOnBhc3NAaG9zdDo1NDMyL2Ri
  API_KEY: c3VwZXItc2VjcmV0LWtleQ==
```

<br />

Podes inyectar estos en Pods como variables de entorno o montarlos como archivos. Asi es como usar
ambos en un Deployment:

<br />

```yaml
spec:
  containers:
    - name: app
      image: my-app:1.0
      envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secrets
```

<br />

##### **Objetos principales: Namespaces**
Los Namespaces proveen aislamiento logico dentro de un cluster. Son como carpetas para tus objetos de
Kubernetes. Diferentes equipos, entornos o aplicaciones pueden tener cada uno su propio namespace.

<br />

Cada cluster arranca con algunos namespaces por defecto:

<br />

> * **default**: Donde van los objetos si no especificas un namespace.
> * **kube-system**: Donde corren los componentes del sistema de Kubernetes (API server, scheduler, CoreDNS, etc.).
> * **kube-public**: Legible por todos los usuarios, usado para informacion publica del cluster.
> * **kube-node-lease**: Contiene objetos de lease para heartbeats de nodos.

<br />

Crear un namespace es simple:

<br />

```bash
kubectl create namespace staging
```

<br />

O con YAML:

<br />

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: staging
```

<br />

Despues desplegamos recursos en ese namespace:

<br />

```bash
kubectl apply -f deployment.yaml -n staging
```

<br />

Los Namespaces tambien son el limite para resource quotas y network policies. Podes limitar cuanta CPU
y memoria puede consumir un namespace, y podes controlar que namespaces pueden comunicarse entre si.

<br />

##### **Labels y selectors**
Los labels son pares clave-valor que se adjuntan a cualquier objeto de Kubernetes. Son el pegamento que
conecta diferentes objetos entre si.

<br />

```yaml
metadata:
  labels:
    app: nginx
    environment: production
    team: platform
    version: "1.27"
```

<br />

Los selectors filtran objetos basandose en sus labels. Asi es como un Service encuentra sus Pods, como
un Deployment sabe que Pods le pertenecen, y como podes consultar objetos especificos con kubectl:

<br />

```bash
# Obtener todos los pods con un label especifico
kubectl get pods -l app=nginx

# Obtener pods que coincidan con multiples labels
kubectl get pods -l app=nginx,environment=production

# Obtener pods donde un label exista (cualquier valor)
kubectl get pods -l team

# Obtener pods donde un label NO exista
kubectl get pods -l '!team'
```

<br />

Los labels y selectors no son solo algo bonito. Son como Kubernetes funciona internamente. Si el
selector de tu Service no coincide con los labels de tus Pods, el trafico no va a fluir. Si el selector
de tu Deployment no coincide con los labels del template de Pod, el Deployment va a rechazar la
configuracion.

<br />

##### **Requests y limits de recursos**
Cada contenedor deberia declarar cuanta CPU y memoria necesita. Sin esto, Kubernetes no tiene idea de
como programar Pods eficientemente y corres riesgo de sobrecargar nodos.

<br />

Hay dos configuraciones:

<br />

> * **Requests**: La cantidad minima de recursos garantizada al contenedor. El scheduler usa los requests para decidir que nodo tiene suficiente lugar para el Pod. Si pedis 256Mi de memoria, Kubernetes va a ubicar el Pod en un nodo que tenga al menos esa cantidad disponible.
> * **Limits**: La cantidad maxima de recursos que un contenedor puede usar. Si un contenedor excede su limite de memoria, Kubernetes lo mata (OOMKilled). Si excede su limite de CPU, se le aplica throttling (se ralentiza pero no se mata).

<br />

```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "500m"
```

<br />

La CPU se mide en milicores. `100m` significa 0.1 nucleos de CPU. `1000m` (o simplemente `1`) significa
un nucleo completo. La memoria usa unidades estandar: `Mi` (mebibytes), `Gi` (gibibytes).

<br />

Algunas reglas generales:

<br />

> * **Siempre configura requests**. Sin ellos, el scheduler esta adivinando.
> * **Configura limits de memoria** para prevenir que contenedores descontrolados crasheen el nodo.
> * **Cuidado con los limits de CPU**. Limits de CPU agresivos causan throttling incluso cuando el nodo tiene CPU libre. Algunos equipos configuran requests de CPU pero no ponen limits de CPU para evitar throttling innecesario.
> * **Monitoea el uso real** y ajusta requests/limits basandote en datos reales, no en suposiciones.

<br />

##### **Levantando un cluster local con kind**
kind (Kubernetes in Docker) es la forma mas rapida de tener un cluster de Kubernetes local corriendo.
Crea un cluster ejecutando nodos de Kubernetes como contenedores Docker. Necesitas Docker instalado y
nada mas.

<br />

Instalar kind:

<br />

```bash
# En Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# En macOS (Homebrew)
brew install kind
```

<br />

Crear un cluster:

<br />

```bash
kind create cluster --name my-cluster
```

<br />

Eso es todo. kind crea un cluster de un solo nodo y configura kubectl para usarlo. Verifica que este
corriendo:

<br />

```bash
kubectl cluster-info --context kind-my-cluster
kubectl get nodes
```

<br />

Deberias ver una salida como esta:

<br />

```plaintext
NAME                       STATUS   ROLES           AGE   VERSION
my-cluster-control-plane   Ready    control-plane   45s   v1.32.2
```

<br />

Cuando termines, borra el cluster:

<br />

```bash
kind delete cluster --name my-cluster
```

<br />

##### **Basicos de kubectl**
kubectl es la herramienta de linea de comandos para interactuar con Kubernetes. Aca estan los comandos
que vas a usar todos los dias:

<br />

```bash
# Obtener recursos
kubectl get pods                     # Listar todos los pods en el namespace actual
kubectl get pods -A                  # Listar pods en TODOS los namespaces
kubectl get deployments              # Listar deployments
kubectl get services                 # Listar services
kubectl get all                      # Listar tipos de recursos comunes

# Informacion detallada sobre un recurso
kubectl describe pod my-nginx        # Mostrar eventos, condiciones, contenedores
kubectl describe deployment nginx-deployment

# Ver logs
kubectl logs my-nginx                # Logs de un pod
kubectl logs my-nginx -f             # Transmitir logs (follow)
kubectl logs my-nginx --previous     # Logs del contenedor anterior (despues de un crash)

# Ejecutar comandos dentro de un contenedor
kubectl exec -it my-nginx -- /bin/bash   # Shell interactiva
kubectl exec my-nginx -- cat /etc/nginx/nginx.conf  # Ejecutar un solo comando

# Aplicar y borrar recursos desde archivos
kubectl apply -f deployment.yaml     # Crear o actualizar recursos desde un archivo
kubectl apply -f ./manifests/        # Aplicar todos los archivos de un directorio
kubectl delete -f deployment.yaml    # Borrar recursos definidos en un archivo
kubectl delete pod my-nginx          # Borrar un pod especifico
```

<br />

Algunos tips que te van a ahorrar tiempo:

<br />

> * **Usa `-o wide`** para ver columnas extra como nombre de nodo e IP: `kubectl get pods -o wide`
> * **Usa `-o yaml`** para ver la definicion completa del objeto: `kubectl get pod my-nginx -o yaml`
> * **Configura un namespace por defecto** asi no tenes que escribir `-n` cada vez: `kubectl config set-context --current --namespace=staging`
> * **Usa aliases**. La mayoria de los usuarios de Kubernetes aliasen `kubectl` a `k`: `alias k=kubectl`

<br />

##### **Ejercicio practico: desplegar, exponer, escalar, actualizar**
Pongamos todo junto con un ejercicio practico. Asegurate de tener un cluster kind corriendo.

<br />

**Paso 1: Crear un Deployment**

<br />

Crea un archivo llamado `nginx-deployment.yaml`:

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "100m"
```

<br />

Aplicalo:

<br />

```bash
kubectl apply -f nginx-deployment.yaml
```

<br />

Verifica los resultados:

<br />

```bash
kubectl get deployments
kubectl get pods
```

<br />

Deberias ver dos Pods corriendo:

<br />

```plaintext
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-5d8f4d7b9c-abc12   1/1     Running   0          15s
nginx-deployment-5d8f4d7b9c-def34   1/1     Running   0          15s
```

<br />

**Paso 2: Exponerlo con un Service**

<br />

Crea un archivo llamado `nginx-service.yaml`:

<br />

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30080
```

<br />

Aplicalo:

<br />

```bash
kubectl apply -f nginx-service.yaml
```

<br />

Verifica el Service:

<br />

```bash
kubectl get services
```

<br />

```plaintext
NAME            TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
nginx-service   NodePort   10.96.45.123   <none>        80:30080/TCP   5s
kubernetes      ClusterIP  10.96.0.1      <none>        443/TCP        10m
```

<br />

Prueba que funcione. Como estamos usando kind, podemos hacer port-forward para acceder al servicio
localmente:

<br />

```bash
kubectl port-forward service/nginx-service 8080:80
```

<br />

Ahora abri otra terminal y hacele un request:

<br />

```bash
curl http://localhost:8080
```

<br />

Deberias ver el HTML de la pagina de bienvenida de nginx.

<br />

**Paso 3: Escalar el Deployment**

<br />

Pasemos de dos replicas a cinco:

<br />

```bash
kubectl scale deployment nginx-deployment --replicas=5
```

<br />

Mira como se levantan los Pods:

<br />

```bash
kubectl get pods -w
```

<br />

En segundos vas a tener cinco Pods corriendo. Escalemos para abajo:

<br />

```bash
kubectl scale deployment nginx-deployment --replicas=2
```

<br />

Kubernetes va a terminar tres Pods de forma graceful.

<br />

**Paso 4: Hacer un rolling update**

<br />

Actualicemos de nginx 1.27 a 1.28. Podes editar el archivo YAML y re-aplicar, o hacerlo inline:

<br />

```bash
kubectl set image deployment/nginx-deployment nginx=nginx:1.28
```

<br />

Mira como pasa el rolling update:

<br />

```bash
kubectl rollout status deployment/nginx-deployment
```

<br />

```plaintext
Waiting for deployment "nginx-deployment" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "nginx-deployment" rollout to finish: 1 old replicas are pending termination...
deployment "nginx-deployment" successfully rolled out
```

<br />

Kubernetes creo Pods nuevos con nginx 1.28 y termino los viejos, uno a la vez, con cero downtime.

<br />

Revisa el historial de rollout:

<br />

```bash
kubectl rollout history deployment/nginx-deployment
```

<br />

Si algo sale mal, hace rollback:

<br />

```bash
kubectl rollout undo deployment/nginx-deployment
```

<br />

Esto revierte a la revision anterior inmediatamente.

<br />

**Paso 5: Inspeccionar y debuggear**

<br />

Obtene informacion detallada sobre un Pod:

<br />

```bash
kubectl describe pod nginx-deployment-<completa-el-nombre-con-tab>
```

<br />

Revisa los logs del contenedor:

<br />

```bash
kubectl logs deployment/nginx-deployment
```

<br />

Abri una shell dentro de un contenedor corriendo:

<br />

```bash
kubectl exec -it deployment/nginx-deployment -- /bin/bash
```

<br />

Dentro del contenedor podes inspeccionar archivos, probar conectividad y debuggear problemas
directamente.

<br />

**Paso 6: Limpiar**

<br />

```bash
kubectl delete -f nginx-service.yaml
kubectl delete -f nginx-deployment.yaml
```

<br />

O borra el cluster kind completo:

<br />

```bash
kind delete cluster --name my-cluster
```

<br />

##### **Notas finales**
Kubernetes tiene fama de ser complejo, y es verdad que el ecosistema es masivo. Pero los conceptos
principales son directos. Tenes Pods que corren contenedores, Deployments que gestionan Pods, Services
que rutean trafico, ConfigMaps y Secrets para configuracion, y Namespaces para aislamiento. Todo se
conecta a traves de labels y selectors.

<br />

La idea clave es que Kubernetes es un sistema declarativo. Le decis lo que queres, y el trabaja
continuamente para que eso pase. No le decis "inicia tres contenedores." Le decis "quiero tres
replicas" y el se encarga de como llegar ahi, ya sea creando Pods nuevos, reiniciando los que se
cayeron, o reprogramandolos en otros nodos.

<br />

Cubrimos mucho terreno en este articulo. Levanta un cluster kind y jugá. Rompe cosas a proposito.
Borra un Pod y mira como el Deployment lo recrea. Cambia los resource limits y ve que pasa. La mejor
forma de aprender Kubernetes es usandolo.

<br />

En los proximos articulos vamos a construir sobre esta base: desplegando aplicaciones reales a
Kubernetes, configurando networking con Ingress controllers, y gestionando todo con Helm charts.

<br />

Espero que te haya resultado util y lo hayas disfrutado! Hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en las [fuentes aca](https://github.com/kainlite/tr)

<br />
