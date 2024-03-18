defmodule TrWeb.PageController do
  use TrWeb, :controller

  alias Tr.Blog

  def index(conn, _params) do
    render(conn, :home, posts: Blog.recent_posts())
  end
end
