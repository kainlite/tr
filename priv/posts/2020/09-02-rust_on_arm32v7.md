%{
  title: "Running Rust on ARM32v7 K3S Oracle cluster",
  author: "Gabriel Garrido",
  description: "In this article we will explore how to create a sample rust project and Dockerfile to run it on ARM32v7...",
  tags: ~w(kubernetes rust arm),
  published: true,
  image: "rust.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![rust](/images/rust.png"){:class="mx-auto"}

#### **Introduction**

In this article we will explore how to create a sample [Rust](https://www.rust-lang.org/) project and Dockerfile to 
run it on [ARM32v7 architectures](https://github.com/docker-library/official-images#architectures-other-than-amd64).
<br />

To configure the cluster I used this project [k3s-oci-cluster](https://github.com/garutilorenzo/k3s-oci-cluster), since
Oracle is providing a very generous free tier for ARM workloads you might as well give it a try, or maybe use your 
raspberry pi cluster.
<br />

The source for this article is here [RCV](https://github.com/kainlite/rcv/) and the docker image is 
[here](https://hub.docker.com/repository/docker/kainlite/rcv).
<br />

##### **Prerequisites**

The cluster is optional if you have any device using linux on ARM32v7 or ARM64v8 you should be able to use the docker
examples.
- [k3s-oci-cluster](https://github.com/garutilorenzo/k3s-oci-cluster)
- [Docker](https://hub.docker.com/?overlay=onboarding)
- [Rust](https://www.rust-lang.org/tools/install)

<br />

### Let's jump to the example

#### Creating the project

Lets create a new Rust project with Cargo, as you might notice we will get a very basic project that will help us get 
get started:
```elixir
❯ cargo new rcv
     Created binary (application) `rcv` package
     
❯ cd rcv
❯ ls
Cargo.toml  src

```
<br />

#### Our example and the dependencies
I was thinking in processing markdown files and show them as html, so that's basically what the code does, it's far from
optimal but it is good enough to illustrate the example, first lets add some crates for the webserver 
([Actix](https://actix.rs/docs/server/)) and converting [markdown to html](https://github.com/johannhof/markdown.rs).

```elixir
[package]
name = "rcv"
version = "0.1.0"
edition = "2021"

# See more keys and their definitions at https://doc.rust-lang.org/cargo/reference/manifest.html

[dependencies]
actix-web = "4"
markdown = "0.3"
```
<br />

#### Lets add some code
This simple snippet only listens for `GET` requests to `/` and logs a line with the unix timestamp and IP and returns 
the contents of the file `cv.md` which is my Curriculum Vitae.
```elixir
use actix_web::{get, App, HttpResponse, HttpServer};
use actix_web::{HttpRequest, Responder};
use std::fs;
use std::time::{Duration, SystemTime};

extern crate markdown;

#[get("/")]
async fn root(req: HttpRequest) -> impl Responder {
    let con_info = req.connection_info();
    let peer_ip = &req.peer_addr().unwrap().to_string();

    let ip = con_info
        .realip_remote_addr()
        .unwrap()
        .split(':')
        .next()
        .unwrap_or(peer_ip);

    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or(Duration::from_millis(0));

    println!("[{}][{}]: Processing cv request...", now.as_secs(), ip);

    let data = fs::read_to_string("./cv.md").expect("Unable to read file");
    let html: String = markdown::to_html(&data);

    HttpResponse::Ok().body(html)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| App::new().service(root))
        .bind(("0.0.0.0", 8080))?
        .run()
        .await
}

```

#### Example logs
Example logs 
```elixir
[1662136558][127.0.0.1]: Processing cv request...
[1662136591][127.0.0.1]: Processing cv request...

```

At this point we have enough to run and test locally, but what about other architectures? (I'm running on linux-amd64),
you can test it locally if you want running `cargo run`.
<br />

#### ARM32v7 Dockerfile
This Dockerfile can be optimized and secured in many ways, but for the sake of simplicity it is good enough to start 
working on something, also we will provide the security at runtime via kubernetes APIs.
We need to consider two things here, first we need to create an ARM32v7 binary using Rust, then we need a Docker image
for that architecture so that's basically what the Dockerfile does.
```elixir
## builder
FROM rust:1.63.0 as builder

RUN apt update && apt upgrade -y
RUN apt install -y g++-arm-linux-gnueabihf libc6-dev-armhf-cross

RUN rustup target add armv7-unknown-linux-gnueabihf
RUN rustup toolchain install stable-armv7-unknown-linux-gnueabihf

WORKDIR /usr/src/app

COPY . .

ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc \
    CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++

RUN cargo build --target armv7-unknown-linux-gnueabihf --release

## release
FROM arm32v7/rust:1.63

WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/target/armv7-unknown-linux-gnueabihf/release/rcv /usr/src/app
COPY --from=builder /usr/src/app/cv.md /usr/src/app

CMD ["/usr/src/app/rcv"]

```
<br />

#### Building and pushing (docker image)
So lets build it and push it [here](https://hub.docker.com/repository/docker/kainlite/rcv).
```elixir
❯ docker build . -f Dockerfile.armv7
Sending build context to Docker daemon  894.2MB
Step 1/14 : FROM rust:1.63.0 as builder
 ---> 2a7d3c69bbf0
Step 2/14 : RUN apt update && apt upgrade -y
 ---> Using cache
 ---> 3a3120a0cb99
Step 3/14 : RUN apt install -y g++-arm-linux-gnueabihf libc6-dev-armhf-cross
 ---> Using cache
 ---> 78e25363f688
Step 4/14 : RUN rustup target add armv7-unknown-linux-gnueabihf
 ---> Using cache
 ---> dc97e983b392
Step 5/14 : RUN rustup toolchain install stable-armv7-unknown-linux-gnueabihf
 ---> Using cache
 ---> a1266f5b3cfa
Step 6/14 : WORKDIR /usr/src/app
 ---> Using cache
 ---> ff1efb7d4bce
Step 7/14 : COPY . .
 ---> a0ceff61a547
Step 8/14 : ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc     CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc     CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++
 ---> Running in 0249ca22cd26
Removing intermediate container 0249ca22cd26
 ---> a803cfa71e49
Step 9/14 : RUN cargo build --target armv7-unknown-linux-gnueabihf --release
 ---> Running in 533c57b89b90
    Updating crates.io index
 Downloading crates ...
  Downloaded actix-macros v0.2.3
  Downloaded firestorm v0.5.1
  Downloaded bytestring v1.1.0
  Downloaded futures-task v0.3.23
  Downloaded actix-service v2.0.2
  Downloaded crc32fast v1.3.2
  Downloaded httpdate v1.0.2
  Downloaded miniz_oxide v0.5.3
  Downloaded generic-array v0.14.6
  Downloaded itoa v1.0.3
  Downloaded once_cell v1.13.1
  Downloaded jobserver v0.1.24
  Downloaded rand v0.8.5
  Downloaded rustc_version v0.4.0
  Downloaded local-channel v0.1.3
  Downloaded serde_json v1.0.85
  Downloaded sha1 v0.10.1
  Downloaded tokio-util v0.7.3
  Downloaded zstd-safe v5.0.2+zstd.1.5.2
  Downloaded unicode-normalization v0.1.21
  Downloaded bitflags v1.3.2
  Downloaded actix-rt v2.7.0
  Downloaded actix-utils v3.0.0
  Downloaded slab v0.4.7
  Downloaded ryu v1.0.11
  Downloaded serde_urlencoded v0.7.1
  Downloaded actix-router v0.5.0
  Downloaded bytes v1.2.1
  Downloaded ahash v0.7.6
  Downloaded alloc-no-stdlib v2.0.3
  Downloaded zstd v0.11.2+zstd.1.5.2
  Downloaded tinyvec_macros v0.1.0
  Downloaded form_urlencoded v1.0.1
  Downloaded cpufeatures v0.2.4
  Downloaded cookie v0.16.0
  Downloaded convert_case v0.4.0
  Downloaded derive_more v0.99.17
  Downloaded actix-codec v0.5.0
  Downloaded futures-sink v0.3.23
  Downloaded actix-server v2.1.1
  Downloaded crypto-common v0.1.6
  Downloaded actix-web-codegen v4.0.1
  Downloaded h2 v0.3.14
  Downloaded httparse v1.7.1
  Downloaded futures-util v0.3.23
  Downloaded num_cpus v1.13.1
  Downloaded markdown v0.3.0
  Downloaded local-waker v0.1.3
  Downloaded time-macros v0.2.4
  Downloaded percent-encoding v2.1.0
  Downloaded scopeguard v1.1.0
  Downloaded smallvec v1.9.0
  Downloaded typenum v1.15.0
  Downloaded tracing-core v0.1.29
  Downloaded unicode-bidi v0.3.8
  Downloaded tinyvec v1.6.0
  Downloaded url v2.2.2
  Downloaded signal-hook-registry v1.4.0
  Downloaded socket2 v0.4.6
  Downloaded semver v1.0.13
  Downloaded rand_core v0.6.3
  Downloaded flate2 v1.0.24
  Downloaded matches v0.1.9
  Downloaded fnv v1.0.7
  Downloaded block-buffer v0.10.2
  Downloaded ppv-lite86 v0.2.16
  Downloaded pin-project-lite v0.2.9
  Downloaded mio v0.8.4
  Downloaded num_threads v0.1.6
  Downloaded paste v1.0.8
  Downloaded language-tags v0.3.2
  Downloaded indexmap v1.9.1
  Downloaded mime v0.3.16
  Downloaded rand_chacha v0.3.1
  Downloaded version_check v0.9.4
  Downloaded log v0.4.17
  Downloaded parking_lot_core v0.9.3
  Downloaded lock_api v0.4.8
  Downloaded getrandom v0.2.7
  Downloaded tracing v0.1.36
  Downloaded digest v0.10.3
  Downloaded http v0.2.8
  Downloaded alloc-stdlib v0.2.1
  Downloaded futures-core v0.3.23
  Downloaded time v0.3.14
  Downloaded idna v0.2.3
  Downloaded actix-http v3.2.1
  Downloaded actix-web v4.1.0
  Downloaded brotli-decompressor v2.3.2
  Downloaded regex v1.6.0
  Downloaded regex-syntax v0.6.27
  Downloaded pipeline v0.5.0
  Downloaded memchr v2.5.0
  Downloaded unicode-ident v1.0.3
  Downloaded cc v1.0.73
  Downloaded aho-corasick v0.7.18
  Downloaded quote v1.0.21
  Downloaded pin-utils v0.1.0
  Downloaded cfg-if v1.0.0
  Downloaded base64 v0.13.0
  Downloaded proc-macro2 v1.0.43
  Downloaded adler v1.0.2
  Downloaded lazy_static v1.4.0
  Downloaded hashbrown v0.12.3
  Downloaded serde v1.0.144
  Downloaded autocfg v1.1.0
  Downloaded parking_lot v0.12.1
  Downloaded syn v1.0.99
  Downloaded tokio v1.20.1
  Downloaded encoding_rs v0.8.31
  Downloaded zstd-sys v2.0.1+zstd.1.5.2
  Downloaded libc v0.2.132
  Downloaded brotli v3.3.4
   Compiling libc v0.2.132
   Compiling cfg-if v1.0.0
   Compiling memchr v2.5.0
   Compiling autocfg v1.1.0
   Compiling log v0.4.17
   Compiling version_check v0.9.4
   Compiling pin-project-lite v0.2.9
   Compiling futures-core v0.3.23
   Compiling bytes v1.2.1
   Compiling parking_lot_core v0.9.3
   Compiling once_cell v1.13.1
   Compiling smallvec v1.9.0
   Compiling scopeguard v1.1.0
   Compiling serde v1.0.144
   Compiling proc-macro2 v1.0.43
   Compiling itoa v1.0.3
   Compiling typenum v1.15.0
   Compiling quote v1.0.21
   Compiling unicode-ident v1.0.3
   Compiling futures-task v0.3.23
   Compiling syn v1.0.99
   Compiling futures-util v0.3.23
   Compiling pin-utils v0.1.0
   Compiling futures-sink v0.3.23
   Compiling percent-encoding v2.1.0
   Compiling alloc-no-stdlib v2.0.3
   Compiling local-waker v0.1.3
   Compiling tinyvec_macros v0.1.0
   Compiling matches v0.1.9
   Compiling crc32fast v1.3.2
   Compiling zstd-safe v5.0.2+zstd.1.5.2
   Compiling fnv v1.0.7
   Compiling regex-syntax v0.6.27
   Compiling ppv-lite86 v0.2.16
   Compiling paste v1.0.8
   Compiling adler v1.0.2
   Compiling httparse v1.7.1
   Compiling hashbrown v0.12.3
   Compiling encoding_rs v0.8.31
   Compiling convert_case v0.4.0
   Compiling firestorm v0.5.1
   Compiling time-macros v0.2.4
   Compiling serde_json v1.0.85
   Compiling num_threads v0.1.6
   Compiling unicode-bidi v0.3.8
   Compiling bitflags v1.3.2
   Compiling ryu v1.0.11
   Compiling mime v0.3.16
   Compiling language-tags v0.3.2
   Compiling base64 v0.13.0
   Compiling httpdate v1.0.2
   Compiling lazy_static v1.4.0
   Compiling pipeline v0.5.0
   Compiling tinyvec v1.6.0
   Compiling actix-utils v3.0.0
   Compiling alloc-stdlib v0.2.1
   Compiling form_urlencoded v1.0.1
   Compiling tracing-core v0.1.29
   Compiling miniz_oxide v0.5.3
   Compiling http v0.2.8
   Compiling bytestring v1.1.0
   Compiling generic-array v0.14.6
   Compiling ahash v0.7.6
   Compiling cookie v0.16.0
   Compiling lock_api v0.4.8
   Compiling tokio v1.20.1
   Compiling slab v0.4.7
   Compiling indexmap v1.9.1
   Compiling brotli-decompressor v2.3.2
   Compiling tracing v0.1.36
   Compiling flate2 v1.0.24
   Compiling aho-corasick v0.7.18
   Compiling unicode-normalization v0.1.21
   Compiling actix-service v2.0.2
   Compiling socket2 v0.4.6
   Compiling signal-hook-registry v1.4.0
   Compiling mio v0.8.4
   Compiling getrandom v0.2.7
   Compiling num_cpus v1.13.1
   Compiling jobserver v0.1.24
   Compiling brotli v3.3.4
   Compiling idna v0.2.3
   Compiling rand_core v0.6.3
   Compiling parking_lot v0.12.1
   Compiling regex v1.6.0
   Compiling cc v1.0.73
   Compiling rand_chacha v0.3.1
   Compiling rand v0.8.5
   Compiling time v0.3.14
   Compiling url v2.2.2
   Compiling local-channel v0.1.3
   Compiling markdown v0.3.0
   Compiling zstd-sys v2.0.1+zstd.1.5.2
   Compiling block-buffer v0.10.2
   Compiling crypto-common v0.1.6
   Compiling digest v0.10.3
   Compiling sha1 v0.10.1
   Compiling actix-router v0.5.0
   Compiling serde_urlencoded v0.7.1
   Compiling tokio-util v0.7.3
   Compiling actix-rt v2.7.0
   Compiling actix-server v2.1.1
   Compiling actix-codec v0.5.0
   Compiling h2 v0.3.14
   Compiling derive_more v0.99.17
   Compiling actix-web-codegen v4.0.1
   Compiling actix-macros v0.2.3
   Compiling zstd v0.11.2+zstd.1.5.2
   Compiling actix-http v3.2.1
   Compiling actix-web v4.1.0
   Compiling rcv v0.1.0 (/usr/src/app)
    Finished release [optimized] target(s) in 1m 44s
Removing intermediate container 533c57b89b90
 ---> 433b7b6c53f5
Step 10/14 : FROM arm32v7/rust:1.63
 ---> d0646b193e07
Step 11/14 : WORKDIR /usr/src/app
 ---> Using cache
 ---> d3245c5f0d73
Step 12/14 : COPY --from=builder /usr/src/app/target/armv7-unknown-linux-gnueabihf/release/rcv /usr/src/app
 ---> Using cache
 ---> b1847312a2fe
Step 13/14 : COPY --from=builder /usr/src/app/cv.md /usr/src/app
 ---> 67c24d175043
Step 14/14 : CMD ["/usr/src/app/rcv"]
 ---> [Warning] The requested image's platform (linux/arm/v7) does not match the detected host platform (linux/amd64) and no specific platform was requested
 ---> Running in d20e832fdb10
Removing intermediate container d20e832fdb10
 ---> 4236fbee04d0
Successfully built 4236fbee04d0


❯ docker tag 4236fbee04d0 kainlite/rcv:armv7-2
❯ docker push kainlite/rcv:armv7-2
The push refers to repository [docker.io/kainlite/rcv]
e6c497a8be6a: Pushed
41cb37c86eb4: Layer already exists
659939c01292: Layer already exists
54a3ca211559: Layer already exists
1f4f3f20d97e: Layer already exists
d55191df9034: Layer already exists
403a5f26ee02: Layer already exists
6c3d1ef471ee: Layer already exists
b74e98d1b921: Layer already exists
armv7-2: digest: sha256:86be73465a5e4819b97d4aafe8195b977a4e9b1d6ff3780315972ad23223f812 size: 2216

```
<br />

### lets quickly review the manifests
The manifests are fairly simple, you can see them there, as you can see we are restricting the user and privileges of
the container using the SecurityContext of the pod and the container.
```elixir
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rcv-deployment
  labels:
    name: rcv
spec:
  replicas: 3
  selector:
    matchLabels:
      name: rcv
  template:
    metadata:
      labels:
        name: rcv
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
      containers:
      - name: rcv
        image: kainlite/rcv:armv7-2
        ports:
        - containerPort: 8080
        securityContext:
          allowPrivilegeEscalation: false
---
apiVersion: v1
kind: Service
metadata:
  name: rcv
spec:
  selector:
    name: rcv
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rcv-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: "rcv.techsquad.rocks"
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: rcv
            port:
              number: 8080

```
<br />

#### Deploying it
Assuming you already have a cluster up and running, this can be deployed like this, you will see a deployment, a service
and the ingress resources, you will also need to have a DNS entry if you want to use it like I did there:
```elixir
❯ kubectl apply -f manifests/
deployment.apps/rcv-deployment created
ingress.networking.k8s.io/rcv-ingress created
service/rcv created

❯ kubectl get pods
NAME                              READY   STATUS    RESTARTS   AGE
rcv-deployment-55588c6f68-5gshl   1/1     Running   0          7s
rcv-deployment-55588c6f68-d7r84   1/1     Running   0          7s
rcv-deployment-55588c6f68-zw27j   1/1     Running   0          7s

❯ kubectl get ingress
NAME          CLASS   HOSTS                 ADDRESS      PORTS   AGE
rcv-ingress   nginx   rcv.techsquad.rocks   10.0.0.104   80      12s

```
<br />

#### Extra

You can see it running [here](http://rcv.techsquad.rocks/), a very basic HTML Curriculum vitae, if it doesn't work don't
worry too much, I'm planning on upgrading the cluster and adding https to the example for another article, it will
eventually be back up, however if you want to see it anyway, try running the example and building the image on your
machine.

For more details and to see how everything fits together I encourage you to clone the repo, test it, and modify it to
make your own.
<br />

### Cleaning up
To clean up the resources you can do this:
```elixir
❯ kubectl delete -f manifests
deployment.apps "rcv-deployment" deleted
ingress.networking.k8s.io "rcv-ingress" deleted
service "rcv" deleted

```
<br />

#### **Closing notes**
Be sure to check the links if you want to learn more about the examples, I hope you enjoyed it, 
see you on [twitter](https://twitter.com/kainlite) or [github](https://github.com/kainlite)!

The source for this article is [here](https://github.com/kainlite/rcv/)
<br />

### Errata

If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io)
and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Running Rust on ARM32v7 K3S Oracle cluster",
  author: "Gabriel Garrido",
  description: "In this article we will explore how to create a sample rust project and Dockerfile to run it on ARM32v7...",
  tags: ~w(kubernetes rust arm),
  published: true,
  image: "rust.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### Traduccion en proceso

![rust](/images/rust.png"){:class="mx-auto"}

#### **Introduction**

In this article we will explore how to create a sample [Rust](https://www.rust-lang.org/) project and Dockerfile to 
run it on [ARM32v7 architectures](https://github.com/docker-library/official-images#architectures-other-than-amd64).
<br />

To configure the cluster I used this project [k3s-oci-cluster](https://github.com/garutilorenzo/k3s-oci-cluster), since
Oracle is providing a very generous free tier for ARM workloads you might as well give it a try, or maybe use your 
raspberry pi cluster.
<br />

The source for this article is here [RCV](https://github.com/kainlite/rcv/) and the docker image is 
[here](https://hub.docker.com/repository/docker/kainlite/rcv).
<br />

##### **Prerequisites**

The cluster is optional if you have any device using linux on ARM32v7 or ARM64v8 you should be able to use the docker
examples.
- [k3s-oci-cluster](https://github.com/garutilorenzo/k3s-oci-cluster)
- [Docker](https://hub.docker.com/?overlay=onboarding)
- [Rust](https://www.rust-lang.org/tools/install)

<br />

### Let's jump to the example

#### Creating the project

Lets create a new Rust project with Cargo, as you might notice we will get a very basic project that will help us get 
get started:
```elixir
❯ cargo new rcv
     Created binary (application) `rcv` package
     
❯ cd rcv
❯ ls
Cargo.toml  src

```
<br />

#### Our example and the dependencies
I was thinking in processing markdown files and show them as html, so that's basically what the code does, it's far from
optimal but it is good enough to illustrate the example, first lets add some crates for the webserver 
([Actix](https://actix.rs/docs/server/)) and converting [markdown to html](https://github.com/johannhof/markdown.rs).

```elixir
[package]
name = "rcv"
version = "0.1.0"
edition = "2021"

# See more keys and their definitions at https://doc.rust-lang.org/cargo/reference/manifest.html

[dependencies]
actix-web = "4"
markdown = "0.3"
```
<br />

#### Lets add some code
This simple snippet only listens for `GET` requests to `/` and logs a line with the unix timestamp and IP and returns 
the contents of the file `cv.md` which is my Curriculum Vitae.
```elixir
use actix_web::{get, App, HttpResponse, HttpServer};
use actix_web::{HttpRequest, Responder};
use std::fs;
use std::time::{Duration, SystemTime};

extern crate markdown;

#[get("/")]
async fn root(req: HttpRequest) -> impl Responder {
    let con_info = req.connection_info();
    let peer_ip = &req.peer_addr().unwrap().to_string();

    let ip = con_info
        .realip_remote_addr()
        .unwrap()
        .split(':')
        .next()
        .unwrap_or(peer_ip);

    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or(Duration::from_millis(0));

    println!("[{}][{}]: Processing cv request...", now.as_secs(), ip);

    let data = fs::read_to_string("./cv.md").expect("Unable to read file");
    let html: String = markdown::to_html(&data);

    HttpResponse::Ok().body(html)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| App::new().service(root))
        .bind(("0.0.0.0", 8080))?
        .run()
        .await
}

```

#### Example logs
Example logs 
```elixir
[1662136558][127.0.0.1]: Processing cv request...
[1662136591][127.0.0.1]: Processing cv request...

```

At this point we have enough to run and test locally, but what about other architectures? (I'm running on linux-amd64),
you can test it locally if you want running `cargo run`.
<br />

#### ARM32v7 Dockerfile
This Dockerfile can be optimized and secured in many ways, but for the sake of simplicity it is good enough to start 
working on something, also we will provide the security at runtime via kubernetes APIs.
We need to consider two things here, first we need to create an ARM32v7 binary using Rust, then we need a Docker image
for that architecture so that's basically what the Dockerfile does.
```elixir
## builder
FROM rust:1.63.0 as builder

RUN apt update && apt upgrade -y
RUN apt install -y g++-arm-linux-gnueabihf libc6-dev-armhf-cross

RUN rustup target add armv7-unknown-linux-gnueabihf
RUN rustup toolchain install stable-armv7-unknown-linux-gnueabihf

WORKDIR /usr/src/app

COPY . .

ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc \
    CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++

RUN cargo build --target armv7-unknown-linux-gnueabihf --release

## release
FROM arm32v7/rust:1.63

WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/target/armv7-unknown-linux-gnueabihf/release/rcv /usr/src/app
COPY --from=builder /usr/src/app/cv.md /usr/src/app

CMD ["/usr/src/app/rcv"]

```
<br />

#### Building and pushing (docker image)
So lets build it and push it [here](https://hub.docker.com/repository/docker/kainlite/rcv).
```elixir
❯ docker build . -f Dockerfile.armv7
Sending build context to Docker daemon  894.2MB
Step 1/14 : FROM rust:1.63.0 as builder
 ---> 2a7d3c69bbf0
Step 2/14 : RUN apt update && apt upgrade -y
 ---> Using cache
 ---> 3a3120a0cb99
Step 3/14 : RUN apt install -y g++-arm-linux-gnueabihf libc6-dev-armhf-cross
 ---> Using cache
 ---> 78e25363f688
Step 4/14 : RUN rustup target add armv7-unknown-linux-gnueabihf
 ---> Using cache
 ---> dc97e983b392
Step 5/14 : RUN rustup toolchain install stable-armv7-unknown-linux-gnueabihf
 ---> Using cache
 ---> a1266f5b3cfa
Step 6/14 : WORKDIR /usr/src/app
 ---> Using cache
 ---> ff1efb7d4bce
Step 7/14 : COPY . .
 ---> a0ceff61a547
Step 8/14 : ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc     CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc     CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++
 ---> Running in 0249ca22cd26
Removing intermediate container 0249ca22cd26
 ---> a803cfa71e49
Step 9/14 : RUN cargo build --target armv7-unknown-linux-gnueabihf --release
 ---> Running in 533c57b89b90
    Updating crates.io index
 Downloading crates ...
  Downloaded actix-macros v0.2.3
  Downloaded firestorm v0.5.1
  Downloaded bytestring v1.1.0
  Downloaded futures-task v0.3.23
  Downloaded actix-service v2.0.2
  Downloaded crc32fast v1.3.2
  Downloaded httpdate v1.0.2
  Downloaded miniz_oxide v0.5.3
  Downloaded generic-array v0.14.6
  Downloaded itoa v1.0.3
  Downloaded once_cell v1.13.1
  Downloaded jobserver v0.1.24
  Downloaded rand v0.8.5
  Downloaded rustc_version v0.4.0
  Downloaded local-channel v0.1.3
  Downloaded serde_json v1.0.85
  Downloaded sha1 v0.10.1
  Downloaded tokio-util v0.7.3
  Downloaded zstd-safe v5.0.2+zstd.1.5.2
  Downloaded unicode-normalization v0.1.21
  Downloaded bitflags v1.3.2
  Downloaded actix-rt v2.7.0
  Downloaded actix-utils v3.0.0
  Downloaded slab v0.4.7
  Downloaded ryu v1.0.11
  Downloaded serde_urlencoded v0.7.1
  Downloaded actix-router v0.5.0
  Downloaded bytes v1.2.1
  Downloaded ahash v0.7.6
  Downloaded alloc-no-stdlib v2.0.3
  Downloaded zstd v0.11.2+zstd.1.5.2
  Downloaded tinyvec_macros v0.1.0
  Downloaded form_urlencoded v1.0.1
  Downloaded cpufeatures v0.2.4
  Downloaded cookie v0.16.0
  Downloaded convert_case v0.4.0
  Downloaded derive_more v0.99.17
  Downloaded actix-codec v0.5.0
  Downloaded futures-sink v0.3.23
  Downloaded actix-server v2.1.1
  Downloaded crypto-common v0.1.6
  Downloaded actix-web-codegen v4.0.1
  Downloaded h2 v0.3.14
  Downloaded httparse v1.7.1
  Downloaded futures-util v0.3.23
  Downloaded num_cpus v1.13.1
  Downloaded markdown v0.3.0
  Downloaded local-waker v0.1.3
  Downloaded time-macros v0.2.4
  Downloaded percent-encoding v2.1.0
  Downloaded scopeguard v1.1.0
  Downloaded smallvec v1.9.0
  Downloaded typenum v1.15.0
  Downloaded tracing-core v0.1.29
  Downloaded unicode-bidi v0.3.8
  Downloaded tinyvec v1.6.0
  Downloaded url v2.2.2
  Downloaded signal-hook-registry v1.4.0
  Downloaded socket2 v0.4.6
  Downloaded semver v1.0.13
  Downloaded rand_core v0.6.3
  Downloaded flate2 v1.0.24
  Downloaded matches v0.1.9
  Downloaded fnv v1.0.7
  Downloaded block-buffer v0.10.2
  Downloaded ppv-lite86 v0.2.16
  Downloaded pin-project-lite v0.2.9
  Downloaded mio v0.8.4
  Downloaded num_threads v0.1.6
  Downloaded paste v1.0.8
  Downloaded language-tags v0.3.2
  Downloaded indexmap v1.9.1
  Downloaded mime v0.3.16
  Downloaded rand_chacha v0.3.1
  Downloaded version_check v0.9.4
  Downloaded log v0.4.17
  Downloaded parking_lot_core v0.9.3
  Downloaded lock_api v0.4.8
  Downloaded getrandom v0.2.7
  Downloaded tracing v0.1.36
  Downloaded digest v0.10.3
  Downloaded http v0.2.8
  Downloaded alloc-stdlib v0.2.1
  Downloaded futures-core v0.3.23
  Downloaded time v0.3.14
  Downloaded idna v0.2.3
  Downloaded actix-http v3.2.1
  Downloaded actix-web v4.1.0
  Downloaded brotli-decompressor v2.3.2
  Downloaded regex v1.6.0
  Downloaded regex-syntax v0.6.27
  Downloaded pipeline v0.5.0
  Downloaded memchr v2.5.0
  Downloaded unicode-ident v1.0.3
  Downloaded cc v1.0.73
  Downloaded aho-corasick v0.7.18
  Downloaded quote v1.0.21
  Downloaded pin-utils v0.1.0
  Downloaded cfg-if v1.0.0
  Downloaded base64 v0.13.0
  Downloaded proc-macro2 v1.0.43
  Downloaded adler v1.0.2
  Downloaded lazy_static v1.4.0
  Downloaded hashbrown v0.12.3
  Downloaded serde v1.0.144
  Downloaded autocfg v1.1.0
  Downloaded parking_lot v0.12.1
  Downloaded syn v1.0.99
  Downloaded tokio v1.20.1
  Downloaded encoding_rs v0.8.31
  Downloaded zstd-sys v2.0.1+zstd.1.5.2
  Downloaded libc v0.2.132
  Downloaded brotli v3.3.4
   Compiling libc v0.2.132
   Compiling cfg-if v1.0.0
   Compiling memchr v2.5.0
   Compiling autocfg v1.1.0
   Compiling log v0.4.17
   Compiling version_check v0.9.4
   Compiling pin-project-lite v0.2.9
   Compiling futures-core v0.3.23
   Compiling bytes v1.2.1
   Compiling parking_lot_core v0.9.3
   Compiling once_cell v1.13.1
   Compiling smallvec v1.9.0
   Compiling scopeguard v1.1.0
   Compiling serde v1.0.144
   Compiling proc-macro2 v1.0.43
   Compiling itoa v1.0.3
   Compiling typenum v1.15.0
   Compiling quote v1.0.21
   Compiling unicode-ident v1.0.3
   Compiling futures-task v0.3.23
   Compiling syn v1.0.99
   Compiling futures-util v0.3.23
   Compiling pin-utils v0.1.0
   Compiling futures-sink v0.3.23
   Compiling percent-encoding v2.1.0
   Compiling alloc-no-stdlib v2.0.3
   Compiling local-waker v0.1.3
   Compiling tinyvec_macros v0.1.0
   Compiling matches v0.1.9
   Compiling crc32fast v1.3.2
   Compiling zstd-safe v5.0.2+zstd.1.5.2
   Compiling fnv v1.0.7
   Compiling regex-syntax v0.6.27
   Compiling ppv-lite86 v0.2.16
   Compiling paste v1.0.8
   Compiling adler v1.0.2
   Compiling httparse v1.7.1
   Compiling hashbrown v0.12.3
   Compiling encoding_rs v0.8.31
   Compiling convert_case v0.4.0
   Compiling firestorm v0.5.1
   Compiling time-macros v0.2.4
   Compiling serde_json v1.0.85
   Compiling num_threads v0.1.6
   Compiling unicode-bidi v0.3.8
   Compiling bitflags v1.3.2
   Compiling ryu v1.0.11
   Compiling mime v0.3.16
   Compiling language-tags v0.3.2
   Compiling base64 v0.13.0
   Compiling httpdate v1.0.2
   Compiling lazy_static v1.4.0
   Compiling pipeline v0.5.0
   Compiling tinyvec v1.6.0
   Compiling actix-utils v3.0.0
   Compiling alloc-stdlib v0.2.1
   Compiling form_urlencoded v1.0.1
   Compiling tracing-core v0.1.29
   Compiling miniz_oxide v0.5.3
   Compiling http v0.2.8
   Compiling bytestring v1.1.0
   Compiling generic-array v0.14.6
   Compiling ahash v0.7.6
   Compiling cookie v0.16.0
   Compiling lock_api v0.4.8
   Compiling tokio v1.20.1
   Compiling slab v0.4.7
   Compiling indexmap v1.9.1
   Compiling brotli-decompressor v2.3.2
   Compiling tracing v0.1.36
   Compiling flate2 v1.0.24
   Compiling aho-corasick v0.7.18
   Compiling unicode-normalization v0.1.21
   Compiling actix-service v2.0.2
   Compiling socket2 v0.4.6
   Compiling signal-hook-registry v1.4.0
   Compiling mio v0.8.4
   Compiling getrandom v0.2.7
   Compiling num_cpus v1.13.1
   Compiling jobserver v0.1.24
   Compiling brotli v3.3.4
   Compiling idna v0.2.3
   Compiling rand_core v0.6.3
   Compiling parking_lot v0.12.1
   Compiling regex v1.6.0
   Compiling cc v1.0.73
   Compiling rand_chacha v0.3.1
   Compiling rand v0.8.5
   Compiling time v0.3.14
   Compiling url v2.2.2
   Compiling local-channel v0.1.3
   Compiling markdown v0.3.0
   Compiling zstd-sys v2.0.1+zstd.1.5.2
   Compiling block-buffer v0.10.2
   Compiling crypto-common v0.1.6
   Compiling digest v0.10.3
   Compiling sha1 v0.10.1
   Compiling actix-router v0.5.0
   Compiling serde_urlencoded v0.7.1
   Compiling tokio-util v0.7.3
   Compiling actix-rt v2.7.0
   Compiling actix-server v2.1.1
   Compiling actix-codec v0.5.0
   Compiling h2 v0.3.14
   Compiling derive_more v0.99.17
   Compiling actix-web-codegen v4.0.1
   Compiling actix-macros v0.2.3
   Compiling zstd v0.11.2+zstd.1.5.2
   Compiling actix-http v3.2.1
   Compiling actix-web v4.1.0
   Compiling rcv v0.1.0 (/usr/src/app)
    Finished release [optimized] target(s) in 1m 44s
Removing intermediate container 533c57b89b90
 ---> 433b7b6c53f5
Step 10/14 : FROM arm32v7/rust:1.63
 ---> d0646b193e07
Step 11/14 : WORKDIR /usr/src/app
 ---> Using cache
 ---> d3245c5f0d73
Step 12/14 : COPY --from=builder /usr/src/app/target/armv7-unknown-linux-gnueabihf/release/rcv /usr/src/app
 ---> Using cache
 ---> b1847312a2fe
Step 13/14 : COPY --from=builder /usr/src/app/cv.md /usr/src/app
 ---> 67c24d175043
Step 14/14 : CMD ["/usr/src/app/rcv"]
 ---> [Warning] The requested image's platform (linux/arm/v7) does not match the detected host platform (linux/amd64) and no specific platform was requested
 ---> Running in d20e832fdb10
Removing intermediate container d20e832fdb10
 ---> 4236fbee04d0
Successfully built 4236fbee04d0


❯ docker tag 4236fbee04d0 kainlite/rcv:armv7-2
❯ docker push kainlite/rcv:armv7-2
The push refers to repository [docker.io/kainlite/rcv]
e6c497a8be6a: Pushed
41cb37c86eb4: Layer already exists
659939c01292: Layer already exists
54a3ca211559: Layer already exists
1f4f3f20d97e: Layer already exists
d55191df9034: Layer already exists
403a5f26ee02: Layer already exists
6c3d1ef471ee: Layer already exists
b74e98d1b921: Layer already exists
armv7-2: digest: sha256:86be73465a5e4819b97d4aafe8195b977a4e9b1d6ff3780315972ad23223f812 size: 2216

```
<br />

### lets quickly review the manifests
The manifests are fairly simple, you can see them there, as you can see we are restricting the user and privileges of
the container using the SecurityContext of the pod and the container.
```elixir
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rcv-deployment
  labels:
    name: rcv
spec:
  replicas: 3
  selector:
    matchLabels:
      name: rcv
  template:
    metadata:
      labels:
        name: rcv
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
      containers:
      - name: rcv
        image: kainlite/rcv:armv7-2
        ports:
        - containerPort: 8080
        securityContext:
          allowPrivilegeEscalation: false
---
apiVersion: v1
kind: Service
metadata:
  name: rcv
spec:
  selector:
    name: rcv
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rcv-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: "rcv.techsquad.rocks"
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: rcv
            port:
              number: 8080

```
<br />

#### Deploying it
Assuming you already have a cluster up and running, this can be deployed like this, you will see a deployment, a service
and the ingress resources, you will also need to have a DNS entry if you want to use it like I did there:
```elixir
❯ kubectl apply -f manifests/
deployment.apps/rcv-deployment created
ingress.networking.k8s.io/rcv-ingress created
service/rcv created

❯ kubectl get pods
NAME                              READY   STATUS    RESTARTS   AGE
rcv-deployment-55588c6f68-5gshl   1/1     Running   0          7s
rcv-deployment-55588c6f68-d7r84   1/1     Running   0          7s
rcv-deployment-55588c6f68-zw27j   1/1     Running   0          7s

❯ kubectl get ingress
NAME          CLASS   HOSTS                 ADDRESS      PORTS   AGE
rcv-ingress   nginx   rcv.techsquad.rocks   10.0.0.104   80      12s

```
<br />

#### Extra

You can see it running [here](http://rcv.techsquad.rocks/), a very basic HTML Curriculum vitae, if it doesn't work don't
worry too much, I'm planning on upgrading the cluster and adding https to the example for another article, it will
eventually be back up, however if you want to see it anyway, try running the example and building the image on your
machine.

For more details and to see how everything fits together I encourage you to clone the repo, test it, and modify it to
make your own.
<br />

### Cleaning up
To clean up the resources you can do this:
```elixir
❯ kubectl delete -f manifests
deployment.apps "rcv-deployment" deleted
ingress.networking.k8s.io "rcv-ingress" deleted
service "rcv" deleted

```
<br />

#### **Closing notes**
Be sure to check the links if you want to learn more about the examples, I hope you enjoyed it, 
see you on [twitter](https://twitter.com/kainlite) or [github](https://github.com/kainlite)!

The source for this article is [here](https://github.com/kainlite/rcv/)
<br />

### Errata

If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io)
and the [sources here](https://github.com/kainlite/blog)

<br />
