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
          "AQpBRVMuR0NNLlYx4ip+EAWEzH1p+PskhwGtZrgGIOm4xMTDVEsqbIusxiTWueU3Mm3k8yCAEw9oweCsEwRO7d0f7ibVEZHgz/zgwecG7Gdy",
        encrypted_content:
          "AQpBRVMuR0NNLlYxyxHp0XKGD8ILH5ghdzsE6y9MLd2FJN1kMurokKoAv4CxUJXB9unmg+jx8yfun0VqXNo53xD/ao3NrWk="
      }

      video_decoded = Base.decode64!(post.video)
      {:ok, video_decrypted} = Tr.Vault.decrypt(video_decoded)

      encrypted_content_decoded = Base.decode64!(post.encrypted_content)
      {:ok, encrypted_content_decrypted} = Tr.Vault.decrypt(encrypted_content_decoded)

      assert post.id == "some-slug"
      assert post.title == "some title"
      assert post.body == "some body"
      assert post.tags == ["elixir", "phoenix"]
      assert post.published == true
      assert post.author == "some author"
      assert post.description == "some description"
      assert post.date == ~D[2020-01-01]
      assert post.image == "terraform.png"
      assert post.sponsored == true
      assert video_decrypted == "https://www.youtube.com/embed/sDjXY5RJX3c"
      assert encrypted_content_decrypted == "This is the content of the post"
    end
  end
end
