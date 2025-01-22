%{
  title: "Why do I need a service mesh?",
  author: "Gabriel Garrido",
  description: "Why do I need a service mesh? Basically because in cloud environments you cannot trust that the network will be reliable 100% of the time, that the latency will be low, that the network is secure and the bandwidth is infinite, the service mesh is just an extra layer to help microservices communicate with each other safely and reliably.",
  tags: ~w(kubernetes istio),
  published: true,
  image: "logo.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

### Introduction
This time we will see how to get started with [Istio](https://istio.io/) and why do we need to use a service mesh.
<br />

In this example I will be using [Digital Ocean](https://m.do.co/c/01d040b789de) (that's my referral link), note that I do not have any association with Digital Ocean but they give you $100 to test their products for 60 days, if you spend $25 I get another $25.
<br />

### Istio
So... You might be wondering some of those questions: why Istio? Why do I need a service mesh?, when do I need that? And I want to help you with some answers:
<br />

Why do I need a service mesh? Basically because in cloud environments you cannot trust that the network will be reliable 100% of the time, that the latency will be low, that the network is secure and the bandwidth is infinite, the service mesh is just an extra layer to help microservices communicate with each other safely and reliably.
<br />

When do I need to have one? This one can be tricky and will depend on your environment, but the moment that you start experiencing network issues between your microservices would be a good moment to do it, it could be done before of course, but it will highly depend on the project, if you can start early with it the better and easier to implement will be, always have in mind the benefits of added security, observability and likely performance improvement.
<br />

Why Istio? This will be a small series of service meshes for kubernetes and I decided to start with Istio.
<br />

In case you don't agree with my explanations that's ok, this is a TL;DR version and also I simplified things a lot, for a more complete overview you can check [this](https://blog.buoyant.io/2017/04/25/whats-a-service-mesh-and-why-do-i-need-one/) article or [this one](https://www.oreilly.com/ideas/do-you-need-a-service-mesh) or if you want a more in-depth introduction you can read more [here](https://www.toptal.com/kubernetes/service-mesh-comparison).
<br />

### Let's get started
First of all we need to download and install Istio in our cluster, the recommended way of doing it is using helm (In this case I will be using the no Tiller alternative, but it could be done with helm install as well, check here for [more info](https://istio.io/docs/setup/kubernetes/helm-install/)):
```elixir
$ curl -L https://git.io/getLatestIstio | sh -
```
This will download and extract the latest release, in this case 1.0.5 at this moment.
<br />

So let's install Istio... only pay attention to the first 3 commands, then you can skip until the end of the code block, I post all the output because I like full examples :)
```elixir
istio-1.0.5 $ helm template install/kubernetes/helm/istio --name istio --namespace istio-system --set grafana.enabled=true > $HOME/istio.yaml
istio-1.0.5 $ kubectl create namespace istio-system
namespace "istio-system" created

istio-1.0.5 $ kubectl apply -f $HOME/istio.yaml
configmap "istio-galley-configuration" created
configmap "istio-statsd-prom-bridge" created
configmap "prometheus" created
configmap "istio-security-custom-resources" created
configmap "istio" created
configmap "istio-sidecar-injector" created
serviceaccount "istio-galley-service-account" created
serviceaccount "istio-egressgateway-service-account" created
serviceaccount "istio-ingressgateway-service-account" created
serviceaccount "istio-mixer-service-account" created
serviceaccount "istio-pilot-service-account" created
serviceaccount "prometheus" created
serviceaccount "istio-cleanup-secrets-service-account" created
clusterrole.rbac.authorization.k8s.io "istio-cleanup-secrets-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-cleanup-secrets-istio-system" created
job.batch "istio-cleanup-secrets" created
serviceaccount "istio-security-post-install-account" created
clusterrole.rbac.authorization.k8s.io "istio-security-post-install-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-security-post-install-role-binding-istio-system" created
job.batch "istio-security-post-install" created
serviceaccount "istio-citadel-service-account" created
serviceaccount "istio-sidecar-injector-service-account" created
customresourcedefinition.apiextensions.k8s.io "virtualservices.networking.istio.io" created
customresourcedefinition.apiextensions.k8s.io "destinationrules.networking.istio.io" created
customresourcedefinition.apiextensions.k8s.io "serviceentries.networking.istio.io" created
customresourcedefinition.apiextensions.k8s.io "gateways.networking.istio.io" created
customresourcedefinition.apiextensions.k8s.io "envoyfilters.networking.istio.io" created
customresourcedefinition.apiextensions.k8s.io "httpapispecbindings.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "httpapispecs.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "quotaspecbindings.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "quotaspecs.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "rules.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "attributemanifests.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "bypasses.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "circonuses.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "deniers.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "fluentds.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "kubernetesenvs.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "listcheckers.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "memquotas.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "noops.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "opas.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "prometheuses.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "rbacs.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "redisquotas.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "servicecontrols.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "signalfxs.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "solarwindses.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "stackdrivers.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "statsds.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "stdios.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "apikeys.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "authorizations.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "checknothings.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "kuberneteses.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "listentries.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "logentries.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "edges.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "metrics.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "quotas.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "reportnothings.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "servicecontrolreports.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "tracespans.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "rbacconfigs.rbac.istio.io" created
customresourcedefinition.apiextensions.k8s.io "serviceroles.rbac.istio.io" created
customresourcedefinition.apiextensions.k8s.io "servicerolebindings.rbac.istio.io" created
customresourcedefinition.apiextensions.k8s.io "adapters.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "instances.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "templates.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "handlers.config.istio.io" created
clusterrole.rbac.authorization.k8s.io "istio-galley-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-egressgateway-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-ingressgateway-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-mixer-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-pilot-istio-system" created
clusterrole.rbac.authorization.k8s.io "prometheus-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-citadel-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-sidecar-injector-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-galley-admin-role-binding-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-egressgateway-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-ingressgateway-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-mixer-admin-role-binding-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-pilot-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "prometheus-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-citadel-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-sidecar-injector-admin-role-binding-istio-system" created
service "istio-galley" created
service "istio-egressgateway" created
service "istio-ingressgateway" created
service "istio-policy" created
service "istio-telemetry" created
service "istio-pilot" created
service "prometheus" created
service "istio-citadel" created
service "istio-sidecar-injector" created
deployment.extensions "istio-galley" created
deployment.extensions "istio-egressgateway" created
deployment.extensions "istio-ingressgateway" created
deployment.extensions "istio-policy" created
deployment.extensions "istio-telemetry" created
deployment.extensions "istio-pilot" created
deployment.extensions "prometheus" created
deployment.extensions "istio-citadel" created
deployment.extensions "istio-sidecar-injector" created
gateway.networking.istio.io "istio-autogenerated-k8s-ingress" created
horizontalpodautoscaler.autoscaling "istio-egressgateway" created
horizontalpodautoscaler.autoscaling "istio-ingressgateway" created
horizontalpodautoscaler.autoscaling "istio-policy" created
horizontalpodautoscaler.autoscaling "istio-telemetry" created
horizontalpodautoscaler.autoscaling "istio-pilot" created
mutatingwebhookconfiguration.admissionregistration.k8s.io "istio-sidecar-injector" created
attributemanifest.config.istio.io "istioproxy" created
attributemanifest.config.istio.io "kubernetes" created
stdio.config.istio.io "handler" created
logentry.config.istio.io "accesslog" created
logentry.config.istio.io "tcpaccesslog" created
rule.config.istio.io "stdio" created
rule.config.istio.io "stdiotcp" created
metric.config.istio.io "requestcount" created
metric.config.istio.io "requestduration" created
metric.config.istio.io "requestsize" created
metric.config.istio.io "responsesize" created
metric.config.istio.io "tcpbytesent" created
metric.config.istio.io "tcpbytereceived" created
prometheus.config.istio.io "handler" created
rule.config.istio.io "promhttp" created
rule.config.istio.io "promtcp" created
kubernetesenv.config.istio.io "handler" created
rule.config.istio.io "kubeattrgenrulerule" created
rule.config.istio.io "tcpkubeattrgenrulerule" created
kubernetes.config.istio.io "attributes" created
destinationrule.networking.istio.io "istio-policy" created
destinationrule.networking.istio.io "istio-telemetry" created
```
WOAH, What did just happen?, a lot of new resources were created, basically we just generated the manifest from the helm chart and applied that to our cluster.
<br />

So lets see what's running and what that means:
```elixir
$ kubectl get pods -n istio-system
NAME                                      READY     STATUS      RESTARTS   AGE
istio-citadel-856f994c58-l96p8            1/1       Running     0          3m
istio-cleanup-secrets-xqqj4               0/1       Completed   0          3m
istio-egressgateway-5649fcf57-7zwkh       1/1       Running     0          3m
istio-galley-7665f65c9c-tzn7d             1/1       Running     0          3m
istio-ingressgateway-6755b9bbf6-bh84r     1/1       Running     0          3m
istio-pilot-56855d999b-c4cp5              2/2       Running     0          3m
istio-policy-6fcb6d655f-9544z             2/2       Running     0          3m
istio-sidecar-injector-768c79f7bf-th8zh   1/1       Running     0          3m
istio-telemetry-664d896cf5-jdcwv          2/2       Running     0          3m
prometheus-76b7745b64-f8jxn               1/1       Running     0          3m
```
A few minutes later, almost everything is up, but what's all that? Istio has several components, see the following overview extracted from [github](https://github.com/istio/istio).
<br />

**Envoy**: Sidecar proxies per microservice to handle ingress/egress traffic between services in the cluster and from a service to external services. The proxies form a secure microservice mesh providing a rich set of functions like discovery, rich layer-7 routing, circuit breakers, policy enforcement and telemetry recording/reporting functions.
Note: The service mesh is not an overlay network. It simplifies and enhances how microservices in an application talk to each other over the network provided by the underlying platform.
<br />

**Mixer**: Central component that is leveraged by the proxies and microservices to enforce policies such as authorization, rate limits, quotas, authentication, request tracing and telemetry collection.
<br />

**Pilot**: A component responsible for configuring the proxies at runtime.
<br />

**Citadel**: A centralized component responsible for certificate issuance and rotation.
<br />

**Node Agent**: A per-node component responsible for certificate issuance and rotation.
<br />

**Galley**: Central component for validating, ingesting, aggregating, transforming and distributing config within Istio.
<br />

Ok so, a lot of new things were installed but how do I know it's working? let's deploy a [test application](https://istio.io/docs/examples/bookinfo/) and check it:
```elixir
$ export PATH="$PATH:~/istio-1.0.5/bin"
istio-1.0.5/samples/bookinfo $ kubectl apply -f <(istioctl kube-inject -f platform/kube/bookinfo.yaml)
service "details" created
deployment.extensions "details-v1" created
service "ratings" created
deployment.extensions "ratings-v1" created
service "reviews" created
deployment.extensions "reviews-v1" created
deployment.extensions "reviews-v2" created
deployment.extensions "reviews-v3" created
service "productpage" created
deployment.extensions "productpage-v1" created
```
<br />
That command not only deployed the application but injected the Istio sidecar to each pod:
```elixir
$ kubectl get pods
NAME                              READY     STATUS    RESTARTS   AGE
details-v1-8bd954dbb-zhrqq        2/2       Running   0          2m
productpage-v1-849c786f96-kpfx9   2/2       Running   0          2m
ratings-v1-68d648d6fd-w68qb       2/2       Running   0          2m
reviews-v1-b4c984bdc-9s6j5        2/2       Running   0          2m
reviews-v2-575446d5db-r6kwc       2/2       Running   0          2m
reviews-v3-74458c4889-kr4wb       2/2       Running   0          2m
```
As we can see each pod has 2 containers in it, the app container and istio-proxy. You can also configure [automatic sidecar injection](https://istio.io/docs/setup/kubernetes/sidecar-injection/#automatic-sidecar-injection).
<br />

Also all services are running:
```elixir
$ kubectl get services
NAME          TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
details       ClusterIP   10.245.134.179   <none>        9080/TCP   3m
kubernetes    ClusterIP   10.245.0.1       <none>        443/TCP    3d
productpage   ClusterIP   10.245.32.221    <none>        9080/TCP   3m
ratings       ClusterIP   10.245.159.112   <none>        9080/TCP   3m
reviews       ClusterIP   10.245.77.125    <none>        9080/TCP   3m
```
<br />

But how do I access the app?
```elixir
istio-1.0.5/samples/bookinfo $ kubectl apply -f networking/bookinfo-gateway.yaml
gateway.networking.istio.io "bookinfo-gateway" created
virtualservice.networking.istio.io "bookinfo" created
```
In Istio a Gateway configures a load balancer for HTTP/TCP traffic, most commonly operating at the edge of the mesh to enable ingress traffic for an application (L4-L6).
<br />

After that we need to set some environment variables to fetch the LB ip, port, etc.
```elixir
$ export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
$ export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
$ export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
$ export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

curl -o /dev/null -s -w "%{http_code}\n" http://${GATEWAY_URL}/productpage
```
If the latest curl returns 200 then we're good, you can also browse the app `open http://${GATEWAY_URL}/productpage` and you will see something like the following image:
![img](/images/productpage-example.webp){:class="mx-auto"}
<br />

Also you can use [Grafana](https://grafana.com/) to check some metrics about the service usage, etc. (You don't have to worry about prometheus since it's enabled by default). Spin up the port-forward so we don't have to expose grafana: to the world with: `kubectl -n istio-system port-forward $(kubectl -n istio-system get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}') 3000:3000`, and then `open http://localhost:3000`.
<br />

As a general advice check all the settings that Istio offers try the ones that you think that could be useful for your project and always measure and compare.
<br />

### Notes
* Do mind that **pilot** pod requires at least 4 Gbs of memory, so you will need at least one node with that amount of memory.
* You can check the load balancer status under: Manage -> Networking -> Load balancers. And if everything is okay your LB will say Healthy.
* Grafana is not enabled by default but we do enable it via helm with `--set grafana.enabled=true`, if you want to check all the possible options [go here](https://istio.io/docs/reference/config/installation-options/), if you are using more than two `--set` options I would recommend creating a `values.yaml` file and use that instead.
* Istio is a big beast and should be treated carefully, there is a lot more to learn and test out. We only scratched the surface here.
<br />

### Upcoming posts
* More examples using Istio.
* Linkerd.
* Maybe some Golang fun.
* Serverless or kubeless, that's the question.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Por que necesito un service mesh o malla de servicio?",
  author: "Gabriel Garrido",
  description: "Muchas veces cuando estamos en la nube, necesitamos garantizar reliabilidad, tiempo de respuesta, y
  comunicacion entre distintos microservicios, en esto y mas podemos sacarle provecho a un service mesh.",
  tags: ~w(kubernetes istio),
  published: true,
  image: "logo.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### **Introducción**
Esta vez veremos cómo empezar con [Istio](https://istio.io/) y por qué necesitamos usar un service mesh.
<br />

### **Istio**
Entonces... Podrías estar preguntándote algunas de estas preguntas: ¿por qué Istio? ¿Por qué necesito un service mesh? ¿Cuándo lo necesito? Y quiero ayudarte con algunas respuestas:
<br />

¿Por qué necesito un service mesh? Básicamente porque en entornos en la nube no puedes confiar en que la red será confiable el 100% del tiempo, que la latencia será baja, que la red es segura y que el ancho de banda es infinito. El service mesh es simplemente una capa adicional que ayuda a los microservicios a comunicarse entre sí de manera segura y confiable.
<br />

¿Cuándo necesito tener uno? Esto puede ser complicado y dependerá de tu entorno, pero el momento en que comiences a experimentar problemas de red entre tus microservicios sería un buen momento para implementarlo. Por supuesto, podría hacerse antes, pero dependerá mucho del proyecto; si puedes empezar temprano, será mejor y más fácil de implementar. Siempre ten en cuenta los beneficios de seguridad adicional, observabilidad y probable mejora del rendimiento.
<br />

¿Por qué Istio? Esta será una pequeña serie sobre service meshes para Kubernetes y decidí comenzar con Istio.
<br />

En caso de que no estés de acuerdo con mis explicaciones, está bien; esta es una versión resumida y también simplifiqué mucho las cosas. Para una visión más completa, puedes consultar [este](https://blog.buoyant.io/2017/04/25/whats-a-service-mesh-and-why-do-i-need-one/) artículo o [este otro](https://www.oreilly.com/ideas/do-you-need-a-service-mesh), o si deseas una introducción más profunda puedes leer más [aquí](https://www.toptal.com/kubernetes/service-mesh-comparison).
<br />

### **Empecemos**

Primero que nada, necesitamos descargar e instalar Istio en nuestro clúster. La forma recomendada de hacerlo es usando Helm (en este caso, utilizaré la alternativa sin Tiller, pero también se podría hacer con `helm install`. Consulta [más información aquí](https://istio.io/docs/setup/kubernetes/helm-install/)):

```elixir
$ curl -L https://git.io/getLatestIstio | sh -
```

Esto descargará y extraerá la última versión, en este caso la 1.0.5 en este momento.

<br />

Así que instalemos Istio... solo presta atención a los primeros 3 comandos, luego puedes saltar hasta el final del bloque de código; publico toda la salida porque me gustan los ejemplos completos :)
```elixir
istio-1.0.5 $ helm template install/kubernetes/helm/istio --name istio --namespace istio-system --set grafana.enabled=true > $HOME/istio.yaml
istio-1.0.5 $ kubectl create namespace istio-system
namespace "istio-system" created

istio-1.0.5 $ kubectl apply -f $HOME/istio.yaml
configmap "istio-galley-configuration" created
configmap "istio-statsd-prom-bridge" created
configmap "prometheus" created
configmap "istio-security-custom-resources" created
configmap "istio" created
configmap "istio-sidecar-injector" created
serviceaccount "istio-galley-service-account" created
serviceaccount "istio-egressgateway-service-account" created
serviceaccount "istio-ingressgateway-service-account" created
serviceaccount "istio-mixer-service-account" created
serviceaccount "istio-pilot-service-account" created
serviceaccount "prometheus" created
serviceaccount "istio-cleanup-secrets-service-account" created
clusterrole.rbac.authorization.k8s.io "istio-cleanup-secrets-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-cleanup-secrets-istio-system" created
job.batch "istio-cleanup-secrets" created
serviceaccount "istio-security-post-install-account" created
clusterrole.rbac.authorization.k8s.io "istio-security-post-install-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-security-post-install-role-binding-istio-system" created
job.batch "istio-security-post-install" created
serviceaccount "istio-citadel-service-account" created
serviceaccount "istio-sidecar-injector-service-account" created
customresourcedefinition.apiextensions.k8s.io "virtualservices.networking.istio.io" created
customresourcedefinition.apiextensions.k8s.io "destinationrules.networking.istio.io" created
customresourcedefinition.apiextensions.k8s.io "serviceentries.networking.istio.io" created
customresourcedefinition.apiextensions.k8s.io "gateways.networking.istio.io" created
customresourcedefinition.apiextensions.k8s.io "envoyfilters.networking.istio.io" created
customresourcedefinition.apiextensions.k8s.io "httpapispecbindings.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "httpapispecs.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "quotaspecbindings.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "quotaspecs.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "rules.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "attributemanifests.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "bypasses.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "circonuses.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "deniers.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "fluentds.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "kubernetesenvs.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "listcheckers.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "memquotas.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "noops.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "opas.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "prometheuses.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "rbacs.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "redisquotas.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "servicecontrols.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "signalfxs.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "solarwindses.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "stackdrivers.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "statsds.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "stdios.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "apikeys.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "authorizations.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "checknothings.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "kuberneteses.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "listentries.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "logentries.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "edges.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "metrics.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "quotas.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "reportnothings.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "servicecontrolreports.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "tracespans.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "rbacconfigs.rbac.istio.io" created
customresourcedefinition.apiextensions.k8s.io "serviceroles.rbac.istio.io" created
customresourcedefinition.apiextensions.k8s.io "servicerolebindings.rbac.istio.io" created
customresourcedefinition.apiextensions.k8s.io "adapters.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "instances.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "templates.config.istio.io" created
customresourcedefinition.apiextensions.k8s.io "handlers.config.istio.io" created
clusterrole.rbac.authorization.k8s.io "istio-galley-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-egressgateway-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-ingressgateway-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-mixer-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-pilot-istio-system" created
clusterrole.rbac.authorization.k8s.io "prometheus-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-citadel-istio-system" created
clusterrole.rbac.authorization.k8s.io "istio-sidecar-injector-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-galley-admin-role-binding-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-egressgateway-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-ingressgateway-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-mixer-admin-role-binding-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-pilot-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "prometheus-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-citadel-istio-system" created
clusterrolebinding.rbac.authorization.k8s.io "istio-sidecar-injector-admin-role-binding-istio-system" created
service "istio-galley" created
service "istio-egressgateway" created
service "istio-ingressgateway" created
service "istio-policy" created
service "istio-telemetry" created
service "istio-pilot" created
service "prometheus" created
service "istio-citadel" created
service "istio-sidecar-injector" created
deployment.extensions "istio-galley" created
deployment.extensions "istio-egressgateway" created
deployment.extensions "istio-ingressgateway" created
deployment.extensions "istio-policy" created
deployment.extensions "istio-telemetry" created
deployment.extensions "istio-pilot" created
deployment.extensions "prometheus" created
deployment.extensions "istio-citadel" created
deployment.extensions "istio-sidecar-injector" created
gateway.networking.istio.io "istio-autogenerated-k8s-ingress" created
horizontalpodautoscaler.autoscaling "istio-egressgateway" created
horizontalpodautoscaler.autoscaling "istio-ingressgateway" created
horizontalpodautoscaler.autoscaling "istio-policy" created
horizontalpodautoscaler.autoscaling "istio-telemetry" created
horizontalpodautoscaler.autoscaling "istio-pilot" created
mutatingwebhookconfiguration.admissionregistration.k8s.io "istio-sidecar-injector" created
attributemanifest.config.istio.io "istioproxy" created
attributemanifest.config.istio.io "kubernetes" created
stdio.config.istio.io "handler" created
logentry.config.istio.io "accesslog" created
logentry.config.istio.io "tcpaccesslog" created
rule.config.istio.io "stdio" created
rule.config.istio.io "stdiotcp" created
metric.config.istio.io "requestcount" created
metric.config.istio.io "requestduration" created
metric.config.istio.io "requestsize" created
metric.config.istio.io "responsesize" created
metric.config.istio.io "tcpbytesent" created
metric.config.istio.io "tcpbytereceived" created
prometheus.config.istio.io "handler" created
rule.config.istio.io "promhttp" created
rule.config.istio.io "promtcp" created
kubernetesenv.config.istio.io "handler" created
rule.config.istio.io "kubeattrgenrulerule" created
rule.config.istio.io "tcpkubeattrgenrulerule" created
kubernetes.config.istio.io "attributes" created
destinationrule.networking.istio.io "istio-policy" created
destinationrule.networking.istio.io "istio-telemetry" created
```
### **¡VAYA! ¿Qué acaba de pasar?**

Se crearon muchos recursos nuevos; básicamente, acabamos de generar el manifiesto del chart de Helm y lo aplicamos a nuestro clúster.

<br />

Así que veamos qué está en ejecución y qué significa eso:
```elixir
$ kubectl get pods -n istio-system
NAME                                      READY     STATUS      RESTARTS   AGE
istio-citadel-856f994c58-l96p8            1/1       Running     0          3m
istio-cleanup-secrets-xqqj4               0/1       Completed   0          3m
istio-egressgateway-5649fcf57-7zwkh       1/1       Running     0          3m
istio-galley-7665f65c9c-tzn7d             1/1       Running     0          3m
istio-ingressgateway-6755b9bbf6-bh84r     1/1       Running     0          3m
istio-pilot-56855d999b-c4cp5              2/2       Running     0          3m
istio-policy-6fcb6d655f-9544z             2/2       Running     0          3m
istio-sidecar-injector-768c79f7bf-th8zh   1/1       Running     0          3m
istio-telemetry-664d896cf5-jdcwv          2/2       Running     0          3m
prometheus-76b7745b64-f8jxn               1/1       Running     0          3m
```
Unos minutos después, casi todo está en funcionamiento, pero ¿qué es todo eso? Istio tiene varios componentes; consulta la siguiente descripción general extraída de [GitHub](https://github.com/istio/istio).

<br />

**Envoy**: Proxies sidecar por microservicio para manejar el tráfico de entrada/salida entre servicios en el clúster y desde un servicio a servicios externos. Los proxies forman un mesh de microservicios seguro que proporciona un conjunto rico de funciones como descubrimiento, enrutamiento avanzado de capa 7, circuit breakers, aplicación de políticas y funciones de registro/informe de telemetría.

Nota: El service mesh no es una red superpuesta. Simplifica y mejora cómo los microservicios en una aplicación se comunican entre sí sobre la red proporcionada por la plataforma subyacente.

<br />

**Mixer**: Componente central que es utilizado por los proxies y microservicios para aplicar políticas como autorización, límites de velocidad, cuotas, autenticación, rastreo de solicitudes y recopilación de telemetría.

<br />

**Pilot**: Un componente responsable de configurar los proxies en tiempo de ejecución.

<br />

**Citadel**: Un componente centralizado responsable de la emisión y rotación de certificados.

<br />

**Node Agent**: Un componente por nodo responsable de la emisión y rotación de certificados.

<br />

**Galley**: Componente central para validar, ingerir, agregar, transformar y distribuir configuraciones dentro de Istio.

<br />

Bien, se instalaron muchas cosas nuevas, pero ¿cómo sé que está funcionando? Vamos a desplegar una [aplicación de prueba](https://istio.io/docs/examples/bookinfo/) y comprobarlo:
```elixir
$ export PATH="$PATH:~/istio-1.0.5/bin"
istio-1.0.5/samples/bookinfo $ kubectl apply -f <(istioctl kube-inject -f platform/kube/bookinfo.yaml)
service "details" created
deployment.extensions "details-v1" created
service "ratings" created
deployment.extensions "ratings-v1" created
service "reviews" created
deployment.extensions "reviews-v1" created
deployment.extensions "reviews-v2" created
deployment.extensions "reviews-v3" created
service "productpage" created
deployment.extensions "productpage-v1" created
```
<br />
Como podemos ver, cada pod tiene 2 contenedores: el contenedor de la aplicación y `istio-proxy`. También puedes configurar la [inyección automática de sidecar](https://istio.io/docs/setup/kubernetes/sidecar-injection/#automatic-sidecar-injection).
```elixir
$ kubectl get pods
NAME                              READY     STATUS    RESTARTS   AGE
details-v1-8bd954dbb-zhrqq        2/2       Running   0          2m
productpage-v1-849c786f96-kpfx9   2/2       Running   0          2m
ratings-v1-68d648d6fd-w68qb       2/2       Running   0          2m
reviews-v1-b4c984bdc-9s6j5        2/2       Running   0          2m
reviews-v2-575446d5db-r6kwc       2/2       Running   0          2m
reviews-v3-74458c4889-kr4wb       2/2       Running   0          2m
```
<br />

Además, todos los servicios están en funcionamiento:

```elixir
$ kubectl get services
NAME          TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
details       ClusterIP   10.245.134.179   <none>        9080/TCP   3m
kubernetes    ClusterIP   10.245.0.1       <none>        443/TCP    3d
productpage   ClusterIP   10.245.32.221    <none>        9080/TCP   3m
ratings       ClusterIP   10.245.159.112   <none>        9080/TCP   3m
reviews       ClusterIP   10.245.77.125    <none>        9080/TCP   3m
```
<br />

Pero, ¿cómo accedo a la aplicación?
```elixir
istio-1.0.5/samples/bookinfo $ kubectl apply -f networking/bookinfo-gateway.yaml
gateway.networking.istio.io "bookinfo-gateway" created
virtualservice.networking.istio.io "bookinfo" created
```
En Istio, un Gateway configura un balanceador de carga para tráfico HTTP/TCP, operando más comúnmente en el borde del mesh para habilitar el tráfico de entrada para una aplicación (L4-L6).
<br />

Después de eso, necesitamos establecer algunas variables de entorno para obtener la IP del balanceador de carga, el puerto, etc.
```elixir
$ export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
$ export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
$ export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
$ export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

curl -o /dev/null -s -w "%{http_code}\n" http://${GATEWAY_URL}/productpage
```
Si el último comando `curl` devuelve 200, entonces estamos bien; también puedes navegar a la aplicación con `open http://${GATEWAY_URL}/productpage` y verás algo como la siguiente imagen:
![img](/images/productpage-example.webp){:class="mx-auto"}
<br />

También puedes usar [Grafana](https://grafana.com/) para verificar algunas métricas sobre el uso del servicio, etc. (No tienes que preocuparte por Prometheus ya que está habilitado por defecto). Inicia el port-forward para que no tengamos que exponer Grafana al mundo con: `kubectl -n istio-system port-forward $(kubectl -n istio-system get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}') 3000:3000`, y luego `open http://localhost:3000`.
<br />

Como consejo general, revisa todas las configuraciones que ofrece Istio; prueba las que creas que podrían ser útiles para tu proyecto y siempre mide y compara.
<br />

### **Notas**
* Ten en cuenta que el pod **pilot** requiere al menos 4 GB de memoria, por lo que necesitarás al menos un nodo con esa cantidad de memoria.
* Puedes verificar el estado del balanceador de carga en: Manage -> Networking -> Load balancers. Si todo está bien, tu LB dirá "Healthy".
* Grafana no está habilitado por defecto, pero lo habilitamos vía Helm con `--set grafana.enabled=true`. Si deseas revisar todas las opciones posibles, [ve aquí](https://istio.io/docs/reference/config/installation-options/). Si estás usando más de dos opciones `--set`, recomendaría crear un archivo `values.yaml` y usar eso en su lugar.
* Istio es una gran herramienta y debe tratarse con cuidado; hay mucho más que aprender y probar. Aquí solo hemos rascado la superficie.

<br />

### **Próximas publicaciones**
* Más ejemplos usando Istio.
* Linkerd.
* Quizás algo de diversión con Golang.
* Serverless o kubeless, esa es la cuestión.

<br />

### **Errata**
Si encuentras algún error o tienes alguna sugerencia, por favor envíame un mensaje para que pueda corregirlo.

<br />
