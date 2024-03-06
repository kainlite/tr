defmodule TrWeb.BlogLive do
  use TrWeb, :live_view
  alias Tr.Blog

  on_mount {TrWeb.UserAuth, :mount_current_user}

  @impl true
  def mount(_params, _session, socket) do
    {
      :ok,
        socket
        |> assign(:posts, Blog.all_posts())
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= for post <- Blog.all_posts() do %>
      <div id={post.id} style="margin-bottom: 3rem;">
        <h2>
          <.link navigate={~p"/blog/#{post.id}"}>
            <%= post.title %>
          </.link>
        </h2>

        <p>
          <time><%= post.date %></time> by <%= post.author %>
        </p>

        <p>
          Tagged as <%= Enum.join(post.tags, ", ") %>
        </p>

        <%= raw(post.description) %>
      </div>
    <% end %>
    """
  end
end
