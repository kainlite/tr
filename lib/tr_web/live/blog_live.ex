defmodule TrWeb.BlogLive do
  use TrWeb, :live_view
  alias Tr.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:posts, Blog.all_posts())
     |> assign(:connected, false)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <%= for post <- Blog.all_posts() do %>
      <div id="<%= post.id %>" style="margin-bottom: 3rem;">
      <h2>
        <%= link post.title, to: Routes.post_path(@socket, :show, post) %>
      </h2>

      <p>
        <time><%= post.date %></time> by <%= post.author %>
      </p>

      <p>
        Tagged as <%= Enum.join(post.tags, ", ") %>
      </p>

      <%= raw post.description %>
      </div>
    <% end %>
    """
  end
end
