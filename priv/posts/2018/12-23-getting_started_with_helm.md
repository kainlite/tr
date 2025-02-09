%{
  title: "Getting started with helm",
  author: "Gabriel Garrido",
  description: "This tutorial will show you how to create a simple chart and also how to deploy it to kubernetes using
  helm...",
  tags: ~w(kubernetes helm),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

### **Introduction**

This tutorial will show you how to create a simple chart and also how to deploy it to kubernetes using [Helm](https://helm.sh/), in the examples I will be using [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube) or you can [check out this repo](https://github.com/kainlite/kainlite.github.io) that has a good overview of minikube, once installed and started (`minikube start`) that command will download and configure the local environment, you can follow with the following example:
<br />

Create the chart:
```elixir
helm create hello-world
```
Always use valid DNS names if you are going to have services, otherwise you will have issues later on.
<br />

Inspect the contents, as you will notice every resource is just a kubernetes resource with some placeholders and basic logic to get something more reusable:
```elixir
$ cd hello-world

charts       <--- Dependencies, charts that your chart depends on.
Chart.yaml   <--- Metadata mostly, defines the version of your chart, etc.
templates    <--- Here is where the magic happens.
values.yaml  <--- Default values file (this is used to replace in the templates at runtime)
```
Note: the following link explains the basics of [dependencies](https://docs.helm.sh/developing_charts/#managing-dependencies-manually-via-the-charts-directory), your chart can have as many dependencies as you need, the only thing that you need to do is add or install the other charts as dependencies.
<br />

The file `values.yaml` by default will look like the following snippet:
```elixir
replicaCount: 1

image:
  repository: nginx
  tag: stable
  pullPolicy: IfNotPresent

nameOverride: ""
fullnameOverride: ""

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  annotations: {}
    # kubernetes.io/ingress.class: nginx
    # kubernetes.io/tls-acme: "true"
  path: /
  hosts:
    - chart-example.local
  tls: []
  #  - secretName: chart-example-tls
  #    hosts:
  #      - chart-example.local

resources: {}
nodeSelector: {}
tolerations: []
affinity: {}
```
<br />

The next step would be to check the `templates` folder:
```elixir
deployment.yaml  <--- Standard kubernetes deployment with go templates variables.
_helpers.tpl     <--- This file defines some common variables.
ingress.yaml     <--- Ingress route, etc.
NOTES.txt        <--- Once deployed this file will display the details of our deployment, usually login data, how to connect, etc.
service.yaml     <--- The service that we will use internally and/or via ingress to reach our deployed service.
```
Go [templates](https://blog.gopheracademy.com/advent-2017/using-go-templates/) basics, if you need a refresher or a crash course in go templates, also always be sure to check Helm's own [documentation](https://github.com/helm/helm/blob/master/docs/chart_template_guide/functions_and_pipelines.md) and also some [tips and tricks](https://github.com/helm/helm/blob/master/docs/charts_tips_and_tricks.md).

<br />
Let's check the [deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) file:
```elixir
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  name: {{ include "hello-world.fullname" . }}
  labels:
    app.kubernetes.io/name: {{ include "hello-world.name" . }}
    helm.sh/chart: {{ include "hello-world.chart" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ include "hello-world.name" . }}
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ include "hello-world.name" . }}
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /
              port: http
          readinessProbe:
            httpGet:
              path: /
              port: http
          resources:
{{ toYaml .Values.resources | indent 12 }}
    {{- with .Values.nodeSelector }}
      nodeSelector:
{{ toYaml . | indent 8 }}
    {{- end }}
    {{- with .Values.affinity }}
      affinity:
{{ toYaml . | indent 8 }}
    {{- end }}
    {{- with .Values.tolerations }}
      tolerations:
{{ toYaml . | indent 8 }}
    {{- end }}
```
As you can see everything will get replaced by what you define in the `values.yaml` file and everything is under `.Values` unless you define a local variable or some other variable using helpers for example.
<br />

Let's check the [service](https://kubernetes.io/docs/concepts/services-networking/service/) file:
```elixir
apiVersion: v1
kind: Service
metadata:
  name: {{ include "hello-world.fullname" . }}
  labels:
    app.kubernetes.io/name: {{ include "hello-world.name" . }}
    helm.sh/chart: {{ include "hello-world.chart" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: {{ include "hello-world.name" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
```

<br />
Let's check the [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) file:
```elixir
{{- if .Values.ingress.enabled -}}
{{- $fullName := include "hello-world.fullname" . -}}
{{- $ingressPath := .Values.ingress.path -}}
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: {{ $fullName }}
  labels:
    app.kubernetes.io/name: {{ include "hello-world.name" . }}
    helm.sh/chart: {{ include "hello-world.chart" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.ingress.annotations }}
  annotations:
{{ toYaml . | indent 4 }}
{{- end }}
spec:
{{- if .Values.ingress.tls }}
  tls:
  {{- range .Values.ingress.tls }}
    - hosts:
      {{- range .hosts }}
        - {{ . | quote }}
      {{- end }}
      secretName: {{ .secretName }}
  {{- end }}
{{- end }}
  rules:
  {{- range .Values.ingress.hosts }}
    - host: {{ . | quote }}
      http:
        paths:
          - path: {{ $ingressPath }}
            backend:
              serviceName: {{ $fullName }}
              servicePort: http
  {{- end }}
{{- end }}
```
The ingress file is one of the most interesting ones in my humble opinion because it has a if else example and also local variables (`$fullName` for example), also iterates over a possible slice of dns record names (hosts), and the same if you have certs for them (a good way to get let's encrypt certificates automatically is using cert-manager, in the next post I will expand on this example adding a basic web app with mysql and ssl/tls).
<br />

After checking that everything is up to our needs the only thing missing is to finally deploy it to kubernetes (But first let's install tiller):
```elixir
$ helm init
$HELM_HOME has been configured at /home/gabriel/.helm.

Tiller (the Helm server-side component) has been installed into your Kubernetes Cluster.

Please note: by default, Tiller is deployed with an insecure 'allow unauthenticated users' policy.
To prevent this, run `helm init` with the --tiller-tls-verify flag.
For more information on securing your installation see: https://docs.helm.sh/using_helm/#securing-your-helm-installation
Happy Helming!
```
Note that many of the complains that Helm receives are because of the admin-y capabilities that Tiller has. A good note on the security issues that Tiller can suffer and some possible mitigation alternatives can be found on the [Bitnami page](https://engineering.bitnami.com/articles/helm-security.html), this mostly applies to multi-tenant clusters. And also be sure to check [Securing Helm](https://docs.helm.sh/using_helm/#securing-your-helm-installation)
<br />

Deploy our chart:
```elixir
$ helm install --name my-nginx -f values.yaml .
NAME:   my-nginx
LAST DEPLOYED: Sun Dec 23 00:30:11 2018
NAMESPACE: default
STATUS: DEPLOYED

RESOURCES:
==> v1/Service
NAME                  AGE
my-nginx-hello-world  0s

==> v1beta2/Deployment
my-nginx-hello-world  0s

==> v1/Pod(related)

NAME                                   READY  STATUS   RESTARTS  AGE
my-nginx-hello-world-6f948db8d5-s76zl  0/1    Pending  0         0s

NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/name=hello-world,app.kubernetes.io/instance=my-nginx" -o jsonpath="{.items[0].metadata.name}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl port-forward $POD_NAME 8080:80
```
Our deployment was successful and we can see that our pod is waiting to be scheduled.
<br />

Let's check that our service is there:
```elixir
$ kubectl get services
NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes             ClusterIP   10.96.0.1       <none>        443/TCP   1h
my-nginx-hello-world   ClusterIP   10.111.222.70   <none>        80/TCP    5m
```

<br />
And now we can test that everything is okay by running another pod in interactive mode, for example:
```elixir
$ kubectl run -i --tty alpine --image=alpine -- sh
If you don't see a command prompt, try pressing enter.

/ # apk add curl
fetch http://dl-cdn.alpinelinux.org/alpine/v3.8/main/x86_64/APKINDEX.tar.gz
fetch http://dl-cdn.alpinelinux.org/alpine/v3.8/community/x86_64/APKINDEX.tar.gz
(1/5) Installing ca-certificates (20171114-r3)
(2/5) Installing nghttp2-libs (1.32.0-r0)
(3/5) Installing libssh2 (1.8.0-r3)
(4/5) Installing libcurl (7.61.1-r1)
(5/5) Installing curl (7.61.1-r1)
Executing busybox-1.28.4-r2.trigger
Executing ca-certificates-20171114-r3.trigger
OK: 6 MiB in 18 packages

/ # curl -v my-nginx-hello-world
* Rebuilt URL to: my-nginx-hello-world/
*   Trying 10.111.222.70...
* TCP_NODELAY set
* Connected to my-nginx-hello-world (10.111.222.70) port 80 (#0)
> GET / HTTP/1.1
> Host: my-nginx-hello-world
> User-Agent: curl/7.61.1
> Accept: */*
>
< HTTP/1.1 200 OK
< Server: nginx/1.14.2
< Date: Sun, 23 Dec 2018 03:45:31 GMT
< Content-Type: text/html
< Content-Length: 612
< Last-Modified: Tue, 04 Dec 2018 14:44:49 GMT
< Connection: keep-alive
< ETag: "5c0692e1-264"
< Accept-Ranges: bytes
<
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
* Connection #0 to host my-nginx-hello-world left intact
```
And voila we see our nginx deployed there and accessible via service name to our other pods (this is fantastic for microservices).
<br />

Our current deployment can be checked like this:
```elixir
$ helm ls
NAME            REVISION        UPDATED                         STATUS          CHART                   APP VERSION     NAMESPACE
my-nginx        1               Sun Dec 23 00:30:11 2018        DEPLOYED        hello-world-0.1.0       1.0             default
```
<br />

The last example would be to upgrade our deployment, lets change the `tag` in the `values.yaml` file from `stable` to `mainline` and update also the metadata file (`Chart.yaml`) to let Helm know that this is a new version of our chart.
```elixir
 $ helm upgrade my-nginx . -f values.yaml
Release "my-nginx" has been upgraded. Happy Helming!
LAST DEPLOYED: Sun Dec 23 00:55:22 2018
NAMESPACE: default
STATUS: DEPLOYED

RESOURCES:
==> v1/Pod(related)
NAME                                   READY  STATUS             RESTARTS  AGE
my-nginx-hello-world-6f948db8d5-s76zl  1/1    Running            0         25m
my-nginx-hello-world-c5cdcc95c-shgc6   0/1    ContainerCreating  0         0s

==> v1/Service

NAME                  AGE
my-nginx-hello-world  25m

==> v1beta2/Deployment
my-nginx-hello-world  25m


NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/name=hello-world,app.kubernetes.io/instance=my-nginx" -o jsonpath="{.items[0].metadata.name}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl port-forward $POD_NAME 8080:80
```
Note that I always specify the -f values.yaml just for explicitness.
<br />

It seems that our upgrade went well, let's see what Helm sees
```elixir
$ helm ls
NAME            REVISION        UPDATED                         STATUS          CHART                   APP VERSION     NAMESPACE
my-nginx        2               Sun Dec 23 00:55:22 2018        DEPLOYED        hello-world-0.1.1       1.0             default
```
<br />

But before we go let's validate that it did deployed the nginx version that we wanted to have:
```elixir
$ kubectl exec my-nginx-hello-world-c5cdcc95c-shgc6 -- /usr/sbin/nginx -v
nginx version: nginx/1.15.7
```
<br />
At the moment of this writing mainline is 1.15.7, we could rollback to the previous version by doing:
```elixir
$ helm rollback my-nginx 1
Rollback was a success! Happy Helming!
```
Basically this command needs a deployment name `my-nginx` and the revision number to rollback to in this case `1`.
<br />

Let's check the versions again:
```elixir
$ kubectl exec my-nginx-hello-world-6f948db8d5-bsml2 -- /usr/sbin/nginx -v
nginx version: nginx/1.14.2
```
<br />

Let's clean up:
```elixir
$ helm del --purge my-nginx
release "my-nginx" deleted
```
<br />

If you need to see what will be sent to the kubernetes API then you can use the following command (sometimes it's really useful for debugging or to inject a sidecar using pipes):
```elixir
$ helm template . -name my-nginx -f values.yaml
# Source: hello-world/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ame-hello-world
```
<br />

And that folks is all I have for now, be sure to check own [Helm Documentation](https://docs.helm.sh/) and `helm help` to know more about what helm can do to help you deploy your applications to any kubernetes cluster.
<br />

### Don't Repeat Yourself
DRY is a good design goal and part of the art of a good template is knowing when to add a new template and when to update an existing one. While you're figuring that out, accept that you'll be doing some refactoring. Helm and go makes that easy and fast.

### Upcoming topics
The following posts will be about package managers, development deployment tools, etc. It's hard to put all the tools in a category, but they are trying to solve similar problems in different ways, and we will be exploring the ones that seem more promising to me, if you would like me to cover any other tool/project/whatever, just send me a message :)

* [Expand on helm, search and install community charts](/blog/deploying_my_apps_with_helm).
* [Getting started with Ksonnet and friends](/blog/getting_started_with_ksonnet)
* [Getting started with Skaffold](/blog/getting_started_with_skaffold).
* [Getting started with Gitkube](/blog/getting_started_with_gitkube).
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Primeros pasos con helm",
  author: "Gabriel Garrido",
  description: "En este tutorial vamos a ver como crear un paquete de Helm...",
  tags: ~w(kubernetes helm),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### **Introduccion**

En este tutorial vamos a ver como usar [Helm](https://helm.sh/), el cluster de despliegue sera [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube) si preferis kind or cualquier otro cluster deberia funcionar de la misma manera:
<br />

Creando el [chart](https://helm.sh/es/docs/topics/charts/):
```elixir
helm create hello-world
```
Siempre hay que tener en cuenta las restricciones de [DNS](https://man7.org/linux/man-pages/man7/hostname.7.html) a la hora de elegir nombres, ya que esto puede traer problemas
despues.
<br />

Inspeccionemos el contenido, como podemos ver son recursos de kubernetes similar a los templates de go:
```elixir
$ cd hello-world

charts       <--- Dependencies, charts that your chart depends on.
Chart.yaml   <--- Metadata mostly, defines the version of your chart, etc.
templates    <--- Here is where the magic happens.
values.yaml  <--- Default values file (this is used to replace in the templates at runtime)
```
Nota: este link explica lo basico de manejo de [dependencias](https://docs.helm.sh/developing_charts/#managing-dependencies-manually-via-the-charts-directory), tu chart puede tener varias dependencias, solo tienes que listarlas como dependencias.
<br />

El archivo `values.yaml` por defecto se ve asi:
```elixir
replicaCount: 1

image:
  repository: nginx
  tag: stable
  pullPolicy: IfNotPresent

nameOverride: ""
fullnameOverride: ""

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  annotations: {}
    # kubernetes.io/ingress.class: nginx
    # kubernetes.io/tls-acme: "true"
  path: /
  hosts:
    - chart-example.local
  tls: []
  #  - secretName: chart-example-tls
  #    hosts:
  #      - chart-example.local

resources: {}
nodeSelector: {}
tolerations: []
affinity: {}
```
<br />

El proximo paso es revisar la carpeta `templates`:
```elixir
deployment.yaml  <--- Recurso deployment estandar de kubernetes con variables de go templates.
_helpers.tpl     <--- En este archivo se definen funciones y variables comunes.
ingress.yaml     <--- Recurso ingress.
NOTES.txt        <--- Este archivo se usa para mostrar las notas una vez que termino el despliegue del chart.
service.yaml     <--- Recurso service de kubernetes o balanceador de carga virtual interno.
```
Go [templates](https://blog.gopheracademy.com/advent-2017/using-go-templates/) basico, si necesitas refrescar go templates, siempre se puede ir a la [documentacion](https://helm.sh/docs/chart_best_practices/templates/).

<br />
Revisemos el archivo [deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/):
```elixir
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  name: {{ include "hello-world.fullname" . }}
  labels:
    app.kubernetes.io/name: {{ include "hello-world.name" . }}
    helm.sh/chart: {{ include "hello-world.chart" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ include "hello-world.name" . }}
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ include "hello-world.name" . }}
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /
              port: http
          readinessProbe:
            httpGet:
              path: /
              port: http
          resources:
{{ toYaml .Values.resources | indent 12 }}
    {{- with .Values.nodeSelector }}
      nodeSelector:
{{ toYaml . | indent 8 }}
    {{- end }}
    {{- with .Values.affinity }}
      affinity:
{{ toYaml . | indent 8 }}
    {{- end }}
    {{- with .Values.tolerations }}
      tolerations:
{{ toYaml . | indent 8 }}
    {{- end }}
```
La mayoria de los campos se reemplazan con lo que pasemos via `values.yaml` esto se pasa via `.Values` a menos que uses
un helper o variable extra.
<br />

Sigamos con el archivo [service](https://kubernetes.io/docs/concepts/services-networking/service/):
```elixir
apiVersion: v1
kind: Service
metadata:
  name: {{ include "hello-world.fullname" . }}
  labels:
    app.kubernetes.io/name: {{ include "hello-world.name" . }}
    helm.sh/chart: {{ include "hello-world.chart" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: {{ include "hello-world.name" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
```

<br />
Luego el archivo [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/):
```elixir
{{- if .Values.ingress.enabled -}}
{{- $fullName := include "hello-world.fullname" . -}}
{{- $ingressPath := .Values.ingress.path -}}
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: {{ $fullName }}
  labels:
    app.kubernetes.io/name: {{ include "hello-world.name" . }}
    helm.sh/chart: {{ include "hello-world.chart" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.ingress.annotations }}
  annotations:
{{ toYaml . | indent 4 }}
{{- end }}
spec:
{{- if .Values.ingress.tls }}
  tls:
  {{- range .Values.ingress.tls }}
    - hosts:
      {{- range .hosts }}
        - {{ . | quote }}
      {{- end }}
      secretName: {{ .secretName }}
  {{- end }}
{{- end }}
  rules:
  {{- range .Values.ingress.hosts }}
    - host: {{ . | quote }}
      http:
        paths:
          - path: {{ $ingressPath }}
            backend:
              serviceName: {{ $fullName }}
              servicePort: http
  {{- end }}
{{- end }}
```
Este es probablemente el archivo mas interesante por que hace uso de variables locales, tambien itera sobre `hosts`.
<br />

Desplegando nuestro chart:
```elixir
$ helm install --name my-nginx -f values.yaml .
NAME:   my-nginx
LAST DEPLOYED: Sun Dec 23 00:30:11 2018
NAMESPACE: default
STATUS: DEPLOYED

RESOURCES:
==> v1/Service
NAME                  AGE
my-nginx-hello-world  0s

==> v1beta2/Deployment
my-nginx-hello-world  0s

==> v1/Pod(related)

NAME                                   READY  STATUS   RESTARTS  AGE
my-nginx-hello-world-6f948db8d5-s76zl  0/1    Pending  0         0s

NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/name=hello-world,app.kubernetes.io/instance=my-nginx" -o jsonpath="{.items[0].metadata.name}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl port-forward $POD_NAME 8080:80
```
Nuestro despliegue parece exitoso, ya que vemos el pod con estado Pending inmediatamente.
<br />

Revisando el servicio:
```elixir
$ kubectl get services
NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes             ClusterIP   10.96.0.1       <none>        443/TCP   1h
my-nginx-hello-world   ClusterIP   10.111.222.70   <none>        80/TCP    5m
```

<br />
Podemos probar desde otro pod de manera interactiva si todo funciona correctamente:
```elixir
$ kubectl run -i --tty alpine --image=alpine -- sh
If you don't see a command prompt, try pressing enter.

/ # apk add curl
fetch http://dl-cdn.alpinelinux.org/alpine/v3.8/main/x86_64/APKINDEX.tar.gz
fetch http://dl-cdn.alpinelinux.org/alpine/v3.8/community/x86_64/APKINDEX.tar.gz
(1/5) Installing ca-certificates (20171114-r3)
(2/5) Installing nghttp2-libs (1.32.0-r0)
(3/5) Installing libssh2 (1.8.0-r3)
(4/5) Installing libcurl (7.61.1-r1)
(5/5) Installing curl (7.61.1-r1)
Executing busybox-1.28.4-r2.trigger
Executing ca-certificates-20171114-r3.trigger
OK: 6 MiB in 18 packages

/ # curl -v my-nginx-hello-world
* Rebuilt URL to: my-nginx-hello-world/
*   Trying 10.111.222.70...
* TCP_NODELAY set
* Connected to my-nginx-hello-world (10.111.222.70) port 80 (#0)
> GET / HTTP/1.1
> Host: my-nginx-hello-world
> User-Agent: curl/7.61.1
> Accept: */*
>
< HTTP/1.1 200 OK
< Server: nginx/1.14.2
< Date: Sun, 23 Dec 2018 03:45:31 GMT
< Content-Type: text/html
< Content-Length: 612
< Last-Modified: Tue, 04 Dec 2018 14:44:49 GMT
< Connection: keep-alive
< ETag: "5c0692e1-264"
< Accept-Ranges: bytes
<
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
* Connection #0 to host my-nginx-hello-world left intact
```
y voila, como podemos ver nuestro chart de nginx funciona perfectamente.
<br />

Podemos verificar el estado via helm de esta manera:
```elixir
$ helm ls
NAME            REVISION        UPDATED                         STATUS          CHART                   APP VERSION     NAMESPACE
my-nginx        1               Sun Dec 23 00:30:11 2018        DEPLOYED        hello-world-0.1.0       1.0             default
```
<br />

Actualizemos nuestro despliegue cambiando el `tag` en el archivo `values.yaml` de `stable` a `mainline` y tambien actualizemos la metadata en `Chart.yaml` para mantener la version de nuestro chart en buenas condiciones.
```elixir
 $ helm upgrade my-nginx . -f values.yaml
Release "my-nginx" has been upgraded. Happy Helming!
LAST DEPLOYED: Sun Dec 23 00:55:22 2018
NAMESPACE: default
STATUS: DEPLOYED

RESOURCES:
==> v1/Pod(related)
NAME                                   READY  STATUS             RESTARTS  AGE
my-nginx-hello-world-6f948db8d5-s76zl  1/1    Running            0         25m
my-nginx-hello-world-c5cdcc95c-shgc6   0/1    ContainerCreating  0         0s

==> v1/Service

NAME                  AGE
my-nginx-hello-world  25m

==> v1beta2/Deployment
my-nginx-hello-world  25m


NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/name=hello-world,app.kubernetes.io/instance=my-nginx" -o jsonpath="{.items[0].metadata.name}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl port-forward $POD_NAME 8080:80
```
<br />

Parece que todo salio bien, como podemos ver cambio la revision y la version del chart
```elixir
$ helm ls
NAME            REVISION        UPDATED                         STATUS          CHART                   APP VERSION     NAMESPACE
my-nginx        2               Sun Dec 23 00:55:22 2018        DEPLOYED        hello-world-0.1.1       1.0             default
```
<br />

Ahora verifiquemos que la version de nginx es la que nosotros especificamos:
```elixir
$ kubectl exec my-nginx-hello-world-c5cdcc95c-shgc6 -- /usr/sbin/nginx -v
nginx version: nginx/1.15.7
```
<br />
al momento de escribir esto la version mainline es 1.15.7, podemos hacer "rollback" si algo no salio bien con helm de
esta manera:
```elixir
$ helm rollback my-nginx 1
Rollback was a success! Happy Helming!
```
Hay varias formas de hacer rollback, en este caso para nuestro chart `my-nginx` especificamos la revision a la que queremos hacer "rollback" y voila.
<br />

Revisemos la version de nginx de nuevo:
```elixir
$ kubectl exec my-nginx-hello-world-6f948db8d5-bsml2 -- /usr/sbin/nginx -v
nginx version: nginx/1.14.2
```
<br />

Siempre es una buena idea limpiar todo cuando terminamos de probar algo:
```elixir
$ helm del --purge my-nginx
release "my-nginx" deleted
```
<br />

Si necesitas depurar o ver los templates a medida que vas trabajando en ellos podes hacer lo siguiente:
```elixir
$ helm template . -n name -f values.yaml
# Source: hello-world/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: name-hello-world
```
<br />

Y eso es todo por hoy, ante cualquier duda deja un comentario o revisa la [documentacion](https://docs.helm.sh/) y el comando `helm help`.
<br />

### DRY: Don't Repeat Yourself
Lo bueno de usar templates es que podemos ahorrar mucho tiempo y a la vez mantener todo ordenado y sin mucha repeticion. 

### Upcoming topics
Algunos articulos que te pueden interesar:

* [Expand on helm, search and install community charts](/blog/deploying_my_apps_with_helm).
* [Getting started with Ksonnet and friends](/blog/getting_started_with_ksonnet)
* [Getting started with Skaffold](/blog/getting_started_with_skaffold).
* [Getting started with Gitkube](/blog/getting_started_with_gitkube).

<br />

### Errata
Si ves algun error por favor enviame un mensaje para poder corregirlo.

<br />
