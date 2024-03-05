defmodule Tr.Tracker do
  @moduledoc """
  The Tracker context.
  """

  import Ecto.Query, warn: false
  alias Tr.Repo

  alias Tr.PostTracker

  ## Database getters
  def get_post_by_slug(slug) when is_binary(slug) do
    Repo.get_by(PostTracker, slug: slug)
  end

  def get_unannounced_posts() do
    query = from(Tr.PostTracker, where: [announced: false])

    Repo.all(query)
  end

  ## Database setters
  def track_post(attrs) do
    %PostTracker{}
    |> PostTracker.changeset(attrs)
    |> Repo.insert()
  end

  def update_post_status(post, attrs) do
    changeset =
      post
      |> PostTracker.changeset(attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:post_tracker, changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{post_tracker: post_tracker}} -> {:ok, post_tracker}
      {:error, :post_tracker, changeset, _} -> {:error, changeset}
    end
  end
end
