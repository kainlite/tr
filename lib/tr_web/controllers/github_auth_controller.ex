defmodule TrWeb.GithubAuthController do
  require Logger

  use TrWeb, :controller

  @doc """
  `index/2` handles the callback from Google Auth API redirect.
  """
  def index(conn, %{"code" => code}) do
    {:ok, profile} = ElixirAuthGithub.github_auth(code)

    Logger.info("Github profile: #{inspect(profile)}")

    if profile.email do
      conn
      |> TrWeb.UserAuth.log_in_github_user(profile)
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
