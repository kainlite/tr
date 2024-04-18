defmodule TrWeb.ErrorHTMLTest do
  use TrWeb.ConnCase, async: false

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html" do
    assert render_to_string(TrWeb.ErrorHTML, "404", "html", []) =~
             "It seems we cannot find the page you are looking for"
  end

  test "renders 500.html" do
    assert render_to_string(TrWeb.ErrorHTML, "500", "html", []) =~
             "It seems we cannot find the page you are looking for"
  end
end
