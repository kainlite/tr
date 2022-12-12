defmodule TrWeb.PostLive do
  use TrWeb, :live_view
  alias Tr.Blog

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:params, params)
     |> assign(:connected, false)}
  end

  @impl true
  def render(assigns) do
    ~L"""
      <% id = Map.get(@params, "id") %>
      <% post = Blog.get_post_by_id!(id) %>

      <%= link "← All posts", to: Routes.blog_path(@socket, :index)%>

      <h2><%= post.title %></h2>
      <h5>
        <time><%= post.date %></time> by <%= post.author %>
      </h5>

      <p>
        Tagged as <%= Enum.join(post.tags, ", ") %>
      </p>

      <%= raw post.body %>
    """
  end
end
