defmodule TrWeb.UserLoginLive do
  use TrWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <div class="font-mono text-accent-light dark:text-accent mb-4">$ login --user</div>
      <.header class="text-center dark:text-zinc-100">
        {gettext("Sign in to account")}
        <:subtitle>
          {gettext("Don't have an account?")}
          <.link
            navigate={~p"/users/register"}
            class="font-semibold text-accent-light dark:text-accent hover:underline"
          >
            {gettext("Sign up")}
          </.link>
          {gettext("for an account now.")}
        </:subtitle>
      </.header>

      <TrWeb.OAuthComponent.buttons
        oauth_google_url={@oauth_google_url}
        oauth_github_url={@oauth_github_url}
      />

      <.simple_form for={@form} id="login_form" action={~p"/users/log_in"} phx-update="ignore">
        <.input field={@form[:email]} type="email" label={gettext("Email")} required />
        <.input field={@form[:password]} type="password" label={gettext("Password")} required />

        <:actions>
          <.input field={@form[:remember_me]} type="checkbox" label={gettext("Keep me logged in")} />
          <.link href={~p"/users/reset_password"} class="text-sm font-semibold">
            {gettext("Forgot your password?")}
          </.link>
        </:actions>
        <:actions>
          <.button phx-disable-with={gettext("Signing in...")} class="w-full">
            {gettext("Sign in")} <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    socket =
      socket
      |> assign(form: form)
      |> assign(:oauth_google_url, ElixirAuthGoogle.generate_oauth_url(TrWeb.Endpoint.url()))
      |> assign(:oauth_github_url, ElixirAuthGithub.login_url(%{scopes: ["user:email"]}))

    {:ok, socket, temporary_assigns: [form: form]}
  end
end
