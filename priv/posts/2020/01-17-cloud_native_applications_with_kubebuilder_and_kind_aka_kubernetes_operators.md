%{
  title: "Cloud native applications with kubebuilder and kind aka kubernetes operators",
  author: "Gabriel Garrido",
  description: "In this article we will see how to use kubebuilder and kind to create and test an operator...",
  tags: ~w(golang kubernetes kubebuilder kind linux),
  published: true,
  image: "forward.png"
}
---

![forward](/images/forward.png){:class="mx-auto"}

##### **Introduction**
In this article we will see how to use [kubebuilder](https://github.com/kubernetes-sigs/kubebuilder) and [Kind](https://github.com/kubernetes-sigs/kind) to create a local test cluster and an operator, then deploy that operator in the cluster and test it, the repository with the files can be found here, also if you want to learn more about the idea and the project go: [forward](https://github.com/kainlite/forward).

Basically what the code does is create an alpine/socat pod and you can specify the host, port and protocol and it will make a tunnel for you, so then you can use port-forward or a service or ingress or whatever to expose things that are in another private subnet, while this might not sound like a good idea it has some use cases, so check your security constraints before doing any of that in a normal scenario it should be safe, it can be useful for testing or for reaching a DB while doing some debugging or test, but well, that is for another discussion, the tools used here is what makes this so interesting, this is a cloud native application, since it native to kubernetes and that's what we will explore here.

While Kind is not actually a requirement I used that for testing and really liked it, it's faster and simpler than minikube.

Also if you are interested how I got the idea to make this operator check this [github issue](https://github.com/kubernetes/kubernetes/issues/72597).

##### **Prerequisites**
* [kubebuilder](https://github.com/kubernetes-sigs/kubebuilder)
* [kustomize](https://github.com/kubernetes-sigs/kustomize)
* [Go 1.13](https://golang.org/dl/)
* [Kind](https://github.com/kubernetes-sigs/kind)
* [Docker](https://hub.docker.com/?overlay=onboarding)

##### Create the project
In this step we need to create the kubebuilder project, so in an empty folder we run:
```elixir
$ go mod init techsquad.rocks
go: creating new go.mod: module techsquad.rocks

$ kubebuilder init --domain techsquad.rocks
go get sigs.k8s.io/controller-runtime@v0.4.0
go mod tidy
Running make...
make
/home/kainlite/Webs/go/bin/controller-gen object:headerFile=./hack/boilerplate.go.txt paths="./..."
go fmt ./...
go vet ./...
go build -o bin/manager main.go
Next: Define a resource with:
$ kubebuilder create api
```

##### Create the API
Next let's create an API, something for us to have control of (our controller).
```elixir
$ kubebuilder create api --group forward --version v1beta1 --kind Map
Create Resource [y/n]
y
Create Controller [y/n]
y
Writing scaffold for you to edit...
api/v1beta1/map_types.go
controllers/map_controller.go
Running make...
/home/kainlite/Webs/go/bin/controller-gen object:headerFile=./hack/boilerplate.go.txt paths="./..."
go fmt ./...
go vet ./...
go build -o bin/manager main.go

```
```elixir
$ kubebuilder create api --group forward --version v1beta1 --kind Map
Create Resource [y/n]
y
Create Controller [y/n]
y
Writing scaffold for you to edit...
api/v1beta1/map_types.go
controllers/map_controller.go
Running make...
/home/kainlite/Webs/go/bin/controller-gen object:headerFile=./hack/boilerplate.go.txt paths="./..."
go fmt ./...
go vet ./...
go build -o bin/manager main.go
```

Right until here we only have some boilerplate and basic or empty project with defaults, if you test it now it will work, but it won't do anything interesting, but it covers a lot of ground and we should be grateful that such a tool exists.

##### Add our code to the mix
First we will add it to `api/v1beta1/map_types.go`, which will add our fields to our type.
```elixir
/*

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1beta1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	PhasePending = "PENDING"
	PhaseRunning = "RUNNING"
	PhaseFailed  = "FAILED"
)

// MapSpec defines the desired state of Map
type MapSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// TCP/UDP protocol
	Protocol string `json:"protocol,omitempty"`

	// Port
	Port int `json:"port,omitempty"`

	// Host
	Host string `json:"host,omitempty"`
}

// MapStatus defines the observed state of Map
type MapStatus struct {
	Phase string `json:"phase,omitempty"`
}

// +kubebuilder:object:root=true

// Map is the Schema for the maps API
type Map struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   MapSpec   `json:"spec,omitempty"`
	Status MapStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// MapList contains a list of Map
type MapList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Map `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Map{}, &MapList{})
}
```
Basically we just edited the `MapSpec` and the `MapStatus` struct.

Now we need to add the code to our controller in `controllers/map_controller.go`
```elixir
/*

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controllers

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	forwardv1beta1 "github.com/kainlite/forward/api/v1beta1"
)

// +kubebuilder:rbac:groups=maps.forward.techsquad.rocks,resources=pods,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=map.forward.techsquad.rocks,resources=pods,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=forward.techsquad.rocks,resources=maps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=forward.techsquad.rocks,resources=pods/status,verbs=get;update;patch
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch;create;update;patch;delete

// MapReconciler reconciles a Map object
type MapReconciler struct {
	client.Client
	Log    logr.Logger
	Scheme *runtime.Scheme
}

func newPodForCR(cr *forwardv1beta1.Map) *corev1.Pod {
	labels := map[string]string{
		"app": cr.Name,
	}
	var command string
	if strings.EqualFold(cr.Spec.Protocol, "tcp") {
		command = fmt.Sprintf("socat -d -d tcp-listen:%s,fork,reuseaddr tcp-connect:%s:%s", strconv.Itoa(cr.Spec.Port), cr.Spec.Host, strconv.Itoa(cr.Spec.Port))
	} else if strings.EqualFold(cr.Spec.Protocol, "udp") {
		command = fmt.Sprintf("socat -d -d UDP4-RECVFROM:%s,fork,reuseaddr UDP4-SENDTO:%s:%s", strconv.Itoa(cr.Spec.Port), cr.Spec.Host, strconv.Itoa(cr.Spec.Port))
	} else {
		// TODO: Create a proper error here if the protocol doesn't match or is unsupported
		command = fmt.Sprintf("socat -V")
	}

	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "forward-" + cr.Name + "-pod",
			Namespace: cr.Namespace,
			Labels:    labels,
		},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{
				{
					Name:    "map",
					Image:   "alpine/socat",
					Command: strings.Split(command, " "),
				},
			},
			RestartPolicy: corev1.RestartPolicyOnFailure,
		},
	}
}

func (r *MapReconciler) Reconcile(req ctrl.Request) (ctrl.Result, error) {
	reqLogger := r.Log.WithValues("namespace", req.Namespace, "MapForward", req.Name)
	reqLogger.Info("=== Reconciling Forward Map")
	// Fetch the Map instance
	instance := &forwardv1beta1.Map{}
	err := r.Get(context.TODO(), req.NamespacedName, instance)
	if err != nil {
		if errors.IsNotFound(err) {
			// Request object not found, could have been deleted after
			// reconcile request—return and don't requeue:
			return reconcile.Result{}, nil
		}
		// Error reading the object—requeue the request:
		return reconcile.Result{}, err
	}

	// If no phase set, default to pending (the initial phase):
	if instance.Status.Phase == "" || instance.Status.Phase == "PENDING" {
		instance.Status.Phase = forwardv1beta1.PhaseRunning
	}

	// Now let's make the main case distinction: implementing
	// the state diagram PENDING -> RUNNING or PENDING -> FAILED
	switch instance.Status.Phase {
	case forwardv1beta1.PhasePending:
		reqLogger.Info("Phase: PENDING")
		reqLogger.Info("Waiting to forward", "Host", instance.Spec.Host, "Port", instance.Spec.Port)
		instance.Status.Phase = forwardv1beta1.PhaseRunning
	case forwardv1beta1.PhaseRunning:
		reqLogger.Info("Phase: RUNNING")
		pod := newPodForCR(instance)
		// Set Map instance as the owner and controller
		err := controllerutil.SetControllerReference(instance, pod, r.Scheme)
		if err != nil {
			// requeue with error
			return reconcile.Result{}, err
		}
		found := &corev1.Pod{}
		nsName := types.NamespacedName{Name: pod.Name, Namespace: pod.Namespace}
		err = r.Get(context.TODO(), nsName, found)
		// Try to see if the pod already exists and if not
		// (which we expect) then create a one-shot pod as per spec:
		if err != nil && errors.IsNotFound(err) {
			err = r.Create(context.TODO(), pod)
			if err != nil {
				// requeue with error
				return reconcile.Result{}, err
			}
			reqLogger.Info("Pod launched", "name", pod.Name)
		} else if err != nil {
			// requeue with error
			return reconcile.Result{}, err
		} else if found.Status.Phase == corev1.PodFailed ||
			found.Status.Phase == corev1.PodSucceeded {
			reqLogger.Info("Container terminated", "reason",
				found.Status.Reason, "message", found.Status.Message)
			instance.Status.Phase = forwardv1beta1.PhaseFailed
		} else {
			// Don't requeue because it will happen automatically when the
			// pod status changes.
			return reconcile.Result{}, nil
		}
	case forwardv1beta1.PhaseFailed:
		reqLogger.Info("Phase: Failed, check that the host and port are reachable from the cluster and that there are no networks policies preventing this access or firewall rules...")
		return reconcile.Result{}, nil
	default:
		reqLogger.Info("NOP")
		return reconcile.Result{}, nil
	}

	// Update the At instance, setting the status to the respective phase:
	err = r.Status().Update(context.TODO(), instance)
	if err != nil {
		return reconcile.Result{}, err
	}

	// Don't requeue. We should be reconcile because either the pod
	// or the CR changes.
	return reconcile.Result{}, nil
}

func (r *MapReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&forwardv1beta1.Map{}).
		Complete(r)
}
```
In this controller we added two functions one to create a pod and modified basically the entire Reconcile function (this one takes care of checking the status and make the transitions in other words makes a controller work like a controller), also notice the kubebuilder annotations which will generate the rbac config for us, pretty handy! right?

##### Starting the cluster
Now we will use [Kind](https://github.com/kubernetes-sigs/kind) to create a local cluster to test
```elixir
$ kind create cluster --name test-cluster-1
Creating cluster "test-cluster-1" ...
 ✓ Ensuring node image (kindest/node:v1.16.3) 🖼 
 ✓ Preparing nodes 📦 
 ✓ Writing configuration 📜 
 ✓ Starting control-plane 🕹️ 
 ✓ Installing CNI 🔌 
 ✓ Installing StorageClass 💾 
Set kubectl context to "kind-test-cluster-1"
You can now use your cluster with:

kubectl cluster-info --context kind-test-cluster-1

Thanks for using kind! 😊

```
it could be that easy!?!?! yes, it is!

##### Running our operator locally
For testing you can run your operator locally like this:
```elixir
$ make run
/home/kainlite/Webs/go/bin/controller-gen object:headerFile=./hack/boilerplate.go.txt paths="./..."
go fmt ./...
go vet ./...
/home/kainlite/Webs/go/bin/controller-gen "crd:trivialVersions=true" rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases
go run ./main.go
2020-01-17T21:00:14.465-0300    INFO    controller-runtime.metrics      metrics server is starting to listen    {"addr": ":8080"}
2020-01-17T21:00:14.466-0300    INFO    setup   starting manager
2020-01-17T21:00:14.466-0300    INFO    controller-runtime.manager      starting metrics server {"path": "/metrics"}
2020-01-17T21:00:14.566-0300    INFO    controller-runtime.controller   Starting EventSource    {"controller": "map", "source": "kind source: /, Kind="}
2020-01-17T21:00:14.667-0300    INFO    controller-runtime.controller   Starting Controller     {"controller": "map"}
2020-01-17T21:00:14.767-0300    INFO    controller-runtime.controller   Starting workers        {"controller": "map", "worker count": 1}

```

##### Testing it
First we spin up a pod, and launch `nc -l -p 8000`
```elixir
$ kubectl run -it --rm --restart=Never alpine --image=alpine sh
If you don't see a command prompt, try pressing enter.

# ifconfig
eth0      Link encap:Ethernet  HWaddr E6:49:53:CA:3D:89  
          inet addr:10.244.0.8  Bcast:10.244.0.255  Mask:255.255.255.0
          inet6 addr: fe80::e449:53ff:feca:3d89/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:9 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0 
          RX bytes:0 (0.0 B)  TX bytes:698 (698.0 B)

lo        Link encap:Local Loopback  
          inet addr:127.0.0.1  Mask:255.0.0.0
          inet6 addr: ::1/128 Scope:Host
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000 
          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)
/ # nc -l -p 8000
test

```

Then we edit our manifest and apply it, check that everything is in place, and do the port-forward and launch another `nc localhost 8000` to test if everything went well.
First the manifest
```elixir
$ cat config/samples/forward_v1beta1_map.yaml 
apiVersion: forward.techsquad.rocks/v1beta1
kind: Map
metadata:
  name: mapsample
  namespace: default
spec:
  host: 10.244.0.8
  port: 8000
  protocol: tcp

```
Then the port-forward and test
```elixir
$ kubectl apply -f config/samples/forward_v1beta1_map.yaml
map.forward.techsquad.rocks/mapsample configured

# Logs in the controller
2020-01-17T23:38:27.650Z        INFO    controllers.Map === Reconciling Forward Map     {"namespace": "default", "MapForward": "mapsample"}
2020-01-17T23:38:27.691Z        INFO    controllers.Map Phase: RUNNING  {"namespace": "default", "MapForward": "mapsample"}
2020-01-17T23:38:27.698Z        DEBUG   controller-runtime.controller   Successfully Reconciled {"controller": "map", "request": "default/mapsample"}

$ kubectl port-forward forward-mapsample-pod 8000:8000                                                                                                                                                                       
Forwarding from 127.0.0.1:8000 -> 8000                                                                                                                                                                                                                                           
Handling connection for 8000                                               

# In another terminal or tab or split
$ nc localhost 8000
test

```

##### Making it publicly ready
Here we just build and push the docker image to dockerhub or our favorite public registry.
```elixir
$ make docker-build docker-push IMG=kainlite/forward:0.0.1
/home/kainlite/Webs/go/bin/controller-gen object:headerFile=./hack/boilerplate.go.txt paths="./..."
go fmt ./...
go vet ./...
/home/kainlite/Webs/go/bin/controller-gen "crd:trivialVersions=true" rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases
go test ./... -coverprofile cover.out
?       github.com/kainlite/forward     [no test files]
?       github.com/kainlite/forward/api/v1beta1 [no test files]
ok      github.com/kainlite/forward/controllers 6.720s  coverage: 0.0% of statements
docker build . -t kainlite/forward:0.0.1
Sending build context to Docker daemon  45.02MB
Step 1/14 : FROM golang:1.13 as builder
1.13: Pulling from library/golang
8f0fdd3eaac0: Pull complete
...
...
...
 ---> 4dab137d22a1
Successfully built 4dab137d22a1
Successfully tagged kainlite/forward:0.0.1
docker push kainlite/forward:0.0.1
The push refers to repository [docker.io/kainlite/forward]
50a214d52a70: Pushed 
84ff92691f90: Pushed 
0d1435bd79e4: Pushed 
0.0.1: digest: sha256:b4479e4721aa9ec9e92d35ac7ad5c4c0898986d9d2c9559c4085d4c98d2e4ae3 size: 945

```
Then you can install it with `make deploy IMG=kainlite/forward:0.0.1` and uninstall it with `make uninstall`

##### **Closing notes**
Be sure to check the [kubebuilder book](https://book.kubebuilder.io/) if you want to learn more and the [kind docs](https://kind.sigs.k8s.io/docs/user/quick-start), I hope you enjoyed it and hope to see you on [twitter](https://twitter.com/kainlite) or [github](https://github.com/kainlite)!

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)
