%{
  title: "Upgrading K3S with system-upgrade-controller",
  author: "Gabriel Garrido",
  description: "Upgrading K3S with system-upgrade-controller",
  tags: ~w(k3s kubernetes linux),
  published: true,
  image: "kubernetes.png",
  sponsored: false,
  video: ""
}
---

##### **Introduction**
In this brief update, I will share how you can leverage the system-upgrade-controller to upgrade your clusters,
basically this blog runs on a k3s cluster, but it was running kubernetes 1.24, I decided it was time to update it so
among the options we had the system-upgrade-controller, after looking into it for a bit I decided it was worth testing
it.

* https://github.com/k3s-io/k3s-upgrade
* https://github.com/rancher/system-upgrade-controller?tab=readme-ov-file

##### **Important considerations**

If you are running stateful workloads or have things like longhorn configured first go and read the maintenance and
upgrade page:

* https://longhorn.io/docs/1.6.0/maintenance/maintenance/

For any other workload you should aim to do the same in order to understand what can block or become unavailable by the
upgrade, any workload that relies on PodDisruptionBudget can also cause issues during the upgrade, my recommendation
would be to detach any PVC before moving forward and then proceed with the upgrade.

If the process gets stuck and it cannot be completed in a given node you can always fetch the binary from github,
example:

* https://github.com/k3s-io/k3s/releases/tag/v1.29.1%2Bk3s2

Then look for the right binary for your architecture, in this case ARM64:

* https://github.com/k3s-io/k3s/releases/download/v1.29.1%2Bk3s2/k3s-arm64
<br />

Jump into the node, go to `/usr/local/bin`, and then:
```elixir
mv k3s k3s.backup
wget https://github.com/k3s-io/k3s/releases/download/v1.29.1%2Bk3s2/k3s-arm64
mv k3s-arm64 k3s
chmod +x k3s

# if the node is a master node
sudo systemctl restart k3s

# or if the node is a worker
sudo systemctl restart k3s-agent
```
<br />

##### **How does it work?**
First you need to install it, I won't delve into much detail but I went with the classic kubectl command:
```elixir
kubectl apply -f https://raw.githubusercontent.com/rancher/system-upgrade-controller/master/manifests/system-upgrade-controller.yaml
``` 
<br />

After that we need to label the nodes that you want to upgrade
```elixir
kubectl label node inst-759va-k3s-workers k3s-upgrade=true
kubectl label node inst-0uk8y-k3s-servers k3s-upgrade=true
kubectl label node inst-sd4tu-k3s-workers k3s-upgrade=true
kubectl label node inst-ziim5-k3s-servers k3s-upgrade=true
```
<br />

Then the final bit, the plan for the controller, save this as `upgrade.yaml` and apply it with kubectl:
```elixir
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-latest
  namespace: system-upgrade
spec:
  concurrency: 1
  version: v1.29.1+k3s2
  nodeSelector:
    matchExpressions:
      - {key: k3s-upgrade, operator: Exists}
  serviceAccountName: system-upgrade
  drain:
    force: true
  upgrade:
    image: rancher/k3s-upgrade
```
<br />

Once that's applied the upgrade will start node by node, once it's complete you will have your cluster running in the
new version as expected, there are some things that can block the progress on some nodes so pay attention to that as
mentioned at the beggining of the article, but if everything goes well you should see something like this:

```elixir
❯ kubectl get pods -A | grep upgrade
system-upgrade     system-upgrade-controller-5b5c68955d-dq7rm           1/1     Running     5 (66m ago)    19h

❯ kubectl get nodes -A
NAME                     STATUS   ROLES                       AGE    VERSION
inst-0uk8y-k3s-servers   Ready    control-plane,etcd,master   536d   v1.29.1+k3s2
inst-759va-k3s-workers   Ready    <none>                      536d   v1.29.1+k3s2
inst-sd4tu-k3s-workers   Ready    <none>                      536d   v1.29.1+k3s2
...
```

And last but not least good luck!
<br />

##### **Closing notes**
Let me know if there is anything that you would like to see implemented or tested, explored and what not in here...
<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
