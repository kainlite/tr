defmodule Tr.CrossPostTracker do
  @moduledoc """
  Schema for tracking cross-posting status of blog posts to LinkedIn and Substack.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "cross_post_tracker" do
    field :slug, :string
    field :linkedin_posted, :boolean, default: false
    field :linkedin_post_id, :string
    field :linkedin_posted_at, :utc_datetime
    field :substack_drafted, :boolean, default: false
    field :substack_post_url, :string
    field :substack_drafted_at, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(tracker, attrs) do
    tracker
    |> cast(attrs, [
      :slug,
      :linkedin_posted,
      :linkedin_post_id,
      :linkedin_posted_at,
      :substack_drafted,
      :substack_post_url,
      :substack_drafted_at
    ])
    |> validate_required([:slug])
    |> unique_constraint(:slug)
  end
end
