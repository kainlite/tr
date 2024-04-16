%{
  title: "Go continuous integration with Travis CI and Docker",
  author: "Gabriel Garrido",
  description: "In this article we will see how to create a simple continuous integration process using github,
  travis-ci and docker...",
  tags: ~w(golang travis cicd),
  published: true,
  image: "travis-ci-docker.png"
}
---

![travis](/images/travis-ci-docker.png){:class="mx-auto"}

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
![image](/images/whatismyip-go-travis-list.png){:class="mx-auto"}
Once you have your account linked you will be able to sync and enable repositories to be built.
<br />

After enabling the repository you can configure some details like environment variables, here we will set the credentials for dockerhub.
![image](/images/whatismyip-go-travis-settings.png){:class="mx-auto"}
<br />

And now we will create the repository in dockerhub:
![image](/images/whatismyip-go-docker-repo.png){:class="mx-auto"}
After the repository is created we can trigger a build from travis or push a commit to the repo in order to trigger a build and to validate that everything works.
<br />

You should see something like this in travis if everything went well:
![image](/images/whatismyip-go-travis-log-1.png){:class="mx-auto"}
You can validate that everything went well by checking the commit SHA that triggered the build.
<br />

And dockerhub:
![image](/images/whatismyip-go-travis-log-2.png){:class="mx-auto"}
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
