defmodule TrWeb.ErrorViewTest do
  use TrWeb.ConnCase, async: true

  # Bring render/3 and render_to_string/3 for testing custom views
  import Phoenix.View

  test "renders 404.html" do
    assert render_to_string(TrWeb.ErrorView, "404.html", []) == "Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(TrWeb.ErrorView, "500.html", []) == "Internal Server Error"
  end
end
