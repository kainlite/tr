%{
  title: "Go echo bot",
  author: "Gabriel Garrido",
  description: "Exploring ksonnet with an echo bot made in Golang...",
  tags: ~w(golang kubernetes jsonnet ksonnet slack tooling),
  published: true,
  image: "logo.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

### **Echo bot**

This post was going to be about advanced ksonnet usage, but it went more about the echo bot itself, so I decided to rename it.
<br />

To be honest, there is no other way to get the benefits of having [ksonnet](https://ksonnet.io/) if you're not going to take advantage of the _deployments as code_ facilities that it brings thanks to Jsonnet.
<br />

This time we will see how to use [proper templates](https://github.com/cybermaggedon/ksonnet-cheat-sheet), it seems that the templates generated with `ks` are outdated at the time of this writing ksonnet version is: 0.13.1, no surprise here because it's not a really mature tool. It does require a lot of effort in learning, hacking and reading to get things to work, but hopefully soon it will be easier, of course this is my personal opinion and I have not used it for a real project yet, but I expect it to grow and become more usable before I attempt to do something for the real world with it.
<br />

In the examples I will be using [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube) or you can [check out this repo](https://github.com/kainlite/kainlite.github.io) that has a good overview of minikube, once installed and started (`minikube start`) that command will download and configure the local environment, if you have been following the previous posts you already have minikube installed and working:
<br />

### Let's get started
This time I'm not going to deploy another wordpress instance but a simple Slack echo bot made with go:
```elixir
package main

import (
        "fmt"
        "os"
        "strings"

        slack "github.com/nlopes/slack"
)

func main() {
        api := slack.New(
                os.Getenv("SLACK_API_TOKEN"),
        )

        rtm := api.NewRTM()
        go rtm.ManageConnection()

        for msg := range rtm.IncomingEvents {
                fmt.Print("Event Received: ")
                switch ev := msg.Data.(type) {
                case *slack.HelloEvent:
                        // Ignore hello

                case *slack.ConnectedEvent:
                        fmt.Println("Infos:", ev.Info)
                        fmt.Println("Connection counter:", ev.ConnectionCount)

                case *slack.MessageEvent:
                        // Only echo what it said to me
                        fmt.Printf("Message: %v\n", ev)
                        info := rtm.GetInfo()
                        prefix := fmt.Sprintf("<@%s> ", info.User.ID)

                        if ev.User != info.User.ID && strings.HasPrefix(ev.Text, prefix) {
                                rtm.SendMessage(rtm.NewOutgoingMessage(ev.Text, ev.Channel))
                        }

                case *slack.PresenceChangeEvent:
                        fmt.Printf("Presence Change: %v\n", ev)

                case *slack.LatencyReport:
                        fmt.Printf("Current latency: %v\n", ev.Value)

                case *slack.RTMError:
                        fmt.Printf("Error: %s\n", ev.Error())

                case *slack.InvalidAuthEvent:
                        fmt.Printf("Invalid credentials")
                        return

                default:

                        // Ignore other events..
                        // fmt.Printf("Unexpected: %v\n", msg.Data)
                }
        }
}
```
As you can see it's the simplest example from the readme of the [Go Slack API](https://github.com/nlopes/slack) project, it only connects to Slack and when it reads a message if it's addressed to the bot then it echoes the message back, creating a bot and everything else is out of the scope of this article but it's really simple, you only need to create an app in the Slack workspace, set it as a bot and grab the token (there is a lot more that you can customize but that is the most basic procedure to get started with a bot), then you just invite it to any channel that you want and start interacting with it.
<br />

Here you can see the `Dockerfile`, for security we create an app user for the build and for running it, and to save space and bandwidth we only ship what we need using a multi-stage build:

```elixir
# Build
FROM golang:1.11.2-alpine as builder

WORKDIR /app
RUN adduser -D -g 'app' app && \
    chown -R app:app /app && \
    apk add git && apk add gcc musl-dev

ADD . /app/
RUN go get -d -v ./... && go build -o main . && chown -R app:app /app /home/app

# Run
FROM golang:1.11.2-alpine

WORKDIR /app
RUN adduser -D -g 'app' app && \
    chown -R app:app /app

COPY --from=builder --chown=app /app/health_check.sh /app/health_check.sh
COPY --from=builder --chown=app /app/main /app/main

USER app
CMD ["/app/main"]
```
There are a few more files in there, you can see the full sources [here](https://github.com/kainlite/echobot), for example `health_check.sh`, as our app doesn't listen on any port we need a way to tell kubernetes how to check if our app is alive.
<br />

Okay, enough boilerplate let's get to business, so let's create a new ksonnet application:
```elixir
$ ks init echobot
INFO Using context "minikube" from kubeconfig file "~/.kube/config"
INFO Creating environment "default" with namespace "default", pointing to "version:v1.8.0" cluster at address "https://192.168.99.100:8443"
INFO Generating ksonnet-lib data at path '~/Webs/echobot/echobot/lib/ksonnet-lib/v1.8.0'
```
<br />

And now let's grab a template and modify it accordingly to be able to create the deployment for the bot `components/echobot.jsonnet`:
```elixir
// Import KSonnet library
local params = std.extVar('__ksonnet/params').components.demo;
local k = import 'k.libsonnet';

// Specify the import objects that we need
local container = k.extensions.v1beta1.deployment.mixin.spec.template.spec.containersType;
local depl = k.extensions.v1beta1.deployment;

// Environment variables, instead of hardcoding it here we could use a param or a secret
// But I will leave that as an exercise for you :)
local envs = [
  {
    name: 'SLACK_API_TOKEN',
    value: 'really-long-token',
  },
];

local livenessProbe = {
  exec: {
    command: [
      '/bin/sh',
      '-c',
      '/app/health_check.sh',
    ],
  },
};

// Define containers
local containers = [
  container.new('echobot', 'kainlite/echobot:0.0.2') {
    env: (envs),
    livenessProbe: livenessProbe,
  },
];

// Define deployment with 3 replicas
local deployment =
  depl.new('echobot', 1, containers, { app: 'echobot' });

local resources = [deployment];

// Return list of resources.
k.core.v1.list.new(resources)
```
<br />

Note that I have uploaded that image to docker hub so you can use it to follow the example if you want, after that just replace `really-long-token` with your token, and then do:
```elixir
$ ks apply default
INFO Applying deployments echobot
INFO Creating non-existent deployments echobot
```
<br />

And now if we check our deployment and pod, we should see something like this:

![echobot](/images/echobot.png)
<br />

And in the logs:
```elixir
$ kubectl get pods
NAME                               READY     STATUS    RESTARTS   AGE
echobot-7456f7d7dd-twg4r           1/1       Running   0          53s

$ kubectl logs -f echobot-7456f7d7dd-twg4r
Event Received: Event Received: Infos: &{wss://cerberus-xxxx.lb.slack-msgs.com/websocket/1gvXP_yQCFE-Y= 0xc000468000 0xc0004482a0 [] [] [] [] []}
Connection counter: 0
Event Received: Event Received: Current latency: 1.256397423s
Event Received: Current latency: 1.25679313s
Event Received: Current latency: 1.256788737s
Event Received: Message: &{{message CEDGU6EA0 UEDJT5DDH <@UED48HD33> echo! 1546124966.002300  false [] [] <nil>  false 0  false  1546124966.002300   <nil>      [] 0 []  [] false <nil>  0 TEDJT5CTD []  false false} <nil>}
```
<br />

And that folks is all I have for now, I hope you enjoyed this small tour of ksonnet. The source code for the bot can be found [here](https://github.com/kainlite/echobot). In a future post I might explore [ksonnet and helm charts](https://ksonnet.io/docs/examples/helm/).

### Upcoming topics
As promised I will be doing one post about [Gitkube](https://github.com/hasura/gitkube) and [Skaffold](https://github.com/GoogleContainerTools/skaffold), there are a lot of deployment tools for kubernetes but those are the most promising ones to me, also after that I will start covering more topics about [Docker](https://www.docker.com/), [ContainerD](https://containerd.io/), [KubeADM](https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/), and Kubernetes in general.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Bot eco hecho en Go",
  author: "Gabriel Garrido",
  description: "Seguimos jugando con ksonnet con un bot eco hecho en Go...",
  tags: ~w(golang kubernetes jsonnet ksonnet slack tooling),
  published: true,
  image: "logo.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### **Bot de eco**

Esta publicación iba a ser sobre el uso avanzado de ksonnet, pero terminó siendo más sobre el bot de eco en sí, así que decidí renombrarla.
<br />

Para ser honesto, no hay otra forma de obtener los beneficios de tener [ksonnet](https://ksonnet.io/) si no vas a aprovechar las facilidades de _despliegues como código_ que trae gracias a Jsonnet.
<br />

Esta vez veremos cómo usar [plantillas adecuadas](https://github.com/cybermaggedon/ksonnet-cheat-sheet); parece que las plantillas generadas con `ks` están desactualizadas. Al momento de escribir esto, la versión de ksonnet es 0.13.1, sin sorpresa aquí porque no es una herramienta realmente madura. Requiere mucho esfuerzo en aprender, hackear y leer para que las cosas funcionen, pero espero que pronto sea más fácil; por supuesto, esta es mi opinión personal y aún no lo he usado para un proyecto real, pero espero que crezca y se vuelva más usable antes de intentar hacer algo para el mundo real con él.
<br />

En los ejemplos estaré usando [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube) o puedes [revisar este repositorio](https://github.com/kainlite/kainlite.github.io) que tiene una buena visión general de minikube. Una vez instalado y iniciado (`minikube start`), ese comando descargará y configurará el entorno local; si has estado siguiendo las publicaciones anteriores, ya tienes minikube instalado y funcionando:
<br />

### Empecemos

Esta vez no voy a desplegar otra instancia de WordPress sino un simple bot de eco de Slack hecho con Go:
```elixir
package main

import (
        "fmt"
        "os"
        "strings"

        slack "github.com/nlopes/slack"
)

func main() {
        api := slack.New(
                os.Getenv("SLACK_API_TOKEN"),
        )

        rtm := api.NewRTM()
        go rtm.ManageConnection()

        for msg := range rtm.IncomingEvents {
                fmt.Print("Event Received: ")
                switch ev := msg.Data.(type) {
                case *slack.HelloEvent:
                        // Ignore hello

                case *slack.ConnectedEvent:
                        fmt.Println("Infos:", ev.Info)
                        fmt.Println("Connection counter:", ev.ConnectionCount)

                case *slack.MessageEvent:
                        // Only echo what it said to me
                        fmt.Printf("Message: %v\n", ev)
                        info := rtm.GetInfo()
                        prefix := fmt.Sprintf("<@%s> ", info.User.ID)

                        if ev.User != info.User.ID && strings.HasPrefix(ev.Text, prefix) {
                                rtm.SendMessage(rtm.NewOutgoingMessage(ev.Text, ev.Channel))
                        }

                case *slack.PresenceChangeEvent:
                        fmt.Printf("Presence Change: %v\n", ev)

                case *slack.LatencyReport:
                        fmt.Printf("Current latency: %v\n", ev.Value)

                case *slack.RTMError:
                        fmt.Printf("Error: %s\n", ev.Error())

                case *slack.InvalidAuthEvent:
                        fmt.Printf("Invalid credentials")
                        return

                default:

                        // Ignore other events..
                        // fmt.Printf("Unexpected: %v\n", msg.Data)
                }
        }
}
```
Como puedes ver, es el ejemplo más simple del archivo readme del proyecto [Go Slack API](https://github.com/nlopes/slack). Solo se conecta a Slack y cuando lee un mensaje, si está dirigido al bot, entonces devuelve el mensaje. Crear un bot y todo lo demás está fuera del alcance de este artículo, pero es realmente simple. Solo necesitas crear una aplicación en el espacio de trabajo de Slack, configurarla como un bot y obtener el token (hay mucho más que puedes personalizar, pero ese es el procedimiento más básico para comenzar con un bot), luego lo invitas a cualquier canal que quieras y comienzas a interactuar con él.
<br />

Aquí puedes ver el `Dockerfile`; por seguridad, creamos un usuario de aplicación para la compilación y para ejecutarlo, y para ahorrar espacio y ancho de banda, solo enviamos lo que necesitamos usando una compilación de múltiples etapas:

```elixir
# Build
FROM golang:1.11.2-alpine as builder

WORKDIR /app
RUN adduser -D -g 'app' app && \
    chown -R app:app /app && \
    apk add git && apk add gcc musl-dev

ADD . /app/
RUN go get -d -v ./... && go build -o main . && chown -R app:app /app /home/app

# Run
FROM golang:1.11.2-alpine

WORKDIR /app
RUN adduser -D -g 'app' app && \
    chown -R app:app /app

COPY --from=builder --chown=app /app/health_check.sh /app/health_check.sh
COPY --from=builder --chown=app /app/main /app/main

USER app
CMD ["/app/main"]
```
Hay algunos archivos más allí; puedes ver las fuentes completas [aquí](https://github.com/kainlite/echobot), por ejemplo `health_check.sh`, como nuestra aplicación no escucha en ningún puerto, necesitamos una forma de decirle a Kubernetes cómo verificar si nuestra aplicación está viva.
<br />

Bien, suficiente código repetitivo, vamos al grano, así que creemos una nueva aplicación ksonnet:

```elixir
$ ks init echobot
INFO Using context "minikube" from kubeconfig file "~/.kube/config"
INFO Creating environment "default" with namespace "default", pointing to "version:v1.8.0" cluster at address "https://192.168.99.100:8443"
INFO Generating ksonnet-lib data at path '~/Webs/echobot/echobot/lib/ksonnet-lib/v1.8.0'
```
<br />

Y ahora tomemos una plantilla y modifiquémosla adecuadamente para poder crear el despliegue para el bot `components/echobot.jsonnet`:

```elixir
// Import KSonnet library
local params = std.extVar('__ksonnet/params').components.demo;
local k = import 'k.libsonnet';

// Specify the import objects that we need
local container = k.extensions.v1beta1.deployment.mixin.spec.template.spec.containersType;
local depl = k.extensions.v1beta1.deployment;

// Environment variables, instead of hardcoding it here we could use a param or a secret
// But I will leave that as an exercise for you :)
local envs = [
  {
    name: 'SLACK_API_TOKEN',
    value: 'really-long-token',
  },
];

local livenessProbe = {
  exec: {
    command: [
      '/bin/sh',
      '-c',
      '/app/health_check.sh',
    ],
  },
};

// Define containers
local containers = [
  container.new('echobot', 'kainlite/echobot:0.0.2') {
    env: (envs),
    livenessProbe: livenessProbe,
  },
];

// Define deployment with 3 replicas
local deployment =
  depl.new('echobot', 1, containers, { app: 'echobot' });

local resources = [deployment];

// Return list of resources.
k.core.v1.list.new(resources)
```
<br />

Ten en cuenta que he subido esa imagen a Docker Hub, así que puedes usarla para seguir el ejemplo si quieres; después de eso, simplemente reemplaza `really-long-token` con tu token, y luego haz:

```elixir
$ ks apply default
INFO Applying deployments echobot
INFO Creating non-existent deployments echobot
```
<br />

Y ahora, si verificamos nuestro despliegue y pod, deberíamos ver algo como esto:

![echobot](/images/echobot.png)
<br />

Y en los logs:

```elixir
$ kubectl get pods
NAME                               READY     STATUS    RESTARTS   AGE
echobot-7456f7d7dd-twg4r           1/1       Running   0          53s

$ kubectl logs -f echobot-7456f7d7dd-twg4r
Event Received: Event Received: Infos: &{wss://cerberus-xxxx.lb.slack-msgs.com/websocket/1gvXP_yQCFE-Y= 0xc000468000 0xc0004482a0 [] [] [] [] []}
Connection counter: 0
Event Received: Event Received: Current latency: 1.256397423s
Event Received: Current latency: 1.25679313s
Event Received: Current latency: 1.256788737s
Event Received: Message: &{{message CEDGU6EA0 UEDJT5DDH <@UED48HD33> echo! 1546124966.002300  false [] [] <nil>  false 0  false  1546124966.002300   <nil>      [] 0 []  [] false <nil>  0 TEDJT5CTD []  false false} <nil>}
```
<br />

Y eso es todo por ahora; espero que hayas disfrutado este pequeño recorrido por ksonnet. El código fuente del bot se puede encontrar [aquí](https://github.com/kainlite/echobot). En una publicación futura, podría explorar [ksonnet y charts de helm](https://ksonnet.io/docs/examples/helm/).

### Temas próximos

Como prometí, haré una publicación sobre [Gitkube](https://github.com/hasura/gitkube) y [Skaffold](https://github.com/GoogleContainerTools/skaffold); hay muchas herramientas de despliegue para Kubernetes, pero esas son las más prometedoras para mí. Además, después de eso, comenzaré a cubrir más temas sobre [Docker](https://www.docker.com/), [ContainerD](https://containerd.io/), [KubeADM](https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/), y Kubernetes en general.
<br />

### Erratas

Si encuentras algún error o tienes alguna sugerencia, por favor envíame un mensaje para que pueda corregirlo.

<br />
