%{
  title: "Kubernetes local playground alternatives",
  author: "Gabriel Garrido",
  description: "In this article we will explore different alternatives for spinning up a cluster locally for testing, practicing or just developing an application...",
  tags: ~w(kubernetes vagrant linux),
  published: true,
}
---

![kubernetes](/images/kubernetes.jpg){:class="mx-auto"}

##### **Introduction**
In this article we will explore different alternatives for spinning up a cluster locally for testing, practicing or just developing an application.

The source code and/or documentation of the projects that we will be testing are listed here:
* [minikube](https://minikube.sigs.k8s.io/docs/start/)
* [kind](https://kind.sigs.k8s.io/docs/user/quick-start/)
* [Kubernetes the hard way using vagrant](https://github.com/kainlite/kubernetes-the-easy-way-with-vagrant)
* [Kubernetes with kubeadm using vagrant](https://github.com/kainlite/kubernetes-the-easy-way-with-vagrant-and-kubeadm)

There are more alternatives like [Microk8s](https://microk8s.io/) but I will leave that as an exercise for the reader.

If you want to give it a try to each one make sure to follow their recommended way of install or your distro/system way.

The first two (minikube and kind) we will see how to configure a CNI plugin in order to be able to use [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/), in the other two environments you can customize everything and these are best for learning rather than for daily usage but if you have enough ram you could do that as well.

We will be using the following pods and network policy to test that it works, we will create 3 pods, 1 client and 2 app backends, one backend will be listening in port TCP/1111 and the other in the port TCP/2222, in our netpolicy we will only allow our client to connect to app1:
```elixir
---
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    app: client
  name: client
spec:
  containers:
  - image: busybox:1.32.0
    name: client
    command:
    - sh
    - -c
    - sleep 7d
  dnsPolicy: ClusterFirst
  restartPolicy: Always
---
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    app: app1
  name: app1
spec:
  containers:
  - image: busybox:1.32.0
    name: app1
    command:
    - sh
    - -c
    - nc -l -v -p 1111 -k
  dnsPolicy: ClusterFirst
  restartPolicy: Always
---
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    app: app2
  name: app2
spec:
  containers:
  - image: busybox:1.32.0
    name: app2
    command:
    - sh
    - -c
    - nc -l -v -p 2222 -k
  dnsPolicy: ClusterFirst
  restartPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  name: app1
  labels:
    app: app1
spec:
  ports:
  - port: 1111
    protocol: TCP
  selector:
    app: app1
---
apiVersion: v1
kind: Service
metadata:
  name: app2
  labels:
    app: app2
spec:
  ports:
  - port: 2222
    protocol: TCP
  selector:
    app: app2
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-network-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: client
  policyTypes:
  - Egress
  egress:
  - to:
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
  - to:
    - podSelector:
        matchLabels:
          app: app1
    ports:
    - protocol: TCP
      port: 1111

```

If you want to learn more about netcat and friends go to: [Cat and friends: netcat and socat](https://techsquad.rocks/blog/cat_and_friends_netcat_socat/)

##### Minikube
Minikube is heavily used but it can be too heavy sometimes, in any case we will see an example of making it work with network policies, the good thing is that it has a lot of documentation because a lot of people use it and it is updated often:
```elixir
❯ minikube start --cni=cilium --memory=4096
😄  minikube v1.15.1 on Arch rolling
    ▪ MINIKUBE_ACTIVE_DOCKERD=minikube
✨  Automatically selected the docker driver
👍  Starting control plane node minikube in cluster minikube
🔥  Creating docker container (CPUs=2, Memory=4096MB) ...
🐳  Preparing Kubernetes v1.19.4 on Docker 19.03.13 ...
🔗  Configuring Cilium (Container Networking Interface) ...
🔎  Verifying Kubernetes components...
🌟  Enabled addons: storage-provisioner, default-storageclass
🏄  Done! kubectl is now configured to use "minikube" cluster and "default" namespace by default

```

###### Give it a couple of minutes to start, for new versions of minikube you can install it like this, otherwise you can specify that you will install the CNI plugin and then just install the manifests.
```elixir
❯ kubectl get pods -A
NAMESPACE     NAME                               READY   STATUS     RESTARTS   AGE
kube-system   cilium-c5bf8                       0/1     Running    0          59s
kube-system   cilium-operator-5d8498fc44-hpzbk   1/1     Running    0          59s
kube-system   coredns-f9fd979d6-qs2m8            1/1     Running    0          3m46s
kube-system   etcd-minikube                      1/1     Running    0          3m54s
...

```

###### Then let's validate that it works
```elixir
❯ kubectl apply -f netpol-example.yaml
pod/client configured
pod/app1 configured
pod/app2 configured
service/app1 created
service/app2 created
networkpolicy.networking.k8s.io/default-network-policy created

❯ kubectl exec pod/client -- nc -v -z app1 1111
app1 (10.103.109.255:1111) open

❯ kubectl exec pod/client -- timeout 5 nc -v -z app2 2222
punt!
command terminated with exit code 143

❯ kubectl exec pod/client -- nc -v -z app2 2222 -w 5
nc: app2 (10.97.248.246:2222): Connection timed out
command terminated with exit code 1
```

Note that we add the timeout command with 5 seconds wait so we don't have to really wait for nc timeout which by default is no timeout, we also tested with nc timeout.

You can get more info for minikube using Cilium on their [docs](https://docs.cilium.io/en/v1.9/gettingstarted/minikube/)

###### Remember to clean up
```elixir
❯ minikube delete
🔥  Deleting "minikube" in docker ...
🔥  Deleting container "minikube" ...
🔥  Removing /home/kainlite/.minikube/machines/minikube ...
💀  Removed all traces of the "minikube" cluster.

```

##### KIND
KIND is really lightweight and fast, I usually test and develop using KIND the main reason is that almost everything works like in a real cluster but it has no overhead, it's simple to install and easy to run, first we need to put this config in place to tell kind not to use it's default CNI.
```elixir
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true # disable kindnet
  podSubnet: 192.168.0.0/16 # set to Calico's default subnet
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 30000
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
- role: worker
- role: worker
- role: worker

```

Then we can create the cluster and install calico (there is a small gotcha here, you need to check that the calico node pods come up if not kill them and they should come up and everything will start working normally, this is due to the environment variable that gets added after the deployment for it to work with KIND):
```elixir
❯ kind create cluster --config kind-calico.yaml
Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.18.2) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/

❯ kubectl apply -f https://docs.projectcalico.org/v3.17/manifests/calico.yaml
configmap/calico-config created
customresourcedefinition.apiextensions.k8s.io/bgpconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/bgppeers.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/blockaffinities.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/clusterinformations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/felixconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworksets.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/hostendpoints.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamblocks.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamconfigs.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamhandles.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ippools.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/kubecontrollersconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networksets.crd.projectcalico.org created
clusterrole.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrolebinding.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrole.rbac.authorization.k8s.io/calico-node created
clusterrolebinding.rbac.authorization.k8s.io/calico-node created
daemonset.apps/calico-node created
serviceaccount/calico-node created
deployment.apps/calico-kube-controllers created
serviceaccount/calico-kube-controllers created
poddisruptionbudget.policy/calico-kube-controllers created

❯ kubectl -n kube-system set env daemonset/calico-node FELIX_IGNORELOOSERPF=true
daemonset.apps/calico-node env updated

```

You can check for more config options for KIND [here](https://kind.sigs.k8s.io/docs/user/configuration/#networking)

###### Validation
```elixir
❯ kubectl get pods -A
NAMESPACE            NAME                                         READY   STATUS    RESTARTS   AGE
kube-system          calico-kube-controllers-5dc87d545c-2kdn2     1/1     Running   0          2m15s
kube-system          calico-node-5pxsg                            1/1     Running   0          25s
kube-system          calico-node-jk5jq                            1/1     Running   0          25s
kube-system          calico-node-ps44s                            1/1     Running   0          25s
kube-system          calico-node-spdpb                            1/1     Running   0          25s
kube-system          coredns-f9fd979d6-gxmcw                      1/1     Running   0          3m14s
kube-system          coredns-f9fd979d6-t2d7t                      1/1     Running   0          3m14s
kube-system          etcd-kind-control-plane                      1/1     Running   0          3m17s
kube-system          kube-apiserver-kind-control-plane            1/1     Running   0          3m17s
kube-system          kube-controller-manager-kind-control-plane   1/1     Running   0          3m17s
kube-system          kube-proxy-ldtw7                             1/1     Running   0          3m4s
kube-system          kube-proxy-rggbh                             1/1     Running   0          3m4s
kube-system          kube-proxy-s2xjw                             1/1     Running   0          3m13s
kube-system          kube-proxy-slbkp                             1/1     Running   0          3m5s
kube-system          kube-scheduler-kind-control-plane            1/1     Running   0          3m17s
local-path-storage   local-path-provisioner-78776bfc44-w8kp6      1/1     Running   0          3m14s

❯ kubectl apply -f netpol-example.yaml
pod/client created
pod/app1 created
pod/app2 created
service/app1 created
service/app2 created
networkpolicy.networking.k8s.io/default-network-policy created

```

###### Testing again:
```elixir
❯ kubectl exec pod/client -- nc -v -z app1 1111 -w 5
app1 (10.96.126.52:1111) open

☸ kind-kind in ~ on ☁️ took 5s
❯ kubectl exec pod/client -- nc -v -z app2 2222 -w 5
nc: app2 (10.96.187.41:2222): Connection timed out
command terminated with exit code 1

```

##### Kubeadm and vagrant
This is an interesting scenario and it's great to understand how clusters are configured using kubeadm also to practice things such as adding/removing/upgrading the nodes, backup and restore etcd, etc. if you want to test this one clone this repo: [Kubernetes with kubeadm using vagrant](https://github.com/kainlite/kubernetes-the-easy-way-with-vagrant-and-kubeadm)
```elixir
❯ ./up.sh
Bringing machine 'cluster1-master1' up with 'virtualbox' provider...
Bringing machine 'cluster1-worker1' up with 'virtualbox' provider...
Bringing machine 'cluster1-worker2' up with 'virtualbox' provider...
==> cluster1-master1: Importing base box 'ubuntu/bionic64'...
==> cluster1-master1: Matching MAC address for NAT networking...
==> cluster1-master1: Setting the name of the VM: cluster1-master1
==> cluster1-master1: Clearing any previously set network interfaces...
==> cluster1-master1: Preparing network interfaces based on configuration...
...
...
...
...
    cluster1-worker2: This node has joined the cluster:
    cluster1-worker2: * Certificate signing request was sent to apiserver and a response was received.
    cluster1-worker2: * The Kubelet was informed of the new secure connection details.
    cluster1-worker2:
    cluster1-worker2: Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
######################## WAITING TILL ALL NODES ARE READY ########################
######################## INITIALISING K8S RESOURCES ########################
namespace/development created
namespace/management created
service/m-2x3-api-svc created
service/m-2x3-web-svc created
priorityclass.scheduling.k8s.io/high-priority-important created
deployment.apps/web-test created
deployment.apps/web-test-2 created
deployment.apps/web-dev-shop created
deployment.apps/web-dev-shop-dev2 created
deployment.apps/what-a-deployment created
deployment.apps/m-2x3-api created
deployment.apps/m-2x3-web created
deployment.apps/m-3cc-runner created
deployment.apps/m-3cc-runner-heavy created
pod/important-pod created
pod/web-server created
Connection to 127.0.0.1 closed.
Connection to 127.0.0.1 closed.
######################## ALL DONE ########################
```

###### Next, lets copy the kubeconfig and deploy our resources then test (this deployment is using weave)
```elixir
❯ vagrant ssh cluster1-master1 -c "sudo cat /root/.kube/config" > vagrant-kubeconfig
Connection to 127.0.0.1 closed.

❯ export KUBECONFIG="$(pwd)/vagrant-kubeconfig"

❯ kubectl apply -f ~/netpol-example.yaml
pod/client created
pod/app1 created
pod/app2 created
service/app1 created
service/app2 created
networkpolicy.networking.k8s.io/default-network-policy created

❯ kubectl get pods
NAME                          READY   STATUS              RESTARTS   AGE
app1                          0/1     ContainerCreating   0          6s
app2                          1/1     Running             0          6s
client                        0/1     ContainerCreating   0          6s
web-test-2-594487698d-vnltx   1/1     Running             0          2m33s

```

###### Test it (wait until the pods are in ready state)
```elixir
❯ kubectl exec pod/client -- nc -v -z app1 1111
app1 (10.97.203.229:1111) open

❯ kubectl exec pod/client -- nc -v -z app2 2222 -w 5
nc: app2 (10.108.254.138:2222): Connection timed out
command terminated with exit code 1

```

###### For more info refer to the readme in the repo and the scripts in there, it should be straight forward to follow and reproduce, remember to clean up:
```elixir
❯ ./down.sh
==> cluster1-worker2: Forcing shutdown of VM...
==> cluster1-worker2: Destroying VM and associated drives...
==> cluster1-worker1: Forcing shutdown of VM...
==> cluster1-worker1: Destroying VM and associated drives...
==> cluster1-master1: Forcing shutdown of VM...
==> cluster1-master1: Destroying VM and associated drives...

```

##### Kubernetes the hard way and vagrant
This is probably the most complex scenario and it's purely educational you get to generate all the certificates by hand basically and configure everything by yourself (see the original repo for instructions in how to do that in gcloud if you are interested), if you want to test this one clone this repo: [Kubernetes the hard way using vagrant](https://github.com/kainlite/kubernetes-the-easy-way-with-vagrant), but be patient and ready to debug if something doesn't go well.
```elixir
❯ ./up.sh
...
...
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
Created symlink /etc/systemd/system/multi-user.target.wants/containerd.service → /etc/systemd/system/containerd.service.
Created symlink /etc/systemd/system/multi-user.target.wants/kubelet.service → /etc/systemd/system/kubelet.service.
Created symlink /etc/systemd/system/multi-user.target.wants/kube-proxy.service → /etc/systemd/system/kube-proxy.service.
Connection to 127.0.0.1 closed.
######################## WAITING TILL ALL NODES ARE READY ########################
######################## ALL DONE ########################

❯ vagrant status
Current machine states:

controller-0              running (virtualbox)
controller-1              running (virtualbox)
controller-2              running (virtualbox)
worker-0                  running (virtualbox)
worker-1                  running (virtualbox)
worker-2                  running (virtualbox)

This environment represents multiple VMs. The VMs are all listed
above with their current state. For more information about a specific
VM, run `vagrant status NAME`.

```

###### Validation:
```elixir
❯ vagrant ssh controller-0
Welcome to Ubuntu 18.04.5 LTS (GNU/Linux 4.15.0-124-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Fri Nov 27 20:19:24 UTC 2020

  System load:  0.7               Processes:             109
  Usage of /:   16.0% of 9.63GB   Users logged in:       1
  Memory usage: 58%               IP address for enp0s3: 10.0.2.15
  Swap usage:   0%                IP address for enp0s8: 10.20.0.100


0 packages can be updated.
0 updates are security updates.

New release '20.04.1 LTS' available.
Run 'do-release-upgrade' to upgrade to it.


Last login: Fri Nov 27 20:18:52 2020 from 10.0.2.2


root@controller-0:~# kubectl get componentstatus
NAME                 STATUS    MESSAGE             ERROR
controller-manager   Healthy   ok
scheduler            Healthy   ok
etcd-1               Healthy   {"health":"true"}
etcd-0               Healthy   {"health":"true"}
etcd-2               Healthy   {"health":"true"}


root@controller-0:~# kubectl get nodes
NAME       STATUS   ROLES    AGE     VERSION
worker-0   Ready    <none>   4m6s    v1.18.6
worker-1   Ready    <none>   3m56s   v1.18.6
worker-2   Ready    <none>   3m47s   v1.18.6
root@controller-0:~#

```
```elixir
root@controller-0:~# kubectl apply -f /vagrant/manifests/coredns-1.7.0.yaml
serviceaccount/coredns created
clusterrole.rbac.authorization.k8s.io/system:coredns created
clusterrolebinding.rbac.authorization.k8s.io/system:coredns created
configmap/coredns created
deployment.apps/coredns created
service/kube-dns created

root@controller-0:~# kubectl apply -f /vagrant/manifests/netpol-example.yaml
pod/client created
pod/app1 created
pod/app2 created
service/app1 created
service/app2 created
networkpolicy.networking.k8s.io/default-network-policy created

root@controller-0:~# kubectl get pods
NAME     READY   STATUS    RESTARTS   AGE
app1     1/1     Running   0          104s
app2     1/1     Running   0          104s
client   1/1     Running   0          104s


root@controller-0:~# kubectl get pods,svc,netpol
NAME         READY   STATUS    RESTARTS   AGE
pod/app1     1/1     Running   0          113s
pod/app2     1/1     Running   0          113s
pod/client   1/1     Running   0          113s

NAME                 TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
service/app1         ClusterIP   10.32.0.20    <none>        1111/TCP   113s
service/app2         ClusterIP   10.32.0.138   <none>        2222/TCP   112s
service/kubernetes   ClusterIP   10.32.0.1     <none>        443/TCP    11m

NAME                                                     POD-SELECTOR   AGE
networkpolicy.networking.k8s.io/default-network-policy   app=client     112s

```


###### Install the manifests and test it:
```elixir
root@controller-0:~# kubectl get pods -A -o wide
NAMESPACE     NAME                       READY   STATUS    RESTARTS   AGE     IP           NODE       NOMINATED NODE   READINESS GATES
default       app1                       1/1     Running   0          6m34s   10.200.0.2   worker-1   <none>           <none>
default       app2                       1/1     Running   0          6m34s   10.200.0.3   worker-0   <none>           <none>
default       client                     1/1     Running   0          20s     10.200.0.4   worker-1   <none>           <none>
kube-system   coredns-5677dc4cdb-2xjhx   1/1     Running   0          6m57s   10.200.0.2   worker-0   <none>           <none>
kube-system   coredns-5677dc4cdb-qmqzs   1/1     Running   0          6m57s   10.200.0.2   worker-2   <none>           <none>
root@controller-0:~# kubectl exec client -- nc -v -z 10.200.0.2 1111
10.200.0.2 (10.200.0.2:1111) open
root@controller-0:~# kubectl exec client -- nc -v -z 10.200.0.3 2222 -w 5
nc: 10.200.0.3 (10.200.0.3:2222): No route to host
command terminated with exit code 1

```

###### Clean up
```elixir
❯ ./down.sh
==> worker-2: Forcing shutdown of VM...
==> worker-2: Destroying VM and associated drives...
==> worker-1: Forcing shutdown of VM...
==> worker-1: Destroying VM and associated drives...
==> worker-0: Forcing shutdown of VM...
==> worker-0: Destroying VM and associated drives...
==> controller-2: Forcing shutdown of VM...
==> controller-2: Destroying VM and associated drives...
==> controller-1: Forcing shutdown of VM...
==> controller-1: Destroying VM and associated drives...
==> controller-0: Forcing shutdown of VM...
==> controller-0: Destroying VM and associated drives...

```

##### Wrap up
Each alternative has its use case, test each one and pick the one that best fit your needs.

##### Clean up
Remember to clean up to recover some resources in your machine.

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)
