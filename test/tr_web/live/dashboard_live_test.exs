defmodule TrWeb.DashboardLiveTest do
  use TrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tr.AccountsFixtures

  describe "Dashboard page" do
    test "an annonymous user cannot render admin dashboard page", %{conn: conn} do
      conn =
        conn
        |> live(~p"/admin/dashboard")

      assert conn ==
               {:error,
                {:redirect,
                 %{to: "/", flash: %{"error" => "You must be an admin to access this page."}}}}
    end

    test "an admin can render the admin dashboard page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(admin_user_fixture())
        |> live(~p"/admin/dashboard")

      assert html =~ "Admin Dashboard"
      assert html =~ "table"
    end
  end
end
