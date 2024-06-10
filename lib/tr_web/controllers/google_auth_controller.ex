defmodule TrWeb.GoogleAuthController do
  use TrWeb, :controller

  @doc """
  `index/2` handles the callback from Google Auth API redirect.
  """
  def index(conn, %{"code" => code}) do
    {:ok, token} = ElixirAuthGoogle.get_token(code, conn)
    {:ok, profile} = ElixirAuthGoogle.get_user_profile(token.access_token)

    if profile.email_verified do
      conn
      |> TrWeb.UserAuth.log_in_google_user(profile)
      |> redirect(to: ~p"/blog", profile: profile)
    else
      conn
      |> put_flash(:error, "Email not verified")
    end
  end
end
