defmodule Tr.SponsorsCache do
  @moduledoc """
  The SponsorsCache context.
  """

  import Ecto.Query, warn: false
  alias Tr.Repo

  alias Tr.Sponsors.Cache

  @doc """
  Updates sponsors cache.

  ## Examples

      iex> add_or_update(sponsor)
      %Sponsor{}

  """
  def add_or_update(sponsor) do
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
  end

  @doc """
  Store a sponsor in the cache.

  ## Examples

      iex> register_sponsor(%{github_username: value, first_seen: date, last_seen: date, amount: value})
      {:ok, %Sponsor{}}
  """
  def register_sponsor(attrs) do
    %Cache{}
    |> Cache.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Checks if a sponsor is in the cache.

  ## Examples

      iex> sponsor?(github_username)
      true
  """
  def sponsor?(github_username) when not is_nil(github_username) do
    sponsor = Repo.get_by(Cache, github_username: github_username)

    if sponsor do
      true
    else
      false
    end
  end

  def sponsor?(_github_username), do: false
end
