defmodule Tr.Sponsors.Cache do
  @moduledoc """
  This module is responsible for the Sponsors Cache Schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "sponsors_cache" do
    field :github_username, :string
    field :first_seen, :naive_datetime
    field :last_seen, :naive_datetime
    field :amount, :integer

    timestamps()
  end

  @doc false
  def changeset(sponsors_cache, attrs) do
    sponsors_cache
    |> cast(attrs, [:github_username, :first_seen, :last_seen, :amount])
    |> validate_required([:github_username, :first_seen, :last_seen, :amount])
  end
end
