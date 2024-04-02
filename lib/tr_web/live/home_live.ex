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
    <section class="phx-hero">
      <h1>Welcome to the laboratory</h1>
      <p>Be brave, explore the unknown...</p>
    </section>
    <p>
      This blog was created to document and learn about different technologies, among other things it has been deployed to a
      k3s cluster running in OCI, using elixir and the phoenix framework, postgres, docker, kubernetes on ARM64, and many other things,
      if that sounds interesting, you can follow me on twitter or create an account here to receive new posts notifications
      and later on a newsletter, so I hope you enjoy your stay and see you on the other side...
    </p>

    <div class="flex">
      <div class="m-auto pb-[10px]">
        <%= unless @current_user do %>
          <.link navigate={~p"/users/register"} class="text-[1.25rem] button h-auto w-[217px]">
            Subscribe
          </.link>
        <% end %>
        <a href="https://www.buymeacoffee.com/NDx5OFh" target="_blank" class="">
          <img
            src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png"
            alt="Buy Me A Coffee"
            style="height: 60px !important;width: 217px !important;"
          />
        </a>
      </div>
    </div>
    <div class="flex">
      <div class="m-auto">
        <p class="text-[1.2rem] justify-center">
          Feel free to register (subscribe) to receive a monthly newsletter related to the topics on this blog and a
          notification on new articles (you can unsubscribe at any time from the settings page), in the future I expect to
          develop more features that rely on authentication, so the earlier is set the easiest will be later on.
        </p>
        <br />
      </div>
    </div>

    <section class="row">
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
