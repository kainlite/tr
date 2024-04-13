defmodule TrWeb.BlogLive do
  use TrWeb, :live_view
  alias Tr.Blog

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
        <div id={post.id}>
          <div class="relative">
            <div class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-md rounded-lg overflow-hidden w-[40rem]
            h-[30rem] m-4">
              <.link navigate={~p"/blog/#{post.id}"} class="">
                <img
                  src={~p"/images/#{post.image}"}
                  alt="Article Image"
                  class="w-full h-32 sm:h-48 object-center object-scale-down"
                />
              </.link>
              <div class="p-6">
                <h2 class="text-xl font-bold mb-2 truncate">
                  <.link navigate={~p"/blog/#{post.id}"} class="inline-block">
                    <%= post.title %>
                  </.link>
                  <p class="text-sm float-right font-semibold">
                    <time><%= post.date %></time> by <%= post.author %>
                  </p>
                </h2>
                <p class="mx-auto text-sm sm:text-base sm:leading-7">
                  <%= raw(post.description) %>
                </p>
              </div>
              <div class="absolute bottom-3 right-6">
                <.link
                  navigate={~p"/blog/#{post.id}"}
                  class="mt-4 inline-block text-blue-500 float-right text-base font-semibold"
                >
                  Read more...
                </.link>
              </div>
              <div class="absolute bottom-0 left-6">
                <%= for tag <- post.tags do %>
                  <li class="bg-white dark:bg-zinc-800 dark:text-gray-200 text-base font-semibold shadow-md p-4 rounded-lg border-l-solid
              border-l-[5px] border-l-gray-700 float-left list-none">
                    <.link navigate={~p"/blog/tags/#{tag}"}>
                      <%= tag %>
                    </.link>
                  </li>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
