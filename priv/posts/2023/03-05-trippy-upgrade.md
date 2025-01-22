%{
  title: "Upgrading to Phoenix 1.7",
  author: "Gabriel Garrido",
  description: "Upgrading phoenix from 1.6 to 1.7...",
  tags: ~w(elixir phoenix),
  published: true,
  image: "phoenix.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
It's been a while since I have been doing anything with this small project, but since I'm playing with some new small
projects using Phoenix 1.7.1 I thought the sane thing to do was to upgrade this blog before it pass too much time so
things are relatively fresh, however it was a really big upgrade, I invite you to review the changes in github, because
I won't put the steps to move away from LiveView helpers to Components.
<br />

Before going into this, be sure to check the release page for additional information on what changes, what to expect,
etc, [Phoenix 1.7.0 release notes](https://phoenixframework.org/blog/phoenix-1.7-final-released), then you can dig
through here for the [upgrade notes](https://gist.github.com/chrismccord/00a6ea2a96bc57df0cce526bd20af8a7).
<br />

[Git commit with all the changes!](https://github.com/kainlite/tr/commit/5cfde253f6ac82dcd41434fcbf9cf503d6848148), hope
this helps figure out everything that you need to do in order to get on the new folder structure.
<br />

##### **Upgrading packages**
Upgrade packages manually in `mix.exs`:
```elixir
    {:phoenix, "~> 1.7.1"},
    {:phoenix_live_view, "~> 0.18.3"},
    {:phoenix_live_dashboard, "~> 0.7.2"},
``` 
If you have `phoenix` and `gettext` from your `:compilers` line in `mix.exs` remove it.
<br />

Update your `.formatter.exs`
```elixir
[
  import_deps: [:ecto, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
```
<br />

Some things that can get a bit tricky, so these have been copied directly from the upgrade notes:
> Phoenix.LiveView.Helpers has been soft deprecated and all relevant functionality has been migrated. You must import Phoenix.Component where you previously imported Phoenix.LiveView.Helpers when upgrading (such as in your lib/app_web.ex). You may also need to import Phoenix.Component where you also imported Phoenix.LiveView and some of its functions have been moved to Phoenix.Component.

> live_title_tag has also been renamed to live_title as a function component. Update your root.html.heex layout to use the new component:
```elixir
-   <%= live_title_tag assigns[:page_title] || "Onesixfifteen", suffix: " · Phoenix Framework" %>
+   <.live_title suffix=" · Phoenix Framework">
+     <%= assigns[:page_title] || "MyApp" %>
+   </.live_title>
```
<br />

##### **Important**
Some important links:
https://hexdocs.pm/phoenix_view/Phoenix.View.html#module-migrating-to-phoenix-component
https://elixirstream.dev/gendiff

kudos to [jbosse](https://gist.github.com/jbosse) and 
[srikanthkyatham](https://gist.github.com/srikanthkyatham) for the links, and everyone in the comments figuring out
different issues.

and last but not least good luck!
<br />

##### **Closing notes**
Let me know if there is anything that you would like to see implemented or tested, explored and what not in here...

This was based from the steps described in the [official upgrade notes]().
<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
---lang---
%{
  title: "Actualizando a Phoenix 1.7",
  author: "Gabriel Garrido",
  description: "Actualizando a Phoenix 1.7 desde 1.6...",
  tags: ~w(elixir phoenix),
  published: true,
  image: "phoenix.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
Hace un tiempo que no hago nada con este pequeño proyecto, pero como estoy jugando con algunos proyectos nuevos usando Phoenix 1.7.1, pensé que lo más sensato era actualizar este blog antes de que pase demasiado tiempo, para que todo esté relativamente fresco. Sin embargo, fue una actualización bastante grande, te invito a revisar los cambios en GitHub, porque no voy a poner los pasos para cambiar de los LiveView helpers a Componentes.
<br />

Antes de continuar, asegúrate de revisar la página del lanzamiento para obtener más información sobre qué cambia, qué esperar, etc., [Phoenix 1.7.0 release notes](https://phoenixframework.org/blog/phoenix-1.7-final-released), luego podés profundizar acá para ver las [notas de actualización](https://gist.github.com/chrismccord/00a6ea2a96bc57df0cce526bd20af8a7).
<br />

[¡Commit de Git con todos los cambios!](https://github.com/kainlite/tr/commit/5cfde253f6ac82dcd41434fcbf9cf503d6848148), espero que esto te ayude a ver todo lo que tenés que hacer para ajustarte a la nueva estructura de carpetas.
<br />

##### **Actualizando paquetes**
Actualizá los paquetes manualmente en `mix.exs`:
```elixir
    {:phoenix, "~> 1.7.1"},
    {:phoenix_live_view, "~> 0.18.3"},
    {:phoenix_live_dashboard, "~> 0.7.2"},
``` 
Si tenés `phoenix` y `gettext` en la línea de `:compilers` en `mix.exs`, eliminá esos.
<br />

Actualizá tu `.formatter.exs`
```elixir
[
  import_deps: [:ecto, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
```
<br />

Algunas cosas pueden ser un poco complicadas, por lo que las he copiado directamente de las notas de actualización:
> Phoenix.LiveView.Helpers ha sido suavemente deprecado y toda la funcionalidad relevante se ha migrado. Debés importar Phoenix.Component donde antes importabas Phoenix.LiveView.Helpers al actualizar (como en tu archivo lib/app_web.ex). También es posible que debas importar Phoenix.Component donde también importabas Phoenix.LiveView, ya que algunas de sus funciones se han movido a Phoenix.Component.

> live_title_tag también se ha renombrado a live_title como un componente funcional. Actualizá tu layout root.html.heex para usar el nuevo componente:
```elixir
-   <%= live_title_tag assigns[:page_title] || "Onesixfifteen", suffix: " · Phoenix Framework" %>
+   <.live_title suffix=" · Phoenix Framework">
+     <%= assigns[:page_title] || "MyApp" %>
+   </.live_title>
```
<br />

##### **Importante**
Algunos enlaces importantes:
https://hexdocs.pm/phoenix_view/Phoenix.View.html#module-migrating-to-phoenix-component
https://elixirstream.dev/gendiff

Kudos a [jbosse](https://gist.github.com/jbosse) y [srikanthkyatham](https://gist.github.com/srikanthkyatham) por los enlaces, y a todos en los comentarios que están resolviendo distintos problemas.

¡Y por último, pero no menos importante, buena suerte!
<br />

##### **Notas finales**
Haceme saber si hay algo que te gustaría ver implementado, probado o explorado acá...

Esto está basado en los pasos descritos en las [notas oficiales de actualización]().
<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, mandame un mensaje para que se pueda corregir.

También podés revisar el código fuente y los cambios en los [sources aquí](https://github.com/kainlite/tr)

<br />
