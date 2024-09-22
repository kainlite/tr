%{
  title: "Gitlab-CI Basics",
  author: "Gabriel Garrido",
  description: "In this article we will continue where we left off the forward project last time, in this article we
  will use gitlab-ci...",
  tags: ~w(kubernetes golang linux kubebuilder cicd),
  published: true,
  image: "gitlab.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![gitlab](/images/gitlab.png){:class="mx-auto"}

##### **Introduction**
In this article we will continue where we left off the [forward](https://github.com/kainlite/forward) project last time, in this article we will use [gitlab-ci](https://gitlab.com) to test, build and push the image of our operator to [dockerhub](https://hub.docker.com/repository/docker/kainlite/forward).
<br />

Gitlab offers a pretty complete solution, but we will only sync our repo from github and set a basic pipeline to test, build and push our docker image to the registry, note that I do not have any kind of affiliation with gitlab, but I like their platform. Also this article demonstrates that you can use github and gitlab in a straight forward manner using the free tier in both sides, we rely in the free shared runners to make our custom CI system.
<br />

If you want to check the previous article [go here](/blog/cloud_native_applications_with_kubebuilder_and_kind_aka_kubernetes_operators), that way you will know what the project is all about.
<br />

##### **Prerequisites**
* [A project in github in this case](https://github.com/kainlite/forward)
* [A gitlab.com account](https://gitlab.com/users/sign_up)
* [A dockerhub account](https://hub.docker.com/u/kainlite)

<br />

##### **Create the project**
Once you have your accounts configured, let's create a project, the page should look something like this
![img](/images/gitlab-1.png){:class="mx-auto"}
We want to create a repo or sync a repo in this case, so we select `Create a project` and continue
<br />

##### **Project type**
In this step we have a few options and since we have our code in Github and we want to work there, we only want to sync it, so we need to choose `CI/CD for external repo`
![img](/images/gitlab-2.png){:class="mx-auto"}
Note that if the repo is public you can fetch/clone using the repo URL, but since I want to check also private repos I went for the github token alternative. Once you hit github it will ask you for the token then it will show you the full list of repos in your account
<br />

##### **Github Token**
I picked to use a personal token to fetch the repos to be able to grab private repos, etc, so you will need to go to your github account, `Settings->Developer settings` and then create a new token or [click here](https://github.com/settings/tokens)
![img](/images/gitlab-3.png){:class="mx-auto"}
<br />

Now you only need to give it access to repo, and hit save or create new personal token
![img](/images/gitlab-4.png){:class="mx-auto"}
Make sure you don't expose or publish that token in any way, otherwise someone could gain access to your account
<br />

##### (Back to gitlab) **Select the repository to sync**
Here we need to select the repo that we want to sync and hit connect, it will automatically fetch everything periodically from github.
![img](/images/gitlab-5.png){:class="mx-auto"}
<br />

##### **Dockerhub token**
Now we will need to create a token for dockerhub so we can push our image from the build runner, go to your dockerhub account and create a token
![img](/images/gitlab-6.png){:class="mx-auto"}
Basically you have to go to `Account settings->Security->New Access Token` or [click here](https://hub.docker.com/settings/security).
<br />

Then we need to save that token as `DOCKERHUB_TOKEN` in this case as an environment variable in the gitlab project, `Settings->CI/CD->Variables`
![img](/images/gitlab-7.png){:class="mx-auto"}
make sure masked is marked but not protected, protected is only used when you want to use that secret in specific branches
<br />

##### **Gitlab-CI config**
After that we only need to add the code to the repo and that will trigger a build, the file needs to be called `.gitlab-ci.yml`
```elixir
image: golang:1.13.7-alpine3.11

stages:
- test
- build

variables:
  PKG_PATH: gitlab.com/kainlite/forward
  IMAGE_NAME: "kainlite/forward"

before_script:
  - apk update && apk add curl make musl-dev gcc build-base
  - BUILD_DIR=$(pwd)
  - export GOPATH=${BUILD_DIR}/_build
  - export PATH=${GOPATH}/bin:${PATH}
  - export PATH=$PATH:/usr/local/bin
  - mkdir -p "${GOPATH}/src/${PKG_PATH}" && cd "${GOPATH}/src/${PKG_PATH}"
  - curl -L https://github.com/kubernetes-sigs/kubebuilder/releases/download/v2.2.0/kubebuilder_2.2.0_linux_amd64.tar.gz > /tmp/kubebuilder.tar.gz
  - tar -zxvf /tmp/kubebuilder.tar.gz
  - chmod +x kubebuilder_2.2.0_linux_amd64/bin/* && mkdir -p /usr/local/kubebuilder && mv kubebuilder_2.2.0_linux_amd64/bin/ /usr/local/kubebuilder/
  - export PATH=$PATH:/usr/local/kubebuilder/bin
  - curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv3.5.4/kustomize_v3.5.4_linux_amd64.tar.gz > /tmp/kustomize.tar.gz
  - tar -zxvf /tmp/kustomize.tar.gz
  - mv kustomize /usr/local/bin
  - curl -L https://github.com/kubernetes-sigs/kind/releases/download/v0.7.0/kind-linux-amd64 > /usr/local/bin/kind
  - chmod +x /usr/local/bin/kind /usr/local/bin/kustomize
  - curl -L https://download.docker.com/linux/static/stable/x86_64/docker-19.03.5.tgz > /tmp/docker.tar.gz
  - tar -xzvf /tmp/docker.tar.gz -C /tmp/
  - chmod +x /tmp/docker/* && cp /tmp/docker/docker* /usr/local/bin && rm -rf /tmp/docker

test:
  stage: test
  script:
    - cd ${BUILD_DIR} && make test
  cache:
    key: "$CI_COMMIT_REF_SLUG"
    paths:
      - _build/pkg

build:
  stage: build
  variables:
    DOCKER_DRIVER: overlay2
    DOCKER_HOST: tcp://docker:2375
  services:
    - docker:dind
  script:
    - cd ${BUILD_DIR}
    - docker login -u "kainlite" -p "${DOCKERHUB_TOKEN}"
    - docker pull "$IMAGE_NAME:${CI_COMMIT_SHA}" || true
    - make docker-build docker-push IMG="${IMAGE_NAME}:${CI_COMMIT_SHA}"
    - docker tag "kainlite/forward:${CI_COMMIT_SHA}" "$IMAGE_NAME:latest"
    - make docker-push IMG="${IMAGE_NAME}:latest"
  cache:
    key: "$CI_COMMIT_REF_SLUG"
    paths:
      - _build/pkg
```
basically we just install everything we need run the tests if everything goes well, then the build and push process. There is a lot of room for improvement in that initial config, but for now we only care in having some sort of CI system
<br />

Then we will see something like this in the `CI/CD->Pipelines` tab, after each commit it will trigger a test, build and push
![img](/images/gitlab-8.png){:class="mx-auto"}
<br />

##### **Checking the results**
And we can validate that the images are in dockerhub
![img](/images/gitlab-9.png){:class="mx-auto"}
<br />

##### **Useful links**
Some useful links:
* [Variables](https://docs.gitlab.com/ee/ci/variables/) and [Predefined variables](https://docs.gitlab.com/ee/ci/variables/predefined_variables.html)
* [Using docker images](https://docs.gitlab.com/ee/ci/docker/using_docker_images.html)
* [Build docker images](https://docs.gitlab.com/ee/ci/docker/using_docker_build.html)

<br />

##### **Closing notes**
I hope you enjoyed it and hope to see you on [twitter](https://twitter.com/kainlite) or [github](https://github.com/kainlite)!
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Primeros pasos con Gitlab-CI",
  author: "Gabriel Garrido",
  description: "Usando gitlab-ci para deployar el proyecto forward...",
  tags: ~w(kubernetes golang linux kubebuilder cicd),
  published: true,
  image: "gitlab.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![gitlab](/images/gitlab.png){:class="mx-auto"}

##### **Introducción**
En este artículo vamos a continuar donde dejamos el proyecto [forward](https://github.com/kainlite/forward) la última vez. En este artículo vamos a usar [gitlab-ci](https://gitlab.com) para testear, construir y empujar la imagen de nuestro operador a [dockerhub](https://hub.docker.com/repository/docker/kainlite/forward).
<br />

Gitlab ofrece una solución bastante completa, pero solo vamos a sincronizar nuestro repo desde github y configurar un pipeline básico para testear, construir y empujar nuestra imagen de docker al registro. Notá que no tengo ninguna afiliación con gitlab, pero me gusta su plataforma. Este artículo también demuestra que podés usar github y gitlab de manera sencilla usando el nivel gratuito en ambos, confiamos en los "shared runners" gratuitos para construir nuestro sistema de CI personalizado.
<br />

Si querés revisar el artículo anterior [andá acá](/blog/cloud_native_applications_with_kubebuilder_and_kind_aka_kubernetes_operators) para saber de qué se trata el proyecto.
<br />

##### **Prerequisitos**
* [Un proyecto en github en este caso](https://github.com/kainlite/forward)
* [Una cuenta en gitlab.com](https://gitlab.com/users/sign_up)
* [Una cuenta en dockerhub](https://hub.docker.com/u/kainlite)

<br />

##### **Crear el proyecto**
Una vez que tengas tus cuentas configuradas, vamos a crear un proyecto. La página debería verse algo así:
![img](/images/gitlab-1.png){:class="mx-auto"}
Queremos crear un repo o sincronizar uno en este caso, así que seleccionamos `Create a project` y continuamos.
<br />

##### **Tipo de proyecto**
En este paso tenemos algunas opciones y como tenemos nuestro código en Github y queremos trabajar ahí, solo queremos sincronizarlo, así que necesitamos elegir `CI/CD for external repo`.
![img](/images/gitlab-2.png){:class="mx-auto"}
Notá que si el repo es público, podés hacer fetch/clone usando la URL del repo, pero como también quiero probar con repos privados, elegí la alternativa del token de github. Una vez que seleccionás github, te pedirá el token y luego te mostrará la lista completa de repos en tu cuenta.
<br />

##### **Token de Github**
Elegí usar un token personal para poder obtener los repos privados, etc., así que tendrás que ir a tu cuenta de github, `Settings->Developer settings` y luego crear un nuevo token o [hacé clic acá](https://github.com/settings/tokens).
![img](/images/gitlab-3.png){:class="mx-auto"}
<br />

Ahora solo necesitás darle acceso a los repos y hacer clic en guardar o crear nuevo token personal.
![img](/images/gitlab-4.png){:class="mx-auto"}
Asegurate de no exponer ni publicar ese token de ninguna manera, de lo contrario alguien podría obtener acceso a tu cuenta.
<br />

##### (Volviendo a gitlab) **Seleccionar el repositorio a sincronizar**
Acá necesitamos seleccionar el repo que queremos sincronizar y hacer clic en conectar, se sincronizará automáticamente todo desde github periódicamente.
![img](/images/gitlab-5.png){:class="mx-auto"}
<br />

##### **Token de Dockerhub**
Ahora necesitaremos crear un token para dockerhub para poder empujar nuestra imagen desde el build runner. Vamos a tu cuenta de dockerhub y creamos un token.
![img](/images/gitlab-6.png){:class="mx-auto"}
Básicamente tenés que ir a `Account settings->Security->New Access Token` o [hacé clic acá](https://hub.docker.com/settings/security).
<br />

Luego necesitamos guardar ese token como `DOCKERHUB_TOKEN`, en este caso, como una variable de entorno en el proyecto de gitlab, `Settings->CI/CD->Variables`.
![img](/images/gitlab-7.png){:class="mx-auto"}
Asegurate de que esté marcado como "masked" pero no como "protected". "Protected" solo se usa cuando querés usar ese secreto en ramas específicas.
<br />

##### **Config de Gitlab-CI**
Después de eso, solo necesitamos agregar el código al repo y eso desencadenará una construcción. El archivo debe llamarse `.gitlab-ci.yml`.
```elixir
image: golang:1.13.7-alpine3.11

stages:
- test
- build

variables:
  PKG_PATH: gitlab.com/kainlite/forward
  IMAGE_NAME: "kainlite/forward"

before_script:
  - apk update && apk add curl make musl-dev gcc build-base
  - BUILD_DIR=$(pwd)
  - export GOPATH=${BUILD_DIR}/_build
  - export PATH=${GOPATH}/bin:${PATH}
  - export PATH=$PATH:/usr/local/bin
  - mkdir -p "${GOPATH}/src/${PKG_PATH}" && cd "${GOPATH}/src/${PKG_PATH}"
  - curl -L https://github.com/kubernetes-sigs/kubebuilder/releases/download/v2.2.0/kubebuilder_2.2.0_linux_amd64.tar.gz > /tmp/kubebuilder.tar.gz
  - tar -zxvf /tmp/kubebuilder.tar.gz
  - chmod +x kubebuilder_2.2.0_linux_amd64/bin/* && mkdir -p /usr/local/kubebuilder && mv kubebuilder_2.2.0_linux_amd64/bin/ /usr/local/kubebuilder/
  - export PATH=$PATH:/usr/local/kubebuilder/bin
  - curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv3.5.4/kustomize_v3.5.4_linux_amd64.tar.gz > /tmp/kustomize.tar.gz
  - tar -zxvf /tmp/kustomize.tar.gz
  - mv kustomize /usr/local/bin
  - curl -L https://github.com/kubernetes-sigs/kind/releases/download/v0.7.0/kind-linux-amd64 > /usr/local/bin/kind
  - chmod +x /usr/local/bin/kind /usr/local/bin/kustomize
  - curl -L https://download.docker.com/linux/static/stable/x86_64/docker-19.03.5.tgz > /tmp/docker.tar.gz
  - tar -xzvf /tmp/docker.tar.gz -C /tmp/
  - chmod +x /tmp/docker/* && cp /tmp/docker/docker* /usr/local/bin && rm -rf /tmp/docker

test:
  stage: test
  script:
    - cd ${BUILD_DIR} && make test
  cache:
    key: "$CI_COMMIT_REF_SLUG"
    paths:
      - _build/pkg

build:
  stage: build
  variables:
    DOCKER_DRIVER: overlay2
    DOCKER_HOST: tcp://docker:2375
  services:
    - docker:dind
  script:
    - cd ${BUILD_DIR}
    - docker login -u "kainlite" -p "${DOCKERHUB_TOKEN}"
    - docker pull "$IMAGE_NAME:${CI_COMMIT_SHA}" || true
    - make docker-build docker-push IMG="${IMAGE_NAME}:${CI_COMMIT_SHA}"
    - docker tag "kainlite/forward:${CI_COMMIT_SHA}" "$IMAGE_NAME:latest"
    - make docker-push IMG="${IMAGE_NAME}:latest"
  cache:
    key: "$CI_COMMIT_REF_SLUG"
    paths:
      - _build/pkg
```
Básicamente, solo instalamos todo lo que necesitamos, ejecutamos las pruebas y, si todo va bien, sigue el proceso de construcción y empuje. Hay mucho espacio para mejorar esa configuración inicial, pero por ahora solo nos interesa tener algún tipo de sistema de CI.
<br />

Entonces veremos algo como esto en la pestaña `CI/CD->Pipelines`. Después de cada commit, se disparará un test, build y push.
![img](/images/gitlab-8.png){:class="mx-auto"}
<br />

##### **Verificando los resultados**
Y podemos validar que las imágenes están en dockerhub.
![img](/images/gitlab-9.png){:class="mx-auto"}
<br />

##### **Links útiles**
Algunos links útiles:
* [Variables](https://docs.gitlab.com/ee/ci/variables/) y [Variables predefinidas](https://docs.gitlab.com/ee/ci/variables/predefined_variables.html)
* [Usar imágenes de docker](https://docs.gitlab.com/ee/ci/docker/using_docker_images.html)
* [Construir imágenes de docker](https://docs.gitlab.com/ee/ci/docker/using_docker_build.html)

<br />

##### **Notas finales**
¡Espero que te haya gustado y espero verte en [twitter](https://twitter.com/kainlite) o [github](https://github.com/kainlite)!
<br />

### Errata
Si ves algún error o tenés alguna sugerencia, por favor mandame un mensaje así lo arreglo.

También podés ver el código fuente y cambios en el [código generado](https://github.com/kainlite/kainlite.github.io) y en las [fuentes acá](https://github.com/kainlite/blog).

<br />
