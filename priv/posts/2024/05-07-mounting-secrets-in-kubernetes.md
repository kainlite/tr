
%{
  title: "How to mount secrets as files or environment variables in kubernetes",
  author: "Gabriel Garrido",
  description: "In this article we will quickly see a few different ways of mounting secrets in kubernetes, that means
  exposing them so you can use them in your application, there are multiple ways and some interesting features that you
  can take advantage of",
  tags: ~w(kubernetes tips-and-tricks),
  published: true,
  image: "kubernetes.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

### **Introduction**

This will be a short article exploring the different ways you can mount secrets in kubernetes and also understand when
to use each method, mount means load or expose basically in your Pod either as an env var or as a file, or multiple
files even, the decision is up to you and how your app uses or consumes those secrets.

First we will explore how to create and expose secrets as environment variables, this is probably the most used way and
is really useful as the format is really easy to follow and maintain, lets see an example:


```elixir
❯ kubectl create secret generic supersecret -n example --from-literal=MY_SUPER_ENVVAR=a_secret --from-literal=ANOTHER_ENVVAR=just_another_secret
secret/supersecret created
```
<br/> 

Lets check the contents of the secret, it maintains a similar shape as we defined, be sure to check the help of kubectl
as it contains many examples of how to pass data into the actual secret.
```elixir
❯ kubectl get secret supersecret -o yaml
apiVersion: v1
data:
  ANOTHER_ENVVAR: anVzdF9hbm90aGVyX3NlY3JldA==
  MY_SUPER_ENVVAR: YV9zZWNyZXQ=
kind: Secret
metadata:
  name: supersecret
  namespace: example
type: Opaque
```

All good so far, but how do we actually use that secret? Lets create a spec for it, then we will explore a few
options there...

<br />

### First scenario: single key from a secret

In this example we have a StatefulSet mounting a secret using a specific key as an environment variable, this is pretty
common and useful when you don't need all keys to be mounted in all pods for example or when using shared
configurations, pay special attention to the `valueFrom` section, the name indicates the name of the secret and the key
how it is stored inside the `data` block of the same, this also works with ConfigMaps as you might have guessed, instead
of `secretKeyRef` use `configMapKeyRef`.
```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: example
  name: example
  namespace: example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example
  template:
    metadata:
      labels:
        app: example
    spec:
      containers:
      - name: example
        image: busybox:1.36
        command: ["sh", "-c", "/bin/sleep 3600"]
        env:
          - name: MY_SUPER_ENVVAR
            valueFrom: 
              secretKeyRef:
                name: supersecret
                key: MY_SUPER_ENVVAR
```

<br />

And the result would be: 

```elixir
❯ kubectl -n example exec -ti example-64f956f9c9-fxn28 -- env | grep ENV
MY_SUPER_ENVVAR=a_secret
```

<br />

### Second scenario: env vars from a secret

In this second example, we will mount all values from the secret as environment variables, so it is important to have
the right format in the secret, and there is a super-handy keyword for that: `envFrom` and it also works with
ConfigMaps, instead of using `secretRef` you would need to specify: `configMapRef`.

```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: example
  name: example
  namespace: example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example
  template:
    metadata:
      labels:
        app: example
    spec:
      containers:
      - name: example
        image: busybox:1.36
        command: ["sh", "-c", "/bin/sleep 3600"]
        envFrom:
          - secretRef:
              name: supersecret
```

<br />

And the result would be: 

```elixir
❯ kubectl -n example exec -ti example-584757d47f-gbxgq -- env | grep ENV
ANOTHER_ENVVAR=just_another_secret
MY_SUPER_ENVVAR=a_secret
```
<br />

### Third scenario: a secret as files

In some cases your application might need a config file mounted in the pod, in those cases you can mount the entire
Secret or ConfigMap or specific keys as specific files (Fourth scenario)

For this case we will use a new secret, with a json file in it stored as the key `test.json` which is the actual
filename, this is pretty handy, there could be multiple files stored there and we could mount all of them at once, or
not:

```elixir
❯ cat test.json
{
  "key1": "value1",
  "key2": "value2"
}

❯ kubectl create secret generic supersecret2 -n example --from-file=test.json
secret/supersecret2 created

❯ kubectl get secret supersecret2 -o yaml
apiVersion: v1
data:
  test.json: ewogICJrZXkxIjogInZhbHVlMSIsCiAgImtleTIiOiAidmFsdWUyIgp9Cg==
kind: Secret
metadata:
  name: supersecret2
  namespace: example
type: Opaque
```

<br />

Now lets use our new secret:
```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: example
  name: example
  namespace: example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example
  template:
    metadata:
      labels:
        app: example
    spec:
      containers:
      - name: example
        image: busybox:1.36
        command: ["sh", "-c", "/bin/sleep 3600"]
        volumeMounts:
          - mountPath: "/var/mysecrets"
            name: test.json
            readOnly: true
      volumes:
        - name: test.json
          secret:
            secretName: supersecret2
```

<br />

And the result would be: 

```elixir
❯ kubectl -n example exec -ti example-5b9c58b7f9-zv9nr -- cat /var/mysecrets/test.json
{
  "key1": "value1",
  "key2": "value2"
}
```
<br />

### Fourth scenario: a secret key as a single file

Sometimes you just need a specific config as a file in a specific path, imagine some json config or a string that needs
to be present in some file for you app to read. 


```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: example
  name: example
  namespace: example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example
  template:
    metadata:
      labels:
        app: example
    spec:
      containers:
      - name: example
        image: busybox:1.36
        command: ["sh", "-c", "/bin/sleep 3600"]
        volumeMounts:
          - mountPath: "/var/myapp/server.config"
            name: config
            readOnly: true
            subPath: test.json
      volumes:
        - name: config
          secret:
            secretName: supersecret2
            items:
              - key: test.json
                path: test.json
```

<br />

And the result would be: 

```elixir
❯ kubectl -n example exec -ti example-59f565fbbf-cgk5c -- cat /var/myapp/server.config
{
  "key1": "value1",
  "key2": "value2"
}
```

<br />

Which is incredible useful because you can mount the file as you need as long as you have it properly stored as a Secret
or ConfigMap, when debugging issues with your containers and secrets make sure to use `kubectl describe pod`, as that is
a big ally to understand the spec that our pod or workload must comply and it will point us in the direction of any
possible error or mistake.

<br />

Example with the wrong secret name (do note that I cleaned up the output a bit to make it more readable): 

```elixir
❯ kubectl -n example describe pod example-58bbc5464f-2mcv7
Name:             example-58bbc5464f-2mcv7
Namespace:        example
Priority:         0
Service Account:  default
Containers:
  example:
    Image:         busybox:1.36
    Image ID:
    Port:          <none>
    Host Port:     <none>
      sh
      -c
      /bin/sleep 3600
    State:          Waiting
      Reason:       ContainerCreating
    Ready:          False
    Restart Count:  0
    Mounts:
      /var/mysecrets from config (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   False
  Initialized                 True
  Ready                       False
  ContainersReady             False
  PodScheduled                True
Volumes:
  config:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  mysupersecret2
    Optional:    false
Events:
  Type     Reason       Age                 From               Message
  ----     ------       ----                ----               -------
  Warning  FailedMount  6s (x9 over 2m14s)  kubelet            MountVolume.SetUp failed for volume "config" : secret "mysupersecret2" not found
```

<br />

With this we have just scratched the surface of what is possible with Kubernetes, but hopefully it was helpful for you,
do you have any questions? drop a comment :point_down:

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
---lang---
%{
  title: "Como montar secretos y configs en Kubernetes como archivos o variables de entorno",
  author: "Gabriel Garrido",
  description: "Vamos a explorar distintas maneras de consumir secretos en Kubernetes",
  tags: ~w(kubernetes tips-and-tricks),
  published: true,
  image: "kubernetes.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### **Introducción**

Este será un artículo corto explorando las diferentes formas en las que podés montar secretos en Kubernetes y también entender cuándo utilizar cada método. Montar significa cargar o exponer, básicamente, dentro de tu Pod, ya sea como una variable de entorno (env var), como un archivo o incluso como múltiples archivos. La decisión depende de vos y de cómo tu aplicación utiliza o consume esos secretos.

Primero exploraremos cómo crear y exponer secretos como variables de entorno, probablemente la forma más utilizada, ya que el formato es fácil de seguir y mantener. Veamos un ejemplo:

```elixir
❯ kubectl create secret generic supersecret -n example --from-literal=MY_SUPER_ENVVAR=a_secret --from-literal=ANOTHER_ENVVAR=just_another_secret
secret/supersecret created
```
<br/> 

Veamos el contenido del secreto, mantiene una forma similar a como lo definimos. Asegurate de revisar la ayuda de `kubectl`, ya que contiene muchos ejemplos de cómo pasar datos dentro del secreto real.
```elixir
❯ kubectl get secret supersecret -o yaml
apiVersion: v1
data:
  ANOTHER_ENVVAR: anVzdF9hbm90aGVyX3NlY3JldA==
  MY_SUPER_ENVVAR: YV9zZWNyZXQ=
kind: Secret
metadata:
  name: supersecret
  namespace: example
type: Opaque
```

Todo bien hasta ahora, pero ¿cómo usamos realmente ese secreto? Vamos a crear una especificación para ello y luego exploraremos algunas opciones...

<br />

### Primer escenario: clave única desde un secreto

En este ejemplo, tenemos un StatefulSet que monta un secreto usando una clave específica como una variable de entorno. Esto es bastante común y útil cuando no necesitas que todas las claves se monten en todos los pods, por ejemplo, o cuando usas configuraciones compartidas. Presta especial atención a la sección `valueFrom`, donde el nombre indica el nombre del secreto y la clave cómo está almacenada dentro del bloque `data` del mismo. Esto también funciona con ConfigMaps, como probablemente hayas adivinado; en lugar de `secretKeyRef`, usa `configMapKeyRef`.

```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: example
  name: example
  namespace: example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example
  template:
    metadata:
      labels:
        app: example
    spec:
      containers:
      - name: example
        image: busybox:1.36
        command: ["sh", "-c", "/bin/sleep 3600"]
        env:
          - name: MY_SUPER_ENVVAR
            valueFrom: 
              secretKeyRef:
                name: supersecret
                key: MY_SUPER_ENVVAR
```

<br />

Y el resultado seria: 

```elixir
❯ kubectl -n example exec -ti example-64f956f9c9-fxn28 -- env | grep ENV
MY_SUPER_ENVVAR=a_secret
```

<br />

### Segundo escenario: variables de entorno desde un secreto

En este segundo ejemplo, vamos a montar todos los valores del secreto como variables de entorno, por lo que es importante tener el formato correcto en el secreto. Para esto, hay una palabra clave súper útil: `envFrom`, y también funciona con ConfigMaps. En lugar de usar `secretRef`, tendrías que especificar: `configMapRef`.

```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: example
  name: example
  namespace: example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example
  template:
    metadata:
      labels:
        app: example
    spec:
      containers:
      - name: example
        image: busybox:1.36
        command: ["sh", "-c", "/bin/sleep 3600"]
        envFrom:
          - secretRef:
              name: supersecret
```

<br />

El resultado seria: 

```elixir
❯ kubectl -n example exec -ti example-584757d47f-gbxgq -- env | grep ENV
ANOTHER_ENVVAR=just_another_secret
MY_SUPER_ENVVAR=a_secret
```
<br />

### Tercer escenario: un secreto como archivos

En algunos casos, tu aplicación podría necesitar un archivo de configuración montado en el pod. En esos casos, puedes montar todo el Secret o ConfigMap, o claves específicas como archivos específicos (esto lo veremos en el cuarto escenario).

Para este ejemplo, usaremos un nuevo secreto que contiene un archivo JSON almacenado bajo la clave `test.json`, que será el nombre real del archivo. Esto es bastante útil, ya que podrías tener múltiples archivos almacenados allí y podrías montarlos todos de una vez, o solo algunos:

```elixir
❯ cat test.json
{
  "key1": "value1",
  "key2": "value2"
}

❯ kubectl create secret generic supersecret2 -n example --from-file=test.json
secret/supersecret2 created

❯ kubectl get secret supersecret2 -o yaml
apiVersion: v1
data:
  test.json: ewogICJrZXkxIjogInZhbHVlMSIsCiAgImtleTIiOiAidmFsdWUyIgp9Cg==
kind: Secret
metadata:
  name: supersecret2
  namespace: example
type: Opaque
```

<br />

Veamos el secreto:
```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: example
  name: example
  namespace: example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example
  template:
    metadata:
      labels:
        app: example
    spec:
      containers:
      - name: example
        image: busybox:1.36
        command: ["sh", "-c", "/bin/sleep 3600"]
        volumeMounts:
          - mountPath: "/var/mysecrets"
            name: test.json
            readOnly: true
      volumes:
        - name: test.json
          secret:
            secretName: supersecret2
```

<br />

Y el resultado seria: 

```elixir
❯ kubectl -n example exec -ti example-5b9c58b7f9-zv9nr -- cat /var/mysecrets/test.json
{
  "key1": "value1",
  "key2": "value2"
}
```
<br />

### Cuarto escenario: una clave de un secreto como un archivo individual

A veces solo necesitas una configuración específica como archivo en una ruta particular. Imagina un archivo de configuración JSON o una cadena que debe estar presente en un archivo para que tu aplicación lo lea.
```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: example
  name: example
  namespace: example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example
  template:
    metadata:
      labels:
        app: example
    spec:
      containers:
      - name: example
        image: busybox:1.36
        command: ["sh", "-c", "/bin/sleep 3600"]
        volumeMounts:
          - mountPath: "/var/myapp/server.config"
            name: config
            readOnly: true
            subPath: test.json
      volumes:
        - name: config
          secret:
            secretName: supersecret2
            items:
              - key: test.json
                path: test.json
```

<br />

Y el resultado seria: 

```elixir
❯ kubectl -n example exec -ti example-59f565fbbf-cgk5c -- cat /var/myapp/server.config
{
  "key1": "value1",
  "key2": "value2"
}
```

<br />
Lo increíblemente útil de este enfoque es que podés montar el archivo como lo necesites, siempre y cuando lo tengas almacenado correctamente como un Secret o ConfigMap. Cuando estés depurando problemas con tus contenedores y secretos, asegurate de usar `kubectl describe pod`, ya que es una gran herramienta para entender la especificación que nuestro pod o carga de trabajo debe cumplir y te indicará cualquier posible error o equivocación.

<br />

Ejemplo con el nombre del secreto incorrecto (he limpiado un poco el output para que sea más legible):

```elixir
❯ kubectl -n example describe pod example-58bbc5464f-2mcv7
Name:             example-58bbc5464f-2mcv7
Namespace:        example
Priority:         0
Service Account:  default
Containers:
  example:
    Image:         busybox:1.36
    Image ID:
    Port:          <none>
    Host Port:     <none>
      sh
      -c
      /bin/sleep 3600
    State:          Waiting
      Reason:       ContainerCreating
    Ready:          False
    Restart Count:  0
    Mounts:
      /var/mysecrets from config (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   False
  Initialized                 True
  Ready                       False
  ContainersReady             False
  PodScheduled                True
Volumes:
  config:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  mysupersecret2
    Optional:    false
Events:
  Type     Reason       Age                 From               Message
  ----     ------       ----                ----               -------
  Warning  FailedMount  6s (x9 over 2m14s)  kubelet            MountVolume.SetUp failed for volume "config" : secret "mysupersecret2" not found
```

<br />

Con esto, apenas hemos arañado la superficie de lo que es posible hacer con Kubernetes, pero espero que te haya sido útil. ¿Tenés alguna pregunta? Dejá un comentario :point_down:

<br />

##### **Erratas**
Si encontrás algún error o tenés alguna sugerencia, mandame un mensaje para que lo corrija.

<br />
