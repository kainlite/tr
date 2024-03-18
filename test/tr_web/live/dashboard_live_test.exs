defmodule TrWeb.DashboardLiveTest do
  use TrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "Dashboard page" do
    test "renders admin dashboard page", %{conn: conn} do
      conn =
        conn
        |> live(~p"/admin/dashboard")

      assert conn ==
               {:error,
                {:redirect,
                 %{to: "/", flash: %{"error" => "You must be an admin to access this page."}}}}
    end
  end
end
