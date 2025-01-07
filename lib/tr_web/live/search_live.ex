defmodule TrWeb.SearchLive do
  use TrWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:q, nil)
     |> assign(:posts, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    {TrWeb.AdsComponent.render_large_ad(assigns)}
    <div class="mx-auto mt-20 flex flex-col space-y-8 bg-white p-8 shadow-sm dark:bg-zinc-900">
      <.form :let={f} for={%{}} as={:search} phx-change="search" phx-submit="search" id="search_form">
        <.input
          type="search"
          field={f[:q]}
          placeholder={gettext("Try full terms like: linux, kubernetes, elixir...")}
          value={@q}
          autofocus="true"
          class="max-w-2xl border border-gray-100 text-2xl active:border-0 active:border-gray-200 focus:border-gray-200 focus:ring-0 bg-gray-50"
        />
      </.form>
      <div class="flex flex-col space-y-8">
        <div :for={post <- @posts} class="flex flex-col space-y-1">
          <h2 class="text-4xl font-medium text-gray-900">
            <.link navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{post.id}"}>
              {post.title}
            </.link>
          </h2>
          {raw(post.description)}
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"search" => %{"q" => q}}, socket) do
    posts =
      try do
        q
        |> Tr.Search.search()
        |> Enum.map(& &1.ref)
        |> Tr.Blog.take()
      rescue
        Haystack.Storage.NotFoundError -> []
      end

    {:noreply, assign(socket, :posts, posts)}
  end
end
