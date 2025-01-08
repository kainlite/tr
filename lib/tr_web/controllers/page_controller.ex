defmodule TrWeb.PageController do
  use TrWeb, :controller

  alias Tr.Blog

  plug :put_layout, false when action in [:sitemap, :json_sitemap]

  def sitemap(conn, %{"locale" => locale}) do
    Gettext.put_locale(TrWeb.Gettext, locale)
    posts = Blog.posts(Gettext.get_locale(TrWeb.Gettext))

    conn
    |> put_resp_content_type("text/xml")
    |> render("index.xml", posts: posts)
  end

  def sitemap(conn, _params) do
    posts = Blog.posts(Gettext.get_locale(TrWeb.Gettext))

    conn
    |> put_resp_content_type("text/xml")
    |> render("index.xml", posts: posts)
  end

  def index(conn, _params) do
    oauth_google_url = ElixirAuthGoogle.generate_oauth_url(conn)
    render(conn, "index.html", oauth_google_url: oauth_google_url)
  end

  def welcome(conn, _params) do
    render(conn, "welcome.html")
  end

  def json_sitemap(conn, %{"locale" => locale}) do
    Gettext.put_locale(TrWeb.Gettext, locale)
    posts = Blog.posts(Gettext.get_locale(TrWeb.Gettext))

    conn
    |> put_resp_content_type("application/feed+json")
    |> json(%{
      version: "https://jsonfeed.org/version/1.1",
      title:
        gettext(
          "Learn about DevOps, Linux, Containers, Kubernetes, CI/CD, AWS, Terraform | Red Beard Team"
        ),
      home_page_url: "https://redbeard.team/",
      feed_url: "https://redbeard.team/index.json",
      description:
        gettext(
          "Learn about DevOps, Linux, Containers, Kubernetes, CI/CD, AWS, Terraform, Docker, and more."
        ),
      favicon: "https://redbeard.team/favicon.ico",
      language: Gettext.get_locale(TrWeb.Gettext),
      items:
        for post <- posts do
          %{
            id: post.id,
            url: url(~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{post.id}"),
            title: post.title,
            content_html: post.body,
            date_published: post.date |> format_date,
            summary: post.description,
            image: url(~p"/images/#{post.image}"),
            tags: Enum.join(post.tags, ", "),
            language: Gettext.get_locale(TrWeb.Gettext),
            authors: [
              %{
                name: "Gabriel"
              }
            ]
          }
        end
    })
  end

  def json_sitemap(conn, _params) do
    json_sitemap(conn, %{locale: "en"})
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def tags(conn, _params) do
    render(conn, tags: Tr.Blog.all_tags())
  end

  def by_tag(conn, %{"tag" => tag} = _params) do
    render(conn, posts: Blog.by_tag(Gettext.get_locale(TrWeb.Gettext), tag))
  end

  defp format_date(date) do
    date
    |> to_string()
  end
end
