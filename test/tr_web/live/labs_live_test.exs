defmodule TrWeb.LabsLiveTest do
  use TrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "Labs index" do
    test "renders the header and intro", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/labs")

      assert html =~ "Interactive Labs"
      assert html =~ "ls /labs"
    end

    test "lists the learning tracks", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/labs")

      assert html =~ "Learn Linux"
      assert html =~ "Learn Kubernetes"
      assert html =~ "Networking &amp; SSH"
    end

    test "renders lab rows with completion hooks for the client", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/labs")

      assert html =~ "data-lab-id"
      assert html =~ "data-track"
      assert html =~ ~s(phx-hook="LabProgress")
    end

    test "lists posts that contain labs and links into them", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/labs")

      assert html =~ "Posts with labs"
      assert html =~ "/en/blog/my_local_environment#"
    end
  end
end
