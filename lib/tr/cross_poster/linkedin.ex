defmodule Tr.CrossPoster.LinkedIn do
  @moduledoc """
  LinkedIn API client for sharing blog posts as link-type posts.

  Requires environment variables:
  - LINKEDIN_ACCESS_TOKEN: OAuth 2.0 access token
  - LINKEDIN_PERSON_URN: LinkedIn person URN (e.g., "urn:li:person:XXXXXXX")
  """

  require Logger

  @linkedin_api_url "https://api.linkedin.com/v2/ugcPosts"

  def configured? do
    access_token() != nil and person_urn() != nil
  end

  def share_post(slug, commentary \\ nil) do
    case Tr.Blog.get_post_by_slug("en", slug) do
      nil ->
        {:error, :post_not_found}

      post ->
        commentary = commentary || build_default_commentary(post)
        url = TrWeb.Endpoint.url() <> "/en/blog/" <> post.id
        do_share(commentary, url, post.title, post.description)
    end
  end

  def build_default_commentary(post) do
    tags = Enum.map_join(post.tags, " ", &"##{&1}")
    "#{post.title}\n\n#{post.description}\n\n#{tags}"
  end

  @doc """
  Generates ready-to-paste HTML for LinkedIn's long-form Article editor.

  It is the same rich HTML as the post body, except `<blockquote>` elements are
  rewritten: a quote that contains a list becomes a native top-level list, and a
  prose quote becomes a single quoted paragraph. LinkedIn's Article editor only
  preserves multi-line structure from a native `<ul>`/`<ol>` (it strips `<br>`
  and drops sibling `<p>` inside a blockquote), so this is what pastes reliably.
  """
  def generate_content(slug) do
    case Tr.Blog.get_post_by_slug("en", slug) do
      nil ->
        {:error, :post_not_found}

      post ->
        canonical_url = TrWeb.Endpoint.url() <> "/en/blog/" <> post.id

        body_html =
          linkedin_safe_html(post.body) <>
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

  @doc """
  Rewrites `<blockquote>` blocks so they survive pasting into LinkedIn's Article
  editor. Non-blockquote HTML is left untouched.

  LinkedIn's editor only keeps multi-line structure from a native top-level
  `<ul>`/`<ol>`: it strips `<br>` and drops sibling `<p>` inside a `<blockquote>`.
  So a quote containing a list becomes a native list (unwrapped from the
  blockquote); a prose quote stays a single quoted paragraph.
  """
  def linkedin_safe_html(html) do
    Regex.replace(~r/<blockquote>(.*?)<\/blockquote>/s, html, fn _full, inner ->
      rewrite_blockquote(inner)
    end)
  end

  defp rewrite_blockquote(inner) do
    items =
      ~r/<li[^>]*>(.*?)<\/li>/s
      |> Regex.scan(inner)
      |> Enum.map(fn [_, li] -> flatten_text(li) end)
      |> Enum.reject(&(&1 == ""))

    case items do
      [] ->
        ~s(<blockquote><p>“ #{flatten_text(inner)} ”</p></blockquote>)

      items ->
        tag = if Regex.match?(~r/<ol[\s>]/, inner), do: "ol", else: "ul"
        intro = inner |> String.split(~r/<[ou]l[\s>]/, parts: 2) |> List.first() |> flatten_text()
        intro_html = if intro == "", do: "", else: "<p>#{intro}</p>"
        list_html = Enum.map_join(items, "", &"<li>#{&1}</li>")
        "#{intro_html}<#{tag}>#{list_html}</#{tag}>"
    end
  end

  defp flatten_text(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\s+([,.;:!?])/, "\\1")
    |> String.trim()
  end

  defp do_share(commentary, url, title, description) do
    body =
      Jason.encode!(%{
        "author" => person_urn(),
        "lifecycleState" => "PUBLISHED",
        "specificContent" => %{
          "com.linkedin.ugc.ShareContent" => %{
            "shareCommentary" => %{"text" => commentary},
            "shareMediaCategory" => "ARTICLE",
            "media" => [
              %{
                "status" => "READY",
                "originalUrl" => url,
                "title" => %{"text" => title},
                "description" => %{"text" => description}
              }
            ]
          }
        },
        "visibility" => %{
          "com.linkedin.ugc.MemberNetworkVisibility" => "PUBLIC"
        }
      })

    headers = [
      {"Authorization", "Bearer #{access_token()}"},
      {"Content-Type", "application/json"},
      {"X-Restli-Protocol-Version", "2.0.0"}
    ]

    Finch.build(:post, @linkedin_api_url, headers, body)
    |> Finch.request(Tr.Finch)
    |> handle_response()
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}})
       when status in [200, 201] do
    case Jason.decode(body) do
      {:ok, %{"id" => post_id}} -> {:ok, post_id}
      {:ok, decoded} -> {:ok, Map.get(decoded, "id")}
      _ -> {:ok, nil}
    end
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}}) do
    Logger.error("LinkedIn API error: status=#{status} body=#{body}")
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}) do
    Logger.error("LinkedIn API request failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp access_token, do: System.get_env("LINKEDIN_ACCESS_TOKEN")
  defp person_urn, do: System.get_env("LINKEDIN_PERSON_URN")
end
