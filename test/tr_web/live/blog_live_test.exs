defmodule TrWeb.BlogLiveTest do
  use TrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "Blog page" do
    test "renders blog page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog")

      assert html =~ "Upgrading K3S with system-upgrade-controller"
    end
  end
end
