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

    test "search with no results shows appropriate message", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> live(~p"/blog/search")

      result =
        form(lv, "#search_form", %{
          "search" => %{"q" => "xyznonexistentterm123"}
        })
        |> render_submit()

      refute result =~ "<article"
    end

    test "search form has correct structure", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/search")

      assert html =~ "search_form"
      assert html =~ "search"
    end
  end
end
