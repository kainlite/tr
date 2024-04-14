defmodule TrWeb.BlogLive do
  use TrWeb, :live_view
  alias Tr.Blog
  alias TrWeb.PostComponent

  @impl true
  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> assign(:posts, Blog.posts())
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= TrWeb.AdsComponent.render_large_ad(assigns) %>

    <div class="flex flex-row flex-wrap columns-3">
      <%= for post <- @posts do %>
        <%= PostComponent.render_post_card(%{post: post}) %>
      <% end %>
    </div>
    """
  end
end
