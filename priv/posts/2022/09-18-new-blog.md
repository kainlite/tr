%{
  title: "New blog",
  author: "Gabriel Garrido",
  description: "New blog to document and learn about the infamous Web3 world with a dynamic self-hosted blog...",
  tags: ~w(elixir phoenix),
  published: true,
  image: "phoenix.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
This is my new blog, I want to run some web3 experiments and this is the place where it will happen and also where it
will be tested and explained, what, how, etc, I will still update and post as usual in my main blog
[here](https://techsquad.rocks) about linux, kubernetes, containers, etc.
<br />

##### **Web3**
Web3 might not be the definitive solution but it does solve some interesting problems, so let's explore here what those
are, and how can we use it in our "Web2" world, that's the idea for this blog, so far you won't see much "Web3" in it,
but sooner or late it will be here, but first let's take a look how all this is working and running here...
<br />

##### **Generating the app**
We need to install hex locally, then the Phoenix generator, and then our app, we also generated a Dockerfile for our
production deployment.
```elixir
mix local.hex
mix archive.install hex phx_new
# Create the app
mix phx.new tr
# Create the Dockerfile
mix phx.gen.release --docker
``` 
<br />

Don't forget about Ecto and the DB:
```elixir
mix ecto.create
mix ecto.migrate
```

You can see all the modified files in this [branch](https://github.com/kainlite/tr/commits/blog).

Then you can follow [this article](https://elixirschool.com/en/lessons/misc/nimble_publisher) to build your own, it's
relatively easy, just be careful with the names.
<br />

##### **What's coming?**
Since the basic stuff is already here, now to improve visuals a bit and start working on some of the experiments, expect
changes on this blog and hopefully many interesting posts, some of the things I want to do for this blog is a comment
system with Web3 authentication (signed messages) for example, and some other things that will come later, for now it's
good enough to get going...

The next article will explore the setup to get here, but that probably belongs to my main blog, since it is fairly
complex I will try to summarize it as much as possible.
<br />

##### **Closing notes**
Let me know if there is anything that you would like to see implemented or tested, explored and what not in here...
<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
---lang---
%{
  title: "Nuevo blog",
  author: "Gabriel Garrido",
  description: "Nuevo blog corriendo en Kubernetes usando Phoenix / Elixir...",
  tags: ~w(elixir phoenix),
  published: true,
  image: "phoenix.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
Este es mi nuevo blog, quiero hacer algunos experimentos con web3 y este es el lugar donde va a suceder, además de ser donde se va a probar y explicar qué, cómo, etc. Todavía voy a actualizar y publicar como de costumbre en mi blog principal [aquí](https://techsquad.rocks) sobre Linux, Kubernetes, contenedores, etc.
<br />

##### **Web3**
Web3 puede que no sea la solución definitiva, pero resuelve algunos problemas interesantes, así que exploremos cuáles son y cómo podemos usarlo en nuestro mundo "Web2". Esa es la idea para este blog. Por ahora, no vas a ver mucho "Web3" en él, pero tarde o temprano estará aquí. Primero, veamos cómo está funcionando todo esto y corriendo acá...
<br />

##### **Generando la app**
Necesitamos instalar hex localmente, luego el generador de Phoenix y después nuestra app. También generamos un Dockerfile para el despliegue en producción.
```elixir
mix local.hex
mix archive.install hex phx_new
# Crear la app
mix phx.new tr
# Crear el Dockerfile
mix phx.gen.release --docker
``` 
<br />

No te olvides de Ecto y la base de datos:
```elixir
mix ecto.create
mix ecto.migrate
```

Podés ver todos los archivos modificados en esta [branch](https://github.com/kainlite/tr/commits/blog).

Después podés seguir [este artículo](https://elixirschool.com/en/lessons/misc/nimble_publisher) para crear el tuyo propio, es relativamente fácil, solo tené cuidado con los nombres.
<br />

##### **¿Qué se viene?**
Ya que lo básico está hecho, ahora toca mejorar un poco los visuales y empezar a trabajar en algunos de los experimentos. Esperá cambios en este blog y, con suerte, muchos posts interesantes. Algunas de las cosas que quiero hacer para este blog es un sistema de comentarios con autenticación Web3 (mensajes firmados), por ejemplo, y algunas otras cosas que vendrán después. Por ahora es suficiente para empezar...

El próximo artículo va a explorar la configuración para llegar hasta acá, pero eso probablemente pertenezca a mi blog principal. Como es algo bastante complejo, voy a intentar resumirlo lo más posible.
<br />

##### **Notas finales**
Haceme saber si hay algo que te gustaría ver implementado, probado o explorado acá...
<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, mandame un mensaje para que se pueda corregir.

<br />
