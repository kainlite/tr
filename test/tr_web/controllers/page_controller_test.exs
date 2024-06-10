defmodule TrWeb.PageControllerTest do
  use TrWeb.ConnCase, async: false

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~
             "Sign in with Google"
  end

  describe "GET /sitemap.xml" do
    test "accesses the sitemap in format xml", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")

      assert response_content_type(conn, :xml)

      assert String.match?(
               response(conn, 200),
               ~r/<link>.*\/blog\/new-blog<\/link>/
             )
    end

    test "get all tags", %{conn: conn} do
      conn = get(conn, ~p"/blog/tags")

      assert response(conn, 200) =~ "kubernetes"
      assert response(conn, 200) =~ "elixir"
      assert response(conn, 200) =~ "vim"
    end

    test "filters by tag", %{conn: conn} do
      conn = get(conn, ~p"/blog/tags/elixir")

      assert response(conn, 200) =~ "RSS is not dead yet"
    end

    test "fetch privacy page", %{conn: conn} do
      conn = get(conn, ~p"/privacy")

      assert response(conn, 200) =~
               "The examples, code snippets, and blog articles provided herein are offered for educational or illustrative purposes\n    only."
    end
  end
end
