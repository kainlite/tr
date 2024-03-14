defmodule Tr.PostTracker do
@moduledoc """
  This is the representation of the posts that have been tracked
"""
  use Ecto.Schema
  import Ecto.Changeset

  schema "post_tracker" do
    field :slug, :string
    field :announced, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(post_tracker, attrs) do
    post_tracker
    |> cast(attrs, [:slug, :announced])
    |> validate_required([:slug, :announced])
    |> unique_constraint(:slug)
  end
end
