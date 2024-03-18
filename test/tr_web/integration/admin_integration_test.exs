defmodule TrWeb.Integration.AdminIntegrationTest do
  use TrWeb.FeatureCase, async: false
  use Wallaby.Feature
  use Phoenix.VerifiedRoutes, router: TrWeb.Router, endpoint: TrWeb.Endpoint

  import Wallaby.Query

  import TrWeb.TestHelpers

  describe "Admin pages" do
    test "a normal user cannot visit the admin dashboard", %{session: session} do
      log_in({:normal, session})

      session
      |> visit("/admin/dashboard")
      |> assert_has(css("div #flash", text: "You must be an admin to access this page."))
    end

    test "annonymous users cannot visit the admin dashboard", %{session: session} do
      session
      |> visit("/admin/dashboard")
      |> assert_has(css("div #flash", text: "You must be an admin to access this page."))
    end
  end

  test "an admin user can visit the admin dashboard", %{session: session} do
    log_in({:admin, session})

    session
    |> visit("/admin/dashboard")
    |> assert_has(css("h2", text: "Admin Dashboard"))
  end
end
