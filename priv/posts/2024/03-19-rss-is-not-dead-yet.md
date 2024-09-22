%{
  title: "RSS is not dead yet",
  author: "Gabriel Garrido",
  description: "In this article we will see how to add an RSS feed to your Phoenix application, and how to render XML.",
  tags: ~w(elixir phoenix),
  published: true,
  image: "rss.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**

RSS stands for Really Simple Syndication. It's a technology that allows users to subscribe to content from their
favorite websites or blogs in a standardized format, in this article we will see how to configure it for a Phoenix
application in the simplest way possible.
<br />

The example will be based in this blog configuration, but it would be the same if you replace the app name `tr` with
your app name.
<br />

##### **Configuration**
First we need to accept the format, this happens in `lib/tr_web.ex`

```elixir
  formats: [:html, :json, :xml],
```
<br />

As I'm using the page controller as index for the site, I decided to reuse that controller for the sitemap and rss feed,
basically the plug disables the layout for that action and the action renders the template.
```elixir
  plug :put_layout, false when action in [:sitemap]

  def sitemap(conn, _params) do
    posts = Blog.all_posts()

    conn
    |> put_resp_content_type("text/xml")
    |> render("index.xml", posts: posts)
  end

```
<br />

Before going into the template we need to add the route for it, first we add a pipeline to accept XML and then we define
the routes that will serve the sitemap.
```elixir
  pipeline :xml do
    plug :accepts, ["xml"]
  end

  scope "/", TrWeb do
    pipe_through :xml

    get "/index.xml", PageController, :sitemap
    get "/sitemap.xml", PageController, :sitemap
  end
```
<br />

The next two files are the last part of the configuration, first `lib/tr_web/controllers/page_xml.ex`, we set the
template and a helper to show the date. 
```elixir
defmodule TrWeb.PageXML do
  @moduledoc """
  Module to support xml rendering
  """
  use TrWeb, :html

  embed_templates "page_xml/*"

  defp format_date(date) do
    date
    |> to_string()
  end
end
```
<br />

And the last part of our configuration is the template itself `lib/tr_web/controllers/page_xml/index.xml.eex`, this will
be used to generate the list of all posts with the relevant fields.
```elixir
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>Techsquad Rocks</title>
    <link><%= ~p"/blog" %></link>
    <atom:link href="<%= ~p"/index.xml" %>" rel="self" type="application/rss+xml" />
    <description>This blog was created to document and learn about different technologies, among other things it has
    been deployed to a k3s cluster running in OCI, using elixir and the phoenix framework, postgres, docker, kubernetes
    on ARM64, and many other things, if that sounds interesting, you can follow me on twitter or create an account here
    to receive new posts notifications and later on a newsletter, so I hope you enjoy your stay and see you on the other
    side...</description>
    <language>en</language>
    <copyright>Copyright <%= DateTime.utc_now.year %> TechSquad Rocks </copyright>
    <lastBuildDate><%= DateTime.utc_now |> format_date() %></lastBuildDate>
    <category>IT/Internet/Web development</category>
    <ttl>60</ttl>

    <%= for post <- @posts do %>
      <item>
        <title><%= post.title %></title>
        <link><%= ~p"/blog/#{post.id}" %></link>
        <guid><%= ~p"/blog/#{post.id}" %></guid>
        <description><![CDATA[ <%= post.description %> ]]></description>
        <pubDate><%= post.date |> format_date %></pubDate>
        <source url="<%= ~p"/blog" %>">Blog Title</source>
      </item>
    <% end %>
  </channel>
</rss>
```
<br />

You can also test it this way, remember that if you decide to use another module you will have to place that there
instead of where the page controller tests are:
```elixir
  describe "GET /sitemap.xml" do
    test "accesses the sitemap in format xml", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")

      assert response_content_type(conn, :xml)
      assert response(conn, 200) =~ "<link>/blog/from_zero_to_hero_with_kops_and_aws</link>"
    end
  end
```
<br />

Then you can provide your readers with a link like this one so your readers can discover your feed:
```elixir
<.link rel="alternate" type="application/rss+xml" title="Blog Title" href={~p"/index.xml"}>
  RSS
</.link>
```
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
  title: "RSS no esta muerto",
  author: "Gabriel Garrido",
  description: "En este articulo vemos como funciona nuestro feed RSS.",
  tags: ~w(elixir phoenix),
  published: true,
  image: "rss.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**

RSS significa Really Simple Syndication. Es una tecnología que permite a los usuarios suscribirse a contenido de sus sitios web o blogs favoritos en un formato estandarizado. En este artículo, veremos cómo configurarlo para una aplicación Phoenix de la forma más simple posible.
<br />

El ejemplo estará basado en la configuración de este blog, pero sería lo mismo si reemplazás el nombre de la app `tr` con el nombre de tu app.
<br />

##### **Configuración**
Primero necesitamos aceptar el formato, esto se hace en `lib/tr_web.ex`

```elixir
  formats: [:html, :json, :xml],
```
<br />

Como estoy usando el controlador de página como índice del sitio, decidí reutilizar ese controlador para el sitemap y el feed RSS. Básicamente, el plug desactiva el layout para esa acción, y la acción renderiza la plantilla.
```elixir
  plug :put_layout, false when action in [:sitemap]

  def sitemap(conn, _params) do
    posts = Blog.all_posts()

    conn
    |> put_resp_content_type("text/xml")
    |> render("index.xml", posts: posts)
  end
```
<br />

Antes de pasar a la plantilla, necesitamos agregar la ruta para ella. Primero agregamos un pipeline para aceptar XML y luego definimos las rutas que servirán el sitemap.
```elixir
  pipeline :xml do
    plug :accepts, ["xml"]
  end

  scope "/", TrWeb do
    pipe_through :xml

    get "/index.xml", PageController, :sitemap
    get "/sitemap.xml", PageController, :sitemap
  end
```
<br />

Los siguientes dos archivos son la última parte de la configuración. Primero `lib/tr_web/controllers/page_xml.ex`, configuramos la plantilla y un helper para mostrar la fecha.
```elixir
defmodule TrWeb.PageXML do
  @moduledoc """
  Módulo para soportar el renderizado de XML
  """
  use TrWeb, :html

  embed_templates "page_xml/*"

  defp format_date(date) do
    date
    |> to_string()
  end
end
```
<br />

Y la última parte de nuestra configuración es la plantilla en sí, `lib/tr_web/controllers/page_xml/index.xml.eex`, que se utilizará para generar la lista de todos los posts con los campos relevantes.
```elixir
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>Techsquad Rocks</title>
    <link><%= ~p"/blog" %></link>
    <atom:link href="<%= ~p"/index.xml" %>" rel="self" type="application/rss+xml" />
    <description>Este blog fue creado para documentar y aprender sobre diferentes tecnologías. Entre otras cosas, ha sido desplegado en un clúster k3s corriendo en OCI, utilizando Elixir, el framework Phoenix, Postgres, Docker, Kubernetes en ARM64, y muchas otras cosas. Si esto suena interesante, podés seguirme en Twitter o crear una cuenta aquí para recibir notificaciones de nuevos posts y, más adelante, un boletín. Espero que disfrutes de tu estadía y nos veamos del otro lado...</description>
    <language>en</language>
    <copyright>Copyright <%= DateTime.utc_now.year %> TechSquad Rocks </copyright>
    <lastBuildDate><%= DateTime.utc_now |> format_date() %></lastBuildDate>
    <category>IT/Internet/Desarrollo web</category>
    <ttl>60</ttl>

    <%= for post <- @posts do %>
      <item>
        <title><%= post.title %></title>
        <link><%= ~p"/blog/#{post.id}" %></link>
        <guid><%= ~p"/blog/#{post.id}" %></guid>
        <description><![CDATA[ <%= post.description %> ]]></description>
        <pubDate><%= post.date |> format_date %></pubDate>
        <source url="<%= ~p"/blog" %>">Blog Title</source>
      </item>
    <% end %>
  </channel>
</rss>
```
<br />

También podés probarlo de esta manera. Recordá que si decidís usar otro módulo, tendrás que colocarlo allí en lugar de donde están las pruebas del controlador de página:
```elixir
  describe "GET /sitemap.xml" do
    test "accede al sitemap en formato xml", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")

      assert response_content_type(conn, :xml)
      assert response(conn, 200) =~ "<link>/blog/from_zero_to_hero_with_kops_and_aws</link>"
    end
  end
```
<br />

Luego podés ofrecer a tus lectores un enlace como este para que descubran tu feed:
```elixir
<.link rel="alternate" type="application/rss+xml" title="Blog Title" href={~p"/index.xml"}>
  RSS
</.link>
```
<br />

##### **Notas finales**
Haceme saber si hay algo que te gustaría ver implementado, probado, explorado o lo que sea en este espacio...
<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, mandame un mensaje para que se pueda corregir.

También podés revisar el código fuente y los cambios en los [sources aquí](https://github.com/kainlite/tr)

<br />
