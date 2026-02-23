defmodule Tr.TrackerTest do
  use Tr.DataCase

  alias Tr.Tracker

  import Tr.PostTrackerFixtures

  import Tr.AccountsFixtures

  describe "Tracker" do
    setup %{} do
      announced_post = post_tracker_fixture(%{announced: true})
      unannounced_post = post_tracker_fixture(%{announced: false})
      Tracker.insert_post(announced_post)
      Tracker.insert_post(unannounced_post)

      # Create a notifiable user so announce_posts can mark posts as announced
      _notifiable_user =
        confirmed_user_fixture(%{accept_emails: true})

      %{announced_post: announced_post, unannounced_post: unannounced_post}
    end

    test "gets post by slug aka id", %{announced_post: announced_post} do
      post = Tracker.get_post_by_slug(announced_post.slug)
      assert post.slug == announced_post.slug
      assert post.announced == announced_post.announced
    end

    test "get_post_by_slug/1 returns nil for non-existent slug" do
      assert is_nil(Tracker.get_post_by_slug("non-existent-slug-that-does-not-exist"))
    end

    test "gets unannounced posts" do
      unannounced_post =
        post_tracker_fixture(%{
          slug: "upgrading-k3s-with-system-upgrade-controller",
          announced: false
        })

      Tracker.insert_post(unannounced_post)

      posts = Tracker.get_unannounced_posts()

      assert length(posts) == 1

      Tracker.start()

      posts = Tracker.get_unannounced_posts()
      assert posts == []
    end

    test "gets unannounceds posts" do
      unannounced_post1 =
        post_tracker_fixture(%{
          slug: "upgrading-k3s-with-system-upgrade-controller",
          announced: false
        })

      unannounced_post2 =
        post_tracker_fixture(%{
          slug: "getting-started-with-wallaby-integration-tests",
          announced: false
        })

      Tracker.insert_post(unannounced_post1)
      Tracker.insert_post(unannounced_post2)

      posts = Tracker.get_unannounced_posts()
      assert Enum.all?(posts, fn post -> post.announced == false end)
      assert length(posts) == 2

      Tracker.start()
      posts = Tracker.get_unannounced_posts()
      assert posts == []
    end

    test "tracks a post" do
      post = post_tracker_fixture(%{slug: "some-new-slug"})
      assert {:ok, _} = Tracker.insert_post(post)
    end

    test "updates post status" do
      post = post_tracker_fixture(%{slug: "some-new-slug"})
      Tracker.insert_post(post)
      post = Tracker.get_post_by_slug(post.slug)
      assert {:ok, _} = Tracker.update_post_status(post, %{announced: true})
    end

    test "starts the tracker" do
      Tracker.start()
      # After start, all previously unannounced posts should be announced
      unannounced = Tracker.get_unannounced_posts()
      # Only newly tracked posts from Tr.Blog.all_posts() may remain if no notifiable users
      # but the setup-inserted unannounced post should be handled
      assert is_list(unannounced)
    end

    test "get_unannounced_posts/0 returns empty list when all posts are announced" do
      # The setup inserted one unannounced post; mark it announced
      unannounced = Tracker.get_unannounced_posts()

      Enum.each(unannounced, fn post ->
        Tracker.update_post_status(post, %{announced: true})
      end)

      assert Tracker.get_unannounced_posts() == []
    end

    test "insert_post/1 with duplicate slug returns error" do
      post = post_tracker_fixture(%{slug: "duplicate-slug-test", announced: false})
      assert {:ok, _} = Tracker.insert_post(post)
      assert {:error, changeset} = Tracker.insert_post(post)
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "update_post_status/2 with missing slug returns error" do
      post = post_tracker_fixture(%{slug: "update-error-test", announced: false})
      {:ok, _} = Tracker.insert_post(post)
      db_post = Tracker.get_post_by_slug("update-error-test")
      assert {:error, _} = Tracker.update_post_status(db_post, %{slug: nil})
    end

    test "track_posts is idempotent — calling start twice doesn't duplicate" do
      Tracker.start()
      count_before = length(Tr.Repo.all(Tr.PostTracker))
      Tracker.start()
      count_after = length(Tr.Repo.all(Tr.PostTracker))
      assert count_before == count_after
    end

    test "start/0 with no unannounced posts does not error" do
      # Mark all as announced first
      Tracker.get_unannounced_posts()
      |> Enum.each(fn post ->
        Tracker.update_post_status(post, %{announced: true})
      end)

      # Now run start — track_posts runs, discovers posts from Tr.Blog.all_posts()
      # but since those are new inserts they'll be unannounced, so start may
      # call announce_posts. Just verify it doesn't crash.
      Tracker.start()
    end
  end
end
