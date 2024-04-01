defmodule TrWeb.SearchLiveTest do
  use TrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "Search page" do
    test "renders search page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/search")

      assert html =~ "Try full terms"
    end

    test "search by term", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> live(~p"/blog/search")

      result =
        form(lv, "#search_form", %{
          "search" => %{"q" => "linux"}
        })
        |> render_submit()

      assert result =~ "linux"
    end
  end
end
