defmodule TrWeb.PageController do
  use TrWeb, :controller

  alias Tr.Blog

  plug :put_layout, false when action in [:sitemap, :json_sitemap]

  def sitemap(conn, _params) do
    posts = Blog.all_posts()

    conn
    |> put_resp_content_type("text/xml")
    |> render("index.xml", posts: posts)
  end

  def json_sitemap(conn, _params) do
    posts = Blog.all_posts()

    conn
    |> put_resp_content_type("application/feed+json")
    |> json(%{
      version: "https://jsonfeed.org/version/1.1",
      title: "TechSquad Rocks",
      home_page_url: "https://techsquad.rocks/",
      feed_url: "https://techsquad.rocks/index.json",
      description:
        "Welcome to the Techsquad blog! This page is dedicated to documenting and exploring various technologies. Our blog is hosted on a k3s cluster in OCI, powered by Elixir and Phoenix. Dive in to discover insights, tutorials, and experiments across the tech landscape.",
      favicon: "https://techsquad.rocks/favicon.ico",
      language: "en-US",
      items:
        for post <- posts do
          %{
            id: post.id,
            url: url(~p"/blog/#{post.id}"),
            title: post.title,
            content_html: post.body,
            date_published: post.date |> format_date,
            summary: post.description,
            image: url(~p"/images/#{post.image}"),
            tags: Enum.join(post.tags, ", "),
            language: "en-US",
            authors: [
              %{
                name: "Gabriel"
              }
            ]
          }
        end
    })
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def tags(conn, _params) do
    render(conn, tags: Tr.Blog.all_tags())
  end

  def by_tag(conn, %{"tag" => tag} = _params) do
    render(conn, posts: Blog.by_tag(tag))
  end

  defp format_date(date) do
    date
    |> to_string()
  end
end
