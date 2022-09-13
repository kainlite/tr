defmodule TrWeb.PageController do
  use TrWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
