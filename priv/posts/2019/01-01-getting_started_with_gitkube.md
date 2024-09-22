%{
  title: "Getting started with gitkube",
  author: "Gabriel Garrido",
  description: "Exploring ksonnet with an echo bot made in Golang...",
  tags: ~w(git gitkube kubernetes cicd),
  published: true,
  image: "logo.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

### **Gitkube**

This time we will see how to get started with [Gitkube](https://gitkube.sh/), it's a young project but it seems to work fine and it has an interesting approach compared to other alternatives, since it only relies on git and kubectl, other than that it's just a [CRD](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) and a controller, so you end up with 2 pods in kube-system one for the controller and the other for gitkubed, gitkubed is in charge of cloning your repos and also build the docker images, it seems that the idea behind gitkube is for the daily use in a dev/test environment where you need to try your changes quickly and without hassle. You can find more [examples here](https://github.com/hasura/gitkube-example), also be sure to check their page and documentation if you like it or want to learn more.
<br />

In the examples I will be using [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube) or you can [check out this repo](https://github.com/kainlite/kainlite.github.io) that has a good overview of minikube, once installed and started (`minikube start`) that command will download and configure the local environment, if you have been following the previous posts you already have minikube installed and working, *but in this post be sure to use _minikube tunnel_* if you configure gitkube with a load balancer (or if you configure any service type as load balancer):
<br />

### Let's get started
We're going to deploy or re-deploy our echo bot one more time but this time using gitkube.
You can find the chat bot: [article here](/blog/go-echobot), and the repo: [here](https://github.com/kainlite/echobot/tree/gitkube)
<br />

First of all we need to install the gitkube binary in our machine and then the CRD in our kubernetes cluster:
```elixir
$ kubectl create -f https://storage.googleapis.com/gitkube/gitkube-setup-stable.yaml
customresourcedefinition.apiextensions.k8s.io "remotes.gitkube.sh" created
serviceaccount "gitkube" created
clusterrolebinding.rbac.authorization.k8s.io "gitkube" created
configmap "gitkube-ci-conf" created
deployment.extensions "gitkubed" created
deployment.extensions "gitkube-controller" created

$ kubectl --namespace kube-system expose deployment gitkubed --type=LoadBalancer --name=gitkubed
service "gitkubed" exposed
```
Note that there are 2 ways to install gitkube into our cluster, using the manifests as displayed there or using the gitkube binary and doing `gitkube install`.
<br />

To install the gitkube binary, the easiest way is to do:
```elixir
curl https://raw.githubusercontent.com/hasura/gitkube/master/gimme.sh | sudo bash
```
This will download and copy the binary into: `/usr/local/bin`, as a general rule I recommend reading whatever you are going to pipe into bash in your terminal to avoid potential dangers of _the internet_.

<br />
Then we need to generate (and then create it in the cluster) a file called `remote.yaml` (or any name you like), it's necessary in order to tell gitkube how to deploy our application once we `git push` it:
```elixir
$ gitkube remote generate -f remote.yaml
Remote name: minikube
namespace: default
SSH public key file: ~/.ssh/id_rsa.pub
Initialisation: K8S YAML Manifests
Manifests/Chart directory: Enter
Choose docker registry: docker.io/kainlite
Deployment name: echobot
Container name: echobot
Dockerfile path: Dockerfile
Build context path: ./
Add another container? [y/N] Enter
Add another deployment? [y/N] Enter
```
And this will yield the following `remote.yaml` file that we then need to create in our cluster as it is a custom resource it might look a bit different from the default kubernetes resources.
<br />

The actual file `remote.yaml`:
```elixir
apiVersion: gitkube.sh/v1alpha1
kind: Remote
metadata:
  creationTimestamp: null
  name: minikube
  namespace: default
spec:
  authorizedKeys:
  - |
    ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA8jvVVtDSVe25p2U2tDGQyVrnv3YcWjJc6AXTUMc0YNi+QDm6s+hMTwkf2wDRD7b6Y3kmgNSqLEE0EEgOkA69c8PgypM7AwbKZ51V9XcdPd7NyLabpomNiftpUwi01DGfBr25lJV9h2MHwsI/6w1izDvQyN7fAl+aTFgx+VGg1p4FygXWeBqm0n0DfHmBI7PDXxGbuFTJHUmRVS+HPd5Bi31S9Kq6eoodBWtV2MlVnZkpF67FWt2Xo2rFKVf4pZR4N1yjZKRsvIaI5i14LvtOoOqNQ+/tPMAFAif3AhldOW06fgnddYGi/iF+CatVttwNDWmClSOek9LO72UzR4s0xQ== gabriel@kainlite
  deployments:
  - containers:
    - dockerfile: Dockerfile
      name: echobot
      path: ./
    name: echobot
  manifests:
    helm: {}
    path: ""
  registry:
    credentials:
      secretKeyRef:
        key: ""
      secretRef: minikube-regsecret
    url: docker.io/kainlite
status:
  remoteUrl: ""
  remoteUrlDesc: ""
```
There are a few details to have in mind here, the _deployment_ name because gitkube expects a deployment to be already present with that name in order to update/upgrade it, the path to the Dockerfile, or helm chart, credentials for the registry if any, I'm using a public image, so we don't need any of that. The _wizard_ will let you choose and customize a few options for your deployment.
<br />

The last step would be to finally create the resource:
```elixir
$ gitkube remote create -f remote.yaml
INFO[0000] remote minikube created
INFO[0000] waiting for remote url
INFO[0000] remote url: ssh://default-minikube@10.98.213.202/~/git/default-minikube

  # add the remote to your git repo and push:
  git remote add minikube ssh://default-minikube@10.98.213.202/~/git/default-minikube
  git push minikube master
```
<br />

After adding the new remote called _minikube_  we have everything ready to go, so let's test it and see what happens:
```elixir
$ git push minikube master
Enumerating objects: 10, done.
Counting objects: 100% (10/10), done.
Delta compression using up to 8 threads
Compressing objects: 100% (10/10), done.
Writing objects: 100% (10/10), 1.92 KiB | 1.92 MiB/s, done.
Total 10 (delta 2), reused 0 (delta 0)
remote: Gitkube build system : Tue Jan  1 23:50:58 UTC 2019: Initialising
remote:
remote: Creating the build directory
remote: Checking out 'master:a0265bc5d0229dce0cffc985ca22ebe28532ee95' to '/home/default-minikube/build/default-minikube'
remote:
remote: 1 deployment(s) found in this repo
remote: Trying to build them...
remote:
remote: Building Docker image for : echobot
remote:
remote: Building Docker image : docker.io/kainlite/default-minikube-default.echobot-echobot:a0265bc5d0229dce0cffc985ca22ebe28532ee95
remote: Sending build context to Docker daemon   7.68kB
remote: Step 1/12 : FROM golang:1.11.2-alpine as builder
remote:  ---> 57915f96905a
remote: Step 2/12 : WORKDIR /app
remote:  ---> Using cache
remote:  ---> 997342e65c61
remote: Step 3/12 : RUN adduser -D -g 'app' app &&     chown -R app:app /app &&     apk add git && apk add gcc musl-dev
remote:  ---> Using cache
remote:  ---> 7c6d8b9d1137
remote: Step 4/12 : ADD . /app/
remote:  ---> Using cache
remote:  ---> ca751c2678c4
remote: Step 5/12 : RUN go get -d -v ./... && go build -o main . && chown -R app:app /app /home/app
remote:  ---> Using cache
remote:  ---> 16e44978b140
remote: Step 6/12 : FROM golang:1.11.2-alpine
remote:  ---> 57915f96905a
remote: Step 7/12 : WORKDIR /app
remote:  ---> Using cache
remote:  ---> 997342e65c61
remote: Step 8/12 : RUN adduser -D -g 'app' app &&     chown -R app:app /app
remote:  ---> Using cache
remote:  ---> 55f48da0f9ac
remote: Step 9/12 : COPY --from=builder --chown=app /app/health_check.sh /app/health_check.sh
remote:  ---> Using cache
remote:  ---> 139250fd6c77
remote: Step 10/12 : COPY --from=builder --chown=app /app/main /app/main
remote:  ---> Using cache
remote:  ---> 2f1eb9f16e9f
remote: Step 11/12 : USER app
remote:  ---> Using cache
remote:  ---> a72f27dccff2
remote: Step 12/12 : CMD ["/app/main"]
remote:  ---> Using cache
remote:  ---> 034275449e08
remote: Successfully built 034275449e08
remote: Successfully tagged kainlite/default-minikube-default.echobot-echobot:a0265bc5d0229dce0cffc985ca22ebe28532ee95
remote: pushing docker.io/kainlite/default-minikube-default.echobot-echobot:a0265bc5d0229dce0cffc985ca22ebe28532ee95 to registry
remote: The push refers to repository [docker.io/kainlite/default-minikube-default.echobot-echobot]
remote: bba61bf193fe: Preparing
remote: 3f0355bbea40: Preparing
remote: 2ebcdc9e5e8f: Preparing
remote: 6f1324339fd4: Preparing
remote: 93391cb9fd4b: Preparing
remote: cb9d0f9550f6: Preparing
remote: 93448d8c2605: Preparing
remote: c54f8a17910a: Preparing
remote: df64d3292fd6: Preparing
remote: cb9d0f9550f6: Waiting
remote: 93448d8c2605: Waiting
remote: c54f8a17910a: Waiting
remote: df64d3292fd6: Waiting
remote: 2ebcdc9e5e8f: Layer already exists
remote: 6f1324339fd4: Layer already exists
remote: 3f0355bbea40: Layer already exists
remote: bba61bf193fe: Layer already exists
remote: 93391cb9fd4b: Layer already exists
remote: 93448d8c2605: Layer already exists
remote: cb9d0f9550f6: Layer already exists
remote: df64d3292fd6: Layer already exists
remote: c54f8a17910a: Layer already exists
remote: a0265bc5d0229dce0cffc985ca22ebe28532ee95: digest: sha256:3046c989fe1b1c4f700aaad875658c73ef571028f731546df38fb404ac22a9c9 size: 2198
remote:
remote: Updating Kubernetes deployment: echobot
remote: deployment "echobot" image updated
remote: deployment "echobot" successfully rolled out
remote: NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
remote: echobot   1         1         1            1           31s
remote:
remote: Removing build directory
remote:
remote: Gitkube build system : Tue Jan  1 23:51:16 UTC 2019: Finished build
remote:
remote:
To ssh://10.98.213.202/~/git/default-minikube
 * [new branch]      master -> master
```
Quite a lot happened there, first of all gitkubed checked out the commit from the branch or HEAD that we pushed to `/home/default-minikube/build/default-minikube` and then started building and tagged the docker image with the corresponding SHA, after that it pushed the image to [docker hub](https://cloud.docker.com/u/kainlite/repository/docker/kainlite/default-minikube-default.echobot-echobot) and then updated the deployment that we already had in there for the echo bot.
<br />

The last step would be to verify that the pod was actually updated, so we can inspect the pod configuration with `kubectl describe pod echobot-654cdbfb99-g4bwv`:
```elixir
 $ kubectl describe pod echobot-654cdbfb99-g4bwv
Name:               echobot-654cdbfb99-g4bwv
Namespace:          default
Priority:           0
PriorityClassName:  <none>
Node:               minikube/10.0.2.15
Start Time:         Tue, 01 Jan 2019 20:51:10 -0300
Labels:             app=echobot
                    pod-template-hash=654cdbfb99
Annotations:        <none>
Status:             Running
IP:                 172.17.0.9
Controlled By:      ReplicaSet/echobot-654cdbfb99
Containers:
  echobot:
    Container ID:   docker://fe26ba9be6e2840c0d43a4fcbb4d79af38a00aa3a16411dee5e4af3823d44664
    Image:          docker.io/kainlite/default-minikube-default.echobot-echobot:a0265bc5d0229dce0cffc985ca22ebe28532ee95
    Image ID:       docker-pullable://kainlite/default-minikube-default.echobot-echobot@sha256:3046c989fe1b1c4f700aaad875658c73ef571028f731546df38fb404ac22a9c9
    Port:           <none>
    Host Port:      <none>
    State:          Running
      Started:      Tue, 01 Jan 2019 20:51:11 -0300
    Ready:          True
    Restart Count:  0
    Liveness:       exec [/bin/sh -c /app/health_check.sh] delay=0s timeout=1s period=10s #success=1 #failure=3
    Environment:
      SLACK_API_TOKEN:  really_long_token
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from default-token-ks4jx (ro)
Conditions:
  Type              Status
  Initialized       True
  Ready             True
  ContainersReady   True
  PodScheduled      True
Volumes:
  default-token-ks4jx:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  default-token-ks4jx
    Optional:    false
QoS Class:       BestEffort
Node-Selectors:  <none>
Tolerations:     node.kubernetes.io/not-ready:NoExecute for 300s
                 node.kubernetes.io/unreachable:NoExecute for 300s
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  39m   default-scheduler  Successfully assigned default/echobot-654cdbfb99-g4bwv to minikube
  Normal  Pulled     39m   kubelet, minikube  Container image "docker.io/kainlite/default-minikube-default.echobot-echobot:a0265bc5d0229dce0cffc985ca22ebe28532ee95" already present on machine
  Normal  Created    39m   kubelet, minikube  Created container
  Normal  Started    39m   kubelet, minikube  Started container
```
As we can see the image is the one that got built from our `git push` and everything is working as expected.
<br />

And that's it for now, I think this tool has a lot of potential, it's simple, nice and fast.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Primeros pasos con gitkube",
  author: "Gabriel Garrido",
  description: "Seguimos explorando ksonnet y gitkube con un bot eco hecho en Go...",
  tags: ~w(git gitkube kubernetes cicd),
  published: true,
  image: "logo.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### **Gitkube**

Esta vez veremos cómo comenzar con [Gitkube](https://gitkube.sh/). Es un proyecto joven, pero parece funcionar bien y tiene un enfoque interesante en comparación con otras alternativas, ya que solo depende de git y kubectl. Aparte de eso, es solo un [CRD](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) y un controlador, por lo que terminas con 2 pods en kube-system: uno para el controlador y otro para gitkubed. Gitkubed se encarga de clonar tus repositorios y también de construir las imágenes de Docker. Parece que la idea detrás de Gitkube es para el uso diario en un entorno de desarrollo/pruebas donde necesitas probar tus cambios rápidamente y sin complicaciones. Puedes encontrar más [ejemplos aquí](https://github.com/hasura/gitkube-example). Asegúrate también de revisar su página y documentación si te gusta o quieres aprender más.
<br />

En los ejemplos estaré usando [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube), o puedes [consultar este repositorio](https://github.com/kainlite/kainlite.github.io) que tiene una buena visión general de minikube. Una vez instalado y arrancado (`minikube start`), ese comando descargará y configurará el entorno local. Si has estado siguiendo las publicaciones anteriores, ya tienes minikube instalado y funcionando, *pero en este post asegúrate de usar _minikube tunnel_* si configuras Gitkube con un balanceador de carga (o si configuras cualquier servicio de tipo balanceador de carga):
<br />

### Empecemos

Vamos a desplegar o re-desplegar nuestro bot de eco una vez más, pero esta vez usando Gitkube.
Puedes encontrar el chat bot: [artículo aquí](/blog/go-echobot), y el repositorio: [aquí](https://github.com/kainlite/echobot/tree/gitkube)
<br />

En primer lugar, necesitamos instalar el binario de Gitkube en nuestra máquina y luego el CRD en nuestro clúster de Kubernetes:
```elixir
$ kubectl create -f https://storage.googleapis.com/gitkube/gitkube-setup-stable.yaml
customresourcedefinition.apiextensions.k8s.io "remotes.gitkube.sh" created
serviceaccount "gitkube" created
clusterrolebinding.rbac.authorization.k8s.io "gitkube" created
configmap "gitkube-ci-conf" created
deployment.extensions "gitkubed" created
deployment.extensions "gitkube-controller" created

$ kubectl --namespace kube-system expose deployment gitkubed --type=LoadBalancer --name=gitkubed
service "gitkubed" exposed
```
Nota que hay 2 formas de instalar Gitkube en nuestro clúster: usando los manifiestos como se muestra ahí o usando el binario de Gitkube y ejecutando `gitkube install`.
<br />

Para instalar el binario de Gitkube, la forma más sencilla es hacer:
```elixir
curl https://raw.githubusercontent.com/hasura/gitkube/master/gimme.sh | sudo bash
```
Esto descargará y copiará el binario en: `/usr/local/bin`. Como regla general, recomiendo leer lo que vas a canalizar a bash en tu terminal para evitar posibles peligros de _internet_.

<br />
Luego, necesitamos generar (y luego crearlo en el clúster) un archivo llamado `remote.yaml` (o cualquier nombre que prefieras). Es necesario para indicarle a Gitkube cómo desplegar nuestra aplicación una vez que hagamos `git push`:
```elixir
$ gitkube remote generate -f remote.yaml
Remote name: minikube
namespace: default
SSH public key file: ~/.ssh/id_rsa.pub
Initialisation: K8S YAML Manifests
Manifests/Chart directory: Enter
Choose docker registry: docker.io/kainlite
Deployment name: echobot
Container name: echobot
Dockerfile path: Dockerfile
Build context path: ./
Add another container? [y/N] Enter
Add another deployment? [y/N] Enter
```
Y esto generará el siguiente archivo `remote.yaml` que luego necesitamos crear en nuestro clúster, ya que es un recurso personalizado y puede verse un poco diferente de los recursos predeterminados de Kubernetes.
<br />

El archivo real `remote.yaml`:
```elixir
apiVersion: gitkube.sh/v1alpha1
kind: Remote
metadata:
  creationTimestamp: null
  name: minikube
  namespace: default
spec:
  authorizedKeys:
  - |
    ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA8jvVVtDSVe25p2U2tDGQyVrnv3YcWjJc6AXTUMc0YNi+QDm6s+hMTwkf2wDRD7b6Y3kmgNSqLEE0EEgOkA69c8PgypM7AwbKZ51V9XcdPd7NyLabpomNiftpUwi01DGfBr25lJV9h2MHwsI/6w1izDvQyN7fAl+aTFgx+VGg1p4FygXWeBqm0n0DfHmBI7PDXxGbuFTJHUmRVS+HPd5Bi31S9Kq6eoodBWtV2MlVnZkpF67FWt2Xo2rFKVf4pZR4N1yjZKRsvIaI5i14LvtOoOqNQ+/tPMAFAif3AhldOW06fgnddYGi/iF+CatVttwNDWmClSOek9LO72UzR4s0xQ== gabriel@kainlite
  deployments:
  - containers:
    - dockerfile: Dockerfile
      name: echobot
      path: ./
    name: echobot
  manifests:
    helm: {}
    path: ""
  registry:
    credentials:
      secretKeyRef:
        key: ""
      secretRef: minikube-regsecret
    url: docker.io/kainlite
status:
  remoteUrl: ""
  remoteUrlDesc: ""
```
Hay algunos detalles a tener en cuenta aquí: el nombre del _deployment_ porque Gitkube espera que ya exista un deployment con ese nombre para poder actualizarlo/mejorarlo; la ruta al Dockerfile o al chart de Helm; credenciales para el registro si las hay. Estoy usando una imagen pública, así que no necesitamos nada de eso. El _asistente_ te permitirá elegir y personalizar algunas opciones para tu despliegue.
<br />

El último paso sería finalmente crear el recurso:
```elixir
$ gitkube remote create -f remote.yaml
INFO[0000] remote minikube created
INFO[0000] waiting for remote url
INFO[0000] remote url: ssh://default-minikube@10.98.213.202/~/git/default-minikube

  # añade el remoto a tu repositorio git y haz push:
  git remote add minikube ssh://default-minikube@10.98.213.202/~/git/default-minikube
  git push minikube master
```
<br />

Después de agregar el nuevo remoto llamado _minikube_, tenemos todo listo para comenzar, así que probémoslo y veamos qué sucede:
```elixir
$ git push minikube master
Enumerating objects: 10, done.
Counting objects: 100% (10/10), done.
Delta compression using up to 8 threads
Compressing objects: 100% (10/10), done.
Writing objects: 100% (10/10), 1.92 KiB | 1.92 MiB/s, done.
Total 10 (delta 2), reused 0 (delta 0)
remote: Gitkube build system : Tue Jan  1 23:50:58 UTC 2019: Initialising
remote:
remote: Creating the build directory
remote: Checking out 'master:a0265bc5d0229dce0cffc985ca22ebe28532ee95' to '/home/default-minikube/build/default-minikube'
remote:
remote: 1 deployment(s) found in this repo
remote: Trying to build them...
remote:
remote: Building Docker image for : echobot
remote:
remote: Building Docker image : docker.io/kainlite/default-minikube-default.echobot-echobot:a0265bc5d0229dce0cffc985ca22ebe28532ee95
remote: Sending build context to Docker daemon   7.68kB
remote: Step 1/12 : FROM golang:1.11.2-alpine as builder
remote:  ---> 57915f96905a
remote: Step 2/12 : WORKDIR /app
remote:  ---> Using cache
remote:  ---> 997342e65c61
remote: Step 3/12 : RUN adduser -D -g 'app' app &&     chown -R app:app /app &&     apk add git && apk add gcc musl-dev
remote:  ---> Using cache
remote:  ---> 7c6d8b9d1137
remote: Step 4/12 : ADD . /app/
remote:  ---> Using cache
remote:  ---> ca751c2678c4
remote: Step 5/12 : RUN go get -d -v ./... && go build -o main . && chown -R app:app /app /home/app
remote:  ---> Using cache
remote:  ---> 16e44978b140
remote: Step 6/12 : FROM golang:1.11.2-alpine
remote:  ---> 57915f96905a
remote: Step 7/12 : WORKDIR /app
remote:  ---> Using cache
remote:  ---> 997342e65c61
remote: Step 8/12 : RUN adduser -D -g 'app' app &&     chown -R app:app /app
remote:  ---> Using cache
remote:  ---> 55f48da0f9ac
remote: Step 9/12 : COPY --from=builder --chown=app /app/health_check.sh /app/health_check.sh
remote:  ---> Using cache
remote:  ---> 139250fd6c77
remote: Step 10/12 : COPY --from=builder --chown=app /app/main /app/main
remote:  ---> Using cache
remote:  ---> 2f1eb9f16e9f
remote: Step 11/12 : USER app
remote:  ---> Using cache
remote:  ---> a72f27dccff2
remote: Step 12/12 : CMD ["/app/main"]
remote:  ---> Using cache
remote:  ---> 034275449e08
remote: Successfully built 034275449e08
remote: Successfully tagged kainlite/default-minikube-default.echobot-echobot:a0265bc5d0229dce0cffc985ca22ebe28532ee95
remote: pushing docker.io/kainlite/default-minikube-default.echobot-echobot:a0265bc5d0229dce0cffc985ca22ebe28532ee95 to registry
remote: The push refers to repository [docker.io/kainlite/default-minikube-default.echobot-echobot]
remote: bba61bf193fe: Preparing
remote: 3f0355bbea40: Preparing
remote: 2ebcdc9e5e8f: Preparing
remote: 6f1324339fd4: Preparing
remote: 93391cb9fd4b: Preparing
remote: cb9d0f9550f6: Preparing
remote: 93448d8c2605: Preparing
remote: c54f8a17910a: Preparing
remote: df64d3292fd6: Preparing
remote: cb9d0f9550f6: Waiting
remote: 93448d8c2605: Waiting
remote: c54f8a17910a: Waiting
remote: df64d3292fd6: Waiting
remote: 2ebcdc9e5e8f: Layer already exists
remote: 6f1324339fd4: Layer already exists
remote: 3f0355bbea40: Layer already exists
remote: bba61bf193fe: Layer already exists
remote: 93391cb9fd4b: Layer already exists
remote: 93448d8c2605: Layer already exists
remote: cb9d0f9550f6: Layer already exists
remote: df64d3292fd6: Layer already exists
remote: c54f8a17910a: Layer already exists
remote: a0265bc5d0229dce0cffc985ca22ebe28532ee95: digest: sha256:3046c989fe1b1c4f700aaad875658c73ef571028f731546df38fb404ac22a9c9 size: 2198
remote:
remote: Updating Kubernetes deployment: echobot
remote: deployment "echobot" image updated
remote: deployment "echobot" successfully rolled out
remote: NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
remote: echobot   1         1         1            1           31s
remote:
remote: Removing build directory
remote:
remote: Gitkube build system : Tue Jan  1 23:51:16 UTC 2019: Finished build
remote:
remote:
To ssh://10.98.213.202/~/git/default-minikube
 * [new branch]      master -> master
```
Pasaron muchas cosas allí. En primer lugar, gitkubed revisó el commit de la rama o HEAD que empujamos a `/home/default-minikube/build/default-minikube` y luego comenzó a construir y etiquetó la imagen de Docker con el SHA correspondiente. Después de eso, empujó la imagen a [Docker Hub](https://cloud.docker.com/u/kainlite/repository/docker/kainlite/default-minikube-default.echobot-echobot) y luego actualizó el deployment que ya teníamos allí para el bot de eco.
<br />

El último paso sería verificar que el pod realmente se actualizó, por lo que podemos inspeccionar la configuración del pod con `kubectl describe pod echobot-654cdbfb99-g4bwv`:
```elixir
 $ kubectl describe pod echobot-654cdbfb99-g4bwv
Name:               echobot-654cdbfb99-g4bwv
Namespace:          default
Priority:           0
PriorityClassName:  <none>
Node:               minikube/10.0.2.15
Start Time:         Tue, 01 Jan 2019 20:51:10 -0300
Labels:             app=echobot
                    pod-template-hash=654cdbfb99
Annotations:        <none>
Status:             Running
IP:                 172.17.0.9
Controlled By:      ReplicaSet/echobot-654cdbfb99
Containers:
  echobot:
    Container ID:   docker://fe26ba9be6e2840c0d43a4fcbb4d79af38a00aa3a16411dee5e4af3823d44664
    Image:          docker.io/kainlite/default-minikube-default.echobot-echobot:a0265bc5d0229dce0cffc985ca22ebe28532ee95
    Image ID:       docker-pullable://kainlite/default-minikube-default.echobot-echobot@sha256:3046c989fe1b1c4f700aaad875658c73ef571028f731546df38fb404ac22a9c9
    Port:           <none>
    Host Port:      <none>
    State:          Running
      Started:      Tue, 01 Jan 2019 20:51:11 -0300
    Ready:          True
    Restart Count:  0
    Liveness:       exec [/bin/sh -c /app/health_check.sh] delay=0s timeout=1s period=10s #success=1 #failure=3
    Environment:
      SLACK_API_TOKEN:  really_long_token
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from default-token-ks4jx (ro)
Conditions:
  Type              Status
  Initialized       True
  Ready             True
  ContainersReady   True
  PodScheduled      True
Volumes:
  default-token-ks4jx:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  default-token-ks4jx
    Optional:    false
QoS Class:       BestEffort
Node-Selectors:  <none>
Tolerations:     node.kubernetes.io/not-ready:NoExecute for 300s
                 node.kubernetes.io/unreachable:NoExecute for 300s
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  39m   default-scheduler  Successfully assigned default/echobot-654cdbfb99-g4bwv to minikube
  Normal  Pulled     39m   kubelet, minikube  Container image "docker.io/kainlite/default-minikube-default.echobot-echobot:a0265bc5d0229dce0cffc985ca22ebe28532ee95" already present on machine
  Normal  Created    39m   kubelet, minikube  Created container
  Normal  Started    39m   kubelet, minikube  Started container
```
Como podemos ver, la imagen es la que se construyó a partir de nuestro `git push` y todo está funcionando como se esperaba.
<br />

Y eso es todo por ahora. Creo que esta herramienta tiene mucho potencial; es simple, agradable y rápida.
<br />

### Erratas

Si encuentras algún error o tienes alguna sugerencia, por favor envíame un mensaje para que pueda corregirlo.

<br />
