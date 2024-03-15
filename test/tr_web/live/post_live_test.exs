defmodule TrWeb.PostLiveTest do
  use TrWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tr.AccountsFixtures

  describe "Blog articles" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = confirmed_user_fixture(%{password: password})
      %{conn: log_in_user(conn, user), user: user, password: password}
    end

    test "renders blog article", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert html =~ "Upgrading K3S with system-upgrade-controller"
    end

    test "sends a comment", %{conn: conn} do
      {:ok, lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      # form =
      #   form(lv, "#comment_form", %{
      #     "comment[body]" => "some random comment",
      #     "comment[slug]" => "upgrading-k3s-with-system-upgrade-controller"
      #   })

      # render_submit(form)
      # follow_trigger_action(form, conn)

      assert html =~ "Online: 1"
      # assert result =~ "Reply"
    end

    test "replies to a comment", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert html =~ "Upgrading K3S with system-upgrade-controller"
    end
  end

  describe "Annonymous users" do
    test "cannot comment as annonymous user", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert html =~ "Please complete your account verification to be able to write comments"
    end

    test "checks the presence counter", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert html =~ "Upgrading K3S with system-upgrade-controller"
    end
  end
end
