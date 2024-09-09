defmodule Tr.Sponsors do
  @moduledoc """
  Basic task to fetch the list of sponsors from GitHub
  """
  @app :tr

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  @doc """
  """
  def start do
    start_app()

    # account for more than a 100 sponsors
    sponsors = get_sponsors(100)

    Enum.each(get_in(sponsors, ["data", "user", "sponsors", "nodes"]), fn sponsor ->
      Tr.SponsorsCache.add_or_update(sponsor)
    end)
  end

  @doc """
    # Example output:

    %Neuron.Response{
      body: %{
        "data" => %{
          "user" => %{
            "sponsors" => %{
              "nodes" => [
                %{"login" => "nnnnnnn"},
                %{"login" => "xxxxxxx"},
                %{...},
                ...
              ],
              "totalCount" => 123
            }
          }
        }
      }
  """
  def get_sponsors(limit) do
    token = System.get_env("GITHUB_BEARER_TOKEN")

    {:ok, body} =
      Neuron.query(
        "{ user(login:\"kainlite\") { ... on Sponsorable { sponsors(first: #{limit}) { totalCount
      nodes { ... on User { login } ... on Organization { login } } } } } }",
        %{},
        url: "https://api.github.com/graphql",
        headers: [authorization: "Bearer #{token}"]
      )

    body.body
  end
end
