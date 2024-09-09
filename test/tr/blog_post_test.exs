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
        image: "terraform.png",
        sponsored: true,
        video:
          "AQpBRVMuR0NNLlYxnMlG3Z1gqmBJsog8BCiq8aJ6Oplpc7ncKP2UWeziuzgze6d6gfgbu5sKEIq6C4ktQxrg+nDhACQkXz9aTZnwhYQUOYJq",
        encrypted_content:
          "AQpBRVMuR0NNLlYxJJUZ6S+zhjv81zDHqUMSo3g5JkVGsTchQlKfB7fZfxg//hMIyX/XsUCygsFRr+MFlpw0vne8FxO2Si6jshOw8lKDMNvoXioHNmgQeozlahuIce0+D0NCh5vFFsbJIi//TTpac1coUdiEbReH94yDQ07V4O848C5J7F5JjZslhGekKVjq0eT3T7PmIibJfii391tqgYUBHIg/jpY2LifxzgrHW5jaFRzrsIZNuCiBF1M4lUjSORF01aPgT68s1vHcG/+r0LE8EsCsHRT9VDvKl0F6ntgwoTUY/OSqONCbkzE2wfWsy5jGGV3YN8jCkMYIWi7FylgpCrMbb99DfNIKRA37GpvoLx08+X8YPbBRHoL1Gs3JGIi91UBAMQ=="
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
