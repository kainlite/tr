%{
  title: "Cloud native applications with kubebuilder and kind aka kubernetes operators",
  author: "Gabriel Garrido",
  description: "In this article we will see how to use kubebuilder and kind to create and test an operator...",
  tags: ~w(golang kubernetes kubebuilder kind linux),
  published: true,
  image: "forward.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![forward](/images/forward.png){:class="mx-auto"}

##### **Introduction**
In this article we will see how to use [kubebuilder](https://github.com/kubernetes-sigs/kubebuilder) and [Kind](https://github.com/kubernetes-sigs/kind) to create a local test cluster and an operator, then deploy that operator in the cluster and test it, the repository with the files can be found here, also if you want to learn more about the idea and the project go: [forward](https://github.com/kainlite/forward).
<br />

Basically what the code does is create an alpine/socat pod and you can specify the host, port and protocol and it will make a tunnel for you, so then you can use port-forward or a service or ingress or whatever to expose things that are in another private subnet, while this might not sound like a good idea it has some use cases, so check your security constraints before doing any of that in a normal scenario it should be safe, it can be useful for testing or for reaching a DB while doing some debugging or test, but well, that is for another discussion, the tools used here is what makes this so interesting, this is a cloud native application, since it native to kubernetes and that's what we will explore here.
<br />

While Kind is not actually a requirement I used that for testing and really liked it, it's faster and simpler than minikube.
<br />

Also if you are interested how I got the idea to make this operator check this [github issue](https://github.com/kubernetes/kubernetes/issues/72597).
<br />

##### **Prerequisites**
* [kubebuilder](https://github.com/kubernetes-sigs/kubebuilder)
* [kustomize](https://github.com/kubernetes-sigs/kustomize)
* [Go](https://golang.org/dl/)
* [Kind](https://github.com/kubernetes-sigs/kind)
* [Docker](https://hub.docker.com/?overlay=onboarding)


##### Note: this article was originally published on 17/01/2020, but rewritten/recreated to latest versions on 18/11/2024.

<br />

##### Create the project
In this step we need to create the kubebuilder project, so in an empty folder we run (to create a go project):
```elixir
❯ go mod init redbeard.team
go: creating new go.mod: module redbeard.team
```

<br />

Then we initialize our kubebuilder project:
```elixir
❯ kubebuilder init --domain redbeard.team --repo redbeard.team/forward
INFO Writing kustomize manifests for you to edit...
INFO Writing scaffold for you to edit...
INFO Get controller runtime:
$ go get sigs.k8s.io/controller-runtime@v0.19.1
INFO Update dependencies:
$ go mod tidy
Next: define a resource with:
$ kubebuilder create api
```

<br />

##### Create the API
Next let's create an API, something for us to have control of (our controller).
```elixir
❯ kubebuilder create api --group forward --version v1alpha1 --kind MapPort
INFO Create Resource [y/n]
y
INFO Create Controller [y/n]
y
INFO Writing kustomize manifests for you to edit...
INFO Writing scaffold for you to edit...
INFO api/v1alpha1/mapport_types.go
INFO api/v1alpha1/groupversion_info.go
INFO internal/controller/suite_test.go
INFO internal/controller/mapport_controller.go
INFO internal/controller/mapport_controller_test.go
INFO Update dependencies:
$ go mod tidy
INFO Running make:
$ make generate
mkdir -p ~/Webs/forward/bin
Downloading sigs.k8s.io/controller-tools/cmd/controller-gen@v0.16.4
~/Webs/forward/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
Next: implement your new API and generate the manifests (e.g. CRDs,CRs) with:
$ make manifests
```

<br />

Right until here we only have some boilerplate and basic or empty project with defaults, if you test it now it will work, 
but it won't do anything interesting, but it covers a lot of ground and mades our lives easier already.
<br />

##### Add our code to the mix
First we will add it to `api/v1alpha1/mapport_types.go`, which will add our fields to our type.
```elixir
/*
Copyright 2024.

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

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	PhasePending = "PENDING"
	PhaseRunning = "RUNNING"
	PhaseFailed  = "FAILED"
)

// MapPortSpec defines the desired state of MapPort.
type MapPortSpec struct {
	// TCP/UDP protocol
	Protocol string `json:"protocol,omitempty"`

	// Port
	Port int `json:"port,omitempty"`

	// Host
	Host string `json:"host,omitempty"`

	// LivenessProbe
	LivenessProbe bool `json:"liveness_probe"`
}

// MapPortStatus defines the observed state of MapPort.
type MapPortStatus struct {
	Phase string `json:"phase,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// MapPort is the Schema for the mapports API.
type MapPort struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   MapPortSpec   `json:"spec,omitempty"`
	Status MapPortStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// MapPortList contains a list of MapPort.
type MapPortList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []MapPort `json:"items"`
}

func init() {
	SchemeBuilder.Register(&MapPort{}, &MapPortList{})
}
```
Basically we just edited the `MapPortSpec` and the `MapPortStatus` struct to give it the fields that we want to use to configure
our deployments.

<br />

Now we need to add the code to our controller in `internal/controller/mapport_controller.go`
```elixir
/*
Copyright 2024.

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

package controller

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
	"sigs.k8s.io/controller-runtime/pkg/log"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	forwardv1alpha1 "redbeard.team/forward/api/v1alpha1"
)

// MapPortReconciler reconciles a MapPort object
type MapPortReconciler struct {
	client.Client
	Log    logr.Logger
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=forward.redbeard.team,resources=mapports,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=forward.redbeard.team,resources=mapports/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=forward.redbeard.team,resources=mapports/finalizers,verbs=update

// +kubebuilder:rbac:groups=mapports.forward.redbeard.team,resources=pods,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=mapports.forward.redbeard.team,resources=pods,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=forward.redbeard.team,resources=pods/status,verbs=get;update;patch
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch;create;update;patch;delete

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the MapPort object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.19.1/pkg/reconcile

func newPodForCR(cr *forwardv1alpha1.MapPort) *corev1.Pod {
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

	var livenessCommand string
	if cr.Spec.LivenessProbe {
		livenessCommand = fmt.Sprintf("nc -v -n -z %s %s", cr.Spec.Host, strconv.Itoa(cr.Spec.Port))
	} else {
		livenessCommand = fmt.Sprintf("echo")
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
					Name:    "mapport",
					Image:   "alpine/socat",
					Command: strings.Split(command, " "),
					LivenessProbe: &corev1.Probe{
						ProbeHandler: corev1.ProbeHandler{
							Exec: &corev1.ExecAction{
								Command: strings.Split(livenessCommand, " "),
							},
						},
					},
				},
			},
			RestartPolicy: corev1.RestartPolicyOnFailure,
		},
	}
}

func (r *MapPortReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = log.FromContext(ctx)

	reqLogger := r.Log.WithValues("namespace", req.Namespace, "MapPortForward", req.Name)
	reqLogger.Info("=== Reconciling Forward MapPort")
	// Fetch the MapPort instance
	instance := &forwardv1alpha1.MapPort{}
	err := r.Get(context.TODO(), req.NamespacedName, instance)
	if err != nil {
		if errors.IsNotFound(err) {
			// Request object not found, could have been deleted after
			// reconcile request—return and don't requeue:
			return ctrl.Result{}, nil
		}
		// Error reading the object—requeue the request:
		return ctrl.Result{}, err
	}

	// If no phase set, default to pending (the initial phase):
	if instance.Status.Phase == "" || instance.Status.Phase == "PENDING" {
		instance.Status.Phase = forwardv1alpha1.PhaseRunning
	}

	// Now let's make the main case distinction: implementing
	// the state diagram PENDING -> RUNNING or PENDING -> FAILED
	switch instance.Status.Phase {
	case forwardv1alpha1.PhasePending:
		reqLogger.Info("Phase: PENDING")
		reqLogger.Info("Waiting to forward", "Host", instance.Spec.Host, "Port", instance.Spec.Port)
		instance.Status.Phase = forwardv1alpha1.PhaseRunning

		// requeue the request
		return ctrl.Result{}, err
	case forwardv1alpha1.PhaseRunning:
		reqLogger.Info("Phase: RUNNING")
		pod := newPodForCR(instance)
		// Set MapPort instance as the owner and controller
		err := controllerutil.SetControllerReference(instance, pod, r.Scheme)
		if err != nil {
			// requeue with error
			return ctrl.Result{}, err
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
				return ctrl.Result{}, err
			}
			reqLogger.Info("Pod launched", "name", pod.Name)
		} else if err != nil {
			// requeue with error
			return ctrl.Result{}, err
		} else if found.Status.Phase == corev1.PodFailed ||
			found.Status.Phase == corev1.PodSucceeded {
			reqLogger.Info("Container terminated", "reason",
				found.Status.Reason, "message", found.Status.Message)
			instance.Status.Phase = forwardv1alpha1.PhaseFailed
		} else {
			// Don't requeue because it will happen automatically when the
			// pod status changes.
			return ctrl.Result{}, nil
		}
	case forwardv1alpha1.PhaseFailed:
		reqLogger.Info("Phase: Failed, check that the host and port are reachable from the cluster and that there are no networks policies preventing this access or firewall rules...")
		return ctrl.Result{}, nil
	default:
		reqLogger.Info("NOP")
		return ctrl.Result{}, nil
	}

	// Update the At instance, setting the status to the respective phase:
	err = r.Status().Update(context.TODO(), instance)
	if err != nil {
		return ctrl.Result{}, err
	}

	// Don't requeue. We should be reconcile because either the pod
	// or the CR changes.
	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *MapPortReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&forwardv1alpha1.MapPort{}).
		Named("mapport").
		Complete(r)
}
```
In this controller we added two functions one to create a pod and modified basically the entire Reconcile function 
(this one takes care of checking the status and make the transitions in other words makes a controller work like a controller), 
also notice the kubebuilder annotations which will generate the rbac config for us, pretty handy! right?

<br />

##### Starting the cluster
Now we will use [Kind](https://github.com/kubernetes-sigs/kind) to create a local cluster to test
```elixir
❯ kind create cluster
Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.30.0) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️                                                                                                                                                                                         ]
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/
```
it could be that easy!?!?! yes, it is!
<br />

##### Running our operator locally
For testing you can run your operator locally like this:
```elixir
make install
make run
```

The output should look something like this:
```elixir
~/Webs/forward/bin/controller-gen rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases
~/Webs/forward/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
go fmt ./...
go vet ./...
go run ./cmd/main.go
2024-11-18T11:32:50-03:00       INFO    setup   starting manager
2024-11-18T11:32:50-03:00       INFO    starting server {"name": "health probe", "addr": "[::]:8081"}
2024-11-18T11:32:50-03:00       INFO    Starting EventSource    {"controller": "mapport", "controllerGroup": "forward.redbeard.team", "controllerKind": "MapPort", "source": "kind source: *v1alpha1.MapPort"}
2024-11-18T11:32:50-03:00       INFO    Starting Controller     {"controller": "mapport", "controllerGroup": "forward.redbeard.team", "controllerKind": "MapPort"}
2024-11-18T11:32:50-03:00       INFO    Starting workers        {"controller": "mapport", "controllerGroup": "forward.redbeard.team", "controllerKind": "MapPort", "worker count": 1}
```

<br />

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
<br />

Then we edit our manifest and apply it, check that everything is in place, and do the port-forward and launch 
another `nc localhost 8000` to test if everything went well.

First the manifest
```elixir
$ cat config/samples/forward_v1alpha1_map.yaml 
apiVersion: forward.techsquad.rocks/v1alpha1
kind: MapPort
metadata:
  name: mapsample
  namespace: default
spec:
  host: 10.244.0.8
  port: 8000
  protocol: tcp
  liveness_probe: false
```

<br />

Then the port-forward and test
```elixir
$ kubectl apply -f config/samples/forward_v1alpha1_map.yaml
map.forward.techsquad.rocks/mapsample configured

# Logs in the controller
2020-01-17T23:38:27.650Z        INFO    controllers.MapPort === Reconciling Forward MapPort     {"namespace": "default", "MapForward": "mapsample"}
2020-01-17T23:38:27.691Z        INFO    controllers.MapPort Phase: RUNNING  {"namespace": "default", "MapForward": "mapsample"}
2020-01-17T23:38:27.698Z        DEBUG   controller-runtime.controller   Successfully Reconciled {"controller": "map", "request": "default/mapsample"}

$ kubectl port-forward forward-mapsample-pod 8000:8000                                                                                                                                                                       
Forwarding from 127.0.0.1:8000 -> 8000                                                                                                                                                                                                                                           
Handling connection for 8000                                               

# In another terminal or tab or split
$ nc localhost 8000
test
```

<br />

##### Making it publicly ready
Here we just build and push the docker image to dockerhub or our favorite public registry.

```elixir
❯ make docker-build docker-push IMG=kainlite/forward:0.0.2
```

The output should look something like this:
```elixir
docker build -t kainlite/forward:0.0.2 .
[+] Building 42.6s (18/18) FINISHED                                                                                                                                                                   docker:default
 => [internal] load build definition from Dockerfile                                                                                                                                                            0.0s
 => => transferring dockerfile: 1.29kB                                                                                                                                                                          0.0s
 => [internal] load metadata for gcr.io/distroless/static:nonroot                                                                                                                                               3.7s
 => [internal] load metadata for docker.io/library/golang:1.22                                                                                                                                                  2.6s
 => [auth] library/golang:pull token for registry-1.docker.io                                                                                                                                                   0.0s
 => [internal] load .dockerignore                                                                                                                                                                               0.0s
 => => transferring context: 160B                                                                                                                                                                               0.0s
 => [builder 1/9] FROM docker.io/library/golang:1.22@sha256:147f428a24c6b80b8afbdaec7f245b9e7ac342601e3aeaffb321a103b7c6b3f4                                                                                   10.6s
 => => resolve docker.io/library/golang:1.22@sha256:147f428a24c6b80b8afbdaec7f245b9e7ac342601e3aeaffb321a103b7c6b3f4                                                                                            0.0s
 => => sha256:596bd91089dc306a74d9a4aaabf672db3d29a1db9e40bb041c3ea4d087de8577 2.32kB / 2.32kB                                                                                                                  0.0s
 => => sha256:0d826da3ae27112120e95619ce6d005ac11f82a89e73bbb206254130711ed623 2.92kB / 2.92kB                                                                                                                  0.0s
 => => sha256:c3cc7b6f04730c072f8b292917e0d95bb886096a2b2b1781196170965161cd27 24.06MB / 24.06MB                                                                                                                1.4s
 => => sha256:147f428a24c6b80b8afbdaec7f245b9e7ac342601e3aeaffb321a103b7c6b3f4 9.74kB / 9.74kB                                                                                                                  0.0s
 => => sha256:b2b31b28ee3c96e96195c754f8679f690db4b18e475682d716122016ef056f39 49.58MB / 49.58MB                                                                                                                2.0s
 => => sha256:2112e5e7c3ff699043b282f1ff24d3ef185c080c28846f1d7acc5ccf650bc13d 64.39MB / 64.39MB                                                                                                                2.8s
 => => sha256:60310c52e63c274b676d54529d45fa48a89423e76423a54f099c78d04ff10f05 92.29MB / 92.29MB                                                                                                                4.0s
 => => extracting sha256:b2b31b28ee3c96e96195c754f8679f690db4b18e475682d716122016ef056f39                                                                                                                       1.3s
 => => sha256:e8432e3fdff3e2806bb266016c8cf75387e22b37343eb42715d8c9f19aacae8d 69.36MB / 69.36MB                                                                                                                4.6s
 => => sha256:4d3c5c274fa0f40c24d5bf0773d5d45f3245c475dea21041213f6e152b23c96c 124B / 124B                                                                                                                      3.1s
 => => sha256:4f4fb700ef54461cfa02571ae0db9a0dc1e0cdb5577484a6d75e68dc38e8acc1 32B / 32B                                                                                                                        3.3s
 => => extracting sha256:c3cc7b6f04730c072f8b292917e0d95bb886096a2b2b1781196170965161cd27                                                                                                                       0.4s
 => => extracting sha256:2112e5e7c3ff699043b282f1ff24d3ef185c080c28846f1d7acc5ccf650bc13d                                                                                                                       1.7s
 => => extracting sha256:60310c52e63c274b676d54529d45fa48a89423e76423a54f099c78d04ff10f05                                                                                                                       1.9s
 => => extracting sha256:e8432e3fdff3e2806bb266016c8cf75387e22b37343eb42715d8c9f19aacae8d                                                                                                                       2.6s
 => => extracting sha256:4d3c5c274fa0f40c24d5bf0773d5d45f3245c475dea21041213f6e152b23c96c                                                                                                                       0.0s
 => => extracting sha256:4f4fb700ef54461cfa02571ae0db9a0dc1e0cdb5577484a6d75e68dc38e8acc1                                                                                                                       0.0s
 => [stage-1 1/3] FROM gcr.io/distroless/static:nonroot@sha256:d71f4b239be2d412017b798a0a401c44c3049a3ca454838473a4c32ed076bfea                                                                                 8.6s
 => => resolve gcr.io/distroless/static:nonroot@sha256:d71f4b239be2d412017b798a0a401c44c3049a3ca454838473a4c32ed076bfea                                                                                         0.0s
 => => sha256:efb26da6283e4bd2cbe5083f3e6da0c4757d5af79884b7a1c300ba8bcfe49659 1.95kB / 1.95kB                                                                                                                  0.0s
 => => sha256:d71f4b239be2d412017b798a0a401c44c3049a3ca454838473a4c32ed076bfea 1.51kB / 1.51kB                                                                                                                  0.0s
 => => sha256:db21beaed18e5217a69a5bbc70b22bacf9625c6181627ea79070c012cb60db0c 1.50kB / 1.50kB                                                                                                                  0.0s
 => => sha256:0baecf37abeec25aad5f5bb99f3fa20e90f15361468ef5b66fae93e9c8283c3d 104.26kB / 104.26kB                                                                                                              5.0s
 => => sha256:bfb59b82a9b65e47d485e53b3e815bca3b3e21a095bd0cb88ced9ac0b48062bf 13.36kB / 13.36kB                                                                                                                6.0s
 => => sha256:8ffb3c3cf71ab16787d74e41347deae1495b9309bae0f0f542d4c5464c245489 536.84kB / 536.84kB                                                                                                              6.8s
 => => extracting sha256:0baecf37abeec25aad5f5bb99f3fa20e90f15361468ef5b66fae93e9c8283c3d                                                                                                                       0.0s
 => => sha256:a62778643d563b511190663ef9a77c30d46d282facfdce4f3a7aecc03423c1f3 67B / 67B                                                                                                                        5.3s
 => => sha256:7c12895b777bcaa8ccae0605b4de635b68fc32d60fa08f421dc3818bf55ee212 188B / 188B                                                                                                                      6.0s
 => => sha256:3214acf345c0cc6bbdb56b698a41ccdefc624a09d6beb0d38b5de0b2303ecaf4 123B / 123B                                                                                                                      6.3s
 => => extracting sha256:bfb59b82a9b65e47d485e53b3e815bca3b3e21a095bd0cb88ced9ac0b48062bf                                                                                                                       0.0s
 => => sha256:5664b15f108bf9436ce3312090a767300800edbbfd4511aa1a6d64357024d5dd 168B / 168B                                                                                                                      6.4s
 => => sha256:0bab15eea81d0fe6ab56ebf5fba14e02c4c1775a7f7436fbddd3505add4e18fa 93B / 93B                                                                                                                        7.0s
 => => sha256:4aa0ea1413d37a58615488592a0b827ea4b2e48fa5a77cf707d0e35f025e613f 385B / 385B                                                                                                                      7.1s
 => => extracting sha256:8ffb3c3cf71ab16787d74e41347deae1495b9309bae0f0f542d4c5464c245489                                                                                                                       0.1s
 => => sha256:da7816fa955ea24533c388143c78804c28682eef99b4ee3723b548c70148bba6 321B / 321B                                                                                                                      7.2s
 => => extracting sha256:a62778643d563b511190663ef9a77c30d46d282facfdce4f3a7aecc03423c1f3                                                                                                                       0.0s
 => => sha256:9aee425378d2c16cd44177dc54a274b312897f5860a8e78fdfda555a0d79dd71 130.50kB / 130.50kB                                                                                                              8.3s
 => => extracting sha256:7c12895b777bcaa8ccae0605b4de635b68fc32d60fa08f421dc3818bf55ee212                                                                                                                       0.0s
 => => extracting sha256:3214acf345c0cc6bbdb56b698a41ccdefc624a09d6beb0d38b5de0b2303ecaf4                                                                                                                       0.0s
 => => extracting sha256:5664b15f108bf9436ce3312090a767300800edbbfd4511aa1a6d64357024d5dd                                                                                                                       0.0s
 => => extracting sha256:0bab15eea81d0fe6ab56ebf5fba14e02c4c1775a7f7436fbddd3505add4e18fa                                                                                                                       0.0s
 => => extracting sha256:4aa0ea1413d37a58615488592a0b827ea4b2e48fa5a77cf707d0e35f025e613f                                                                                                                       0.0s
 => => extracting sha256:da7816fa955ea24533c388143c78804c28682eef99b4ee3723b548c70148bba6                                                                                                                       0.0s
 => => extracting sha256:9aee425378d2c16cd44177dc54a274b312897f5860a8e78fdfda555a0d79dd71                                                                                                                       0.0s
 => [internal] load build context                                                                                                                                                                               0.0s
 => => transferring context: 53.19kB                                                                                                                                                                            0.0s
 => [builder 2/9] WORKDIR /workspace                                                                                                                                                                            0.0s
 => [builder 3/9] COPY go.mod go.mod                                                                                                                                                                            0.0s
 => [builder 4/9] COPY go.sum go.sum                                                                                                                                                                            0.0s
 => [builder 5/9] RUN go mod download                                                                                                                                                                           8.7s
 => [builder 6/9] COPY cmd/main.go cmd/main.go                                                                                                                                                                  0.1s
 => [builder 7/9] COPY api/ api/                                                                                                                                                                                0.0s
 => [builder 8/9] COPY internal/ internal/                                                                                                                                                                      0.0s
 => [builder 9/9] RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o manager cmd/main.go                                                                                                                 18.7s
 => [stage-1 2/3] COPY --from=builder /workspace/manager .                                                                                                                                                      0.1s
 => exporting to image                                                                                                                                                                                          0.3s
 => => exporting layers                                                                                                                                                                                         0.3s
 => => writing image sha256:e212023164067a237cc8851165cf768fe078bd3d17d166c43ab89839d5e1853d                                                                                                                    0.0s
 => => naming to docker.io/kainlite/forward:0.0.2                                                                                                                                                               0.0s
docker push kainlite/forward:0.0.2
The push refers to repository [docker.io/kainlite/forward]
2c41cab843bd: Pushed
b336e209998f: Pushed
f4aee9e53c42: Pushed
1a73b54f556b: Pushed
2a92d6ac9e4f: Pushed
bbb6cacb8c82: Pushed
6f1cdceb6a31: Pushed
af5aa97ebe6c: Pushed
4d049f83d9cf: Pushed
ddc6e550070c: Pushed
8fa10c0194df: Pushed
03af25190641: Pushed
0.0.2: digest: sha256:38ef89b0ef4ca2b2e8796c60ffdf8c9f7ffeb12c9704d5c42ab05c041d39430e size: 2814
```
Then you can install it with `make deploy IMG=kainlite/forward:0.0.2` and uninstall it with `make uninstall`
<br />

##### **Closing notes**
Be sure to check the [kubebuilder book](https://book.kubebuilder.io/) if you want to learn more and the [kind docs](https://kind.sigs.k8s.io/docs/user/quick-start), I hope you enjoyed it and hope to see you on [twitter](https://twitter.com/kainlite) or [github](https://github.com/kainlite)!
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Cloud native applications with kubebuilder and kind aka kubernetes operators",
  author: "Gabriel Garrido",
  description: "In this article we will see how to use kubebuilder and kind to create and test an operator...",
  tags: ~w(golang kubernetes kubebuilder kind linux),
  published: true,
  image: "forward.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![forward](/images/forward.png){:class="mx-auto"}

##### **Introducción**
En este artículo vamos a ver cómo usar [kubebuilder](https://github.com/kubernetes-sigs/kubebuilder) y [Kind](https://github.com/kubernetes-sigs/kind) para crear un clúster local de prueba y un operador. Luego vamos a desplegar ese operador en el clúster y probarlo. El repositorio con los archivos se puede encontrar [aquí](https://github.com/kainlite/forward), y si querés aprender más sobre la idea y el proyecto, podés seguir este enlace: [forward](https://github.com/kainlite/forward).

Básicamente, lo que hace el código es crear un pod de Alpine/Socat donde podés especificar el host, puerto y protocolo, y te hará un túnel. De esta manera, podés usar port-forward, un servicio, un ingress o lo que necesites para exponer cosas que están en otra subred privada. Si bien esto puede no sonar como la mejor idea, tiene algunos casos de uso específicos, por lo que es importante que revises tus restricciones de seguridad antes de hacer algo así en un escenario normal. Aun así, debería ser seguro. Puede ser útil para pruebas o para acceder a una base de datos mientras hacés debugging o testeo. Pero bueno, esa es otra discusión. Las herramientas que usamos acá son lo que hace que esto sea tan interesante: esta es una aplicación nativa de la nube, ya que es nativa de Kubernetes, y eso es lo que vamos a explorar acá.

Aunque Kind no es un requisito indispensable, lo usé para hacer pruebas y me gustó mucho, ya que es más rápido y simple que Minikube.

Además, si te interesa saber cómo surgió la idea de hacer este operador, podés chequear este [issue de GitHub](https://github.com/kubernetes/kubernetes/issues/72597).

##### **Requisitos**
* [kubebuilder](https://github.com/kubernetes-sigs/kubebuilder)
* [kustomize](https://github.com/kubernetes-sigs/kustomize)
* [Go](https://golang.org/dl/)
* [Kind](https://github.com/kubernetes-sigs/kind)
* [Docker](https://hub.docker.com/?overlay=onboarding)

##### Nota: Este articulo se publico originalmente el 17/01/2020, pero re-escrito con las ultimas versiones el 18/11/2024.

<br />

##### Crear el proyecto
En este paso, necesitamos crear el proyecto con kubebuilder. Así que, en una carpeta vacía, ejecutamos:
```elixir
❯ go mod init redbeard.team
go: creating new go.mod: module redbeard.team
```

<br />

Luego inicializamos el proyecto con kubebuilder:
```elixir
❯ kubebuilder init --domain redbeard.team --repo redbeard.team/forward
INFO Writing kustomize manifests for you to edit...
INFO Writing scaffold for you to edit...
INFO Get controller runtime:
$ go get sigs.k8s.io/controller-runtime@v0.19.1
INFO Update dependencies:
$ go mod tidy
Next: define a resource with:
$ kubebuilder create api
```

<br />

##### Creamos la API
Creamos la API, el corazon de nuestro controlador.
```elixir
❯ kubebuilder create api --group forward --version v1alpha1 --kind MapPort
INFO Create Resource [y/n]
y
INFO Create Controller [y/n]
y
INFO Writing kustomize manifests for you to edit...
INFO Writing scaffold for you to edit...
INFO api/v1alpha1/mapport_types.go
INFO api/v1alpha1/groupversion_info.go
INFO internal/controller/suite_test.go
INFO internal/controller/mapport_controller.go
INFO internal/controller/mapport_controller_test.go
INFO Update dependencies:
$ go mod tidy
INFO Running make:
$ make generate
mkdir -p ~/Webs/forward/bin
Downloading sigs.k8s.io/controller-tools/cmd/controller-gen@v0.16.4
~/Webs/forward/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
Next: implement your new API and generate the manifests (e.g. CRDs,CRs) with:
$ make manifests
```
Hasta acá solo tenemos algo de código base y un proyecto básico o vacío con valores por defecto. Si lo probás ahora,
va a funcionar, pero no va a hacer nada interesante. Sin embargo, cubre bastante terreno, y deberíamos estar agradecidos 
de que exista una herramienta como esta. 

<br />

##### Empecemos...
Primero agregamos los tipos `api/v1alpha1/mapport_types.go`.
```elixir
/*
Copyright 2024.

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

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	PhasePending = "PENDING"
	PhaseRunning = "RUNNING"
	PhaseFailed  = "FAILED"
)

// MapPortSpec defines the desired state of MapPort.
type MapPortSpec struct {
	// TCP/UDP protocol
	Protocol string `json:"protocol,omitempty"`

	// Port
	Port int `json:"port,omitempty"`

	// Host
	Host string `json:"host,omitempty"`

	// LivenessProbe
	LivenessProbe bool `json:"liveness_probe"`
}

// MapPortStatus defines the observed state of MapPort.
type MapPortStatus struct {
	Phase string `json:"phase,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// MapPort is the Schema for the mapports API.
type MapPort struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   MapPortSpec   `json:"spec,omitempty"`
	Status MapPortStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// MapPortList contains a list of MapPort.
type MapPortList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []MapPort `json:"items"`
}

func init() {
	SchemeBuilder.Register(&MapPort{}, &MapPortList{})
}
```
Editamos `MapPortSpec` y `MapPortStatus`.
<br />

Ahora necesitamos darle vida a nuestro controlador `internal/controller/mapport_controller.go`
```elixir
/*
Copyright 2024.

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

package controller

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
	"sigs.k8s.io/controller-runtime/pkg/log"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	forwardv1alpha1 "redbeard.team/forward/api/v1alpha1"
)

// MapPortReconciler reconciles a MapPort object
type MapPortReconciler struct {
	client.Client
	Log    logr.Logger
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=forward.redbeard.team,resources=mapports,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=forward.redbeard.team,resources=mapports/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=forward.redbeard.team,resources=mapports/finalizers,verbs=update

// +kubebuilder:rbac:groups=mapports.forward.redbeard.team,resources=pods,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=mapports.forward.redbeard.team,resources=pods,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=forward.redbeard.team,resources=pods/status,verbs=get;update;patch
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch;create;update;patch;delete

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the MapPort object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.19.1/pkg/reconcile

func newPodForCR(cr *forwardv1alpha1.MapPort) *corev1.Pod {
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

	var livenessCommand string
	if cr.Spec.LivenessProbe {
		livenessCommand = fmt.Sprintf("nc -v -n -z %s %s", cr.Spec.Host, strconv.Itoa(cr.Spec.Port))
	} else {
		livenessCommand = fmt.Sprintf("echo")
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
					Name:    "mapport",
					Image:   "alpine/socat",
					Command: strings.Split(command, " "),
					LivenessProbe: &corev1.Probe{
						ProbeHandler: corev1.ProbeHandler{
							Exec: &corev1.ExecAction{
								Command: strings.Split(livenessCommand, " "),
							},
						},
					},
				},
			},
			RestartPolicy: corev1.RestartPolicyOnFailure,
		},
	}
}

func (r *MapPortReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = log.FromContext(ctx)

	reqLogger := r.Log.WithValues("namespace", req.Namespace, "MapPortForward", req.Name)
	reqLogger.Info("=== Reconciling Forward MapPort")
	// Fetch the MapPort instance
	instance := &forwardv1alpha1.MapPort{}
	err := r.Get(context.TODO(), req.NamespacedName, instance)
	if err != nil {
		if errors.IsNotFound(err) {
			// Request object not found, could have been deleted after
			// reconcile request—return and don't requeue:
			return ctrl.Result{}, nil
		}
		// Error reading the object—requeue the request:
		return ctrl.Result{}, err
	}

	// If no phase set, default to pending (the initial phase):
	if instance.Status.Phase == "" || instance.Status.Phase == "PENDING" {
		instance.Status.Phase = forwardv1alpha1.PhaseRunning
	}

	// Now let's make the main case distinction: implementing
	// the state diagram PENDING -> RUNNING or PENDING -> FAILED
	switch instance.Status.Phase {
	case forwardv1alpha1.PhasePending:
		reqLogger.Info("Phase: PENDING")
		reqLogger.Info("Waiting to forward", "Host", instance.Spec.Host, "Port", instance.Spec.Port)
		instance.Status.Phase = forwardv1alpha1.PhaseRunning

		// requeue the request
		return ctrl.Result{}, err
	case forwardv1alpha1.PhaseRunning:
		reqLogger.Info("Phase: RUNNING")
		pod := newPodForCR(instance)
		// Set MapPort instance as the owner and controller
		err := controllerutil.SetControllerReference(instance, pod, r.Scheme)
		if err != nil {
			// requeue with error
			return ctrl.Result{}, err
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
				return ctrl.Result{}, err
			}
			reqLogger.Info("Pod launched", "name", pod.Name)
		} else if err != nil {
			// requeue with error
			return ctrl.Result{}, err
		} else if found.Status.Phase == corev1.PodFailed ||
			found.Status.Phase == corev1.PodSucceeded {
			reqLogger.Info("Container terminated", "reason",
				found.Status.Reason, "message", found.Status.Message)
			instance.Status.Phase = forwardv1alpha1.PhaseFailed
		} else {
			// Don't requeue because it will happen automatically when the
			// pod status changes.
			return ctrl.Result{}, nil
		}
	case forwardv1alpha1.PhaseFailed:
		reqLogger.Info("Phase: Failed, check that the host and port are reachable from the cluster and that there are no networks policies preventing this access or firewall rules...")
		return ctrl.Result{}, nil
	default:
		reqLogger.Info("NOP")
		return ctrl.Result{}, nil
	}

	// Update the At instance, setting the status to the respective phase:
	err = r.Status().Update(context.TODO(), instance)
	if err != nil {
		return ctrl.Result{}, err
	}

	// Don't requeue. We should be reconcile because either the pod
	// or the CR changes.
	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *MapPortReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&forwardv1alpha1.MapPort{}).
		Named("mapport").
		Complete(r)
}
```

En este controlador, agregamos dos funciones: una para crear un pod y modificamos básicamente toda la función **Reconcile** 
(esta se encarga de verificar el estado y hacer las transiciones, en otras palabras, hace que un controlador funcione como un controlador). 
¡También notá las anotaciones de **kubebuilder** que generarán la configuración de **RBAC** por nosotros, bastante útil, ¿no?
<br />

##### **Iniciando el cluster**
Ahora vamos a usar [Kind](https://github.com/kubernetes-sigs/kind) para crear un cluster local para pruebas
```elixir
❯ kind create cluster
Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.30.0) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️                                                                                                                                                                                         ]
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/
```
¿Podría ser tan fácil? ¡Sí, lo es!
<br />

##### **Ejecutando nuestro operador localmente**
Para pruebas, podés correr tu operador localmente así:
```elixir
make install
make run
```

La salida deberia verse similar a esto
```elixir
~/Webs/forward/bin/controller-gen rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases
~/Webs/forward/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
go fmt ./...
go vet ./...
go run ./cmd/main.go
2024-11-18T11:32:50-03:00       INFO    setup   starting manager
2024-11-18T11:32:50-03:00       INFO    starting server {"name": "health probe", "addr": "[::]:8081"}
2024-11-18T11:32:50-03:00       INFO    Starting EventSource    {"controller": "mapport", "controllerGroup": "forward.redbeard.team", "controllerKind": "MapPort", "source": "kind source: *v1alpha1.MapPort"}
2024-11-18T11:32:50-03:00       INFO    Starting Controller     {"controller": "mapport", "controllerGroup": "forward.redbeard.team", "controllerKind": "MapPort"}
2024-11-18T11:32:50-03:00       INFO    Starting workers        {"controller": "mapport", "controllerGroup": "forward.redbeard.team", "controllerKind": "MapPort", "worker count": 1}
```
<br />

##### **Probándolo**
Primero levantamos un pod y lanzamos `nc -l -p 8000`
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
<br />

Luego editamos nuestro manifest y lo aplicamos. Verificamos que todo esté en orden, hacemos el port-forward y lanzamos otro `nc localhost 8000` para probar si todo salió bien.
Primero el manifest:
```elixir
$ cat config/samples/forward_v1alpha1_map.yaml 
apiVersion: forward.techsquad.rocks/v1alpha1
kind: MapPort
metadata:
  name: mapsample
  namespace: default
spec:
  host: 10.244.0.8
  port: 8000
  protocol: tcp
  liveness_probe: false
```
<br />
Luego hacemos el port-forward y la prueba:
```elixir
$ kubectl apply -f config/samples/forward_v1beta1_map.yaml
map.forward.techsquad.rocks/mapsample configured

# Logs en el controlador
2020-01-17T23:38:27.650Z        INFO    controllers.MapPort === Reconciling Forward MapPort     {"namespace": "default", "MapForward": "mapsample"}
2020-01-17T23:38:27.691Z        INFO    controllers.MapPort Phase: RUNNING  {"namespace": "default", "MapForward": "mapsample"}
2020-01-17T23:38:27.698Z        DEBUG   controller-runtime.controller   Successfully Reconciled {"controller": "map", "request": "default/mapsample"}

$ kubectl port-forward forward-mapsample-pod 8000:8000                                                                                                                                                                       
Forwarding from 127.0.0.1:8000 -> 8000                                                                                                                                                                                                                                           
Handling connection for 8000                                               

# En otra terminal o pestaña
$ nc localhost 8000
test

```
<br />

##### **Haciéndolo público**
Ahora simplemente construimos y subimos la imagen de Docker a DockerHub o a nuestro registry favorito.
```elixir
❯ make docker-build docker-push IMG=kainlite/forward:0.0.2
```

La salida deberia ser algo asi:
```elixir
docker build -t kainlite/forward:0.0.2 .
[+] Building 42.6s (18/18) FINISHED                                                                                                                                                                   docker:default
 => [internal] load build definition from Dockerfile                                                                                                                                                            0.0s
 => => transferring dockerfile: 1.29kB                                                                                                                                                                          0.0s
 => [internal] load metadata for gcr.io/distroless/static:nonroot                                                                                                                                               3.7s
 => [internal] load metadata for docker.io/library/golang:1.22                                                                                                                                                  2.6s
 => [auth] library/golang:pull token for registry-1.docker.io                                                                                                                                                   0.0s
 => [internal] load .dockerignore                                                                                                                                                                               0.0s
 => => transferring context: 160B                                                                                                                                                                               0.0s
 => [builder 1/9] FROM docker.io/library/golang:1.22@sha256:147f428a24c6b80b8afbdaec7f245b9e7ac342601e3aeaffb321a103b7c6b3f4                                                                                   10.6s
 => => resolve docker.io/library/golang:1.22@sha256:147f428a24c6b80b8afbdaec7f245b9e7ac342601e3aeaffb321a103b7c6b3f4                                                                                            0.0s
 => => sha256:596bd91089dc306a74d9a4aaabf672db3d29a1db9e40bb041c3ea4d087de8577 2.32kB / 2.32kB                                                                                                                  0.0s
 => => sha256:0d826da3ae27112120e95619ce6d005ac11f82a89e73bbb206254130711ed623 2.92kB / 2.92kB                                                                                                                  0.0s
 => => sha256:c3cc7b6f04730c072f8b292917e0d95bb886096a2b2b1781196170965161cd27 24.06MB / 24.06MB                                                                                                                1.4s
 => => sha256:147f428a24c6b80b8afbdaec7f245b9e7ac342601e3aeaffb321a103b7c6b3f4 9.74kB / 9.74kB                                                                                                                  0.0s
 => => sha256:b2b31b28ee3c96e96195c754f8679f690db4b18e475682d716122016ef056f39 49.58MB / 49.58MB                                                                                                                2.0s
 => => sha256:2112e5e7c3ff699043b282f1ff24d3ef185c080c28846f1d7acc5ccf650bc13d 64.39MB / 64.39MB                                                                                                                2.8s
 => => sha256:60310c52e63c274b676d54529d45fa48a89423e76423a54f099c78d04ff10f05 92.29MB / 92.29MB                                                                                                                4.0s
 => => extracting sha256:b2b31b28ee3c96e96195c754f8679f690db4b18e475682d716122016ef056f39                                                                                                                       1.3s
 => => sha256:e8432e3fdff3e2806bb266016c8cf75387e22b37343eb42715d8c9f19aacae8d 69.36MB / 69.36MB                                                                                                                4.6s
 => => sha256:4d3c5c274fa0f40c24d5bf0773d5d45f3245c475dea21041213f6e152b23c96c 124B / 124B                                                                                                                      3.1s
 => => sha256:4f4fb700ef54461cfa02571ae0db9a0dc1e0cdb5577484a6d75e68dc38e8acc1 32B / 32B                                                                                                                        3.3s
 => => extracting sha256:c3cc7b6f04730c072f8b292917e0d95bb886096a2b2b1781196170965161cd27                                                                                                                       0.4s
 => => extracting sha256:2112e5e7c3ff699043b282f1ff24d3ef185c080c28846f1d7acc5ccf650bc13d                                                                                                                       1.7s
 => => extracting sha256:60310c52e63c274b676d54529d45fa48a89423e76423a54f099c78d04ff10f05                                                                                                                       1.9s
 => => extracting sha256:e8432e3fdff3e2806bb266016c8cf75387e22b37343eb42715d8c9f19aacae8d                                                                                                                       2.6s
 => => extracting sha256:4d3c5c274fa0f40c24d5bf0773d5d45f3245c475dea21041213f6e152b23c96c                                                                                                                       0.0s
 => => extracting sha256:4f4fb700ef54461cfa02571ae0db9a0dc1e0cdb5577484a6d75e68dc38e8acc1                                                                                                                       0.0s
 => [stage-1 1/3] FROM gcr.io/distroless/static:nonroot@sha256:d71f4b239be2d412017b798a0a401c44c3049a3ca454838473a4c32ed076bfea                                                                                 8.6s
 => => resolve gcr.io/distroless/static:nonroot@sha256:d71f4b239be2d412017b798a0a401c44c3049a3ca454838473a4c32ed076bfea                                                                                         0.0s
 => => sha256:efb26da6283e4bd2cbe5083f3e6da0c4757d5af79884b7a1c300ba8bcfe49659 1.95kB / 1.95kB                                                                                                                  0.0s
 => => sha256:d71f4b239be2d412017b798a0a401c44c3049a3ca454838473a4c32ed076bfea 1.51kB / 1.51kB                                                                                                                  0.0s
 => => sha256:db21beaed18e5217a69a5bbc70b22bacf9625c6181627ea79070c012cb60db0c 1.50kB / 1.50kB                                                                                                                  0.0s
 => => sha256:0baecf37abeec25aad5f5bb99f3fa20e90f15361468ef5b66fae93e9c8283c3d 104.26kB / 104.26kB                                                                                                              5.0s
 => => sha256:bfb59b82a9b65e47d485e53b3e815bca3b3e21a095bd0cb88ced9ac0b48062bf 13.36kB / 13.36kB                                                                                                                6.0s
 => => sha256:8ffb3c3cf71ab16787d74e41347deae1495b9309bae0f0f542d4c5464c245489 536.84kB / 536.84kB                                                                                                              6.8s
 => => extracting sha256:0baecf37abeec25aad5f5bb99f3fa20e90f15361468ef5b66fae93e9c8283c3d                                                                                                                       0.0s
 => => sha256:a62778643d563b511190663ef9a77c30d46d282facfdce4f3a7aecc03423c1f3 67B / 67B                                                                                                                        5.3s
 => => sha256:7c12895b777bcaa8ccae0605b4de635b68fc32d60fa08f421dc3818bf55ee212 188B / 188B                                                                                                                      6.0s
 => => sha256:3214acf345c0cc6bbdb56b698a41ccdefc624a09d6beb0d38b5de0b2303ecaf4 123B / 123B                                                                                                                      6.3s
 => => extracting sha256:bfb59b82a9b65e47d485e53b3e815bca3b3e21a095bd0cb88ced9ac0b48062bf                                                                                                                       0.0s
 => => sha256:5664b15f108bf9436ce3312090a767300800edbbfd4511aa1a6d64357024d5dd 168B / 168B                                                                                                                      6.4s
 => => sha256:0bab15eea81d0fe6ab56ebf5fba14e02c4c1775a7f7436fbddd3505add4e18fa 93B / 93B                                                                                                                        7.0s
 => => sha256:4aa0ea1413d37a58615488592a0b827ea4b2e48fa5a77cf707d0e35f025e613f 385B / 385B                                                                                                                      7.1s
 => => extracting sha256:8ffb3c3cf71ab16787d74e41347deae1495b9309bae0f0f542d4c5464c245489                                                                                                                       0.1s
 => => sha256:da7816fa955ea24533c388143c78804c28682eef99b4ee3723b548c70148bba6 321B / 321B                                                                                                                      7.2s
 => => extracting sha256:a62778643d563b511190663ef9a77c30d46d282facfdce4f3a7aecc03423c1f3                                                                                                                       0.0s
 => => sha256:9aee425378d2c16cd44177dc54a274b312897f5860a8e78fdfda555a0d79dd71 130.50kB / 130.50kB                                                                                                              8.3s
 => => extracting sha256:7c12895b777bcaa8ccae0605b4de635b68fc32d60fa08f421dc3818bf55ee212                                                                                                                       0.0s
 => => extracting sha256:3214acf345c0cc6bbdb56b698a41ccdefc624a09d6beb0d38b5de0b2303ecaf4                                                                                                                       0.0s
 => => extracting sha256:5664b15f108bf9436ce3312090a767300800edbbfd4511aa1a6d64357024d5dd                                                                                                                       0.0s
 => => extracting sha256:0bab15eea81d0fe6ab56ebf5fba14e02c4c1775a7f7436fbddd3505add4e18fa                                                                                                                       0.0s
 => => extracting sha256:4aa0ea1413d37a58615488592a0b827ea4b2e48fa5a77cf707d0e35f025e613f                                                                                                                       0.0s
 => => extracting sha256:da7816fa955ea24533c388143c78804c28682eef99b4ee3723b548c70148bba6                                                                                                                       0.0s
 => => extracting sha256:9aee425378d2c16cd44177dc54a274b312897f5860a8e78fdfda555a0d79dd71                                                                                                                       0.0s
 => [internal] load build context                                                                                                                                                                               0.0s
 => => transferring context: 53.19kB                                                                                                                                                                            0.0s
 => [builder 2/9] WORKDIR /workspace                                                                                                                                                                            0.0s
 => [builder 3/9] COPY go.mod go.mod                                                                                                                                                                            0.0s
 => [builder 4/9] COPY go.sum go.sum                                                                                                                                                                            0.0s
 => [builder 5/9] RUN go mod download                                                                                                                                                                           8.7s
 => [builder 6/9] COPY cmd/main.go cmd/main.go                                                                                                                                                                  0.1s
 => [builder 7/9] COPY api/ api/                                                                                                                                                                                0.0s
 => [builder 8/9] COPY internal/ internal/                                                                                                                                                                      0.0s
 => [builder 9/9] RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o manager cmd/main.go                                                                                                                 18.7s
 => [stage-1 2/3] COPY --from=builder /workspace/manager .                                                                                                                                                      0.1s
 => exporting to image                                                                                                                                                                                          0.3s
 => => exporting layers                                                                                                                                                                                         0.3s
 => => writing image sha256:e212023164067a237cc8851165cf768fe078bd3d17d166c43ab89839d5e1853d                                                                                                                    0.0s
 => => naming to docker.io/kainlite/forward:0.0.2                                                                                                                                                               0.0s
docker push kainlite/forward:0.0.2
The push refers to repository [docker.io/kainlite/forward]
2c41cab843bd: Pushed
b336e209998f: Pushed
f4aee9e53c42: Pushed
1a73b54f556b: Pushed
2a92d6ac9e4f: Pushed
bbb6cacb8c82: Pushed
6f1cdceb6a31: Pushed
af5aa97ebe6c: Pushed
4d049f83d9cf: Pushed
ddc6e550070c: Pushed
8fa10c0194df: Pushed
03af25190641: Pushed
0.0.2: digest: sha256:38ef89b0ef4ca2b2e8796c60ffdf8c9f7ffeb12c9704d5c42ab05c041d39430e size: 2814
```
Luego lo podés instalar con `make deploy IMG=kainlite/forward:0.0.2` y desinstalarlo con `make uninstall`.
<br />

##### **Notas finales**
Asegurate de revisar el [libro de kubebuilder](https://book.kubebuilder.io/) si querés aprender más y 
la [documentación de kind](https://kind.sigs.k8s.io/docs/user/quick-start). ¡Espero que lo hayas disfrutado y 
te veo en [twitter](https://twitter.com/kainlite) o [github](https://github.com/kainlite)!
<br />

### Erratas
Si ves algún error o tenés alguna sugerencia, por favor mandame un mensaje así lo arreglo.

<br />
