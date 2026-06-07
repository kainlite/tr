defmodule TrWeb.PageControllerTest do
  use TrWeb.ConnCase, async: false

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~
             "DevOps, Linux, Containers, Kubernetes, and cloud technologies."
  end

  describe "GET /sitemap.xml" do
    test "accesses the sitemap in format xml", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")

      assert response_content_type(conn, :xml)

      body = response(conn, 200)
      assert body =~ "<urlset"
      assert body =~ "sitemaps.org/schemas/sitemap/0.9"
      assert body =~ "/en/blog/new-blog"
      assert body =~ "hreflang"
    end

    test "accesses the RSS feed in format xml", %{conn: conn} do
      conn = get(conn, "/index.xml")

      assert response_content_type(conn, :xml)

      body = response(conn, 200)

      assert String.match?(
               body,
               ~r/<link>.*\/blog\/new-blog<\/link>/
             )

      # The feed must carry the full post body via content:encoded so that
      # off-site consumers (RSS readers, Substack import) get the whole article
      # and not just the short description.
      assert body =~ "xmlns:content=\"http://purl.org/rss/1.0/modules/content/\""
      assert body =~ "<content:encoded>"
      assert body =~ "This is my new blog"
    end

    test "RSS content:encoded rewrites root-relative image paths to absolute URLs", %{conn: conn} do
      conn = get(conn, "/index.xml")

      body = response(conn, 200)
      base = TrWeb.Endpoint.url()

      # Post bodies reference images as /images/... ; in the exported feed these
      # must be absolute so they render off-site (e.g. when imported to Substack).
      refute body =~ "src=\"/images/"
      assert body =~ "src=\"#{base}/images/"
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

    test "fetch about page", %{conn: conn} do
      conn = get(conn, ~p"/about")

      assert response(conn, 200) =~ "Gabriel Garrido"
      assert response(conn, 200) =~ "About the blog"
    end
  end

  describe "GET /llms.txt" do
    test "serves llms.txt with correct format", %{conn: conn} do
      conn = get(conn, "/llms.txt")

      body = response(conn, 200)
      assert response_content_type(conn, :text)
      assert body =~ "# SegFault"
      assert body =~ "Gabriel Garrido"
      assert body =~ "## DevOps from Zero to Hero Series"
      assert body =~ "## SRE Series"
      assert body =~ "## Optional"
    end
  end

  describe "GET /index.json" do
    test "accesses the sitemap in format json", %{conn: conn} do
      conn = get(conn, "/en/index.json")
      assert response_content_type(conn, :json)

      assert String.match?(
               response(conn, 200),
               ~r/{\"version\":\"https\:\/\/jsonfeed.org\/version\/1\.1\"\,\"description\"\:\"Learn about DevOps\, Linux\,/
             )
    end
  end
end
