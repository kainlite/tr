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
    <div class="max-w-2xl mx-auto py-8">
      <div class="font-mono text-accent-light dark:text-accent mb-4">$ search</div>
      <.form :let={f} for={%{}} as={:search} phx-change="search" phx-submit="search" id="search_form">
        <div class="flex items-center gap-2 border border-terminal-300 dark:border-terminal-600 bg-terminal-100 dark:bg-terminal-800 px-4 py-3">
          <span class="font-mono text-accent-light dark:text-accent">></span>
          <input
            type="text"
            name={f[:q].name}
            id={f[:q].id}
            value={@q}
            placeholder={gettext("Try full terms like: linux, kubernetes, elixir...")}
            class="flex-1 bg-transparent border-none font-mono text-lg focus:ring-0 focus:outline-none p-0 text-zinc-900 dark:text-zinc-100 placeholder:text-terminal-400"
            autofocus="true"
          />
        </div>
      </.form>

      <div :if={@posts != []} class="mt-6 space-y-0">
        <div :for={post <- @posts} class="border-b border-terminal-300 dark:border-terminal-600 py-3">
          <.link
            navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{post.id}"}
            class="font-mono font-semibold hover:text-accent-light dark:hover:text-accent transition-colors"
          >
            {post.title}
          </.link>
          <p class="text-sm text-terminal-400 mt-1 line-clamp-2">{raw(post.description)}</p>
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
