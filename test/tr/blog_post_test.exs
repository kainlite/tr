defmodule Tr.Blog.PostTest do
  use Tr.DataCase

  alias Tr.Blog.Post

  describe "Blog.Post" do
    test "builds a post" do
      post = %Post{
        id: "some-slug",
        title: "some title",
        body: "some body",
        tags: ["elixir", "phoenix"],
        published: true,
        author: "some author",
        description: "some description",
        date: ~D[2020-01-01],
        image: "terraform.png"
      }

      assert post.id == "some-slug"
      assert post.title == "some title"
      assert post.body == "some body"
      assert post.tags == ["elixir", "phoenix"]
      assert post.published == true
      assert post.author == "some author"
      assert post.description == "some description"
      assert post.date == ~D[2020-01-01]
      assert post.image == "terraform.png"
    end
  end
end
