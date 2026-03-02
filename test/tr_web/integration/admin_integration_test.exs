defmodule TrWeb.Integration.AdminIntegrationTest do
  use TrWeb.FeatureCase, async: false
  use Wallaby.Feature
  use Phoenix.VerifiedRoutes, router: TrWeb.Router, endpoint: TrWeb.Endpoint

  import Tr.PostFixtures

  import Wallaby.Query
  import Wallaby.Browser

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
    |> assert_has(css("span", text: "sre-dashboard --stats"))
    |> assert_has(css("table#comments"))
    |> assert_has(css("table#comments th", text: "id"))
    |> assert_has(css("table#comments th", text: "email"))
    |> assert_has(css("table#comments th", text: "slug"))
    |> assert_has(css("table#comments th", text: "body"))
    |> assert_has(css("table#comments th", text: "actions"))
  end

  test "an admin user can approve a comment", %{session: session} do
    comment_fixture()

    log_in({:admin, session})

    session
    |> visit("/admin/dashboard")
    |> assert_has(css("span", text: "sre-dashboard --stats"))
    |> assert_has(css("table#comments"))
    |> accept_confirm(fn s ->
      click(s, css("a", text: "[approve]"))
    end)

    session
    |> assert_has(css("div#flash", text: "Comment approved successfully.", wait: 10_000))
  end

  test "an admin user can delete a comment", %{session: session} do
    comment_fixture()

    log_in({:admin, session})

    session
    |> visit("/admin/dashboard")
    |> assert_has(css("span", text: "sre-dashboard --stats"))
    |> assert_has(css("table#comments"))
    |> accept_confirm(fn s ->
      click(s, css("a", text: "[delete]"))
    end)

    session
    |> assert_has(css("div#flash", text: "Comment deleted successfully."))
  end
end
