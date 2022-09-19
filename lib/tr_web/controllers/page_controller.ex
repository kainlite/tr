defmodule TrWeb.PageController do
  use TrWeb, :controller

  alias Tr.Blog

  def index(conn, _params) do
    render(conn, "index.html", posts: Blog.all_posts())
  end
end
