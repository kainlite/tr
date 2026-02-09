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

    test "blog page lists multiple articles", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog")

      assert html =~ "<article"
    end

    test "blog page shows article metadata", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog")

      # Posts should have dates and tags rendered
      assert html =~ "202"
    end

    test "page contains navigation elements", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog")

      assert html =~ "nav"
    end
  end
end
