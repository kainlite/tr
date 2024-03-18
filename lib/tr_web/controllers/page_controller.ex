defmodule TrWeb.PageController do
  use TrWeb, :controller

  alias Tr.Blog

  plug :put_layout, false when action in [:sitemap]

  def index(conn, _params) do
    render(conn, :home, posts: Blog.recent_posts())
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def sitemap(conn, _params) do
    posts = Blog.all_posts()

    conn
    |> put_resp_content_type("text/xml")
    |> render("index.xml", posts: posts)
  end
end
