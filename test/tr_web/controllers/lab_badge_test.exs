defmodule TrWeb.LabBadgeTest do
  use TrWeb.ConnCase, async: true

  test "serves an SVG badge for a known track", %{conn: conn} do
    conn = get(conn, "/labs/badge/kubernetes.svg")

    assert conn |> get_resp_header("content-type") |> hd() =~ "image/svg+xml"
    body = response(conn, 200)
    assert body =~ "<svg"
    assert body =~ "SegFault Labs"
    assert body =~ "Learn Kubernetes"
    assert body =~ "✓"
  end

  test "renders an unknown track without crashing", %{conn: conn} do
    conn = get(conn, "/labs/badge/not-a-track.svg")
    body = response(conn, 200)
    assert body =~ "<svg"
    assert body =~ "unknown track"
  end
end
