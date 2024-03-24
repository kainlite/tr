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

      # 1st reply
      comments = Tr.Post.get_comments_for_post(slug)
      comment = hd(comments)

      conn = assign(conn, :parent_comment_id, comment.id)
      IO.inspect(conn, pretty: true)

      resultreply =
        form(lv, "#comment_form", %{
          "comment" => %{
            "body" => "some random reply",
            "slug" => slug
          }
        })

      render_submit(resultreply, %{parent_comment_id: comment.id})
      _ = follow_trigger_action(resultreply, conn)

      comments = Tr.Post.get_comments_for_post(slug)
      reply = Enum.at(comments, 1)

      IO.inspect(reply, pretty: true)

      assert Enum.count(comments) == 2
      assert reply.parent_comment_id == comment.id
      assert reply.body =~ "some random reply"

      # 2nd reply
      first_reply = Enum.at(comment, 1)
      conn = assign(conn, :parent_comment_id, first_reply.id)

      IO.inspect(conn, pretty: true)

      resultreply2 =
        form(lv, "#comment_form", %{
          "comment" => %{
            "body" => "some random reply 2",
            "slug" => slug
          }
        })

      render_submit(resultreply2, %{parent_comment_id: reply.id})
      _ = follow_trigger_action(resultreply2, conn)

      comments = Tr.Post.get_comments_for_post(slug)
      reply2 = Enum.at(comments, 2)

      IO.inspect(reply2, pretty: true)

      assert Enum.count(comments) == 3
      assert reply2.parent_comment_id == comment.id
      assert reply2.body =~ "some random reply 2"
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
