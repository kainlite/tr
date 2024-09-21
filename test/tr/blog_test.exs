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
      posts = Blog.by_tag(Enum.random(Blog.all_tags()))
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
  end
end
