defmodule Tr.CrossPoster.SubstackTest do
  use Tr.DataCase, async: true
  use Mimic

  alias Tr.CrossPoster.Substack

  describe "draft_api_configured?/0" do
    test "returns false when env vars are not set" do
      refute Substack.draft_api_configured?()
    end
  end

  describe "generate_content/1" do
    test "returns content for a valid post" do
      post = Tr.Blog.all_posts() |> Enum.find(&(&1.lang == "en"))
      assert {:ok, content} = Substack.generate_content(post.id)

      assert content.title == post.title
      assert content.subtitle == post.description
      assert content.body_html =~ "Originally published at"
      assert content.canonical_url =~ post.id
      assert is_list(content.tags)
    end

    test "returns error for non-existent slug" do
      assert {:error, :post_not_found} = Substack.generate_content("nonexistent-slug-xyz")
    end

    test "includes canonical URL in body" do
      post = Tr.Blog.all_posts() |> Enum.find(&(&1.lang == "en"))
      {:ok, content} = Substack.generate_content(post.id)

      assert content.body_html =~ content.canonical_url
    end
  end

  describe "create_draft/1" do
    test "returns error when not configured" do
      assert {:error, :not_configured} = Substack.create_draft("some-slug")
    end

    test "creates draft successfully with mocked Finch" do
      post = Tr.Blog.all_posts() |> Enum.find(&(&1.lang == "en"))

      System.put_env("SUBSTACK_SUBDOMAIN", "testblog")
      System.put_env("SUBSTACK_SESSION_COOKIE", "test-session-cookie")

      expect(Finch, :request, fn _request, _name ->
        {:ok,
         %Finch.Response{
           status: 200,
           body: Jason.encode!(%{"id" => 12_345})
         }}
      end)

      assert {:ok, draft_url} = Substack.create_draft(post.id)
      assert draft_url =~ "testblog.substack.com/publish/post/"

      System.delete_env("SUBSTACK_SUBDOMAIN")
      System.delete_env("SUBSTACK_SESSION_COOKIE")
    end

    test "returns error on API failure" do
      post = Tr.Blog.all_posts() |> Enum.find(&(&1.lang == "en"))

      System.put_env("SUBSTACK_SUBDOMAIN", "testblog")
      System.put_env("SUBSTACK_SESSION_COOKIE", "test-session-cookie")

      expect(Finch, :request, fn _request, _name ->
        {:ok, %Finch.Response{status: 401, body: "Unauthorized"}}
      end)

      assert {:error, %{status: 401, body: "Unauthorized"}} = Substack.create_draft(post.id)

      System.delete_env("SUBSTACK_SUBDOMAIN")
      System.delete_env("SUBSTACK_SESSION_COOKIE")
    end

    test "returns error for non-existent post" do
      System.put_env("SUBSTACK_SUBDOMAIN", "testblog")
      System.put_env("SUBSTACK_SESSION_COOKIE", "test-session-cookie")

      assert {:error, :post_not_found} = Substack.create_draft("nonexistent-slug-xyz")

      System.delete_env("SUBSTACK_SUBDOMAIN")
      System.delete_env("SUBSTACK_SESSION_COOKIE")
    end
  end
end
