defmodule TrWeb.PageController do
  use TrWeb, :controller

  alias Tr.Blog

  plug :put_layout, false when action in [:rss_feed, :xml_sitemap, :json_sitemap]

  def xml_sitemap(conn, _params) do
    en_posts = Blog.posts("en")
    es_posts = Blog.posts("es")

    conn
    |> put_resp_content_type("text/xml")
    |> render("sitemap.xml", en_posts: en_posts, es_posts: es_posts)
  end

  def rss_feed(conn, %{"locale" => locale}) do
    Gettext.put_locale(TrWeb.Gettext, locale)
    posts = Blog.posts(Gettext.get_locale(TrWeb.Gettext))

    conn
    |> put_resp_content_type("text/xml")
    |> render("index.xml", posts: posts)
  end

  def rss_feed(conn, _params) do
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
          "Learn about DevOps, Linux, Containers, Kubernetes, CI/CD, AWS, Terraform | SegFault"
        ),
      home_page_url: "https://segfault.pw/",
      feed_url: "https://segfault.pw/index.json",
      description:
        gettext(
          "Learn about DevOps, Linux, Containers, Kubernetes, CI/CD, AWS, Terraform, Docker, and more."
        ),
      favicon: "https://segfault.pw/favicon.ico",
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
    json_sitemap(conn, %{"locale" => "en"})
  end

  def privacy(conn, _params) do
    locale = Gettext.get_locale(TrWeb.Gettext)

    conn
    |> assign(:og_url, TrWeb.Endpoint.url() <> "/#{locale}/privacy")
    |> assign(:page_title, "SegFault - Privacy Policy")
    |> assign(:og_hreflang_en, TrWeb.Endpoint.url() <> "/en/privacy")
    |> assign(:og_hreflang_es, TrWeb.Endpoint.url() <> "/es/privacy")
    |> render(:privacy)
  end

  def about(conn, _params) do
    locale = Gettext.get_locale(TrWeb.Gettext)

    conn
    |> assign(:og_url, TrWeb.Endpoint.url() <> "/#{locale}/about")
    |> assign(:page_title, "SegFault - About")
    |> assign(:og_hreflang_en, TrWeb.Endpoint.url() <> "/en/about")
    |> assign(:og_hreflang_es, TrWeb.Endpoint.url() <> "/es/about")
    |> render(:about)
  end

  def tags(conn, _params) do
    locale = Gettext.get_locale(TrWeb.Gettext)

    conn
    |> assign(:og_url, TrWeb.Endpoint.url() <> "/#{locale}/blog/tags")
    |> assign(:page_title, "SegFault - Tags")
    |> assign(:og_hreflang_en, TrWeb.Endpoint.url() <> "/en/blog/tags")
    |> assign(:og_hreflang_es, TrWeb.Endpoint.url() <> "/es/blog/tags")
    |> render(tags: Tr.Blog.all_tags())
  end

  def by_tag(conn, %{"tag" => tag} = _params) do
    locale = Gettext.get_locale(TrWeb.Gettext)

    conn
    |> assign(:og_url, TrWeb.Endpoint.url() <> "/#{locale}/blog/tags/#{tag}")
    |> assign(:page_title, "SegFault - #{tag}")
    |> assign(:og_hreflang_en, TrWeb.Endpoint.url() <> "/en/blog/tags/#{tag}")
    |> assign(:og_hreflang_es, TrWeb.Endpoint.url() <> "/es/blog/tags/#{tag}")
    |> render(posts: Blog.by_tag(Gettext.get_locale(TrWeb.Gettext), tag))
  end

  defp format_date(date) do
    date
    |> to_string()
  end
end
