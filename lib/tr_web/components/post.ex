defmodule TrWeb.PostComponent do
  @moduledoc """
  Comment dumb component
  """
  use TrWeb, :html

  def render_tag_card(assigns) do
    ~H"""
    <li class="tag-pill list-none mx-1 px-3 py-1.5 hover:shadow-glow-sm">
      <.link
        navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/tags/#{@tag}"}
        class="inline-flex items-center gap-2 font-mono text-sm no-underline"
      >
        <span class="text-terminal-500 dark:text-accent-muted">[{@tag}]</span>
        <span class="text-terminal-400 text-xs">
          {Enum.count(Tr.Blog.by_tag(Gettext.get_locale(TrWeb.Gettext), @tag))}
        </span>
      </.link>
    </li>
    """
  end

  def render_post_card(assigns) do
    ~H"""
    <div id={@post.id} class="border-b border-terminal-300 dark:border-terminal-600 py-4">
      <div class="flex items-start justify-between gap-4">
        <div class="flex-1 min-w-0">
          <h2 class="text-lg font-bold font-mono break-words">
            <.link
              navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{@post.id}"}
              class="text-zinc-900 dark:text-zinc-100 hover:text-accent-light dark:hover:text-accent transition-colors no-underline"
            >
              {@post.title}
            </.link>
          </h2>
          <div class="font-mono text-sm text-terminal-400 mt-1">
            {@post.date} | {Tr.Blog.reading_time(@post)} {Gettext.gettext(TrWeb.Gettext, "min read")}
          </div>
          <p class="mt-1 text-sm text-zinc-600 dark:text-zinc-300 line-clamp-2">
            {raw(@post.description)}
          </p>
          <div class="flex flex-wrap gap-2 mt-2">
            <%= for tag <- @post.tags do %>
              <.link
                navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/tags/#{tag}"}
                class="font-mono text-xs text-terminal-400 dark:text-accent-muted hover:text-accent-light dark:hover:text-accent no-underline transition-colors"
              >
                [{tag}]
              </.link>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
