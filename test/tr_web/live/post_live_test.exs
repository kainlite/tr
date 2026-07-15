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

      # Post a parent comment
      result =
        form(lv, "#comment_form", %{
          "comment" => %{
            "body" => "some random comment33",
            "slug" => slug
          }
        })

      render_submit(result)

      # 1st reply: click reply to set parent_comment_id in socket assigns
      comments = Tr.Post.get_comments_for_post(slug)
      comment = hd(comments)

      lv
      |> element(~s([phx-click="prepare_comment_form"][phx-value-comment-id="#{comment.id}"]))
      |> render_click()

      resultreply =
        form(lv, "#comment_form", %{
          "comment" => %{
            "body" => "some random reply",
            "slug" => slug
          }
        })

      render_submit(resultreply)

      comments = Tr.Post.get_comments_for_post(slug)
      reply = Enum.find(comments, &(&1.body =~ "some random reply"))

      assert Enum.count(comments) == 2
      assert reply.parent_comment_id == comment.id

      # 2nd reply: click reply again on the parent comment
      lv
      |> element(~s([phx-click="prepare_comment_form"][phx-value-comment-id="#{comment.id}"]))
      |> render_click()

      resultreply2 =
        form(lv, "#comment_form", %{
          "comment" => %{
            "body" => "some random reply 2",
            "slug" => slug
          }
        })

      render_submit(resultreply2)

      comments = Tr.Post.get_comments_for_post(slug)
      reply2 = Enum.find(comments, &(&1.body =~ "some random reply 2"))

      assert Enum.count(comments) == 3
      assert reply2.parent_comment_id == comment.id
    end

    test "can like a post", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> live(~p"/blog/upgrading-k3s-with-system-upgrade-controller")

      lv |> element("#hero-heart-link") |> render_click()

      assert lv |> element(".float-right span.font-semibold", "1")
    end

    test "cannot spoof user_id or self-approve a comment", %{conn: conn, user: user} do
      other = confirmed_user_fixture()
      slug = "upgrading-k3s-with-system-upgrade-controller"
      {:ok, lv, _html} = live(conn, ~p"/blog/#{slug}")

      # Simulate a crafted socket event bypassing the form fields.
      render_hook(lv, "save", %{
        "comment" => %{
          "body" => "mass-assignment attempt",
          "slug" => slug,
          "user_id" => other.id,
          "approved" => true
        }
      })

      [comment] = Tr.Post.get_comments_for_post(slug)
      assert comment.body == "mass-assignment attempt"
      assert comment.user_id == user.id
      refute comment.user_id == other.id
      refute comment.approved
    end

    test "cannot spoof user_id on a reaction", %{conn: conn, user: user} do
      slug = "upgrading-k3s-with-system-upgrade-controller"
      {:ok, lv, _html} = live(conn, ~p"/blog/#{slug}")

      render_hook(lv, "react", %{"value" => "heart", "slug" => slug, "user_id" => 999_999})

      assert Tr.Post.reaction_exists?(slug, "heart", user.id)
      refute Tr.Post.reaction_exists?(slug, "heart", 999_999)
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
