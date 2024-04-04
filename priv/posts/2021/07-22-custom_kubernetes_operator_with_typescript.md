%{
  title: "Custom Kubernetes Operator With TypeScript (Typed JavaScript)",
  author: "Gabriel Garrido",
  description: "In this article we will explore how to create a sample operator using typescript and to deploy it to our cluster, the operator will be pretty dummy...",
  tags: ~w(kubernetes typescript operator),
  published: true,
}
---

![operator](/images/kubernetes-ts-js.png){:class="mx-auto"}

#### **Introduction**

In this article we will explore how to create a sample operator using typescript and to deploy it to our cluster, the operator will be pretty dummy in the sense that it will only deploy some resources based in a CRD, but you can customize it to do whatever you might need or want, the idea is to get an idea of all that it takes to do an operator outside of the magic land of [Go](https://golang.org/) and [kubebuilder](https://github.com/kubernetes-sigs/kubebuilder).

If you want to check past articles that explore other alternative frameworks and languages go to:

- [Cloud native applications with kubebuilder and kind aka kubernetes operators](/blog/cloud_native_applications_with_kubebuilder_and_kind_aka_kubernetes_operators/).
- [Testing the Operator SDK and making a prefetch mechanism for Kubernetes](/blog/testing_the_operator_sdk_and_making_a_prefetch_mechanism_for_kubernetes/).

You will notice that both are very similar and it is because the operator-sdk uses kubebuilder.

The source for this article is here [TypeScript Operator](https://github.com/kainlite/ts-operator/) and the docker image is [here](https://github.com/kainlite/ts-operator/pkgs/container/ts-operator), also this article is based in this example from Nodeshift's [Operator in JavaScript](https://github.com/nodeshift-blog-examples/operator-in-JavaScript).

##### **Prerequisites**

- [Kind](https://github.com/kubernetes-sigs/kind)
- [Docker](https://hub.docker.com/?overlay=onboarding)
- [kustomize](https://github.com/kubernetes-sigs/kustomize)
- [Node.js](https://nodejs.org/)
- [TypeScript](https://www.typescriptlang.org/)

### Let's jump to the example

#### Creating the cluster

We will need a cluster to run and test our operator, so kind is pretty straight forward and lightweight enough to run anywhere.
```elixir=system('gist -r ' . submatch(1))```

#### Creating our operator

Creating all necessary resources for our operator to work
```elixir
❯ kustomize build resources/ | kubectl apply -f -
namespace/ts-operator created
customresourcedefinition.apiextensions.k8s.io/mycustomresources.custom.example.com created
serviceaccount/ts-operator created
clusterrole.rbac.authorization.k8s.io/mycustomresource-editor-role created
clusterrolebinding.rbac.authorization.k8s.io/manager-rolebinding created
deployment.apps/ts-operator created

❯ kubectl get pods -A
NAMESPACE            NAME                                         READY   STATUS              RESTARTS   AGE
kube-system          coredns-558bd4d5db-284q5                     1/1     Running             0          21m
kube-system          coredns-558bd4d5db-5qs64                     1/1     Running             0          21m
kube-system          etcd-kind-control-plane                      1/1     Running             0          21m
kube-system          kindnet-njtns                                1/1     Running             0          21m
kube-system          kube-apiserver-kind-control-plane            1/1     Running             0          21m
kube-system          kube-controller-manager-kind-control-plane   1/1     Running             0          21m
kube-system          kube-proxy-d2gkx                             1/1     Running             0          21m
kube-system          kube-scheduler-kind-control-plane            1/1     Running             0          21m
local-path-storage   local-path-provisioner-547f784dff-tp6cq      1/1     Running             0          21m
ts-operator          ts-operator-86dbcd9f9c-xwgdt                 0/1     ContainerCreating   0          23s

```

#### Deploying our operator

Creating our custom resource to see the operator in action
```elixir
❯ kubectl apply -f resources/mycustomresource-sample.yaml
mycustomresource.custom.example.com/mycustomresource-sample created

❯ kubectl apply -f resources/mycustomresource-sample.yaml
mycustomresource.custom.example.com/mycustomresource-sample configured

❯ kubectl get pods -A
NAMESPACE            NAME                                         READY   STATUS              RESTARTS   AGE
kube-system          coredns-558bd4d5db-284q5                     1/1     Running             0          8h
kube-system          coredns-558bd4d5db-5qs64                     1/1     Running             0          8h
kube-system          etcd-kind-control-plane                      1/1     Running             0          8h
kube-system          kindnet-njtns                                1/1     Running             0          8h
kube-system          kube-apiserver-kind-control-plane            1/1     Running             0          8h
kube-system          kube-controller-manager-kind-control-plane   1/1     Running             0          8h
kube-system          kube-proxy-d2gkx                             1/1     Running             0          8h
kube-system          kube-scheduler-kind-control-plane            1/1     Running             0          8h
local-path-storage   local-path-provisioner-547f784dff-tp6cq      1/1     Running             0          8h
ts-operator          ts-operator-86dbcd9f9c-xwgdt                 1/1     Running             0          8h
workers              mycustomresource-sample-644c6fdf78-75hh7     1/1     Running             0          2m9s
workers              mycustomresource-sample-644c6fdf78-fv5n8     1/1     Running             0          2m9s
workers              mycustomresource-sample-644c6fdf78-hprt7     0/1     ContainerCreating   0          1s

❯ kubectl delete -f resources/mycustomresource-sample.yaml
mycustomresource.custom.example.com "mycustomresource-sample" deleted

```

#### Logs from the operator

Example logs based in the creation, update and deletion of our custom resource
```elixir
❯ node_modules/ts-node/dist/bin.js src/index.ts
7/22/2021, 8:51:54 PM: Watching API
7/22/2021, 8:51:54 PM: Received event in phase ADDED.
7/22/2021, 8:52:04 PM: Received event in phase MODIFIED.
7/22/2021, 8:53:39 PM: Received event in phase ADDED.
7/22/2021, 8:53:40 PM: Nothing to update...Skipping...
7/22/2021, 8:53:40 PM: Received event in phase MODIFIED.
7/22/2021, 8:56:15 PM: Received event in phase ADDED.
7/22/2021, 8:56:20 PM: Received event in phase DELETED.
7/22/2021, 8:56:20 PM: Deleted mycustomresource-sample

```

#### Brief comparison operator-sdk vs custom operator?

There are some main differences to have in mind, in Go you:

- Have code generation from the framework for RBAC, controllers, etc.
- Out of the box tooling to build, deploy and manage your operator.

In TypeScript or JavaScript you have to handle more things which can be easily done from a CI system, In this example I used github actions to build the image and the example already had everything else configured to make typescript usable with kubernetes as an example.

#### Building and pushing (docker image)

In this case we don't have to do that it will be managed by actions using the free container registry that they provide, it will build and push the image matching the branch name, notice that it is fully transparent, you don't need to configure anything on the repo, you can see the result [here](https://github.com/kainlite/ts-operator/pkgs/container/ts-operator).
```elixir
name: Create and publish a Docker image

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

  workflow_dispatch:

jobs:
  build-and-push-image:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v2

      - name: Log in to the Container registry
        uses: docker/login-action@f054a8b539a109f9f41c372932f1ae047eff08c9
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags, labels) for Docker
        id: meta
        uses: docker/metadata-action@98669ae865ea3cffbcbaa878cf57c20bbf1c6c38
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}

      - name: Build and push Docker image
        uses: docker/build-push-action@ad44023a93711e3deb337508980b4b5e9bcdc5dc
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}

```

#### Local development

Bonus: if you want to run the operator locally when developing or debugging you can do so easily with `ts-node`, like this:
```elixir
❯ node_modules/ts-node/dist/bin.js src/index.ts
7/22/2021, 8:51:54 PM: Watching API
7/22/2021, 8:51:54 PM: Received event in phase ADDED.
7/22/2021, 8:52:04 PM: Received event in phase MODIFIED.
7/22/2021, 8:52:10 PM: Received event in phase DELETED.
....

```
The reason I used it like this was mostly to assume zero configuration, and it is possible because ts-node is listed as a development dependency, also the docker image could have been used with a bit of configuration.

Note that I did not add all the code from the resources folder or the setup for the typescript project, I recommend you to check that directly in the repo to understand all the missing pieces.

### Now let's see the code

Enough words, let's see code, I have added comments and changed the original code a bit
```elixir
/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable @typescript-eslint/no-non-null-assertion */
import * as k8s from "@kubernetes/client-node";
import * as fs from "fs";

// Configure the operator to deploy your custom resources
// and the destination namespace for your pods
const MYCUSTOMRESOURCE_GROUP = "custom.example.com";
const MYCUSTOMRESOURCE_VERSION = "v1";
const MYCUSTOMRESOURCE_PLURAL = "mycustomresources";
const NAMESPACE = "workers";

// This value specifies the amount of pods that your deployment will have
interface MyCustomResourceSpec {
  size: number;
}

interface MyCustomResourceStatus {
  pods: string[];
}

interface MyCustomResource {
  apiVersion: string;
  kind: string;
  metadata: k8s.V1ObjectMeta;
  spec?: MyCustomResourceSpec;
  status?: MyCustomResourceStatus;
}

// Generates a client from an existing kubeconfig whether in memory
// or from a file.
const kc = new k8s.KubeConfig();
kc.loadFromDefault();

// Creates the different clients for the different parts of the API.
const k8sApi = kc.makeApiClient(k8s.AppsV1Api);
const k8sApiMC = kc.makeApiClient(k8s.CustomObjectsApi);
const k8sApiPods = kc.makeApiClient(k8s.CoreV1Api);

// This is to listen for events or notifications and act accordingly
// after all it is the core part of a controller or operator to
// watch or observe, compare and reconcile
const watch = new k8s.Watch(kc);

// Then this function determines what flow needs to happen
// Create, Update or Destroy?
async function onEvent(phase: string, apiObj: any) {
  log(`Received event in phase ${phase}.`);
  if (phase == "ADDED") {
    scheduleReconcile(apiObj);
  } else if (phase == "MODIFIED") {
    try {
      scheduleReconcile(apiObj);
    } catch (err) {
      log(err);
    }
  } else if (phase == "DELETED") {
    await deleteResource(apiObj);
  } else {
    log(`Unknown event type: ${phase}`);
  }
}

// Call the API to destroy the resource, happens when the CRD instance is deleted.
async function deleteResource(obj: MyCustomResource) {
  log(`Deleted ${obj.metadata.name}`);
  return k8sApi.deleteNamespacedDeployment(obj.metadata.name!, NAMESPACE);
}

// Helpers to continue watching after an event
function onDone(err: any) {
  log(`Connection closed. ${err}`);
  watchResource();
}

async function watchResource(): Promise<any> {
  log("Watching API");
  return watch.watch(
    `/apis/${MYCUSTOMRESOURCE_GROUP}/${MYCUSTOMRESOURCE_VERSION}/namespaces/${NAMESPACE}/${MYCUSTOMRESOURCE_PLURAL}`,
    {},
    onEvent,
    onDone,
  );
}

let reconcileScheduled = false;

// Keep the controller checking every 1000 ms
// If after any condition the controller needs to be stopped
// it can be done by setting reconcileScheduled to true
function scheduleReconcile(obj: MyCustomResource) {
  if (!reconcileScheduled) {
    setTimeout(reconcileNow, 1000, obj);
    reconcileScheduled = true;
  }
}

// This is probably the most complex function since it first checks if the
// deployment already exists and if it doesn't it creates the resource.
// If it does exists updates the resources and leaves early.
async function reconcileNow(obj: MyCustomResource) {
  reconcileScheduled = false;
  const deploymentName: string = obj.metadata.name!;
  // Check if the deployment exists and patch it.
  try {
    const response = await k8sApi.readNamespacedDeployment(deploymentName, NAMESPACE);
    const deployment: k8s.V1Deployment = response.body;
    deployment.spec!.replicas = obj.spec!.size;
    k8sApi.replaceNamespacedDeployment(deploymentName, NAMESPACE, deployment);
    return;
  } catch (err) {
    log("An unexpected error occurred...");
    log(err);
  }

  // Create the deployment if it doesn't exists
  try {
    const deploymentTemplate = fs.readFileSync("deployment.json", "utf-8");
    const newDeployment: k8s.V1Deployment = JSON.parse(deploymentTemplate);

    newDeployment.metadata!.name = deploymentName;
    newDeployment.spec!.replicas = obj.spec!.size;
    newDeployment.spec!.selector!.matchLabels!["deployment"] = deploymentName;
    newDeployment.spec!.template!.metadata!.labels!["deployment"] = deploymentName;
    k8sApi.createNamespacedDeployment(NAMESPACE, newDeployment);
  } catch (err) {
    log("Failed to parse template: deployment.json");
    log(err);
  }

  //set the status of our resource to the list of pod names.
  const status: MyCustomResource = {
    apiVersion: obj.apiVersion,
    kind: obj.kind,
    metadata: {
      name: obj.metadata.name!,
      resourceVersion: obj.metadata.resourceVersion,
    },
    status: {
      pods: await getPodList(`deployment=${obj.metadata.name}`),
    },
  };

  try {
    k8sApiMC.replaceNamespacedCustomObjectStatus(
      MYCUSTOMRESOURCE_GROUP,
      MYCUSTOMRESOURCE_VERSION,
      NAMESPACE,
      MYCUSTOMRESOURCE_PLURAL,
      obj.metadata.name!,
      status,
    );
  } catch (err) {
    log(err);
  }
}

// Helper to get the pod list for the given deployment.
async function getPodList(podSelector: string): Promise<string[]> {
  try {
    const podList = await k8sApiPods.listNamespacedPod(
      NAMESPACE,
      undefined,
      undefined,
      undefined,
      undefined,
      podSelector,
    );
    return podList.body.items.map((pod) => pod.metadata!.name!);
  } catch (err) {
    log(err);
  }
  return [];
}

// The watch has begun
async function main() {
  await watchResource();
}

// Helper to pretty print logs
function log(message: string) {
  console.log(`${new Date().toLocaleString()}: ${message}`);
}

// Helper to get better errors if we miss any promise rejection.
process.on("unhandledRejection", (reason, p) => {
  console.log("Unhandled Rejection at: Promise", p, "reason:", reason);
});

// Run
main();

```

#### The `deployment.json` file

This file basically is what gets deployed when we create our custom resource
```elixir
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "mycustomresource"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "mycustomresource"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "mycustomresource"
        }
      },
      "spec": {
        "containers": [
          {
            "command": ["sleep", "3600"],
            "image": "busybox:latest",
            "name": "busybox"
          }
        ]
      }
    }
  }
}

```

#### And finally our custom resource

This is how we tell our operator that we need our operator to create some resources for a given task
```elixir
apiVersion: custom.example.com/v1
kind: MyCustomResource
metadata:
  name: mycustomresource-sample
  namespace: workers
spec:
  size: 2

```

#### Extra

For more details and to see how everything fits together I encourage you to clone the repo, test it, and modify it yourself.

### Cleaning up

To clean up the operator from the cluster you can do this
```elixir
❯ kubectl delete -f resources/mycustomresource-sample.yaml
❯ kustomize build resources/ | kubectl delete -f -
namespace "ts-operator" deleted
customresourcedefinition.apiextensions.k8s.io "mycustomresources.custom.example.com" deleted
serviceaccount "ts-operator" deleted
clusterrole.rbac.authorization.k8s.io "mycustomresource-editor-role" deleted
clusterrolebinding.rbac.authorization.k8s.io "manager-rolebinding" deleted
deployment.apps "ts-operator" deleted

❯ kubectl get pods -A
NAMESPACE            NAME                                         READY   STATUS    RESTARTS   AGE
kube-system          coredns-558bd4d5db-284q5                     1/1     Running   0          10h
kube-system          coredns-558bd4d5db-5qs64                     1/1     Running   0          10h
kube-system          etcd-kind-control-plane                      1/1     Running   0          10h
kube-system          kindnet-njtns                                1/1     Running   0          10h
kube-system          kube-apiserver-kind-control-plane            1/1     Running   0          10h
kube-system          kube-controller-manager-kind-control-plane   1/1     Running   0          10h
kube-system          kube-proxy-d2gkx                             1/1     Running   0          10h
kube-system          kube-scheduler-kind-control-plane            1/1     Running   0          10h
local-path-storage   local-path-provisioner-547f784dff-tp6cq      1/1     Running   0          10h

```

#### **Closing notes**

Be sure to check the links if you want to learn more about the examples from Nodeshift and I hope you enjoyed it, see you on [twitter](https://twitter.com/kainlite) or [github](https://github.com/kainlite)!

- https://github.com/nodeshift/nodeshift

The source for this article is [here](https://github.com/kainlite/ts-operator/)

DISCLAIMER: I'm not using OpenShift, but all examples are easily translatables to a vanilla cluster.

### Errata

If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)
