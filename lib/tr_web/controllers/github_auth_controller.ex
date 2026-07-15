defmodule TrWeb.GithubAuthController do
  use TrWeb, :controller

  alias Tr.Telemetry.Spans
  alias TrWeb.OAuthState

  @state_key :github_oauth_state

  @doc """
  Starts the GitHub OAuth flow: stores a CSRF state in the session and redirects
  to GitHub's authorization screen with that state.
  """
  def request(conn, _params) do
    {conn, state} = OAuthState.put(conn, @state_key)
    url = ElixirAuthGithub.login_url(%{scopes: ["user:email"], state: state})
    redirect(conn, external: url)
  end

  @doc """
  `index/2` handles the callback from the GitHub OAuth redirect.
  """
  def index(conn, %{"code" => code} = params) do
    Spans.trace("auth.github_callback", %{}, fn ->
      if OAuthState.valid?(conn, @state_key, params) do
        conn
        |> delete_session(@state_key)
        |> complete_login(code)
      else
        auth_failed(conn)
      end
    end)
  end

  def index(conn, _params), do: auth_failed(conn)

  defp complete_login(conn, code) do
    locale = Gettext.get_locale(TrWeb.Gettext)

    with {:ok, profile} <- ElixirAuthGithub.github_auth(code),
         email when not is_nil(email) <- profile.email do
      conn
      |> TrWeb.UserAuth.log_in_github_user(profile)
      |> redirect(to: ~p"/#{locale}/blog")
    else
      nil ->
        conn
        |> put_flash(:error, gettext("Email not verified"))
        |> redirect(to: ~p"/#{locale}/blog")

      _ ->
        auth_failed(conn)
    end
  end

  defp auth_failed(conn) do
    conn
    |> put_flash(:error, gettext("Authentication failed, please try again"))
    |> redirect(to: ~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog")
  end
end
