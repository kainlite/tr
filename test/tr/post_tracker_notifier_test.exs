defmodule Tr.PostTracker.NotifierTest do
  use Tr.DataCase

  alias Tr.PostTracker.Notifier

  import Tr.AccountsFixtures
  import Tr.PostFixtures

  describe "PostTracker Notifier" do
    setup %{} do
      password = valid_user_password()
      user = confirmed_user_fixture(%{password: password})
      _ = admin_user_fixture(%{password: password})
      post = post_fixture(%{user_id: user.id})

      %{user: user, post: post, password: password}
    end

    test "deliver new post notification", %{user: user, post: post} do
      {:ok, mail} =
        Notifier.deliver_new_post_notification(
          user,
          "New post",
          post.body,
          "/blog/upgrading-k3s-with-system-upgrade-controller"
        )

      assert mail.subject =~ "New post"
      assert mail.html_body =~ "A new article has been published on"
      assert mail.html_body =~ "upgrading-k3s-with-system-upgrade-controller"
    end

    test "deliver new comment notification", %{user: user, post: post} do
      {:ok, mail} =
        Notifier.deliver_new_comment_notification(
          user,
          post.body,
          "/blog/upgrading-k3s-with-system-upgrade-controller"
        )

      assert mail.subject =~ "new message"
      assert mail.html_body =~ "A new comment was just added to a post you are following:"
      assert mail.html_body =~ "upgrading-k3s-with-system-upgrade-controller"
    end

    test "deliver new reply notification", %{user: user, post: post} do
      {:ok, mail} =
        Notifier.deliver_new_reply_notification(
          user,
          post.body,
          "/blog/upgrading-k3s-with-system-upgrade-controller"
        )

      assert mail.subject =~ "new reply"
      assert mail.html_body =~ "A new reply was just added to a comment you are following:"
      assert mail.html_body =~ "upgrading-k3s-with-system-upgrade-controller"
    end

    test "email to field matches user email", %{user: user, post: post} do
      {:ok, mail} =
        Notifier.deliver_new_post_notification(
          user,
          "New post",
          post.body,
          "/blog/some-post"
        )

      assert [{_, email}] = mail.to
      assert email == user.email
    end

    test "email from field matches configured sender", %{user: user, post: post} do
      {:ok, mail} =
        Notifier.deliver_new_post_notification(
          user,
          "New post",
          post.body,
          "/blog/some-post"
        )

      assert {"segfault", "noreply@segfault.pw"} = mail.from
    end

    test "post notification body contains the URL", %{user: user, post: post} do
      url = "/blog/my-specific-test-post"

      {:ok, mail} =
        Notifier.deliver_new_post_notification(
          user,
          "New post",
          post.body,
          url
        )

      assert mail.html_body =~ url
    end

    test "comment notification subject includes URL slug", %{user: user, post: post} do
      url = "/blog/upgrading-k3s-with-system-upgrade-controller"

      {:ok, mail} =
        Notifier.deliver_new_comment_notification(
          user,
          post.body,
          url
        )

      assert mail.subject =~ url
    end

    test "reply notification subject includes URL slug", %{user: user, post: post} do
      url = "/blog/upgrading-k3s-with-system-upgrade-controller"

      {:ok, mail} =
        Notifier.deliver_new_reply_notification(
          user,
          post.body,
          url
        )

      assert mail.subject =~ url
    end
  end
end
