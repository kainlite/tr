defmodule TrWeb.GoogleAuthController do
  use TrWeb, :controller

  @doc """
  `index/2` handles the callback from Google Auth API redirect.
  """
  def index(conn, %{"code" => code}) do
    {:ok, token} = ElixirAuthGoogle.get_token(code, TrWeb.Endpoint.url())
    {:ok, profile} = ElixirAuthGoogle.get_user_profile(token.access_token)

    if profile.email_verified do
      conn
      |> TrWeb.UserAuth.log_in_google_user(profile)
      |> redirect(to: ~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog", profile: profile)
    else
      conn
      |> put_flash(:error, gettext("Email not verified"))
    end
  end

  def index(conn, params) do
    index(conn, params["code"])
  end
end
