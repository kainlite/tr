defmodule Tr.CrossPoster.LinkedInTest do
  use Tr.DataCase, async: true
  use Mimic

  alias Tr.CrossPoster.LinkedIn

  describe "configured?/0" do
    test "returns false when env vars are not set" do
      refute LinkedIn.configured?()
    end
  end

  describe "build_default_commentary/1" do
    test "builds commentary from post struct" do
      post = %{
        title: "Test Post",
        description: "A test description",
        tags: ["elixir", "phoenix"]
      }

      commentary = LinkedIn.build_default_commentary(post)
      assert commentary =~ "Test Post"
      assert commentary =~ "A test description"
      assert commentary =~ "#elixir"
      assert commentary =~ "#phoenix"
    end

    test "handles empty tags" do
      post = %{title: "No Tags", description: "desc", tags: []}
      commentary = LinkedIn.build_default_commentary(post)
      assert commentary == "No Tags\n\ndesc\n\n"
    end
  end

  describe "share_post/1" do
    test "returns error when post not found" do
      assert {:error, :post_not_found} = LinkedIn.share_post("nonexistent-slug-xyz")
    end

    test "shares post successfully with mocked Finch" do
      # Get a real post slug
      post = Tr.Blog.all_posts() |> Enum.find(&(&1.lang == "en"))

      System.put_env("LINKEDIN_ACCESS_TOKEN", "test-token")
      System.put_env("LINKEDIN_PERSON_URN", "urn:li:person:test123")

      expect(Finch, :request, fn _request, _name ->
        {:ok,
         %Finch.Response{
           status: 201,
           body: Jason.encode!(%{"id" => "urn:li:share:12345"})
         }}
      end)

      assert {:ok, "urn:li:share:12345"} = LinkedIn.share_post(post.id)

      System.delete_env("LINKEDIN_ACCESS_TOKEN")
      System.delete_env("LINKEDIN_PERSON_URN")
    end

    test "returns error on API failure" do
      post = Tr.Blog.all_posts() |> Enum.find(&(&1.lang == "en"))

      System.put_env("LINKEDIN_ACCESS_TOKEN", "test-token")
      System.put_env("LINKEDIN_PERSON_URN", "urn:li:person:test123")

      expect(Finch, :request, fn _request, _name ->
        {:ok, %Finch.Response{status: 403, body: "Forbidden"}}
      end)

      assert {:error, %{status: 403, body: "Forbidden"}} = LinkedIn.share_post(post.id)

      System.delete_env("LINKEDIN_ACCESS_TOKEN")
      System.delete_env("LINKEDIN_PERSON_URN")
    end

    test "handles custom commentary" do
      post = Tr.Blog.all_posts() |> Enum.find(&(&1.lang == "en"))

      System.put_env("LINKEDIN_ACCESS_TOKEN", "test-token")
      System.put_env("LINKEDIN_PERSON_URN", "urn:li:person:test123")

      expect(Finch, :request, fn _request, _name ->
        {:ok,
         %Finch.Response{
           status: 201,
           body: Jason.encode!(%{"id" => "urn:li:share:99999"})
         }}
      end)

      assert {:ok, "urn:li:share:99999"} = LinkedIn.share_post(post.id, "Custom commentary!")

      System.delete_env("LINKEDIN_ACCESS_TOKEN")
      System.delete_env("LINKEDIN_PERSON_URN")
    end
  end
end
