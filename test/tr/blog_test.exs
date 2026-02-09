defmodule Tr.BlogTest do
  use Tr.DataCase

  alias Tr.Blog

  describe "Blog" do
    test "gets all posts sorted by date and filtered by published" do
      posts = Blog.posts("en")

      assert Enum.sort_by(posts, & &1.date, {:desc, Date}) == posts
      assert Enum.all?(posts, & &1.published)
      assert Enum.count(posts, & &1.published) > 0
    end

    test "gets all slugs" do
      slugs = Blog.all_slugs()
      assert Enum.sort(slugs) == slugs
      assert Enum.count(slugs) > 0
    end

    test "gets all tags" do
      tags = Blog.all_tags()
      assert Enum.sort(tags) == tags
      assert Enum.count(tags) > 0
    end

    test "gets posts by tag" do
      posts = Blog.by_tag("en", Enum.random(Blog.all_tags()))
      assert Enum.count(posts) > 0
    end

    test "gets recent posts" do
      posts = Blog.recent_posts("en")
      assert Enum.count(posts) > 0
    end

    test "gets post by id" do
      post = Enum.random(Blog.posts("en"))
      assert Blog.get_post_by_id!(post.id) == post
    end

    test "gets post by slug" do
      post = Enum.random(Blog.posts("en"))
      assert Blog.get_post_by_slug("en", post.id) == post
    end

    test "raises NotFoundError when post by id is not found" do
      assert_raise Blog.NotFoundError, "post with id=0 not found", fn ->
        Blog.get_post_by_id!(0)
      end
    end

    test "gets Spanish posts" do
      posts = Blog.posts("es")
      assert Enum.all?(posts, &(&1.lang == "es"))
      assert Enum.count(posts) > 0
    end

    test "all_posts/0 returns all published posts" do
      posts = Blog.all_posts()
      assert Enum.all?(posts, & &1.published)
      assert Enum.count(posts) > 0
    end

    test "recent_posts/2 respects the count parameter" do
      posts = Blog.recent_posts("en", 3)
      assert length(posts) == 3
    end

    test "get_latest_post/2 returns single latest post" do
      post = Blog.get_latest_post("en")
      [first | _] = Blog.posts("en")
      assert post.id == first.id
    end

    test "get_post_by_slug/1 without locale returns post or nil" do
      post = Enum.random(Blog.posts("en"))
      assert Blog.get_post_by_slug(post.id) != nil
    end

    test "get_post_by_slug/2 returns nil for non-existent slug" do
      assert Blog.get_post_by_slug("en", "nonexistent-slug-that-does-not-exist") == nil
    end

    test "get_post_by_id!/2 with locale raises for non-existent" do
      assert_raise Blog.NotFoundError, fn ->
        Blog.get_post_by_id!("en", "nonexistent-id")
      end
    end

    test "by_tag/2 raises NotFoundError for non-existent tag" do
      assert_raise Blog.NotFoundError, fn ->
        Blog.by_tag("en", "nonexistent-tag-xyz")
      end
    end

    test "encrypted_posts/1 returns only encrypted posts" do
      posts = Blog.encrypted_posts("en")
      assert Enum.all?(posts, &(&1.encrypted_content == true))
    end

    test "take/1 returns posts for given ids" do
      [p1, p2 | _] = Blog.posts("en")
      result = Blog.take([p1.id, p2.id])
      assert length(result) == 2
      assert Enum.at(result, 0).id == p1.id
      assert Enum.at(result, 1).id == p2.id
    end
  end
end
