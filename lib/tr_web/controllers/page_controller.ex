defmodule TrWeb.PageController do
  use TrWeb, :controller

  alias Tr.Blog

  plug :put_layout, false when action in [:sitemap]

  def sitemap(conn, _params) do
    posts = Blog.all_posts()

    conn
    |> put_resp_content_type("text/xml")
    |> render("index.xml", posts: posts)
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
end
