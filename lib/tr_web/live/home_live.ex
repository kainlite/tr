defmodule TrWeb.HomeLive do
  use TrWeb, :live_view

  alias Tr.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :posts, Blog.recent_posts())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="phx-hero dark:bg-zinc-800 dark:text-gray-200">
      <h1>Welcome to the laboratory</h1>
      <p>Be brave, explore the unknown...</p>
    </section>
    <p>
      This blog was created to document and learn about different technologies, among other things it has been deployed to a
      k3s cluster running in OCI, using elixir and the phoenix framework, postgres, docker, kubernetes on ARM64, and many other things,
      if that sounds interesting, you can follow me on twitter or create an account here to receive new posts notifications
      and later on a newsletter, so I hope you enjoy your stay and see you on the other side...
    </p>

    <%= TrWeb.AdsComponent.render_large_ad(assigns) %>

    <div class="flex flex-col">
      <div class="m-auto pb-[10px]">
        <%= unless @current_user do %>
          <p class="text-[1.2rem]">
            Get access to comments, reactions and get rid of ads for free!
            <.link navigate={~p"/users/register"} class="text-[1.25rem]  h-auto w-[217px]">
              Register
            </.link>
          </p>
        <% end %>
      </div>

      <div class="m-auto">
        <a href="https://www.buymeacoffee.com/NDx5OFh" target="_blank" class="">
          <img
            src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png"
            alt="Buy Me A Coffee"
            style="height: 60px !important;width: 217px !important; padding-bottom: 0px !important; padding-top: 0px
        !important;"
          />
        </a>
      </div>
    </div>
    <div class="flex">
      <div class="m-auto">
        <p class="text-[1.2rem] justify-center">
          Feel free to register (subscribe) to receive a monthly newsletter related to the topics on this blog and a
          notification on new articles (you can unsubscribe at any time from the settings page).
          <br /> New reactions! now you can react to posts, use these at the top of an article:
          <.icon name="hero-heart" />
          <.icon name="hero-heart-solid" />

          <.icon name="hero-hand-thumb-up" />
          <.icon name="hero-hand-thumb-up-solid" />

          <.icon name="hero-rocket-launch" />
          <.icon name="hero-rocket-launch-solid" />
        </p>
      </div>
    </div>

    <section class="row columns-2">
      <article class="column">
        <h2>Latest articles</h2>

        <ul>
          <%= for post <- @posts do %>
            <li>
              <.link navigate={~p"/blog/#{post.id}"}>
                <%= post.title %>
              </.link>
            </li>
          <% end %>
        </ul>
      </article>

      <article class="column">
        <h2>Resources</h2>
        <ul>
          <li>
            <a href="https://techsquad.rocks/blog">This blog</a>
          </li>
          <li>
            <a href="https://github.com/kainlite/tr">Github repository</a>
          </li>
          <li>
            <a href="https://twitter.com/kainlite">Twitter @kainlite</a>
          </li>
          <li>
            <.link
              rel="alternate"
              type="application/rss+xml"
              title="Blog Title"
              navigate={~p"/index.xml"}
            >
              RSS
            </.link>
          </li>
          <li>
            <.link navigate={~p"/privacy"}>
              Privacy policy
            </.link>
          </li>
        </ul>
      </article>
    </section>
    """
  end
end
