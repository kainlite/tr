defmodule TrWeb.BlogLive do
  use TrWeb, :live_view
  alias Tr.Blog
  alias TrWeb.PostComponent

  @impl true
  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> assign(:posts, Blog.posts(Gettext.get_locale(TrWeb.Gettext)))
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
    {TrWeb.AdsComponent.render_large_ad(assigns)}

    <div class="flex flex-col">
      <div class="m-auto pb-[10px]">
        <div class="mx-auto items-center text-center justify-center">
          <iframe
            src="https://github.com/sponsors/kainlite/card"
            title="Sponsor kainlite"
            height="225"
            width="600"
            style="border: 0;"
          >
          </iframe>
          <br />

          <%= unless @current_user do %>
            <p class="text-[1.2rem]">
              <div
                style="display:flex; flex-direction:column;"
                class="mx-auto text-center items-center justify-center"
              >
                <link href="https://fonts.googleapis.com/css?family=Roboto&display=swap" />
                <a
                  href={@oauth_github_url}
                  style="display:inline-flex; align-items:center; min-height:30px;
                background-color:#24292e; font-family:'Roboto',sans-serif;
                font-size:14px; color:white; text-decoration:none;"
                >
                  <div style="margin: 1px; padding-top:5px; min-height:30px;">
                    <svg height="18" viewBox="0 0 16 16" width="32px" style="fill:white;">
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
                  </div>
                  <div style="margin-left: 5px;">{gettext("Sign in with GitHub")}</div>
                </a>
              </div>
              <div
                style="display:flex; flex-direction:column;"
                class="text-center items-center justify-center"
              >
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
                    {gettext("Sign in with Google")}
                  </div>
                </a>
              </div>
            </p>
          <% end %>
        </div>
      </div>
    </div>
    <div class="flex flex-row flex-wrap columns-3 text-center justify-center">
      <%= for post <- @posts do %>
        {PostComponent.render_post_card(%{post: post})}
      <% end %>
    </div>
    """
  end
end
