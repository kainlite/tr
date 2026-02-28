defmodule Tr.CrossPoster.Substack do
  @moduledoc """
  Substack helper for generating cross-posting content and optionally pushing drafts.

  Always available:
  - `generate_content/1` — generates ready-to-paste HTML content from a blog post

  Optional (requires env vars):
  - `create_draft/1` — pushes a draft via the unofficial Substack API
  - Requires: SUBSTACK_SUBDOMAIN, SUBSTACK_SESSION_COOKIE
  """

  require Logger

  def draft_api_configured? do
    subdomain() != nil and session_cookie() != nil
  end

  def generate_content(slug) do
    case Tr.Blog.get_post_by_slug("en", slug) do
      nil ->
        {:error, :post_not_found}

      post ->
        canonical_url = TrWeb.Endpoint.url() <> "/en/blog/" <> post.id

        body_html =
          post.body <>
            ~s(<p><em>Originally published at <a href="#{canonical_url}">#{canonical_url}</a></em></p>)

        {:ok,
         %{
           title: post.title,
           subtitle: post.description,
           body_html: body_html,
           tags: post.tags,
           canonical_url: canonical_url
         }}
    end
  end

  def create_draft(slug) do
    if draft_api_configured?() do
      case generate_content(slug) do
        {:error, reason} ->
          {:error, reason}

        {:ok, content} ->
          do_create_draft(content)
      end
    else
      {:error, :not_configured}
    end
  end

  defp do_create_draft(content) do
    url = "https://#{subdomain()}.substack.com/api/v1/drafts"

    body =
      Jason.encode!(%{
        "draft_title" => content.title,
        "draft_subtitle" => content.subtitle,
        "draft_body" => content.body_html,
        "draft_bylines" => [],
        "audience" => "everyone"
      })

    headers = [
      {"Content-Type", "application/json"},
      {"Cookie", "substack.sid=#{session_cookie()}"}
    ]

    Finch.build(:post, url, headers, body)
    |> Finch.request(Tr.Finch)
    |> handle_response()
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}})
       when status in [200, 201] do
    case Jason.decode(body) do
      {:ok, %{"id" => draft_id}} ->
        draft_url = "https://#{subdomain()}.substack.com/publish/post/#{draft_id}"
        {:ok, draft_url}

      {:ok, _} ->
        {:ok, nil}

      _ ->
        {:ok, nil}
    end
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}}) do
    Logger.error("Substack API error: status=#{status} body=#{body}")
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}) do
    Logger.error("Substack API request failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp subdomain, do: System.get_env("SUBSTACK_SUBDOMAIN")
  defp session_cookie, do: System.get_env("SUBSTACK_SESSION_COOKIE")
end
