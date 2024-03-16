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

    test "filters by tag", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog?tag=elixir")

      assert html =~ "Upgrading to Phoenix 1.7"
    end
  end
end
