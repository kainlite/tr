%{
  title: "Upcoming courses: docker, kubernetes, terraform, github actions",
  author: "Gabriel Garrido",
  description: "In this article I want to explain what the courses will be covering at a high level so you know what to
  expect",
  tags: ~w(courses),
  published: true,
  image: "logo-beard-bg.webp",
  sponsored: false,
  video: "",
  encrypted_content: "",
  lang: "en"
}
---

### **Introduction**
<br />

Hello there,

I will be working in some courses that will be available here through GitHub Sponsors, but I wanted to explain what you
will get by sponsoring me and also how it works on a high level, by becoming a sponsor you will get lifetime access to
the courses, these courses will be highly practical with explanations and enough theory to understand the topic at hand, 
everything else will be open source (code examples, etc), by supporting me you will receive more content in return
😄 
<br />

Upcoming courses:
* Docker: Understand docker from scratch.
* Kubernetes: Deploy your apps and manage clusters, autoscale your apps and best practices.
* Terraform: Code your infrastructure and automate it through GitHub and Atlantis.
* GitHub Actions: Configure your pipelines to build, test and deploy your applications in Kubernetes.
* Observability: Learn how to deploy and use Prometheus and Grafana to observe and monitor your apps, create dashboards
  and also meaningful alerts.

I expect to officially launch the Docker course in about a month from now, the other courses might start after that,
also by joining you will receive an invite to Discord/Slack (to be defined) so you can connect with me and ask me any
question that you might have. 

<br />

Thank you 💥

<br />

### **But wait... how does it work?**

