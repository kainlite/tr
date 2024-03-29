defmodule TrWeb.BlogLive do
  use TrWeb, :live_view
  alias Tr.Blog

  @impl true
  def mount(%{"tag" => tag} = _params, _session, socket) do
    {
      :ok,
      socket
      |> assign(:posts, Blog.by_tag(tag))
    }
  end

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
    <%= for post <- @posts do %>
      <div id={post.id} style="margin-bottom: 3rem;">
        <h2>
          <.link navigate={~p"/blog/#{post.id}"}>
            <%= post.title %>
          </.link>
        </h2>

        <p>
          <time><%= post.date %></time> by <%= post.author %>
        </p>
        <%= raw(post.description) %>

        <p class="clear-both"></p>
        <div class="mx-auto">
          <ul class="space-y-4 list-none">
            <li class="px-1"></li>
            <%= for tag <- post.tags do %>
              <li class="bg-white shadow-md p-4 rounded-lg border-l-solid border-l-[5px] border-l-gray-700 float-left">
                <.link navigate={~p"/blog?tag=#{tag}"}>
                  <%= tag %>
                </.link>
              </li>
            <% end %>
          </ul>
        </div>
        <p class="clear-both"></p>
      </div>
    <% end %>
    """
  end
end
