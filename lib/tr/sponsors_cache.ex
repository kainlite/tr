defmodule Tr.SponsorsCache do
  @moduledoc """
  The SponsorsCache context.
  """

  import Ecto.Query, warn: false
  alias Tr.Repo

  alias Tr.Sponsors.Cache
  alias Tr.Telemetry.Spans

  @doc """
  Updates sponsors cache.

  ## Examples

      iex> add_or_update(sponsor)
      %Sponsor{}

  """
  def add_or_update(sponsor) do
    Spans.trace("sponsors_cache.add_or_update", %{}, fn ->
      user = Repo.get_by(Cache, github_username: sponsor.login)

      if is_nil(user) do
        {:ok, user} =
          register_sponsor(%{
            github_username: sponsor.github_username,
            first_seen: NaiveDateTime.utc_now(),
            last_seen: NaiveDateTime.utc_now(),
            amount: 10
          })

        user
      else
        user
      end
    end)
  end

  @doc """
  Store a sponsor in the cache.

  ## Examples

      iex> register_sponsor(%{github_username: value, first_seen: date, last_seen: date, amount: value})
      {:ok, %Sponsor{}}
  """
  def register_sponsor(attrs) do
    Spans.trace("sponsors_cache.register", %{}, fn ->
      %Cache{}
      |> Cache.changeset(attrs)
      |> Repo.insert()
    end)
  end

  @doc """
  Checks if a sponsor is in the cache.

  ## Examples

      iex> sponsor?(github_username)
      true
  """
  def sponsor?(username) when not is_nil(username) do
    Spans.trace("sponsors_cache.check", %{"github.username" => username || ""}, fn ->
      sponsor = Repo.get_by(Cache, github_username: username)

      if sponsor do
        true
      else
        false
      end
    end)
  end

  def sponsor?(_github_username), do: false
end
