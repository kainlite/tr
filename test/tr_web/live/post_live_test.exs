defmodule TrWeb.PostLiveTest do
  use TrWeb.ConnCase, async: false

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
      {:ok, lv, _html} = live(conn, ~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      slug = "upgrading-k3s-with-system-upgrade-controller"

      result =
        form(lv, "#comment_form", %{
          "comment" => %{
            "body" => "some random comment33",
            "slug" => slug
          }
        })

      render_submit(result)
      _ = follow_trigger_action(result, conn)

      comments = Tr.Post.get_comments_for_post(slug)

      assert Enum.count(comments) == 1
      assert hd(comments).body =~ "some random comment"
    end

    test "replies to a comment", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      slug = "upgrading-k3s-with-system-upgrade-controller"

      result =
        form(lv, "#comment_form", %{
          "comment" => %{
            "body" => "some random comment33",
            "slug" => slug
          }
        })

      render_submit(result)
      _ = follow_trigger_action(result, conn)

      comments = Tr.Post.get_comments_for_post(slug)
      comment = hd(comments)

      assign(conn, :parent_comment_id, comment.id)

      resultreply =
        form(lv, "#comment_form", %{
          "comment" => %{
            "body" => "some random reply",
            "slug" => slug
          }
        })

      render_submit(resultreply)
      _ = follow_trigger_action(resultreply, conn)

      comments = Tr.Post.get_comments_for_post(slug)
      reply = Enum.at(comments, 1)

      assert Enum.count(comments) == 2
      assert reply.body =~ "some random reply"
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

      assert html =~ "Online: 1"

      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert html =~ "Online: 2"
    end
  end
end
