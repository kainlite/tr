defmodule Tr.CrossPosterTest do
  use Tr.DataCase

  alias Tr.CrossPoster

  import Tr.CrossPostTrackerFixtures

  describe "CRUD operations" do
    test "insert_tracker/1 creates a tracker" do
      attrs = cross_post_tracker_fixture(%{slug: "crud-insert-test"})
      assert {:ok, tracker} = CrossPoster.insert_tracker(attrs)
      assert tracker.slug == "crud-insert-test"
      assert tracker.linkedin_posted == false
      assert tracker.substack_drafted == false
    end

    test "get_by_slug/1 returns tracker for existing slug" do
      attrs = cross_post_tracker_fixture(%{slug: "get-by-slug-test"})
      {:ok, _} = CrossPoster.insert_tracker(attrs)

      tracker = CrossPoster.get_by_slug("get-by-slug-test")
      assert tracker.slug == "get-by-slug-test"
    end

    test "get_by_slug/1 returns nil for non-existent slug" do
      assert is_nil(CrossPoster.get_by_slug("does-not-exist"))
    end

    test "update_tracker/2 updates fields" do
      attrs = cross_post_tracker_fixture(%{slug: "update-test"})
      {:ok, tracker} = CrossPoster.insert_tracker(attrs)

      assert {:ok, updated} =
               CrossPoster.update_tracker(tracker, %{
                 linkedin_posted: true,
                 linkedin_post_id: "urn:li:share:456"
               })

      assert updated.linkedin_posted == true
      assert updated.linkedin_post_id == "urn:li:share:456"
    end

    test "insert_tracker/1 with duplicate slug returns error" do
      attrs = cross_post_tracker_fixture(%{slug: "dup-test"})
      assert {:ok, _} = CrossPoster.insert_tracker(attrs)
      assert {:error, changeset} = CrossPoster.insert_tracker(attrs)
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "list_all/0 returns all trackers" do
      CrossPoster.insert_tracker(cross_post_tracker_fixture(%{slug: "list-all-1"}))
      CrossPoster.insert_tracker(cross_post_tracker_fixture(%{slug: "list-all-2"}))

      all = CrossPoster.list_all()
      slugs = Enum.map(all, & &1.slug)
      assert "list-all-1" in slugs
      assert "list-all-2" in slugs
    end

    test "get_all_pending/0 returns trackers with incomplete cross-posting" do
      CrossPoster.insert_tracker(cross_post_tracker_fixture(%{slug: "pending-1"}))

      CrossPoster.insert_tracker(
        cross_post_tracker_fixture(%{slug: "pending-2", linkedin_posted: true})
      )

      pending = CrossPoster.get_all_pending()
      slugs = Enum.map(pending, & &1.slug)
      assert "pending-1" in slugs
      assert "pending-2" in slugs
    end

    test "get_unposted_linkedin/0 returns trackers not posted to linkedin" do
      CrossPoster.insert_tracker(cross_post_tracker_fixture(%{slug: "li-1"}))

      CrossPoster.insert_tracker(
        cross_post_tracker_fixture(%{slug: "li-2", linkedin_posted: true})
      )

      unposted = CrossPoster.get_unposted_linkedin()
      slugs = Enum.map(unposted, & &1.slug)
      assert "li-1" in slugs
      refute "li-2" in slugs
    end

    test "get_undrafted_substack/0 returns trackers not drafted to substack" do
      CrossPoster.insert_tracker(cross_post_tracker_fixture(%{slug: "sub-1"}))

      CrossPoster.insert_tracker(
        cross_post_tracker_fixture(%{slug: "sub-2", substack_drafted: true})
      )

      undrafted = CrossPoster.get_undrafted_substack()
      slugs = Enum.map(undrafted, & &1.slug)
      assert "sub-1" in slugs
      refute "sub-2" in slugs
    end
  end

  describe "start/0" do
    test "tracks English posts from the blog" do
      CrossPoster.start()

      en_posts = Tr.Blog.all_posts() |> Enum.filter(&(&1.lang == "en"))
      assert en_posts != []

      for post <- en_posts do
        assert CrossPoster.get_by_slug(post.id) != nil
      end
    end

    test "is idempotent — calling start twice doesn't duplicate" do
      CrossPoster.start()
      count_before = length(Tr.Repo.all(Tr.CrossPostTracker))
      CrossPoster.start()
      count_after = length(Tr.Repo.all(Tr.CrossPostTracker))
      assert count_before == count_after
    end

    test "only tracks English posts" do
      CrossPoster.start()

      es_only_posts =
        Tr.Blog.all_posts()
        |> Enum.filter(&(&1.lang == "es"))
        |> Enum.reject(fn post ->
          Enum.any?(Tr.Blog.all_posts(), &(&1.lang == "en" && &1.id == post.id))
        end)

      for post <- es_only_posts do
        # Spanish-only posts should not be tracked (though most posts have both languages)
        tracker = CrossPoster.get_by_slug(post.id)

        if tracker do
          # If it exists, it's because an English version also exists
          en_post = Tr.Blog.get_post_by_slug("en", post.id)
          assert en_post != nil
        end
      end
    end
  end
end
