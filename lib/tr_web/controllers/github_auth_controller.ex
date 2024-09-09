defmodule TrWeb.GithubAuthController do
  use TrWeb, :controller

  @doc """
  `index/2` handles the callback from Google Auth API redirect.
  """
  def index(conn, %{"code" => code}) do
    {:ok, profile} = ElixirAuthGithub.github_auth(code)

    if profile.email do
      conn
      |> TrWeb.UserAuth.log_in_github_user(profile)
      |> redirect(to: ~p"/blog", profile: profile)
    else
      conn
      |> put_flash(:error, "Email not verified")
    end
  end

  def index(conn, params) do
    index(conn, params["code"])
  end
end
