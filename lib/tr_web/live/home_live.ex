defmodule TrWeb.HomeLive do
  use TrWeb, :live_view

  alias Tr.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:posts, Blog.recent_posts(6))
     |> assign(
       :oauth_google_url,
       ElixirAuthGoogle.generate_oauth_url(%{
         host: System.get_env("PHX_HOST") || "techsquad.rocks",
         scheme: System.get_env("PHX_SCHEME") || :https
       })
     )}
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
              <!-- <div style="display:flex; flex-direction:column; width:368px; text-center items-center
              justify-center"> -->
              <div style="display:none; flex-direction:column; width:368px; text-center items-center justify-center">
                <link href="https://fonts.googleapis.com/css?family=Roboto&display=swap" />

                <a
                  href={@oauth_google_url}
                  style="display:inline-flex; align-items:center; min-height:50px;
              background-color:#4285F4; font-family:'Roboto',sans-serif;
              font-size:28px; color:white; text-decoration:none;
              margin-top: 12px;"
                  class="rounded-lg center-content text-center"
                >
                  <div style="background-color: white; margin:2px; padding-top:18px; padding-bottom:6px; min-height:59px; width:72px">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      viewBox="0 0 533.5 544.3"
                      width="52px"
                      height="35"
                      style="display:inline-flex; align-items:center;"
                    >
                      <path
                        d="M533.5 278.4c0-18.5-1.5-37.1-4.7-55.3H272.1v104.8h147c-6.1 33.8-25.7 63.7-54.4 82.7v68h87.7c51.5-47.4 81.1-117.4 81.1-200.2z"
                        fill="#4285f4"
                      />
                      <path
                        d="M272.1 544.3c73.4 0 135.3-24.1 180.4-65.7l-87.7-68c-24.4 16.6-55.9 26-92.6 26-71 0-131.2-47.9-152.8-112.3H28.9v70.1c46.2 91.9 140.3 149.9 243.2 149.9z"
                        fill="#34a853"
                      />
                      <path
                        d="M119.3 324.3c-11.4-33.8-11.4-70.4 0-104.2V150H28.9c-38.6 76.9-38.6 167.5 0 244.4l90.4-70.1z"
                        fill="#fbbc04"
                      />
                      <path
                        d="M272.1 107.7c38.8-.6 76.3 14 104.4 40.8l77.7-77.7C405 24.6 339.7-.8 272.1 0 169.2 0 75.1 58 28.9 150l90.4 70.1c21.5-64.5 81.8-112.4 152.8-112.4z"
                        fill="#ea4335"
                      />
                    </svg>
                  </div>
                  <div style="margin-left: 27px;">
                    Sign in with Google
                  </div>
                </a>
              </div>
            </p>
          <% end %>
        </div>

        <div class="m-auto">
          <p class="text-[1.2rem] items-center text-center justify-center">
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
