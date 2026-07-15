defmodule TrWeb.Plugs.CSPTest do
  use TrWeb.ConnCase, async: true

  alias TrWeb.Plugs.CSP

  test "call/2 sets a Content-Security-Policy header", %{conn: conn} do
    conn = CSP.call(conn, CSP.init([]))
    assert [csp] = get_resp_header(conn, "content-security-policy")

    assert csp =~ "default-src 'self'"
    assert csp =~ "object-src 'none'"
    assert csp =~ "base-uri 'self'"
    assert csp =~ "frame-ancestors 'self'"
    assert csp =~ "form-action 'self'"
  end

  test "script-src is strict: no unsafe-inline or unsafe-eval" do
    script =
      CSP.header()
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.find(&String.starts_with?(&1, "script-src"))

    refute script =~ "'unsafe-inline'"
    refute script =~ "'unsafe-eval'"
    # wasm-unsafe-eval is required for the v86 in-browser VM and is much narrower
    assert script =~ "'wasm-unsafe-eval'"
  end

  test "style-src allows unsafe-inline for server-rendered inline styles" do
    style =
      CSP.header()
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.find(&String.starts_with?(&1, "style-src"))

    assert style =~ "'unsafe-inline'"
  end

  test "the header is applied to browser routes", %{conn: conn} do
    conn = get(conn, ~p"/en/about")
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "default-src 'self'"
  end
end
