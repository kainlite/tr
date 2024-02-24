%{
  title: "Running a phoenix app in a multinode fashion in kubernetes",
  author: "Gabriel Garrido",
  description: "Running a phoenix app in a multinode fashion in kubernetes",
  tags: ~w(elixir phoenix kubernetes),
}
---

##### **Introduction**
In this brief update, I'm going to make all nodes able to connect and communicate with each other using the library
libcluster with some basic configuration.

##### **Upgrading packages**
For that to work you need to add in `mix.exs`:
```shell
    {:libcluster, "~> 3.3"},
``` 

Update your `lib/tr/application.ex` file to start libcluster
```
    topologies = Application.get_env(:libcluster, :topologies, [])

    children = [
      # Start the Cluster supervisor for libcluster
      {Cluster.Supervisor, [topologies, [name: Tr.ClusterSupervisor]]},
      ...
```

Then we need to update our `config/config.exs` file to tell libcluster what to look for in the cluster:
```
# Libcluster configuration
namespace =
  System.get_env("NAMESPACE") || "tr"

config :libcluster,
  topologies: [
    default: [
      strategy: Elixir.Cluster.Strategy.Kubernetes,
      config: [
        mode: :ip,
        kubernetes_node_basename: "tr",
        kubernetes_selector: "app=tr",
        kubernetes_namespace: namespace,
        kubernetes_ip_lookup_mode: :pods,
        polling_interval: 10_000
      ]
    ]
  ]
```

That's enough for elixir to try to find the other pods and attempt to connect to the nodes, however we need to allow
that communication and let the pods read the information from the kubernetes API, next up add these permissions to your
deployment `05-role.yaml`:

```
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: tr
  name: pod-reader
rules:
  - apiGroups: [""]
    resources: ["pods"]
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


Some useful links:
https://hexdocs.pm/libcluster/readme.html

and last but not least good luck!

##### **Closing notes**
Let me know if there is anything that you would like to see implemented or tested, explored and what not in here...

This was based from the steps described in the [official upgrade notes]().

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)
