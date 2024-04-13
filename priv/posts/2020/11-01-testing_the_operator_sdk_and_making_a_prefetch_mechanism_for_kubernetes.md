%{
  title: "Testing the Operator SDK and making a prefetch mechanism for Kubernetes",
  author: "Gabriel Garrido",
  description: "In this article we will explore how to create an operator that can prefetch our images (from our deployments to all nodes) using the Operator SDK, you might be wondering why...",
  tags: ~w(golang kubernetes),
  published: true,
  image: "operator-sdk.png"
}
---

![operator](/images/operator-sdk.png){:class="mx-auto"}

#### **Introduction**
In this article we will explore how to create an operator that can prefetch our images (from our deployments to all nodes) using the Operator SDK, you might be wondering why would you want to do this? the main idea is to get the images in advance so you don't have to pull them when the pod actually needs to start running in a given node, this can speed up things a bit and it's also an interesting exercise.

If you have read the article [Cloud native applications with kubebuilder and kind aka kubernetes operators](/blog/cloud_native_applications_with_kubebuilder_and_kind_aka_kubernetes_operators/) you will note that the commands are really similar between each other, since now the operator-sdk uses kubebuilder, you can read more [here](https://github.com/operator-framework/operator-sdk/issues/3558#issuecomment-664206538).

The source for this article is [here](https://github.com/kainlite/kubernetes-prefetch-operator/)

##### **Prerequisites**
* [Operator SDK](https://sdk.operatorframework.io/docs/installation/install-operator-sdk/)
* [Go](https://golang.org/dl/)
* [Kind](https://github.com/kubernetes-sigs/kind)
* [Docker](https://hub.docker.com/?overlay=onboarding)
* [kustomize](https://github.com/kubernetes-sigs/kustomize)

#### Creating our local cluster
##### Kind config for multi-cluster
This is the kind config necessary to have a multi-node setup locally: `kind create cluster --config kind.yaml`
```elixir
# kind create cluster --config kind.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker

```

##### Creating the cluster
We will need a cluster to run and test our operator, so kind is pretty straight forward and lightweight enough to run anywhere.
```elixir
❯ kind create cluster --config kind.yaml
Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.18.2) 🖼
 ✓ Preparing nodes 📦 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Have a nice day! 👋

```

#### Creating our operator
Here we bootstrap our go project aka as kubernetes operator
```elixir
$ operator-sdk init --domain=techsquad.rocks --repo=github.com/kainlite/kubernetes-prefetch-operator
Writing scaffold for you to edit...
Get controller runtime:
$ go get sigs.k8s.io/controller-runtime@v0.6.2
go: downloading sigs.k8s.io/controller-runtime v0.6.2
go: downloading k8s.io/apimachinery v0.18.6
go: downloading k8s.io/client-go v0.18.6
go: downloading github.com/prometheus/client_model v0.2.0
go: downloading k8s.io/apiextensions-apiserver v0.18.6
go: downloading github.com/gogo/protobuf v1.3.1
go: downloading golang.org/x/sys v0.0.0-20200323222414-85ca7c5b95cd
go: downloading github.com/google/gofuzz v1.1.0
go: downloading k8s.io/api v0.18.6
go: downloading github.com/golang/protobuf v1.4.2
go: downloading sigs.k8s.io/structured-merge-diff/v3 v3.0.0
go: downloading github.com/fsnotify/fsnotify v1.4.9
go: downloading k8s.io/utils v0.0.0-20200603063816-c1c6865ac451
go: downloading github.com/imdario/mergo v0.3.9
go: downloading github.com/hashicorp/golang-lru v0.5.4
go: downloading github.com/json-iterator/go v1.1.10
go: downloading github.com/google/go-cmp v0.4.0
go: downloading golang.org/x/crypto v0.0.0-20200220183623-bac4c82f6975
go: downloading google.golang.org/protobuf v1.23.0
go: downloading gopkg.in/yaml.v2 v2.3.0
go: downloading sigs.k8s.io/yaml v1.2.0
go: downloading k8s.io/kube-openapi v0.0.0-20200410145947-61e04a5be9a6
go: downloading github.com/prometheus/procfs v0.0.11
go: downloading golang.org/x/net v0.0.0-20200520004742-59133d7f0dd7
go: downloading k8s.io/klog/v2 v2.0.0
go: downloading golang.org/x/text v0.3.3
Update go.mod:
$ go mod tidy
go: downloading github.com/onsi/gomega v1.10.1
go: downloading github.com/onsi/ginkgo v1.12.1
go: downloading go.uber.org/atomic v1.4.0
go: downloading golang.org/x/xerrors v0.0.0-20191204190536-9bdfabe68543
go: downloading github.com/nxadm/tail v1.4.4
Running make:
$ make
/home/kainlite/Webs/go/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
go fmt ./...
go vet ./...
go build -o bin/manager main.go
Next: define a resource with:
$ operator-sdk create api

```

#### Creating our API
This will be the object that it will hold all the important information for a given image, the files that we need to modify at first hand are in: `controllers/*_controller.go` and `api/v1/*_types.go`
```elixir
$ operator-sdk init --domain=techsquad.rocks --repo=github.com/kainlite/kubernetes-prefetch-operator
Writing scaffold for you to edit...
Get controller runtime:
$ go get sigs.k8s.io/controller-runtime@v0.6.2
go: downloading sigs.k8s.io/controller-runtime v0.6.2
go: downloading k8s.io/apimachinery v0.18.6
go: downloading k8s.io/client-go v0.18.6
go: downloading github.com/prometheus/client_model v0.2.0
go: downloading k8s.io/apiextensions-apiserver v0.18.6
go: downloading github.com/gogo/protobuf v1.3.1
go: downloading golang.org/x/sys v0.0.0-20200323222414-85ca7c5b95cd
go: downloading github.com/google/gofuzz v1.1.0
go: downloading k8s.io/api v0.18.6
go: downloading github.com/golang/protobuf v1.4.2
go: downloading sigs.k8s.io/structured-merge-diff/v3 v3.0.0
go: downloading github.com/fsnotify/fsnotify v1.4.9
go: downloading k8s.io/utils v0.0.0-20200603063816-c1c6865ac451
go: downloading github.com/imdario/mergo v0.3.9
go: downloading github.com/hashicorp/golang-lru v0.5.4
go: downloading github.com/json-iterator/go v1.1.10
go: downloading github.com/google/go-cmp v0.4.0
go: downloading golang.org/x/crypto v0.0.0-20200220183623-bac4c82f6975
go: downloading google.golang.org/protobuf v1.23.0
go: downloading gopkg.in/yaml.v2 v2.3.0
go: downloading sigs.k8s.io/yaml v1.2.0
go: downloading k8s.io/kube-openapi v0.0.0-20200410145947-61e04a5be9a6
go: downloading github.com/prometheus/procfs v0.0.11
go: downloading golang.org/x/net v0.0.0-20200520004742-59133d7f0dd7
go: downloading k8s.io/klog/v2 v2.0.0
go: downloading golang.org/x/text v0.3.3
Update go.mod:
$ go mod tidy
go: downloading github.com/onsi/gomega v1.10.1
go: downloading github.com/onsi/ginkgo v1.12.1
go: downloading go.uber.org/atomic v1.4.0
go: downloading golang.org/x/xerrors v0.0.0-20191204190536-9bdfabe68543
go: downloading github.com/nxadm/tail v1.4.4
Running make:
$ make
/home/kainlite/Webs/go/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
go fmt ./...
go vet ./...
go build -o bin/manager main.go
Next: define a resource with:
$ operator-sdk create api

```

#### Building and pushing (docker image)
Basic build and push of the operator image with the projects helper
```elixir
$ make docker-build docker-push IMG=kainlite/kubernetes-prefetch-operator:latest
/home/kainlite/Webs/go/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
go fmt ./...
go vet ./...
/home/kainlite/Webs/go/bin/controller-gen "crd:trivialVersions=true" rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases
mkdir -p /home/kainlite/Webs/kubernetes-prefetch-operator/testbin
test -f /home/kainlite/Webs/kubernetes-prefetch-operator/testbin/setup-envtest.sh || curl -sSLo /home/kainlite/Webs/kubernetes-prefetch-operator/testbin/setup-envtest.sh https://raw.githubusercontent.com/kubernetes-sigs/controller-runtime/v0.6.3/hack/setup-envtest.sh
source /home/kainlite/Webs/kubernetes-prefetch-operator/testbin/setup-envtest.sh; fetch_envtest_tools /home/kainlite/Webs/kubernetes-prefetch-operator/testbin; setup_envtest_env /home/kainlite/Webs/kubernetes-prefetch-operator/testbin; go test ./... -coverprofile cover.out
Using cached envtest tools from /home/kainlite/Webs/kubernetes-prefetch-operator/testbin
setting up env vars
?       github.com/kainlite/kubernetes-prefetch-operator        [no test files]
?       github.com/kainlite/kubernetes-prefetch-operator/api/v1 [no test files]
ok      github.com/kainlite/kubernetes-prefetch-operator/controllers    7.643s  coverage: 0.0% of statements
docker build . -t kainlite/kubernetes-prefetch-operator:latest
Sending build context to Docker daemon  283.5MB
Step 1/14 : FROM golang:1.13 as builder
 ---> d6f3656320fe
Step 2/14 : WORKDIR /workspace
 ---> Using cache
 ---> daa8163e90d8
Step 3/14 : COPY go.mod go.mod
 ---> Using cache
 ---> 915e48e7d848
Step 4/14 : COPY go.sum go.sum
 ---> Using cache
 ---> aaafab83a12c
Step 5/14 : RUN go mod download
 ---> Using cache
 ---> 4f9b0dc66b6e
Step 6/14 : COPY main.go main.go
 ---> Using cache
 ---> 6650d207bf3d
Step 7/14 : COPY api/ api/
 ---> Using cache
 ---> 02f5deba19a4
Step 8/14 : COPY controllers/ controllers/
 ---> Using cache
 ---> c115b1d97125
Step 9/14 : RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GO111MODULE=on go build -a -o manager main.go
 ---> Using cache
 ---> 93d496caf9b3
Step 10/14 : FROM gcr.io/distroless/static:nonroot
 ---> 0b9eb5cc7e55
Step 11/14 : WORKDIR /
 ---> Using cache
 ---> 6cbde711827b
Step 12/14 : COPY --from=builder /workspace/manager .
 ---> Using cache
 ---> e5b22a5aba41
Step 13/14 : USER nonroot:nonroot
 ---> Using cache
 ---> a77bd02bcecd
Step 14/14 : ENTRYPOINT ["/manager"]
 ---> Using cache
 ---> 582cb3195193
Successfully built 582cb3195193
Successfully tagged kainlite/kubernetes-prefetch-operator:latest
docker push kainlite/kubernetes-prefetch-operator:latest
The push refers to repository [docker.io/kainlite/kubernetes-prefetch-operator]
b667daa3236e: Pushed
fd6fa224ea91: Pushed
latest: digest: sha256:f0519419c8c4bfdcd4a9b2d3f0e7d0086f3654659058de62447f373fd0489ddc size: 739

```

#### Deploying
Now that we have the project built into a docker image and stored in dockerhub then we can install our CRD and then deploy the operator
```elixir
$ make install
/home/kainlite/Webs/go/bin/controller-gen "crd:trivialVersions=true" rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases
/usr/bin/kustomize build config/crd | kubectl apply -f -
customresourcedefinition.apiextensions.k8s.io/prefetches.cache.techsquad.rocks created

```

##### Deploy the operator
Then we can deploy our operator
```elixir
$ make deploy IMG=kainlite/kubernetes-prefetch-operator:latest
/home/kainlite/Webs/go/bin/controller-gen "crd:trivialVersions=true" rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases
cd config/manager && /usr/bin/kustomize edit set image controller=kainlite/kubernetes-prefetch-operator:latest
/usr/bin/kustomize build config/default | kubectl apply -f -
namespace/kubernetes-prefetch-operator-system created
customresourcedefinition.apiextensions.k8s.io/prefetches.cache.techsquad.rocks configured
role.rbac.authorization.k8s.io/kubernetes-prefetch-operator-leader-election-role created
clusterrole.rbac.authorization.k8s.io/kubernetes-prefetch-operator-manager-role created
clusterrole.rbac.authorization.k8s.io/kubernetes-prefetch-operator-proxy-role created
clusterrole.rbac.authorization.k8s.io/kubernetes-prefetch-operator-metrics-reader created
rolebinding.rbac.authorization.k8s.io/kubernetes-prefetch-operator-leader-election-rolebinding created
clusterrolebinding.rbac.authorization.k8s.io/kubernetes-prefetch-operator-manager-rolebinding created
clusterrolebinding.rbac.authorization.k8s.io/kubernetes-prefetch-operator-proxy-rolebinding created
service/kubernetes-prefetch-operator-controller-manager-metrics-service created
deployment.apps/kubernetes-prefetch-operator-controller-manager created

```

##### Validate that our operator was deployed
Check that our pods are running
```elixir
$ kubectl get pods -n kubernetes-prefetch-operator-system
NAME                                                             READY   STATUS    RESTARTS   AGE
kubernetes-prefetch-operator-controller-manager-59d8bc86-2z2sq   2/2     Running   0          66s

```

So far everything is peachy but our operator is kind of useless at the moment, so let's drop some code to make it do what we want...

#### Our code
A lot of what we use is generated however we need to give it some specific permissions and behaviour to our operator so it does what we want when we create an object in kubernetes

##### Our manifest
This will be the manifest that we will be using to tell our operator which deployments we want to prefetch images for
```elixir
apiVersion: cache.techsquad.rocks/v1
kind: Prefetch
metadata:
  name: prefetch-sample
  namespace: default
spec:
  # We will use labels to fetch the deployments that we want to fetch images for, but we
  # don't want to prefetch everything in the cluster that would be too much bandwidth
  # for no reason, but for this deployment we want to have it everywhere ready to be used.
  filter_by_labels:
    app: nginx
  retry_after: 60
  # this is a strings.Contains
  node_filter: worker

```

##### Sample nginx deployment
This nginx deployment will be used to validate that the images are fetched in all nodes
```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  # One of our nodes won't have that label so we can validate
  # that our operator prefetches images even if the deployment
  # has not created a pod in that node (this isn't really necessary
  # because we can have 3 nodes and request 2 replicas, but just in case)
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: nginx-schedulable
                operator: In
                values:
                  - "yes"
            topologyKey: "kubernetes.io/hostname"
      containers:
      - name: nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80

```
We don't actually need to do this, but this way it's easy to make sure that a pod won't be scheduled if the label is not present: `kubectl label nodes kind-worker3 nginx-schedulable="true"`

##### Our actual logic (this made me chuckle so much bootstrap just to get here, but imagine having to do all that by yourself)
This is where things actually happen, first we get our Spec updated:
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

package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Phases
const (
	PhasePending = "PENDING"
	PhaseRunning = "RUNNING"
	PhaseFailed  = "FAILED"
)

// PrefetchSpec defines the desired state of Prefetch
type PrefetchSpec struct {
	// Labels are the labels to use to filter the deployments
	// +kubebuilder:default={}
	FilterByLabels map[string]string `json:"filter_by_labels,omitempty"`

	// Simple matcher of the hostname of the nodes
	NodeFilter string `json:"node_filter,omitempty"`

	// The default time to wait between fetch and fetch
	// if not specified it will default to 300 seconds
	// +optional
	// +kubebuilder:validation:Minimum=0
	RetryAfter int `json:"retry_after,omitempty"`
}

// PrefetchStatus defines the observed state of Prefetch
type PrefetchStatus struct {
	Phase string `json:"phase,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// Prefetch is the Schema for the prefetches API
type Prefetch struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   PrefetchSpec   `json:"spec,omitempty"`
	Status PrefetchStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// PrefetchList contains a list of Prefetch
type PrefetchList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Prefetch `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Prefetch{}, &PrefetchList{})
}

```
You can find this file [here](https://github.com/kainlite/kubernetes-prefetch-operator/blob/master/api/v1/prefetch_types.go)

Then we can put some code, I will add more comments later in the code to explain what everything does:
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
	"strings"
	"time"

	"github.com/go-logr/logr"
	"github.com/prometheus/common/log"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	"github.com/google/uuid"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	set "k8s.io/apimachinery/pkg/labels"

	cachev1 "github.com/kainlite/kubernetes-prefetch-operator/api/v1"
)

// PrefetchReconciler reconciles a Prefetch object
type PrefetchReconciler struct {
	client.Client
	Log    logr.Logger
	Scheme *runtime.Scheme
}

// I have been rather permissive than restrictive here, so be aware of that when using this
// +kubebuilder:rbac:groups=cache.techsquad.rocks,resources=prefetches,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=cache.techsquad.rocks,resources=cache,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=cache.techsquad.rocks,resources=prefetches/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cache.techsquad.rocks,resources=pods/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;delete
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=events,verbs=create;patch
// +kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch

func getClientSet() (*kubernetes.Clientset, error) {
	// creates the in-cluster config
	config, err := rest.InClusterConfig()
	if err != nil {
		panic(err.Error())
	}
	// creates the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	return clientset, err
}

func fetchImagesWithTags(clientset *kubernetes.Clientset, labels map[string]string) []string {
	list := []string{}
	labelsAsString := set.FormatLabels(labels)
	fmt.Printf("labelsAsString: %+v
", labelsAsString)

	// List Deployments
	deploymentsClient := clientset.AppsV1().Deployments("")
	DeploymentList, err := deploymentsClient.List(context.TODO(), metav1.ListOptions{LabelSelector: labelsAsString})
	if err != nil {
		fmt.Printf("Error fetching deployments, check your labels: %+v
", err)
	}
	for _, d := range DeploymentList.Items {
		for _, f := range d.Spec.Template.Spec.InitContainers {
			fmt.Printf("Adding init container %s to the list
", f.Image)
			list = append(list, fmt.Sprintf("%s", f.Image))
		}

		for _, f := range d.Spec.Template.Spec.Containers {
			fmt.Printf("Adding container %s to the list
", f.Image)
			list = append(list, fmt.Sprintf("%s", f.Image))
		}
	}

	return list
}

func fetchNodeNames(clientset *kubernetes.Clientset, prefetch *cachev1.Prefetch) []string {
	list := []string{}
	nodes, err := clientset.CoreV1().Nodes().List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		fmt.Printf("Error fetching nodes, check your permissions: %+v
", err)
	}

	for _, node := range nodes.Items {
		if strings.Contains(node.Name, prefetch.Spec.NodeFilter) {
			list = append(list, node.Name)
		}
	}

	fmt.Printf("Node list: %+v
", list)

	return list
}

func PrefetchImages(r *PrefetchReconciler, prefetch *cachev1.Prefetch) {
	id := uuid.New()
	prefix := "prefetch-pod"
	name := prefix + "-" + id.String()
	labels := map[string]string{
		"app": prefix,
	}

	clientset, _ := getClientSet()
	imagesWithTags := fetchImagesWithTags(clientset, prefetch.Spec.FilterByLabels)
	nodeList := fetchNodeNames(clientset, prefetch)

	for _, node := range nodeList {
		for _, image := range imagesWithTags {
			// command := fmt.Sprintf("docker pull %s")
			command := fmt.Sprintf("/bin/sh -c exit")

			pod := &corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name:      name + "-" + node,
					Namespace: prefetch.Namespace,
					Labels:    labels,
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:    "prefetch",
							Command: strings.Split(command, " "),
							Image:   image,
							// Initially I was going to use a privileged container
							// to talk to the docker daemon, but I then realized
							// it's easier to call the image with exit 0
							// Image:           "docker/dind",
							// SecurityContext: &v1.SecurityContext{Privileged: &privileged},
						},
					},
					RestartPolicy: corev1.RestartPolicyOnFailure,
					Affinity: &corev1.Affinity{
						NodeAffinity: &corev1.NodeAffinity{
							RequiredDuringSchedulingIgnoredDuringExecution: &corev1.NodeSelector{
								NodeSelectorTerms: []corev1.NodeSelectorTerm{
									{
										MatchExpressions: []corev1.NodeSelectorRequirement{
											{
												Key:      "kubernetes.io/hostname",
												Operator: "In",
												Values:   []string{node},
											},
										},
									},
								},
							},
						},
					},
				},
			}

			if prefetch.Status.Phase == "" || prefetch.Status.Phase == "PENDING" {
				prefetch.Status.Phase = cachev1.PhaseRunning
			}

			switch prefetch.Status.Phase {
			case cachev1.PhasePending:
				prefetch.Status.Phase = cachev1.PhaseRunning
			case cachev1.PhaseRunning:
				err := controllerutil.SetControllerReference(prefetch, pod, r.Scheme)
				found := &corev1.Pod{}
				nsName := types.NamespacedName{Name: pod.Name, Namespace: pod.Namespace}
				err = r.Get(context.TODO(), nsName, found)
				if err != nil && errors.IsNotFound(err) {
					_ = r.Create(context.TODO(), pod)
					fmt.Printf("Pod launched with name: %+v
", pod.Name)
				} else if found.Status.Phase == corev1.PodFailed ||
					found.Status.Phase == corev1.PodSucceeded {
					fmt.Printf("Container terminated reason with message: %+v, and status: %+v",
						found.Status.Reason, found.Status.Message)
					prefetch.Status.Phase = cachev1.PhaseFailed
				}
			}

			// Update the At prefetch, setting the status to the respective phase:
			err := r.Status().Update(context.TODO(), prefetch)
			err = r.Create(context.TODO(), pod)
			if err != nil {
				fmt.Printf("There was an error invoking the pod: %+v
", err)
			}
		}
	}
}

func DeleteCompletedPods(prefetch *cachev1.Prefetch) {
	fieldSelectorFilter := "status.phase=Succeeded"
	clientset, _ := getClientSet()

	pods, err := clientset.CoreV1().Pods(prefetch.Namespace).List(context.TODO(), metav1.ListOptions{FieldSelector: fieldSelectorFilter})
	if err != nil {
		fmt.Printf("failed to retrieve Pods: %+v
", err)
	}

	for _, pod := range pods.Items {
		fmt.Printf("Deleting pod: %+v
", pod.Name)
		if err := clientset.CoreV1().Pods(prefetch.Namespace).Delete(context.TODO(), pod.Name, metav1.DeleteOptions{}); err != nil {
			fmt.Printf("Failed to delete Pod: %+v", err)
		}
	}
}

func (r *PrefetchReconciler) Reconcile(req ctrl.Request) (ctrl.Result, error) {
	_ = context.Background()
	r.Log.WithValues("prefetch", req.NamespacedName)

	prefetch := &cachev1.Prefetch{}
	err := r.Client.Get(context.TODO(), req.NamespacedName, prefetch)
	if err != nil {
		log.Error(err, "failed to get Prefetch resource
")
		if errors.IsNotFound(err) {
			// Request object not found, could have been deleted after
			// reconcile request—return and don't requeue:
			return reconcile.Result{}, client.IgnoreNotFound(err)
		}
		// Error reading the object—requeue the request:
		return reconcile.Result{}, err
	}

	fmt.Printf("Filter by labels %+v
", prefetch.Spec.FilterByLabels)
	fmt.Printf("RetryAfter %+v
", prefetch.Spec.RetryAfter)

	var retryAfter int
	if prefetch.Spec.RetryAfter != 0 {
		retryAfter = prefetch.Spec.RetryAfter
	} else {
		retryAfter = 300
	}

	if len(prefetch.Spec.FilterByLabels) > 0 {
		PrefetchImages(r, prefetch)
	} else {
		fmt.Printf("Skipping empty labels
")
	}

	DeleteCompletedPods(prefetch)

	if err != nil {
		return ctrl.Result{RequeueAfter: time.Second * time.Duration(retryAfter)}, nil
	} else {
		return ctrl.Result{RequeueAfter: time.Second * time.Duration(retryAfter)}, err
	}
}

func (r *PrefetchReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cachev1.Prefetch{}).
		Complete(r)
}

```
Basically what we do is set a timer to create a pod in each node to force it fetch the image that the deployments (that we filter by labels) needs or is going to use, by doing this if the node already has the image nothing happens and it will be removed in the next run, however if the image is not there it will be fetched so if anything happens and a pod needs to be actually scheduled there it won't need to download everything so it should be relatively faster.
You can find this file [here](https://github.com/kainlite/kubernetes-prefetch-operator/blob/master/controllers/prefetch_controller.go)

##### What we should be seeing in our cluster
```elixir
$ kubectl get pods -A -o wide
NAMESPACE                             NAME                                                              READY   STATUS      RESTARTS   AGE     IP            NODE                 NOMINATED NODE   READINESS GATES
default                               nginx-deployment-697c4998bb-2qm6h                                 1/1     Running     3          6d4h    10.244.2.3    kind-worker3         <none>           <none>
default                               nginx-deployment-697c4998bb-tnzpx                                 1/1     Running     3          6d4h    10.244.2.4    kind-worker3         <none>           <none>
default                               nginx-deployment-798984b768-ndsrk                                 0/1     Pending     0          27m     <none>        <none>               <none>           <none>
default                               prefetch-pod-b1ba3b2f-6667-4cb0-99c8-30d5cafa572a-kind-worker     0/1     Completed   0          51s     10.244.3.72   kind-worker          <none>           <none>
default                               prefetch-pod-b1ba3b2f-6667-4cb0-99c8-30d5cafa572a-kind-worker2    0/1     Completed   0          51s     10.244.1.84   kind-worker2         <none>           <none>
default                               prefetch-pod-b1ba3b2f-6667-4cb0-99c8-30d5cafa572a-kind-worker3    0/1     Completed   0          51s     10.244.2.37   kind-worker3         <none>           <none>
kube-system                           coredns-66bff467f8-4vnd8                                          1/1     Running     6          6d7h    10.244.3.2    kind-worker          <none>           <none>
kube-system                           coredns-66bff467f8-tsrtp                                          1/1     Running     6          6d7h    10.244.3.3    kind-worker          <none>           <none>

```

#### Cleaning up
To clean up the operator from the cluster you can do, and also remember to clean up your clusters or whatever you are using if it's in the cloud to avoid unexpected bills
```elixir
$ kubectl delete -f config/samples/cache_v1_prefetch.yaml
prefetch.cache.techsquad.rocks "prefetch-sample" deleted

$ kustomize build config/default | kubectl delete -f -
namespace "kubernetes-prefetch-operator-system" deleted
customresourcedefinition.apiextensions.k8s.io "prefetches.cache.techsquad.rocks" deleted
role.rbac.authorization.k8s.io "kubernetes-prefetch-operator-leader-election-role" deleted
clusterrole.rbac.authorization.k8s.io "kubernetes-prefetch-operator-manager-role" deleted
clusterrole.rbac.authorization.k8s.io "kubernetes-prefetch-operator-proxy-role" deleted
clusterrole.rbac.authorization.k8s.io "kubernetes-prefetch-operator-metrics-reader" deleted
rolebinding.rbac.authorization.k8s.io "kubernetes-prefetch-operator-leader-election-rolebinding" deleted
clusterrolebinding.rbac.authorization.k8s.io "kubernetes-prefetch-operator-manager-rolebinding" deleted
clusterrolebinding.rbac.authorization.k8s.io "kubernetes-prefetch-operator-proxy-rolebinding" deleted
service "kubernetes-prefetch-operator-controller-manager-metrics-service" deleted
deployment.apps "kubernetes-prefetch-operator-controller-manager" deleted

$ kubectl get pods -A
NAMESPACE            NAME                                         READY   STATUS    RESTARTS   AGE
default              nginx-deployment-697c4998bb-2qm6h            1/1     Running   3          6d4h
default              nginx-deployment-697c4998bb-tnzpx            1/1     Running   3          6d4h
default              nginx-deployment-798984b768-ndsrk            0/1     Pending   0          38m
kube-system          coredns-66bff467f8-4vnd8                     1/1     Running   6          6d7h
kube-system          coredns-66bff467f8-tsrtp                     1/1     Running   6          6d7h
kube-system          etcd-kind-control-plane                      1/1     Running   2          5d7h
kube-system          kindnet-6g7fc                                1/1     Running   7          6d7h
kube-system          kindnet-jxjdd                                1/1     Running   6          6d7h
kube-system          kindnet-rw28j                                1/1     Running   5          6d7h
kube-system          kindnet-w4wqg                                1/1     Running   5          6d7h
kube-system          kube-apiserver-kind-control-plane            1/1     Running   2          5d7h
kube-system          kube-controller-manager-kind-control-plane   1/1     Running   9          6d7h
kube-system          kube-proxy-b9js2                             1/1     Running   4          6d7h
kube-system          kube-proxy-cc89w                             1/1     Running   4          6d7h
kube-system          kube-proxy-fwk7n                             1/1     Running   4          6d7h
kube-system          kube-proxy-prbds                             1/1     Running   4          6d7h
kube-system          kube-scheduler-kind-control-plane            1/1     Running   10         6d7h
local-path-storage   local-path-provisioner-bd4bb6b75-6mnrg       1/1     Running   13         6d7h

$ kind delete cluster
Deleting cluster "kind" ...

```

##### **Closing notes**
Be sure to check the links if you want to learn more about the project and I hope you enjoyed it, see you on [twitter](https://twitter.com/kainlite) or [github](https://github.com/kainlite)!

* https://sdk.operatorframework.io/docs/building-operators/golang/tutorial/
* https://sdk.operatorframework.io/docs/building-operators/golang/operator-scope/
* https://opensource.com/article/20/3/kubernetes-operator-sdk

The source for this article is [here](https://github.com/kainlite/kubernetes-prefetch-operator/)

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)
