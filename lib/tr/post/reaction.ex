defmodule Tr.Post.Reaction do
  @moduledoc """
  Reactions changeset
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "post_reactions" do
    field :value, :string
    field :slug, :string
    field :user_id, :id

    timestamps()
  end

  @doc false
  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:value, :slug, :user_id])
    |> validate_required([:value, :slug, :user_id])
    |> validate_inclusion(:value, ["rocket-launch", "hand-thumb-up", "heart"])
    |> unique_constraint(:post_reactions_user_id_slug_value, name: :unique_reaction)
  end
end
