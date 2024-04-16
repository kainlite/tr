%{
  title: "Running Rust on ARM32v7 via QEMU",
  author: "Gabriel Garrido",
  description: "In this article we will explore how to use QEMU to run emulating the ARM32v7 architecture to build and
  run a rust project...",
  tags: ~w(rust arm linux),
  published: true,
  image: "rust.png"
}
---

![rust](/images/rust.jpg"){:class="mx-auto"}

#### **Introduction**

In this article we will explore how to use [QEMU](https://www.qemu.org/download/#linux) to run emulating the ARM32v7 
architecture to build and run [Rust](https://www.rust-lang.org/) code like if it was a native 
[ARM32v7 architecture](https://github.com/docker-library/official-images#architectures-other-than-amd64).
<br />

There are some drawbacks and performance considerations when using this approach, it can be simpler but way slower for
big projects.
<br />

The source for this article is here [RCV](https://github.com/kainlite/rcv/) and the docker image is 
[here](https://hub.docker.com/repository/docker/kainlite/rcv).
<br />

This article can be considered a part 2 of 
[Running rust on ARM32v7K3S Oracle cluster](https://techsquad.rocks/blog/rust_on_arm32v7/) 
so we will not be creating the rust project and all that here, but focusing on building and running the project.
<br />

##### **Prerequisites**

- [Docker](https://hub.docker.com/?overlay=onboarding)
- [Buildah](https://github.com/containers/buildah/blob/main/install.md)
- [QEMU](https://www.qemu.org/download/#linux)
- [Rust](https://www.rust-lang.org/tools/install)

<br />

### Let's jump to the example

#### The new Dockerfile
You will notice that this [Dockerfile](https://raw.githubusercontent.com/kainlite/rcv/master/Dockerfile.armv7v2) 
is way simpler than the ones from the previous article, since it runs natively
as ARM32v7, the main difference is the base image being `arm32v7/rust:1.63.0`, this can be further extended for more
architectures, see this [article](https://devopstales.github.io/home/running_and_building_multi_arch_containers/) for 
more information.
```elixir
## builder
FROM arm32v7/rust:1.63.0 as builder

RUN apt update && apt upgrade -y

WORKDIR /usr/src/app

COPY . .

RUN cargo build --release

## release
FROM arm32v7/rust:1.63

WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/target/release/rcv /usr/src/app
COPY --from=builder /usr/src/app/cv.md /usr/src/app

CMD ["/usr/src/app/rcv"]

```
<br />

#### Last steps for QEMU/Docker
After installing the required packages you will still need to perform some simple steps in order for it to work with
docker and buildah, the first command is needed for docker to be able to use the required QEMU emulation and the second
is just to validate that everything works fine
```elixir
❯ docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
Setting /usr/bin/qemu-alpha-static as binfmt interpreter for alpha
Setting /usr/bin/qemu-arm-static as binfmt interpreter for arm
Setting /usr/bin/qemu-armeb-static as binfmt interpreter for armeb
Setting /usr/bin/qemu-sparc-static as binfmt interpreter for sparc
Setting /usr/bin/qemu-sparc32plus-static as binfmt interpreter for sparc32plus
Setting /usr/bin/qemu-sparc64-static as binfmt interpreter for sparc64
Setting /usr/bin/qemu-ppc-static as binfmt interpreter for ppc
Setting /usr/bin/qemu-ppc64-static as binfmt interpreter for ppc64
Setting /usr/bin/qemu-ppc64le-static as binfmt interpreter for ppc64le
Setting /usr/bin/qemu-m68k-static as binfmt interpreter for m68k
Setting /usr/bin/qemu-mips-static as binfmt interpreter for mips
Setting /usr/bin/qemu-mipsel-static as binfmt interpreter for mipsel
Setting /usr/bin/qemu-mipsn32-static as binfmt interpreter for mipsn32
Setting /usr/bin/qemu-mipsn32el-static as binfmt interpreter for mipsn32el
Setting /usr/bin/qemu-mips64-static as binfmt interpreter for mips64
Setting /usr/bin/qemu-mips64el-static as binfmt interpreter for mips64el
Setting /usr/bin/qemu-sh4-static as binfmt interpreter for sh4
Setting /usr/bin/qemu-sh4eb-static as binfmt interpreter for sh4eb
Setting /usr/bin/qemu-s390x-static as binfmt interpreter for s390x
Setting /usr/bin/qemu-aarch64-static as binfmt interpreter for aarch64
Setting /usr/bin/qemu-aarch64_be-static as binfmt interpreter for aarch64_be
Setting /usr/bin/qemu-hppa-static as binfmt interpreter for hppa
Setting /usr/bin/qemu-riscv32-static as binfmt interpreter for riscv32
Setting /usr/bin/qemu-riscv64-static as binfmt interpreter for riscv64
Setting /usr/bin/qemu-xtensa-static as binfmt interpreter for xtensa
Setting /usr/bin/qemu-xtensaeb-static as binfmt interpreter for xtensaeb
Setting /usr/bin/qemu-microblaze-static as binfmt interpreter for microblaze
Setting /usr/bin/qemu-microblazeel-static as binfmt interpreter for microblazeel
Setting /usr/bin/qemu-or1k-static as binfmt interpreter for or1k
Setting /usr/bin/qemu-hexagon-static as binfmt interpreter for hexagon


❯ docker run --rm -t arm32v7/ubuntu uname -m
Unable to find image 'arm32v7/ubuntu:latest' locally
latest: Pulling from arm32v7/ubuntu
af25ea170fdc: Pull complete
Digest: sha256:7723f8c211cbc089f836e13136b35157ba572b61e0419d8f978917fca049db68
Status: Downloaded newer image for arm32v7/ubuntu:latest
WARNING: The requested image's platform (linux/arm/v7) does not match the detected host platform (linux/amd64) and no specific platform was requested
armv7l

```
<br />

##### Short names error
If you get an error about short names when pulling images add the following line to your `/etc/containers/registries.conf`
file
```elixir
unqualified-search-registries = ["docker.io"]

```
<br />

#### Lets build it
For the build we will use buildah because it is smarter than docker for this kind of scenarios.
```elixir
❯ buildah build -f Dockerfile.armv7v2 .
[1/2] STEP 1/5: FROM arm32v7/rust:1.63.0 AS builder
WARNING: image platform ({arm linux  [] v7}) does not match the expected platform ({amd64 linux  [] })
[1/2] STEP 2/5: RUN apt update && apt upgrade -y

WARNING: apt does not have a stable CLI interface. Use with caution in scripts.

Get:1 http://deb.debian.org/debian bullseye InRelease [116 kB]
Get:2 http://deb.debian.org/debian-security bullseye-security InRelease [48.4 kB]
Get:3 http://deb.debian.org/debian bullseye-updates InRelease [44.1 kB]
Get:4 http://deb.debian.org/debian bullseye/main armhf Packages [7949 kB]
Get:5 http://deb.debian.org/debian-security bullseye-security/main armhf Packages [175 kB]
Get:6 http://deb.debian.org/debian bullseye-updates/main armhf Packages [2608 B]
Fetched 8334 kB in 1min 11s (117 kB/s)
Reading package lists...
Building dependency tree...
Reading state information...
4 packages can be upgraded. Run 'apt list --upgradable' to see them.

WARNING: apt does not have a stable CLI interface. Use with caution in scripts.

Reading package lists...
Building dependency tree...
Reading state information...
Calculating upgrade...
The following packages will be upgraded:
  libxslt1-dev libxslt1.1 zlib1g zlib1g-dev
4 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Need to get 819 kB of archives.
After this operation, 6144 B of additional disk space will be used.
Get:1 http://deb.debian.org/debian-security bullseye-security/main armhf zlib1g-dev armhf 1:1.2.11.dfsg-2+deb11u2 [185 kB]
Get:2 http://deb.debian.org/debian-security bullseye-security/main armhf zlib1g armhf 1:1.2.11.dfsg-2+deb11u2 [85.0 kB]
Get:3 http://deb.debian.org/debian-security bullseye-security/main armhf libxslt1-dev armhf 1.1.34-4+deb11u1 [329 kB]
Get:4 http://deb.debian.org/debian-security bullseye-security/main armhf libxslt1.1 armhf 1.1.34-4+deb11u1 [221 kB]
debconf: delaying package configuration, since apt-utils is not installed
Fetched 819 kB in 5s (167 kB/s)
(Reading database ... 22525 files and directories currently installed.)
Preparing to unpack .../zlib1g-dev_1%3a1.2.11.dfsg-2+deb11u2_armhf.deb ...
Unpacking zlib1g-dev:armhf (1:1.2.11.dfsg-2+deb11u2) over (1:1.2.11.dfsg-2+deb11u1) ...
Preparing to unpack .../zlib1g_1%3a1.2.11.dfsg-2+deb11u2_armhf.deb ...
Unpacking zlib1g:armhf (1:1.2.11.dfsg-2+deb11u2) over (1:1.2.11.dfsg-2+deb11u1) ...
Setting up zlib1g:armhf (1:1.2.11.dfsg-2+deb11u2) ...
(Reading database ... 22525 files and directories currently installed.)
Preparing to unpack .../libxslt1-dev_1.1.34-4+deb11u1_armhf.deb ...
Unpacking libxslt1-dev:armhf (1.1.34-4+deb11u1) over (1.1.34-4) ...
Preparing to unpack .../libxslt1.1_1.1.34-4+deb11u1_armhf.deb ...
Unpacking libxslt1.1:armhf (1.1.34-4+deb11u1) over (1.1.34-4) ...
Setting up zlib1g-dev:armhf (1:1.2.11.dfsg-2+deb11u2) ...
Setting up libxslt1.1:armhf (1.1.34-4+deb11u1) ...
Setting up libxslt1-dev:armhf (1.1.34-4+deb11u1) ...
Processing triggers for libc-bin (2.31-13+deb11u3) ...
[1/2] STEP 3/5: WORKDIR /usr/src/app
[1/2] STEP 4/5: COPY . .
[1/2] STEP 5/5: RUN cargo build --release
    Updating crates.io index
 Downloading crates ...
  Downloaded aho-corasick v0.7.18
  Downloaded fnv v1.0.7
  Downloaded pin-project-lite v0.2.9
  Downloaded block-buffer v0.10.2
  Downloaded adler v1.0.2
  Downloaded markdown v0.3.0
  Downloaded actix-rt v2.7.0
  Downloaded actix-codec v0.5.0
  Downloaded lazy_static v1.4.0
  Downloaded futures-task v0.3.23
  Downloaded signal-hook-registry v1.4.0
  Downloaded pin-utils v0.1.0
  Downloaded actix-web v4.1.0
  Downloaded once_cell v1.13.1
  Downloaded semver v1.0.13
  Downloaded crc32fast v1.3.2
  Downloaded language-tags v0.3.2
  Downloaded getrandom v0.2.7
  Downloaded miniz_oxide v0.5.3
  Downloaded bytes v1.2.1
  Downloaded generic-array v0.14.6
  Downloaded rand_chacha v0.3.1
  Downloaded cfg-if v1.0.0
  Downloaded tokio v1.20.1
  Downloaded futures-util v0.3.23
  Downloaded flate2 v1.0.24
  Downloaded jobserver v0.1.24
  Downloaded time-macros v0.2.4
  Downloaded matches v0.1.9
  Downloaded sha1 v0.10.1
  Downloaded form_urlencoded v1.0.1
  Downloaded indexmap v1.9.1
  Downloaded base64 v0.13.0
  Downloaded local-waker v0.1.3
  Downloaded rand v0.8.5
  Downloaded parking_lot_core v0.9.3
  Downloaded actix-utils v3.0.0
  Downloaded crypto-common v0.1.6
  Downloaded firestorm v0.5.1
  Downloaded actix-http v3.2.1
  Downloaded local-channel v0.1.3
  Downloaded mime v0.3.16
  Downloaded parking_lot v0.12.1
  Downloaded futures-sink v0.3.23
  Downloaded derive_more v0.99.17
  Downloaded cc v1.0.73
  Downloaded bitflags v1.3.2
  Downloaded paste v1.0.8
  Downloaded brotli-decompressor v2.3.2
  Downloaded tinyvec_macros v0.1.0
  Downloaded h2 v0.3.14
  Downloaded log v0.4.17
  Downloaded tinyvec v1.6.0
  Downloaded ryu v1.0.11
  Downloaded tokio-util v0.7.3
  Downloaded actix-web-codegen v4.0.1
  Downloaded syn v1.0.99
  Downloaded cookie v0.16.0
  Downloaded itoa v1.0.3
  Downloaded pipeline v0.5.0
  Downloaded serde_urlencoded v0.7.1
  Downloaded num_threads v0.1.6
  Downloaded socket2 v0.4.6
  Downloaded scopeguard v1.1.0
  Downloaded percent-encoding v2.1.0
  Downloaded ppv-lite86 v0.2.16
  Downloaded mio v0.8.4
  Downloaded serde v1.0.144
  Downloaded num_cpus v1.13.1
  Downloaded quote v1.0.21
  Downloaded digest v0.10.3
  Downloaded bytestring v1.1.0
  Downloaded alloc-no-stdlib v2.0.3
  Downloaded proc-macro2 v1.0.43
  Downloaded http v0.2.8
  Downloaded tracing-core v0.1.29
  Downloaded unicode-normalization v0.1.21
  Downloaded zstd-safe v5.0.2+zstd.1.5.2
  Downloaded smallvec v1.9.0
  Downloaded httpdate v1.0.2
  Downloaded unicode-bidi v0.3.8
  Downloaded regex-syntax v0.6.27
  Downloaded regex v1.6.0
  Downloaded actix-router v0.5.0
  Downloaded version_check v0.9.4
  Downloaded ahash v0.7.6
  Downloaded memchr v2.5.0
  Downloaded url v2.2.2
  Downloaded tracing v0.1.36
  Downloaded autocfg v1.1.0
  Downloaded actix-server v2.1.1
  Downloaded zstd v0.11.2+zstd.1.5.2
  Downloaded slab v0.4.7
  Downloaded rand_core v0.6.3
  Downloaded actix-service v2.0.2
  Downloaded rustc_version v0.4.0
  Downloaded actix-macros v0.2.3
  Downloaded httparse v1.7.1
  Downloaded serde_json v1.0.85
  Downloaded lock_api v0.4.8
  Downloaded hashbrown v0.12.3
  Downloaded typenum v1.15.0
  Downloaded convert_case v0.4.0
  Downloaded unicode-ident v1.0.3
  Downloaded futures-core v0.3.23
  Downloaded alloc-stdlib v0.2.1
  Downloaded time v0.3.14
  Downloaded idna v0.2.3
  Downloaded libc v0.2.132
  Downloaded zstd-sys v2.0.1+zstd.1.5.2
  Downloaded brotli v3.3.4
  Downloaded encoding_rs v0.8.31
   Compiling libc v0.2.132
   Compiling cfg-if v1.0.0
   Compiling memchr v2.5.0
   Compiling autocfg v1.1.0
   Compiling log v0.4.17
   Compiling version_check v0.9.4
   Compiling pin-project-lite v0.2.9
   Compiling futures-core v0.3.23
   Compiling bytes v1.2.1
   Compiling once_cell v1.13.1
   Compiling parking_lot_core v0.9.3
   Compiling serde v1.0.144
   Compiling smallvec v1.9.0
   Compiling scopeguard v1.1.0
   Compiling proc-macro2 v1.0.43
   Compiling typenum v1.15.0
   Compiling itoa v1.0.3
   Compiling futures-task v0.3.23
   Compiling unicode-ident v1.0.3
   Compiling quote v1.0.21
   Compiling futures-util v0.3.23
   Compiling syn v1.0.99
   Compiling percent-encoding v2.1.0
   Compiling pin-utils v0.1.0
   Compiling futures-sink v0.3.23
   Compiling zstd-safe v5.0.2+zstd.1.5.2
   Compiling local-waker v0.1.3
   Compiling crc32fast v1.3.2
   Compiling tinyvec_macros v0.1.0
   Compiling fnv v1.0.7
   Compiling matches v0.1.9
   Compiling alloc-no-stdlib v2.0.3
   Compiling regex-syntax v0.6.27
   Compiling encoding_rs v0.8.31
   Compiling adler v1.0.2
   Compiling httparse v1.7.1
   Compiling ppv-lite86 v0.2.16
   Compiling paste v1.0.8
   Compiling hashbrown v0.12.3
   Compiling num_threads v0.1.6
   Compiling bitflags v1.3.2
   Compiling ryu v1.0.11
   Compiling convert_case v0.4.0
   Compiling unicode-bidi v0.3.8
   Compiling firestorm v0.5.1
   Compiling serde_json v1.0.85
   Compiling time-macros v0.2.4
   Compiling language-tags v0.3.2
   Compiling httpdate v1.0.2
   Compiling base64 v0.13.0
   Compiling mime v0.3.16
   Compiling lazy_static v1.4.0
   Compiling pipeline v0.5.0
   Compiling tinyvec v1.6.0
   Compiling actix-utils v3.0.0
   Compiling form_urlencoded v1.0.1
   Compiling tracing-core v0.1.29
   Compiling alloc-stdlib v0.2.1
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
   Compiling actix-service v2.0.2
   Compiling unicode-normalization v0.1.21
   Compiling jobserver v0.1.24
   Compiling mio v0.8.4
   Compiling socket2 v0.4.6
   Compiling signal-hook-registry v1.4.0
   Compiling getrandom v0.2.7
   Compiling num_cpus v1.13.1
   Compiling time v0.3.14
   Compiling cc v1.0.73
   Compiling idna v0.2.3
   Compiling parking_lot v0.12.1
   Compiling rand_core v0.6.3
   Compiling brotli v3.3.4
   Compiling regex v1.6.0
   Compiling rand_chacha v0.3.1
   Compiling url v2.2.2
   Compiling rand v0.8.5
   Compiling crypto-common v0.1.6
   Compiling block-buffer v0.10.2
   Compiling digest v0.10.3
   Compiling local-channel v0.1.3
   Compiling zstd-sys v2.0.1+zstd.1.5.2
   Compiling markdown v0.3.0
   Compiling sha1 v0.10.1
   Compiling serde_urlencoded v0.7.1
   Compiling actix-router v0.5.0
   Compiling tokio-util v0.7.3
   Compiling actix-rt v2.7.0
   Compiling actix-server v2.1.1
   Compiling actix-codec v0.5.0
   Compiling h2 v0.3.14
   Compiling derive_more v0.99.17
   Compiling actix-macros v0.2.3
   Compiling actix-web-codegen v4.0.1
   Compiling zstd v0.11.2+zstd.1.5.2
   Compiling actix-http v3.2.1
   Compiling actix-web v4.1.0
   Compiling rcv v0.1.0 (/usr/src/app)
    Finished release [optimized] target(s) in 6m 41s
[2/2] STEP 1/5: FROM arm32v7/rust:1.63
Resolving "arm32v7/rust" using unqualified-search registries (/etc/containers/registries.conf)
Trying to pull docker.io/arm32v7/rust:1.63...
Getting image source signatures
Copying blob 60ad8c571b2b skipped: already exists
Copying blob 94cbc350f4a2 skipped: already exists
Copying blob c715a126a4d5 skipped: already exists
Copying blob cdfc7e160811 skipped: already exists
Copying blob 3cecc62e2752 skipped: already exists
Copying blob 818eb872fe75 skipped: already exists
Copying config d0646b193e done
Writing manifest to image destination
Storing signatures
WARNING: image platform ({arm linux  [] v7}) does not match the expected platform ({amd64 linux  [] })
[2/2] STEP 2/5: WORKDIR /usr/src/app
[2/2] STEP 3/5: COPY --from=builder /usr/src/app/target/release/rcv /usr/src/app
[2/2] STEP 4/5: COPY --from=builder /usr/src/app/cv.md /usr/src/app
[2/2] STEP 5/5: CMD ["/usr/src/app/rcv"]
[2/2] COMMIT
Getting image source signatures
Copying blob b74e98d1b921 skipped: already exists
Copying blob 6c3d1ef471ee skipped: already exists
Copying blob 403a5f26ee02 skipped: already exists
Copying blob d55191df9034 skipped: already exists
Copying blob 1f4f3f20d97e skipped: already exists
Copying blob 54a3ca211559 skipped: already exists
Copying blob 7fd29dd92a8e done
Copying config f9fe5e59b8 done
Writing manifest to image destination
Storing signatures
--> f9fe5e59b8d
f9fe5e59b8d124fe147ef045ceb9195421a2613e48df91f48875ed11c1d9f5de

```
<br />

#### Lets test it
After building it, we can push it to the docker daemon and then run it and test it from another terminal
```elixir
❯ buildah push f9fe5e59b8d docker-daemon:rcv:f9fe5e59b8d
Getting image source signatures
Copying blob b74e98d1b921 done
Copying blob 6c3d1ef471ee done
Copying blob 403a5f26ee02 done
Copying blob d55191df9034 done
Copying blob 1f4f3f20d97e done
Copying blob 54a3ca211559 done
Copying blob 7fd29dd92a8e done
Copying config f9fe5e59b8 done
Writing manifest to image destination
Storing signatures

❯ docker run -p 8080:8080 f9fe5e59b8d
WARNING: The requested image's platform (linux/arm/v7) does not match the detected host platform (linux/amd64) and no specific platform was requested
[1662239178][172.17.0.1]: Processing cv request...

```

Notice: you will see some warnings about the architecture, that's fine as we are emulating things.
<br />

#### Performance considerations
This project build with the rust toolchain and then copied to an ARM32v7 image took 2 minutes, but using QEMU and the
given emulation it took around 8 minutes and a half, so it is something to be aware since the difference is quite big.
<br />

#### Extra

You can see it running [here](http://rcv.techsquad.rocks/), a very basic HTML Curriculum vitae.

For more details and to see how everything fits together I encourage you to clone the repo, test it, and modify it to
make your own.
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
