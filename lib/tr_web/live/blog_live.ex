defmodule TrWeb.BlogLive do
  use TrWeb, :live_view
  alias Tr.Blog
  alias TrWeb.PostComponent

  @impl true
  def mount(_params, _session, socket) do
    locale = Gettext.get_locale(TrWeb.Gettext)
    posts = Blog.posts(locale)
    featured_post = Blog.get_latest_post(locale, 1)

    {
      :ok,
      socket
      |> assign(:page_title, "SegFault - Blog")
      |> assign(:og_url, TrWeb.Endpoint.url() <> "/#{locale}/blog")
      |> assign(:og_hreflang_en, TrWeb.Endpoint.url() <> "/en/blog")
      |> assign(:og_hreflang_es, TrWeb.Endpoint.url() <> "/es/blog")
      |> assign(:posts, posts)
      |> assign(:featured_post, featured_post)
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Terminal header -->
      <div class="font-mono">
        <span class="text-accent-light dark:text-accent">$</span>
        <span class="text-terminal-400 ml-2">whoami</span>
        <p class="text-lg mt-1 text-zinc-900 dark:text-zinc-100">
          SegFault - {gettext("DevOps, Linux, Containers, Kubernetes, and cloud technologies.")}
        </p>
      </div>
      
    <!-- Featured post -->
      <%= if @featured_post do %>
        <div
          id={@featured_post.id}
          class="border-l-2 border-accent-light dark:border-accent pl-4 py-2"
        >
          <div class="font-mono text-xs text-accent-light dark:text-accent uppercase tracking-wider mb-1">
            {gettext("Latest post")}
          </div>
          <.link
            navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{@featured_post.id}"}
            class="block no-underline group"
          >
            <h2 class="text-xl sm:text-2xl font-bold font-mono text-zinc-900 dark:text-zinc-100 group-hover:text-accent-light dark:group-hover:text-accent transition-colors">
              {@featured_post.title}
            </h2>
          </.link>
          <div class="font-mono text-sm text-terminal-400 mt-1">
            {@featured_post.date} | {Tr.Blog.reading_time(@featured_post)} {gettext("min read")}
          </div>
          <p class="mt-2 text-zinc-600 dark:text-zinc-300 line-clamp-2">
            {@featured_post.description}
          </p>
        </div>
      <% end %>
      
    <!-- Post list -->
      <div class="space-y-0">
        <%= for post <- Enum.drop(@posts, 1) do %>
          {PostComponent.render_post_card(%{post: post})}
        <% end %>
      </div>
      
    <!-- Support section -->
      <div class="border-t border-terminal-300 dark:border-terminal-600 pt-4 font-mono text-sm text-terminal-400">
        <span class="text-accent-light dark:text-accent">$</span>
        <span class="ml-2">{gettext("Support this blog")}:</span>
        <a
          href="https://buymeacoffee.com/kainlite"
          target="_blank"
          rel="noopener noreferrer"
          class="ml-2 text-accent-light dark:text-accent hover:underline"
        >
          Buy Me a Coffee
        </a>
        <span class="mx-1">|</span>
        <a
          href="https://github.com/sponsors/kainlite"
          target="_blank"
          rel="noopener noreferrer"
          class="text-accent-light dark:text-accent hover:underline"
        >
          GitHub Sponsors
        </a>
      </div>
    </div>
    """
  end
end
