defmodule TrWeb.Router do
  use TrWeb, :router

  import TrWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {TrWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug TrWeb.Plugs.Locale, "en"
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :xml do
    plug :accepts, ["xml"]
  end

  scope "/", TrWeb do
    pipe_through :browser

    get "/auth/google/callback", GoogleAuthController, :index
    get "/auth/github/callback", GithubAuthController, :index

    get "/blog/tags", PageController, :tags
    get "/blog/tags/:tag", PageController, :by_tag
    get "/privacy", PageController, :privacy
  end

  scope "/:locale", TrWeb do
    pipe_through :browser

    get "/auth/google/callback", GoogleAuthController, :index
    get "/auth/github/callback", GithubAuthController, :index

    get "/blog/tags", PageController, :tags
    get "/blog/tags/:tag", PageController, :by_tag
    get "/privacy", PageController, :privacy
  end

  scope "/", TrWeb do
    pipe_through :api

    get "/index.json", PageController, :json_sitemap
  end

  scope "/:locale", TrWeb do
    scope "/" do
      pipe_through :api

      get "/index.json", PageController, :json_sitemap
    end
  end

  scope "/", TrWeb do
    pipe_through :xml

    get "/index.xml", PageController, :sitemap
    get "/sitemap.xml", PageController, :sitemap
  end

  scope "/:locale", TrWeb do
    scope "/" do
      pipe_through :xml

      get "/index.xml", PageController, :sitemap
      get "/sitemap.xml", PageController, :sitemap
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:tr, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TrWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  live_session :default,
    on_mount: [{TrWeb.Hooks.AllowEctoSandbox, :default}, {TrWeb.UserAuth, :mount_current_user}] do
    # scope "/", TrWeb, host: ["local.redbeard.team", "redbeard.team"] do
    #   pipe_through :browser

    #   # live "/", BeardLive, :index
    #   live "/", BlogLive, :index
    #   live "/blog/search", SearchLive, :index

    #   live "/blog/", BlogLive, :index
    #   live "/blog/:id", PostLive, :show
    # end

    scope "/", TrWeb do
      pipe_through :browser

      # live "/", HomeLive, :index
      live "/", BlogLive, :index

      live "/blog/search", SearchLive, :index

      live "/blog/", BlogLive, :index
      live "/blog/:id", PostLive, :show
    end

    # scope "/:locale", TrWeb, host: ["local.redbeard.team", "redbeard.team"] do
    #   pipe_through :browser

    #   # live "/", BeardLive, :index
    #   live "/", BlogLive, :index
    #   live "/blog/search", SearchLive, :index

    #   live "/blog/", BlogLive, :index
    #   live "/blog/:id", PostLive, :show
    # end

    scope "/:locale", TrWeb do
      pipe_through :browser

      # live "/", HomeLive, :index
      live "/", BlogLive, :index

      live "/blog/search", SearchLive, :index

      live "/blog/", BlogLive, :index
      live "/blog/:id", PostLive, :show
    end
  end

  scope "/admin", TrWeb do
    pipe_through [:browser, :require_admin_user]

    live_session :require_admin_user,
      on_mount: [
        {TrWeb.Hooks.AllowAdmin, :require_admin_user},
        {TrWeb.Hooks.AllowEctoSandbox, :default},
        {TrWeb.UserAuth, :mount_current_user}
      ] do
      live "/dashboard", DashboardLive, :index
    end
  end

  ## Authentication routes
  scope "/", TrWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [
        {TrWeb.UserAuth, :redirect_if_user_is_authenticated},
        {TrWeb.Hooks.AllowEctoSandbox, :default},
        {TrWeb.UserAuth, :mount_current_user}
      ] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/:locale", TrWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated_localized,
      on_mount: [
        {TrWeb.UserAuth, :redirect_if_user_is_authenticated},
        {TrWeb.Hooks.AllowEctoSandbox, :default},
        {TrWeb.UserAuth, :mount_current_user}
      ] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", TrWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {TrWeb.UserAuth, :ensure_authenticated},
        {TrWeb.Hooks.AllowEctoSandbox, :default},
        {TrWeb.UserAuth, :mount_current_user}
      ] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/:locale", TrWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user_localized,
      on_mount: [
        {TrWeb.UserAuth, :ensure_authenticated},
        {TrWeb.Hooks.AllowEctoSandbox, :default},
        {TrWeb.UserAuth, :mount_current_user}
      ] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", TrWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [
        {TrWeb.UserAuth, :mount_current_user},
        {TrWeb.Hooks.AllowEctoSandbox, :default},
        {TrWeb.UserAuth, :mount_current_user}
      ] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
