defmodule TrWeb.PageControllerTest do
  use TrWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Welcome to the laboratory"
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
  end
end
