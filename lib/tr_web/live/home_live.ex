defmodule TrWeb.HomeLive do
  use TrWeb, :live_view

  alias Tr.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :posts, Blog.recent_posts(6))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
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
          <p class="text-[1.4rem] justify-center font-semibold">
            Do you need help with your project (kubernetes/dockerization/cicd/automation/etc)?
            <a href="mailto:support@techsquad.rocks" class="text-[1.25rem]  h-auto w-[217px]">
              Contact us
            </a>
            Or <link href="https://assets.calendly.com/assets/external/widget.css" rel="stylesheet" />
            <script
              src="https://assets.calendly.com/assets/external/widget.js"
              type="text/javascript"
              async
            >
            </script>
            <a
              href=""
              onclick="Calendly.initPopupWidget({url: 'https://calendly.com/kainlite/15min'});return false;"
            >
              Schedule time with me
            </a>
          </p>
          <p class="text-[1.2rem] items-center text-center justify-center">
            Register to receive a notification on new articles, the ability to comment and react to acticles.
            <.icon name="hero-heart" class="hidden" />
            <.icon name="hero-heart-solid" class="hidden" />

            <.icon name="hero-hand-thumb-up" class="hidden" />
            <.icon name="hero-hand-thumb-up-solid" class="hidden" />

            <.icon name="hero-rocket-launch" class="hidden" />
            <.icon name="hero-rocket-launch-solid" class="hidden" />
          </p>
          <div class="flex">
            <div class="mx-auto items-center text-center">
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
        </div>
      </div>
      <div class="flex flex-row flex-wrap columns-3">
        <%= for post <- @posts do %>
          <%= TrWeb.PostComponent.render_post_card(%{post: post}) %>
        <% end %>
      </div>
      <.link navigate={~p"/blog"} aria-label="blog" class="text-center items-center m-4 ">
        More...
      </.link>
    </div>
    """
  end
end
