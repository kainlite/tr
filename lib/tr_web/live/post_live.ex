defmodule TrWeb.PostLive do
  use TrWeb, :live_view
  alias Tr.Blog

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign(socket, params: params, post: Blog.get_post_by_id!(Map.get(params, "id")))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.link navigate={~p"/blog"}>
      ← All posts
    </.link>

    <h2><%= @post.title %></h2>
    <h5>
      <time><%= @post.date %></time> by <%= @post.author %>
    </h5>

    <p>
      Tagged as <%= Enum.join(@post.tags, ", ") %>
    </p>
    <%= raw(@post.body) %>
    """
  end
end