I mentioned everything was going to be open-source even this blog or learning platform, wouldn't we be able to just read
the articles since they are plaintext in the repository? [tr](https://github.com/kainlite/tr), and that would be a fair
question, introducing "Cloak", the sponsored content will be in fact in the repository readable by anyone, but encrypted
and only rendered to those who sign in via GitHub (because I need to know your username) and also make sure you are in
fact a sponsor 🥲. 

With just a few calls to this module we can safely encrypt and decrypt the content of a given page, for example this is
what it looks like:
<br />

```yaml
%{
  title: "Master Docker from scratch (coming soon...)",
  author: "Gabriel Garrido",
  description: "This will be a short course to master docker on linux, it will consist of 3 parts and the first
  sponsored content posted here (video and text)",
  tags: ~w(docker courses),
  published: true,
  image: "docker-logo.svg",
  sponsored: true,
  video: "AQpBRVMuR0NNLlYxTJxSRfOfhl7jf3JuF/iCr59Ft4wVtu0td5HG//On8X1qfAwkUvdCST8aXPtgFedBaVfkKIATz1TgZNoe9R17SdiB066J",
  encrypted_content: "AQpBRVMuR0NNLlYxJJUZ6S+zhjv81zDHqUMSo3g5JkVGsTchQlKfB7fZfxg//hMIyX/XsUCygsFRr+MFlpw0vne8FxO2Si6jshOw8lKDMNvoXioHNmgQeozlahuIce0+D0NCh5vFFsbJIi//TTpac1coUdiEbReH94yDQ07V4O848C5J7F5JjZslhGekKVjq0eT3T7PmIibJfii391tqgYUBHIg/jpY2LifxzgrHW5jaFRzrsIZNuCiBF1M4lUjSORF01aPgT68s1vHcG/+r0LE8EsCsHRT9VDvKl0F6ntgwoTUY/OSqONCbkzE2wfWsy5jGGV3YN8jCkMYIWi7FylgpCrMbb99DfNIKRA37GpvoLx08+X8YPbBRHoL1Gs3JGIi91UBAMQ=="
}
---
```

<br />

Then we have our vault configured (it is just a Genserver giving us encrypt/decrypt capabilities given a particular key), that will be this particular module:
```hcl
defmodule Tr.Vault do
  @moduledoc """
  This module is responsible for interfacing with the vault
  """
  use Cloak.Vault, otp_app: :tr

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1", key: decode_env!("CLOAK_KEY"), iv_length: 12
        }
      )

    {:ok, config}
  end

  defp decode_env!(var) do
    var
    |> System.get_env()
    |> Base.decode64!()
  end
end
```

Then to keep rate-limits at hand every 5 minutes I'm polling GitHub GraphQL API to fetch the list of sponsors and
caching that in the local DB:
```elixir
defmodule Tr.Sponsors do
  @moduledoc """
  Basic task to fetch the list of sponsors from GitHub
  """
  @app :tr

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  @doc """
  """
  def start do
    start_app()

    # account for more than a 100 sponsors
    sponsors = get_sponsors(100)

    Enum.each(get_in(sponsors, ["data", "user", "sponsors", "nodes"]), fn sponsor ->
      Tr.SponsorsCache.add_or_update(sponsor)
    end)
  end

  @doc """
    # Example output:

    %Neuron.Response{
      body: %{
        "data" => %{
          "user" => %{
            "sponsors" => %{
              "nodes" => [
                %{"login" => "nnnnnnn"},
                %{"login" => "xxxxxxx"},
                %{...},
                ...
              ],
              "totalCount" => 123
            }
          }
        }
      }
  """
  def get_sponsors(limit) do
    token = System.get_env("GITHUB_BEARER_TOKEN")

    {:ok, body} =
      Neuron.query(
        "{ user(login:\"kainlite\") { ... on Sponsorable { sponsors(first: #{limit}) { totalCount
      nodes { ... on User { login } ... on Organization { login } } } } } }",
        %{},
        url: "https://api.github.com/graphql",
        headers: [authorization: "Bearer #{token}"]
      )

    body.body
  end
end
```
<br />

The last step would be to just decrypt and render the content:
```xml
    <%= cond do %>
      <% @post.sponsored && @current_user && Tr.SponsorsCache.sponsor?(@current_user.github_username) -> %>
        <br />
        <p>
          <iframe
            width="100%"
            height="800px"
            src={decrypt(@post.video)}
            title=""
            frameBorder="0"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowFullScreen
          >
          </iframe>
        </p>
        <br />
        <%= raw(Earmark.as_html!(decrypt(@post.encrypted_content))) %>
    ...
    ...
```
<br />

At a high level that's what it looks like, are you interested in learning more about this or the approach taken here?
leave a comment 👇

<br />
---lang---
%{
  title: "Proximos cursos: docker, kubernetes, terraform, github actions",
  author: "Gabriel Garrido",
  description: "En este articulo vemos los proximos cursos que estaran disponibles en la pagina",
  tags: ~w(courses),
  published: true,
  image: "logo-beard-bg.webp",
  sponsored: false,
  video: "",
  encrypted_content: "",
  lang: "es"
}
---

### **Introducción**
<br />

Hola,

Voy a estar trabajando en algunos cursos que estarán disponibles aquí a través de GitHub Sponsors, pero quería explicar qué obtendrás al patrocinarme y cómo funciona a un nivel alto. Al convertirte en patrocinador, obtendrás acceso de por vida a los cursos. Estos cursos serán altamente prácticos con explicaciones y la teoría necesaria para entender el tema en cuestión. Todo lo demás será de código abierto (ejemplos de código, etc.). Al apoyarme, recibirás más contenido a cambio 😄 
<br />

Próximos cursos:
* Docker: Comprende Docker desde cero.
* Kubernetes: Despliega tus aplicaciones y gestiona clústeres, autoescala tus apps y mejores prácticas.
* Terraform: Codifica tu infraestructura y automatízala a través de GitHub y Atlantis.
* GitHub Actions: Configura tus pipelines para construir, probar y desplegar tus aplicaciones en Kubernetes.
* Observabilidad: Aprende a desplegar y usar Prometheus y Grafana para observar y monitorear tus aplicaciones, crear dashboards y también alertas significativas.

Espero lanzar oficialmente el curso de Docker en aproximadamente un mes. Los demás cursos comenzarán después de eso. Además, al unirte, recibirás una invitación para Discord/Slack (por definir) para que puedas conectarte conmigo y hacerme cualquier pregunta que puedas tener.

<br />

Gracias 💥

<br />

### **Pero espera... ¿cómo funciona?**

Mencioné que todo iba a ser de código abierto, incluso este blog o plataforma de aprendizaje. ¿No podríamos simplemente leer los artículos ya que están en texto plano en el repositorio? [tr](https://github.com/kainlite/tr), y sería una pregunta justa. Presentando "Cloak", el contenido patrocinado estará, de hecho, en el repositorio, legible por cualquiera, pero encriptado y solo será renderizado para aquellos que inicien sesión a través de GitHub (porque necesito conocer tu nombre de usuario) y también para asegurarme de que, de hecho, eres un patrocinador 🥲. 

Con solo algunas llamadas a este módulo, podemos encriptar y desencriptar el contenido de una página dada. Por ejemplo, así es como se ve:
<br />

```yaml
%{
  title: "Domina Docker desde cero (próximamente...)",
  author: "Gabriel Garrido",
  description: "Este será un curso corto para dominar Docker en Linux. Consistirá en 3 partes y será el primer contenido patrocinado publicado aquí (video y texto)",
  tags: ~w(docker cursos),
  published: true,
  image: "docker-logo.svg",
  sponsored: true,
  video: "AQpBRVMuR0NNLlYxTJxSRfOfhl7jf3JuF/iCr59Ft4wVtu0td5HG//On8X1qfAwkUvdCST8aXPtgFedBaVfkKIATz1TgZNoe9R17SdiB066J",
  encrypted_content: "AQpBRVMuR0NNLlYxJJUZ6S+zhjv81zDHqUMSo3g5JkVGsTchQlKfB7fZfxg//hMIyX/XsUCygsFRr+MFlpw0vne8FxO2Si6jshOw8lKDMNvoXioHNmgQeozlahuIce0+D0NCh5vFFsbJIi//TTpac1coUdiEbReH94yDQ07V4O848C5J7F5JjZslhGekKVjq0eT3T7PmIibJfii391tqgYUBHIg/jpY2LifxzgrHW5jaFRzrsIZNuCiBF1M4lUjSORF01aPgT68s1vHcG/+r0LE8EsCsHRT9VDvKl0F6ntgwoTUY/OSqONCbkzE2wfWsy5jGGV3YN8jCkMYIWi7FylgpCrMbb99DfNIKRA37GpvoLx08+X8YPbBRHoL1Gs3JGIi91UBAMQ=="
}
---
```

<br />

Luego tenemos nuestro vault configurado (es solo un Genserver que nos da capacidades de encriptar/desencriptar dada una clave particular), que será este módulo en particular:
```elixir
defmodule Tr.Vault do
  @moduledoc """
  Este módulo se encarga de interactuar con el vault
  """
  use Cloak.Vault, otp_app: :tr

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1", key: decode_env!("CLOAK_KEY"), iv_length: 12
        }
      )

    {:ok, config}
  end

  defp decode_env!(var) do
    var
    |> System.get_env()
    |> Base.decode64!()
  end
end
```

Para mantener los límites de tasa bajo control, cada 5 minutos hago polling a la API GraphQL de GitHub para obtener la lista de patrocinadores y almacenarla en la DB local:
```elixir
defmodule Tr.Sponsors do
  @moduledoc """
  Tarea básica para obtener la lista de patrocinadores desde GitHub
  """
  @app :tr

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  @doc """
  """
  def start do
    start_app()

    # contemplar más de 100 patrocinadores
    sponsors = get_sponsors(100)

    Enum.each(get_in(sponsors, ["data", "user", "sponsors", "nodes"]), fn sponsor ->
      Tr.SponsorsCache.add_or_update(sponsor)
    end)
  end

  @doc """
    # Ejemplo de salida:

    %Neuron.Response{
      body: %{
        "data" => %{
          "user" => %{
            "sponsors" => %{
              "nodes" => [
                %{"login" => "nnnnnnn"},
                %{"login" => "xxxxxxx"},
                %{...},
                ...
              ],
              "totalCount" => 123
            }
          }
        }
      }
  """
  def get_sponsors(limit) do
    token = System.get_env("GITHUB_BEARER_TOKEN")

    {:ok, body} =
      Neuron.query(
        "{ user(login:\"kainlite\") { ... on Sponsorable { sponsors(first: #{limit}) { totalCount
      nodes { ... on User { login } ... on Organization { login } } } } } }",
        %{},
        url: "https://api.github.com/graphql",
        headers: [authorization: "Bearer #{token}"]
      )

    body.body
  end
end
```
<br />

El último paso sería simplemente desencriptar y renderizar el contenido:
```xml
    <%= cond do %>
      <% @post.sponsored && @current_user && Tr.SponsorsCache.sponsor?(@current_user.github_username) -> %>
        <br />
        <p>
          <iframe
            width="100%"
            height="800px"
            src={decrypt(@post.video)}
            title=""
            frameBorder="0"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowFullScreen
          >
          </iframe>
        </p>
        <br />
        <%= raw(Earmark.as_html!(decrypt(@post.encrypted_content))) %>
    ...
    ...
```
<br />

A alto nivel, así es como funciona. ¿Te interesa aprender más sobre esto o el enfoque adoptado aquí? Dejá un comentario 👇

<br />
