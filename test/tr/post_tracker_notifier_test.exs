defmodule Tr.PostTracker.NotifierTest do
  use Tr.DataCase

  alias Tr.PostTracker.Notifier

  import Tr.AccountsFixtures
  import Tr.PostFixtures

  describe "PostTracker Notifier" do
    setup %{} do
      password = valid_user_password()
      user = confirmed_user_fixture(%{password: password})
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
      assert mail.text_body =~ "A new article was just added:"
      assert mail.text_body =~ "upgrading-k3s-with-system-upgrade-controller"
    end

    test "deliver new comment notification", %{user: user, post: post} do
      {:ok, mail} =
        Notifier.deliver_new_comment_notification(
          user,
          "New comment",
          post.body,
          "/blog/upgrading-k3s-with-system-upgrade-controller"
        )

      assert mail.subject =~ "New comment"
      assert mail.text_body =~ "A new comment was just added to a post you are following:"
      assert mail.text_body =~ "upgrading-k3s-with-system-upgrade-controller"
    end

    test "deliver new reply notification", %{user: user, post: post} do
      {:ok, mail} =
        Notifier.deliver_new_reply_notification(
          user,
          "New comment",
          post.body,
          "/blog/upgrading-k3s-with-system-upgrade-controller"
        )

      assert mail.subject =~ "New comment"
      assert mail.text_body =~ "A new reply was just added to a comment you are following:"
      assert mail.text_body =~ "upgrading-k3s-with-system-upgrade-controller"
    end
  end
end
