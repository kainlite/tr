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
