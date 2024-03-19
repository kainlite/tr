defmodule Tr.TrackerTest do
  use Tr.DataCase

  alias Tr.Tracker

  import Tr.PostTrackerFixtures

  describe "Tracker" do
    setup %{} do
      announced_post = post_tracker_fixture(%{announced: true})
      unannounced_post = post_tracker_fixture(%{announced: false})
      Tracker.insert_post(announced_post)
      Tracker.insert_post(unannounced_post)

      %{announced_post: announced_post, unannounced_post: unannounced_post}
    end

    test "gets post by slug aka id", %{announced_post: announced_post} do
      post = Tracker.get_post_by_slug(announced_post.slug)
      assert post.slug == announced_post.slug
      assert post.announced == announced_post.announced
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
      assert [] = Tracker.start()
    end
  end
end
