defmodule TrWeb.GoogleAuthController do
  use TrWeb, :controller

  alias Tr.Telemetry.Spans
  alias TrWeb.OAuthState

  @state_key :google_oauth_state

  @doc """
  Starts the Google OAuth flow: stores a CSRF state in the session and redirects
  to Google's consent screen with that state.
  """
  def request(conn, _params) do
    {conn, state} = OAuthState.put(conn, @state_key)
    redirect(conn, external: ElixirAuthGoogle.generate_oauth_url(TrWeb.Endpoint.url(), state))
  end

  @doc """
  `index/2` handles the callback from the Google OAuth redirect.
  """
  def index(conn, %{"code" => code} = params) do
    Spans.trace("auth.google_callback", %{}, fn ->
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

    with {:ok, token} <- ElixirAuthGoogle.get_token(code, TrWeb.Endpoint.url()),
         {:ok, profile} <- ElixirAuthGoogle.get_user_profile(token.access_token),
         true <- profile.email_verified do
      conn
      |> TrWeb.UserAuth.log_in_google_user(profile)
      |> redirect(to: ~p"/#{locale}/blog")
    else
      false ->
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
