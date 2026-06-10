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

  describe "linkedin_safe_html/1" do
    test "converts a blockquote containing a list into a native top-level list" do
      html =
        "<p>Intro paragraph.</p><blockquote><ul><li><strong>One</strong>: first item.</li><li>Two: second item.</li></ul></blockquote><p>Outro paragraph.</p>"

      result = LinkedIn.linkedin_safe_html(html)

      # The list is unwrapped from the blockquote into a native <ul> that
      # LinkedIn renders as a real bullet list. Inline tags are stripped and the
      # space left before the colon is cleaned up.
      assert result =~ "<ul><li>One: first item.</li><li>Two: second item.</li></ul>"
      refute result =~ "<blockquote>"
      refute result =~ "<strong>"
      assert result =~ "<p>Intro paragraph.</p>"
      assert result =~ "<p>Outro paragraph.</p>"
    end

    test "keeps intro text that precedes the list" do
      html =
        "<blockquote><p>Before you start:</p><ul><li>Check A.</li><li>Check B.</li></ul></blockquote>"

      assert LinkedIn.linkedin_safe_html(html) ==
               "<p>Before you start:</p><ul><li>Check A.</li><li>Check B.</li></ul>"
    end

    test "preserves ordered lists as <ol>" do
      html = "<blockquote><ol><li>First.</li><li>Second.</li></ol></blockquote>"
      assert LinkedIn.linkedin_safe_html(html) == "<ol><li>First.</li><li>Second.</li></ol>"
    end

    test "collapses a prose blockquote (no list) into one quoted paragraph" do
      html = "<blockquote><p><strong>A real quote</strong> spanning words.</p></blockquote>"

      assert LinkedIn.linkedin_safe_html(html) ==
               "<blockquote><p>“ A real quote spanning words. ”</p></blockquote>"
    end

    test "leaves HTML without blockquotes unchanged" do
      html = "<h2>Title</h2><p>Body with <em>emphasis</em>.</p>"
      assert LinkedIn.linkedin_safe_html(html) == html
    end

    test "handles multiple separate blockquotes independently" do
      html =
        "<blockquote><p>First.</p></blockquote><p>mid</p><blockquote><ul><li>Bullet.</li></ul></blockquote>"

      result = LinkedIn.linkedin_safe_html(html)

      assert result =~ "<blockquote><p>“ First. ”</p></blockquote>"
      assert result =~ "<ul><li>Bullet.</li></ul>"
      assert result =~ "<p>mid</p>"
    end
  end

  describe "generate_content/1" do
    test "returns LinkedIn-safe content for a valid post" do
      post = Tr.Blog.all_posts() |> Enum.find(&(&1.lang == "en"))
      assert {:ok, content} = LinkedIn.generate_content(post.id)

      assert content.title == post.title
      assert content.subtitle == post.description
      assert content.body_html =~ "Originally published at"
      assert content.canonical_url =~ post.id
      assert is_list(content.tags)
      # Any blockquotes in the body are flattened (no nested <p> inside the quote).
      refute content.body_html =~ ~r/<blockquote>\s*<p>[^“]/
    end

    test "returns error for non-existent slug" do
      assert {:error, :post_not_found} = LinkedIn.generate_content("nonexistent-slug-xyz")
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
