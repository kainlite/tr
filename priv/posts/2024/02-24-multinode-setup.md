%{
  title: "Running a phoenix app in a multinode fashion in kubernetes",
  author: "Gabriel Garrido",
  description: "Running a phoenix app in a multinode fashion in kubernetes",
  tags: ~w(elixir phoenix kubernetes),
  published: true,
  image: "phoenix.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In this brief update, I'm going to make all nodes able to connect and communicate with each other using the library
libcluster with some basic configuration.
<br />

##### **Upgrading packages**
For that to work you need to add in `mix.exs`:
```elixir
    {:libcluster, "~> 3.3"},
``` 
<br />

Update your `lib/tr/application.ex` file to start libcluster
```elixir
    topologies = Application.get_env(:libcluster, :topologies, [])

    children = [
      # Start the Cluster supervisor for libcluster
      {Cluster.Supervisor, [topologies, [name: Tr.ClusterSupervisor]]},
      ...
```
<br />

Then we need to update our `config/prod.exs` file to tell libcluster what to look for in the cluster:
```elixir
# Libcluster configuration
config :libcluster,
  topologies: [
    erlang_nodes_in_k8s: [
      strategy: Elixir.Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: "tr-cluster-svc",
        application_name: "tr",
        kubernetes_namespace: "tr",
        polling_interval: 10_000
      ]
    ]
  ]
```
<br />

Dev config `config/dev.exs`:
```elixir
config :libcluster,
  topologies: [
    example: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: [:"a@127.0.0.1", :"b@127.0.0.1"]],
      connect: {:net_kernel, :connect_node, []},
      disconnect: {:erlang, :disconnect_node, []},
      list_nodes: {:erlang, :nodes, [:connected]}
    ]
  ]
```

<br />

That's enough for elixir to try to find the other pods and attempt to connect to the nodes, however we need to allow
that communication and let the pods read the information from the kubernetes API, next up add these permissions to your
deployment `05-role.yaml`:

```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: tr
  name: pod-reader
rules:
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: tr
subjects:
- kind: ServiceAccount
  name: tr
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```
<br />

Then in your `02-deployment.yaml` file:
```elixir
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
```
<br />

And a service to make things easier `03-service.yaml` (epmd port):
```elixir
apiVersion: v1
kind: Service
metadata:
  name: tr-cluster-svc
  namespace: tr
spec:
  clusterIP: None
  selector:
    name: tr
```

This is to set the right environment variables for the application to use and to be able to connect to the other
`nodes`.
<br />

Before moving on, make sure you generate the release files:
```elixir
mix release.init
```
<br />

And now update your `rel/env.sh.eex` file so it looks like this:
```elixir
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=<%= @release.name %>@${POD_IP}
```
<br />


If everything went well, you should see something like this in the logs:
```elixir
tr-deployment-6cf5c65b56-ndrgm tr 04:13:13.411 [info] [libcluster:erlang_nodes_in_k8s] connected to :"tr@10.42.1.217"
tr-deployment-6cf5c65b56-ndrgm tr 04:13:13.416 [info] [libcluster:erlang_nodes_in_k8s] connected to :"tr@10.42.3.185"
```
<br />

If you want to validate it locally, use this command instead from `iex`:
```elixir
❯ iex --name a@127.0.0.1 --cookie secret -S mix

❯ iex --name b@127.0.0.1 --cookie secret -S mix

iex(b@127.0.0.1)> Node.list()
```

Some useful links:
https://hexdocs.pm/libcluster/readme.html
https://hexdocs.pm/libcluster/Cluster.Strategy.Kubernetes.DNS.html
https://brain.d.foundation/Engineering/Backend/libcluster+in+elixir

and last but not least good luck!
<br />

##### **Closing notes**
Let me know if there is anything that you would like to see implemented or tested, explored and what not in here...
<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
---lang---
%{
  title: "Corriendo una applicacion Elixir en modo cluster en Kubernetes",
  author: "Gabriel Garrido",
  description: "Aprovechemos las ventajas de clustering de BEAM, veamos como... ",
  tags: ~w(elixir phoenix kubernetes),
  published: true,
  image: "phoenix.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En esta breve actualización, voy a hacer que todos los nodos puedan conectarse y comunicarse entre sí utilizando la librería libcluster con una configuración básica.
<br />

##### **Actualizando paquetes**
Para que esto funcione, necesitás agregar en `mix.exs`:
```elixir
    {:libcluster, "~> 3.3"},
``` 
<br />

Actualizá tu archivo `lib/tr/application.ex` para iniciar libcluster:
```elixir
    topologies = Application.get_env(:libcluster, :topologies, [])

    children = [
      # Iniciar el supervisor del Cluster para libcluster
      {Cluster.Supervisor, [topologies, [name: Tr.ClusterSupervisor]]},
      ...
```
<br />

Luego necesitás actualizar tu archivo `config/prod.exs` para indicarle a libcluster qué buscar en el clúster:
```elixir
# Configuración de Libcluster
config :libcluster,
  topologies: [
    erlang_nodes_in_k8s: [
      strategy: Elixir.Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: "tr-cluster-svc",
        application_name: "tr",
        kubernetes_namespace: "tr",
        polling_interval: 10_000
      ]
    ]
  ]
```
<br />

Config para desarrollo `config/dev.exs`:
```elixir
config :libcluster,
  topologies: [
    example: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: [:"a@127.0.0.1", :"b@127.0.0.1"]],
      connect: {:net_kernel, :connect_node, []},
      disconnect: {:erlang, :disconnect_node, []},
      list_nodes: {:erlang, :nodes, [:connected]}
    ]
  ]
```

<br />

Eso es suficiente para que Elixir intente encontrar los otros pods y conectarse a los nodos. Sin embargo, necesitamos permitir esa comunicación y dejar que los pods lean la información de la API de Kubernetes. A continuación, agregá estos permisos a tu despliegue en `05-role.yaml`:

```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: tr
  name: pod-reader
rules:
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: tr
subjects:
- kind: ServiceAccount
  name: tr
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```
<br />

Luego en tu archivo `02-deployment.yaml`:
```elixir
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
```
<br />

Y un servicio para facilitar las cosas `03-service.yaml` (puerto epmd):
```elixir
apiVersion: v1
kind: Service
metadata:
  name: tr-cluster-svc
  namespace: tr
spec:
  clusterIP: None
  selector:
    name: tr
```

Esto es para establecer las variables de entorno correctas para que la aplicación las use y pueda conectarse a los otros `nodos`.
<br />

Antes de seguir, asegurate de generar los archivos de release:
```elixir
mix release.init
```
<br />

Ahora actualizá tu archivo `rel/env.sh.eex` para que se vea así:
```elixir
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=<%= @release.name %>@${POD_IP}
```
<br />

Si todo salió bien, deberías ver algo como esto en los logs:
```elixir
tr-deployment-6cf5c65b56-ndrgm tr 04:13:13.411 [info] [libcluster:erlang_nodes_in_k8s] connected to :"tr@10.42.1.217"
tr-deployment-6cf5c65b56-ndrgm tr 04:13:13.416 [info] [libcluster:erlang_nodes_in_k8s] connected to :"tr@10.42.3.185"
```
<br />

Si querés validarlo localmente, usá este comando desde `iex`:
```elixir
❯ iex --name a@127.0.0.1 --cookie secret -S mix

❯ iex --name b@127.0.0.1 --cookie secret -S mix

iex(b@127.0.0.1)> Node.list()
```

Algunos enlaces útiles:
https://hexdocs.pm/libcluster/readme.html
https://hexdocs.pm/libcluster/Cluster.Strategy.Kubernetes.DNS.html
https://brain.d.foundation/Engineering/Backend/libcluster+in+elixir

y por último pero no menos importante, ¡buena suerte!
<br />

##### **Notas finales**
Haceme saber si hay algo que te gustaría ver implementado, probado, explorado o lo que sea en este espacio...
<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, mandame un mensaje para que se pueda corregir.

También podés revisar el código fuente y los cambios en los [sources aquí](https://github.com/kainlite/tr)

<br />
