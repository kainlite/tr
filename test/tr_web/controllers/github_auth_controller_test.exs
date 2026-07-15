defmodule TrWeb.GithubAuthControllerTest do
  use TrWeb.ConnCase, async: true

  describe "request/2" do
    test "stores a CSRF state in the session and redirects to GitHub", %{conn: conn} do
      conn = get(conn, ~p"/auth/github")

      location = redirected_to(conn, 302)
      state = get_session(conn, :github_oauth_state)

      assert is_binary(state)
      assert location =~ "github.com/login/oauth"
      assert location =~ "state=#{state}"
    end
  end

  describe "index/2 callback CSRF protection" do
    test "rejects a callback with no state (login CSRF)", %{conn: conn} do
      conn = get(conn, "/auth/github/callback?code=attacker-code")

      assert redirected_to(conn) =~ "/blog"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Authentication failed"
    end

    test "rejects a callback with a forged state", %{conn: conn} do
      conn = get(conn, "/auth/github/callback?code=attacker-code&state=forged")

      assert redirected_to(conn) =~ "/blog"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Authentication failed"
    end
  end
end
