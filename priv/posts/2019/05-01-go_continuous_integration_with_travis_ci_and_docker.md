%{
  title: "Go continuous integration with Travis CI and Docker",
  author: "Gabriel Garrido",
  description: "In this article we will see how to create a simple continuous integration process using github,
  travis-ci and docker...",
  tags: ~w(golang travis cicd),
  published: true,
  image: "travis-ci-docker.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![travis](/images/travis-ci-docker.webp){:class="mx-auto"}

##### **Introduction**
In this article we will see how to create a simple continuous integration process using [Github](https://github.com), [Travis-CI](https://travis-ci.org) and [Docker HUB](https://cloud.docker.com), the files used here can be found [HERE](https://github.com/kainlite/whatismyip-go), in the next article we will continue with what we have here to provide continuous deployment possibly using Jenkins or maybe Travis, let me know which one you would prefer to see.
<br />

##### **First thing first**
##### App
We will review the docker file, the app code and the travis-ci file, so let's start with the app `main.go`:
```elixir
package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
)

func httphandler(w http.ResponseWriter, r *http.Request) {
	ipAddress, _, _ := net.SplitHostPort(r.RemoteAddr)
	fmt.Fprintf(w, "%s", ipAddress)
}

func main() {
	port, err := strconv.Atoi(os.Getenv("WHATISMYIP_PORT"))
	if err != nil {
		log.Fatalf("Please make sure the environment variable WHATISMYIP_PORT is defined and is a valid integer [1024-65535], error: %s", err)
	}

	listener := fmt.Sprintf(":%d", port)

	http.HandleFunc("/", httphandler)
	log.Fatal(http.ListenAndServe(listener, nil))
}

```
Let's quickly check what this code does, first we check for the port to use, then convert it to a number, register the handler for our HTTP function and listen for requests, this code should print our ip address as you would expect by the name.
<br />

Then the `main_test.go` code:
```elixir
package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandler(t *testing.T) {
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(httphandler)

	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("Status code got: %v want %v",
			status, http.StatusOK)
	}

	expected := ``
	if rr.Body.String() != expected {
		t.Errorf("Unexpected body got: %v want %v",
			rr.Body.String(), expected)
	}
}

```
The test is fairly simple it just checks that the web server works by trying to fetch `/` and checking for an empty body and `200` status code.
<br />

##### Docker
Next the `Dockerfile`:
```elixir
FROM golang:1.12-alpine

LABEL maintainer="kainlite@gmail.com"

# Set the Current Working Directory inside the container
WORKDIR $GOPATH/src/github.com/kainlite/whatismyip-go
COPY . .

# Download all the dependencies
# https://stackoverflow.com/questions/28031603/what-do-three-dots-mean-in-go-command-line-invocations
RUN go get -d -v ./...

# Install the package and create test binary
RUN go install -v ./... && \
    CGO_ENABLED=0 GOOS=linux go test -c

# This container exposes port 8080 to the outside world
EXPOSE 8000

# Set default environment variable values
ENV WHATISMYIP_PORT 8000

# Perform any further action as an unprivileged user.
USER nobody:nobody

# Run the executable
CMD ["whatismyip-go"]

```
We set the working directory to please go, then fetch dependencies and install our binary, we also generate a test binary, expose the port that we want to use and set the user as nobody in case someone can exploit our app and jump into our container, then just set the command to execute on `docker run`.

##### Travis
And last but not least the `.travis.yml` file:
```elixir
language: go

services:
  - docker

before_install:
- docker build --no-cache -t ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT} .
- docker run ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT} /go/src/github.com/kainlite/whatismyip-go/whatismyip-go.test
- docker run -d -p 127.0.0.1:8000:8000 ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT}

script:
  - curl 127.0.0.1:8000
  - echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
  - docker push ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT}

```
We let travis know that we will be running some go code and also docker, then build the image, run the tests and then the app as initialization, after that we validate that the app works and lastly login to dockerhub and push the image, the important things to have in mind here is that we use variables for example the repo name, the commit SHA, and the docker username and password in a secure way, since travis-ci hides the values that we tell them to.
<br />

##### **Putting everything together**
So far we got the [repo](https://github.com/kainlite/whatismyip-go) going, the configuration for travis, the dockerfile, the app, but now we need to make use of it, so you will need to create a travis account for this to work then link your github account to it, then you will be able to sync your repositories and you should see something like this:
![image](/images/whatismyip-go-travis-list.webp){:class="mx-auto"}
Once you have your account linked you will be able to sync and enable repositories to be built.
<br />

After enabling the repository you can configure some details like environment variables, here we will set the credentials for dockerhub.
![image](/images/whatismyip-go-travis-settings.webp){:class="mx-auto"}
<br />

And now we will create the repository in dockerhub:
![image](/images/whatismyip-go-docker-repo.webp){:class="mx-auto"}
After the repository is created we can trigger a build from travis or push a commit to the repo in order to trigger a build and to validate that everything works.
<br />

You should see something like this in travis if everything went well:
![image](/images/whatismyip-go-travis-log-1.webp){:class="mx-auto"}
You can validate that everything went well by checking the commit SHA that triggered the build.
<br />

And dockerhub:
![image](/images/whatismyip-go-travis-log-2.webp){:class="mx-auto"}
The same SHA will be used to tag the image.
<br />

##### **Closing notes**
I will be posting some articles about CI and CD and good practices that DevOps/SREs should have in mind, tips, tricks, and full deployment examples, this is the first part of a possible series of two or three articles with a complete but basic example of CI first and then CD. This can of course change and any feedback would be greatly appreciated :).

Some useful links for travis and [docker](https://docs.travis-ci.com/user/docker/) and the [environment variables list](https://docs.travis-ci.com/user/environment-variables/) that can be used.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Integracion continue con Travis CI y Docker",
  author: "Gabriel Garrido",
  description: "En este articulo vamos a ver como crear un proceso de integracion continue simple con github,
  travis-ci y docker...",
  tags: ~w(golang travis cicd),
  published: true,
  image: "travis-ci-docker.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![travis](/images/travis-ci-docker.webp){:class="mx-auto"}

##### **Introducción**
En este artículo veremos cómo crear un proceso simple de integración continua utilizando [Github](https://github.com), [Travis-CI](https://travis-ci.org) y [Docker HUB](https://cloud.docker.com). Los archivos utilizados aquí se pueden encontrar [AQUÍ](https://github.com/kainlite/whatismyip-go). En el próximo artículo continuaremos con lo que tenemos aquí para proporcionar despliegue continuo, posiblemente usando Jenkins o quizás Travis. Hazme saber cuál prefieres ver.
<br />

##### **Primero lo primero**
##### Aplicación
Revisaremos el archivo docker, el código de la aplicación y el archivo travis-ci, así que comencemos con la aplicación `main.go`:
```elixir
package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
)

func httphandler(w http.ResponseWriter, r *http.Request) {
	ipAddress, _, _ := net.SplitHostPort(r.RemoteAddr)
	fmt.Fprintf(w, "%s", ipAddress)
}

func main() {
	port, err := strconv.Atoi(os.Getenv("WHATISMYIP_PORT"))
	if err != nil {
		log.Fatalf("Please make sure the environment variable WHATISMYIP_PORT is defined and is a valid integer [1024-65535], error: %s", err)
	}

	listener := fmt.Sprintf(":%d", port)

	http.HandleFunc("/", httphandler)
	log.Fatal(http.ListenAndServe(listener, nil))
}

```
Revisemos rápidamente lo que hace este código. Primero verificamos el puerto a utilizar, luego lo convertimos en un número, registramos el manejador para nuestra función HTTP y escuchamos las solicitudes. Este código imprimirá nuestra dirección IP como se esperaría por el nombre.
<br />

Luego el código de `main_test.go`:
```elixir
package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandler(t *testing.T) {
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(httphandler)

	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("Status code got: %v want %v",
			status, http.StatusOK)
	}

	expected := ``
	if rr.Body.String() != expected {
		t.Errorf("Unexpected body got: %v want %v",
			rr.Body.String(), expected)
	}
}

```
La prueba es bastante simple, solo verifica que el servidor web funcione al intentar acceder a `/` y comprobando que el cuerpo esté vacío y el código de estado sea `200`.
<br />

##### Docker
A continuación, el `Dockerfile`:
```elixir
FROM golang:1.12-alpine

LABEL maintainer="kainlite@gmail.com"

# Set the Current Working Directory inside the container
WORKDIR $GOPATH/src/github.com/kainlite/whatismyip-go
COPY . .

# Download all the dependencies
# https://stackoverflow.com/questions/28031603/what-do-three-dots-mean-in-go-command-line-invocations
RUN go get -d -v ./...

# Install the package and create test binary
RUN go install -v ./... && \
    CGO_ENABLED=0 GOOS=linux go test -c

# This container exposes port 8080 to the outside world
EXPOSE 8000

# Set default environment variable values
ENV WHATISMYIP_PORT 8000

# Perform any further action as an unprivileged user.
USER nobody:nobody

# Run the executable
CMD ["whatismyip-go"]

```
Configuramos el directorio de trabajo para satisfacer a go, luego obtenemos las dependencias e instalamos nuestro binario. También generamos un binario de prueba, exponemos el puerto que queremos utilizar y configuramos el usuario como `nobody` en caso de que alguien pueda explotar nuestra aplicación y acceder al contenedor. Finalmente, establecemos el comando a ejecutar en `docker run`.

##### Travis
Y por último, pero no menos importante, el archivo `.travis.yml`:
```elixir
language: go

services:
  - docker

before_install:
- docker build --no-cache -t ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT} .
- docker run ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT} /go/src/github.com/kainlite/whatismyip-go/whatismyip-go.test
- docker run -d -p 127.0.0.1:8000:8000 ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT}

script:
  - curl 127.0.0.1:8000
  - echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
  - docker push ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT}

```
Le indicamos a Travis que ejecutaremos código Go y Docker. Luego, construimos la imagen, ejecutamos las pruebas y después la aplicación como parte de la inicialización. Después de eso, validamos que la aplicación funcione y, por último, iniciamos sesión en Docker Hub y subimos la imagen. Las cosas importantes a tener en cuenta aquí son que usamos variables, por ejemplo, el nombre del repositorio, el SHA del commit, y el nombre de usuario y contraseña de Docker de manera segura, ya que Travis-CI oculta los valores que le indicamos.
<br />

##### **Juntando todo**
Hasta ahora, tenemos el [repositorio](https://github.com/kainlite/whatismyip-go) funcionando, la configuración de Travis, el Dockerfile y la aplicación, pero ahora necesitamos usarlo. Necesitarás crear una cuenta de Travis para que esto funcione, luego vincula tu cuenta de GitHub con Travis. Podrás sincronizar tus repositorios y deberías ver algo como esto:
![image](/images/whatismyip-go-travis-list.webp){:class="mx-auto"}
Una vez que tu cuenta esté vinculada, podrás sincronizar y habilitar los repositorios para que se construyan.
<br />

Después de habilitar el repositorio, puedes configurar algunos detalles como variables de entorno. Aquí estableceremos las credenciales para Docker Hub.
![image](/images/whatismyip-go-travis-settings.webp){:class="mx-auto"}
<br />

Y ahora crearemos el repositorio en Docker Hub:
![image](/images/whatismyip-go-docker-repo.webp){:class="mx-auto"}
Después de que se crea el repositorio, podemos activar una compilación desde Travis o enviar un commit al repositorio para activar una compilación y validar que todo funciona.
<br />

Deberías ver algo como esto en Travis si todo salió bien:
![image](/images/whatismyip-go-travis-log-1.webp){:class="mx-auto"}
Puedes validar que todo salió bien revisando el SHA del commit que activó la compilación.
<br />

Y en Docker Hub:
![image](/images/whatismyip-go-travis-log-2.webp){:class="mx-auto"}
El mismo SHA se utilizará para etiquetar la imagen.
<br />

##### **Notas finales**
Publicaré algunos artículos sobre CI y CD, y buenas prácticas que los DevOps/SRE deberían tener en cuenta: consejos, trucos y ejemplos completos de despliegue. Esta es la primera parte de una posible serie de dos o tres artículos con un ejemplo básico pero completo de CI primero y luego CD. Esto, por supuesto, puede cambiar, y cualquier comentario será muy apreciado :).

Algunos enlaces útiles para [Travis y Docker](https://docs.travis-ci.com/user/docker/) y la [lista de variables de entorno](https://docs.travis-ci.com/user/environment-variables/) que se pueden usar.
<br />

### Errata
Si encuentras algún error o tienes alguna sugerencia, por favor envíame un mensaje para que se corrija.

<br />
