defmodule TrWeb.PostLiveTest do
  use TrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tr.AccountsFixtures

  describe "Blog articles" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = confirmed_user_fixture(%{password: password})
      admin_user_fixture()

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

      # 1st reply
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

      render_submit(resultreply, %{"comment" => %{"parent_comment_id" => comment.id}})

      comments = Tr.Post.get_comments_for_post(slug)
      reply = Enum.at(comments, 1)

      assert Enum.count(comments) == 2
      assert reply.parent_comment_id == comment.id
      assert reply.body =~ "some random reply"

      # 2nd reply
      assign(conn, :parent_comment_id, reply.id)

      resultreply2 =
        form(lv, "#comment_form", %{
          "comment" => %{
            "body" => "some random reply 2",
            "slug" => slug
          }
        })

      render_submit(resultreply2, %{"comment" => %{"parent_comment_id" => comment.id}})

      comments = Tr.Post.get_comments_for_post(slug)
      reply2 = Enum.at(comments, 2)

      assert Enum.count(comments) == 3
      assert reply2.parent_comment_id == comment.id
      assert reply2.body =~ "some random reply 2"
    end

    test "can like a post", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      lv |> element("#hero-heart-link") |> render_click()

      assert lv |> element(".float-right span.font-semibold", "1")
    end
  end

  describe "SEO and engagement" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = confirmed_user_fixture(%{password: password})
      admin_user_fixture()

      %{conn: log_in_user(conn, user), user: user, password: password}
    end

    test "renders og and twitter meta tags", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert html =~ ~s(property="og:description")
      assert html =~ ~s(property="og:image")
      assert html =~ ~s(property="og:url")
      assert html =~ ~s(name="twitter:card")
      assert html =~ ~s(name="twitter:title")
    end

    test "renders reading time", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert html =~ "min read"
    end

    test "renders related posts section", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert html =~ "Related Posts"
    end

    test "renders share buttons", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert html =~ "twitter.com/intent/tweet"
      assert html =~ "linkedin.com/sharing/share-offsite"
      assert html =~ "news.ycombinator.com/submitlink"
    end
  end

  describe "Annonymous users" do
    test "cannot comment as annonymous user", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert html =~ "Please sign in to be able to write comments"
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

    test "cannot like a post", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      assert lv |> element("#hero-heart-link") |> render_click() =~ "You need to be logged in"
    end
  end
end
