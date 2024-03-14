defmodule Tr.Post.Comment do
  @moduledoc """
    This schema handles the representation of a comment
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "comments" do
    field :slug, :string
    field :body, :string
    field :parent_comment_id, :integer, default: nil

    timestamps()

    belongs_to :user, Tr.Accounts.User
  end

  @doc false
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:slug, :body, :user_id, :parent_comment_id])
    |> validate_required([:slug, :body, :user_id])
  end
end
