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
      |> assign(:posts, posts)
      |> assign(:featured_post, featured_post)
      |> assign(
        :oauth_google_url,
        ElixirAuthGoogle.generate_oauth_url(TrWeb.Endpoint.url())
      )
      |> assign(
        :oauth_github_url,
        ElixirAuthGithub.login_url(%{scopes: ["user:email"]})
      )
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-center py-6 sm:py-10 mb-6">
      <h1 class="text-4xl sm:text-5xl font-bold text-zinc-900 dark:text-white mb-3">
        SegFault
      </h1>
      <p class="text-lg sm:text-xl text-zinc-500 dark:text-zinc-400 max-w-2xl mx-auto">
        {gettext(
          "DevOps, Linux, Containers, Kubernetes, and cloud technologies. Tutorials, insights, and experiments."
        )}
      </p>
    </div>

    <%= if @featured_post do %>
      <div class="mb-8" id={@featured_post.id}>
        <.link
          navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{@featured_post.id}"}
          class="block group"
        >
          <div class="card-tech rounded-xl overflow-hidden hover:shadow-glow transition-all duration-300">
            <div class="flex flex-col sm:flex-row">
              <div class="sm:w-2/5">
                <img
                  src={~p"/images/#{@featured_post.image}"}
                  alt={@featured_post.title}
                  class="w-full h-48 sm:h-64 object-cover object-center"
                />
              </div>
              <div class="p-6 sm:w-3/5 flex flex-col justify-center">
                <span class="text-xs font-semibold uppercase tracking-wider text-brand-500 dark:text-brand-400 mb-2">
                  {gettext("Latest post")}
                </span>
                <h2 class="text-2xl sm:text-3xl font-bold text-zinc-900 dark:text-white mb-3 group-hover:text-brand-500 dark:group-hover:text-brand-400 transition-colors">
                  {@featured_post.title}
                </h2>
                <p class="text-zinc-500 dark:text-zinc-400 mb-3 line-clamp-2">
                  {@featured_post.description}
                </p>
                <div class="flex items-center gap-3 text-sm text-zinc-400 dark:text-zinc-500">
                  <time>{@featured_post.date}</time>
                  <span>-</span>
                  <span>{@featured_post.author}</span>
                </div>
              </div>
            </div>
          </div>
        </.link>
      </div>
    <% end %>

    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 justify-items-center">
      <%= for post <- Enum.drop(@posts, 1) do %>
        {PostComponent.render_post_card(%{post: post})}
      <% end %>
    </div>

    <div class="mt-12 text-center">
      <h3 class="text-xl font-bold mb-2 text-zinc-900 dark:text-white">
        {gettext("Support this blog")}
      </h3>
      <p class="text-sm text-zinc-500 dark:text-zinc-400 mb-4">
        {gettext("If you find this content useful, consider supporting the blog.")}
      </p>
      <div class="flex flex-wrap gap-4 justify-center items-center">
        <div class="overflow-x-auto">
          <iframe
            src="https://github.com/sponsors/kainlite/card"
            title="Sponsor kainlite"
            height="225"
            width="600"
            style="border: 0; max-width: 100%;"
          >
          </iframe>
        </div>
        <a
          href="https://buymeacoffee.com/kainlite"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-2 px-5 py-3 bg-[#FFDD00] text-zinc-900 font-semibold rounded-lg hover:bg-[#e5c700] transition-colors"
        >
          <svg class="w-5 h-5" viewBox="0 0 884 1279" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path
              d="m791 298c-1 0-2 0-3 0-34-2-183-1-216 0-11 0-20 10-19 21 1 10 9 18 20 18h1l102-1c-1 9-8 124-14 188-7 79-14 159-14 230 0 13 0 26 1 39 2 45 4 97 62 125 20 9 42 14 64 14 26 0 53-7 78-21 45-25 76-72 92-140 6 1 13 2 19 2 50 0 82-24 82-63 0-18-7-43-28-62-17-16-41-25-69-27 0-3 0-5 0-8-1-50-1-100-3-150l-2-79c1 0 2 0 4 1 16 1 33 2 50 2 7 0 13 0 20-1 51-4 89-36 91-77 2-27-13-63-76-72-15-2-30-3-46-3-17 0-34 1-50 2-13 1-26 2-38 2-23 0-45-3-67-5-13-2-26-3-39-4z"
              fill="#0d0c22"
            />
            <path
              d="m474 199c-107 0-127 84-127 84s-21-84-127-84c-75 0-136 61-136 136 0 86 72 180 263 277 191-97 263-191 263-277 0-75-61-136-136-136z"
              fill="#FF813F"
            />
          </svg>
          {gettext("Buy Me a Coffee")}
        </a>
      </div>
    </div>

    <%= unless @current_user do %>
      <div class="mt-10 text-center">
        <p class="text-sm text-zinc-500 dark:text-zinc-400 mb-4">
          {gettext("Sign in to comment, react, and get notifications for new posts.")}
        </p>
        <div class="flex flex-col sm:flex-row gap-3 justify-center items-center">
          <a
            href={@oauth_github_url}
            class="inline-flex items-center gap-2 px-4 py-2 bg-[#24292e] text-white text-sm font-medium rounded-lg hover:bg-[#1b1f23] transition-colors"
          >
            <svg height="18" viewBox="0 0 16 16" width="18" fill="white">
              <path
                fill-rule="evenodd"
                d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38
            0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01
            1.08.58 1.23.82.72 1.21 1.87.87
            2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12
            0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08
            2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0
            .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"
              />
            </svg>
            {gettext("Sign in with GitHub")}
          </a>
          <a
            href={@oauth_google_url}
            class="inline-flex items-center gap-2 px-4 py-2 bg-[#4285F4] text-white text-sm font-medium rounded-lg hover:bg-[#3367d6] transition-colors"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 533.5 544.3" width="18" height="18">
              <path
                d="M533.5 278.4c0-18.5-1.5-37.1-4.7-55.3H272.1v104.8h147c-6.1 33.8-25.7 63.7-54.4 82.7v68h87.7c51.5-47.4 81.1-117.4 81.1-200.2z"
                fill="#fff"
              />
              <path
                d="M272.1 544.3c73.4 0 135.3-24.1 180.4-65.7l-87.7-68c-24.4 16.6-55.9 26-92.6 26-71 0-131.2-47.9-152.8-112.3H28.9v70.1c46.2 91.9 140.3 149.9 243.2 149.9z"
                fill="#fff"
              />
              <path
                d="M119.3 324.3c-11.4-33.8-11.4-70.4 0-104.2V150H28.9c-38.6 76.9-38.6 167.5 0 244.4l90.4-70.1z"
                fill="#fff"
              />
              <path
                d="M272.1 107.7c38.8-.6 76.3 14 104.4 40.8l77.7-77.7C405 24.6 339.7-.8 272.1 0 169.2 0 75.1 58 28.9 150l90.4 70.1c21.5-64.5 81.8-112.4 152.8-112.4z"
                fill="#fff"
              />
            </svg>
            {gettext("Sign in with Google")}
          </a>
        </div>
      </div>
    <% end %>
    """
  end
end
