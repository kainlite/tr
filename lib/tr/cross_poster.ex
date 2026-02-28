defmodule Tr.CrossPoster do
  @moduledoc """
  Context module for tracking cross-posting status of blog posts to LinkedIn and Substack.
  """

  @app :tr

  import Ecto.Query, warn: false
  alias Tr.Repo

  alias Tr.CrossPostTracker

  def get_by_slug(slug) when is_binary(slug) do
    Repo.get_by(CrossPostTracker, slug: slug)
  end

  def get_all_pending do
    query =
      from(t in CrossPostTracker,
        where: t.linkedin_posted == false or t.substack_drafted == false,
        order_by: [desc: t.inserted_at]
      )

    Repo.all(query)
  end

  def get_unposted_linkedin do
    query = from(t in CrossPostTracker, where: t.linkedin_posted == false)
    Repo.all(query)
  end

  def get_undrafted_substack do
    query = from(t in CrossPostTracker, where: t.substack_drafted == false)
    Repo.all(query)
  end

  def list_all do
    Repo.all(from(t in CrossPostTracker, order_by: [desc: t.inserted_at]))
  end

  def insert_tracker(attrs) do
    %CrossPostTracker{}
    |> CrossPostTracker.changeset(attrs)
    |> Repo.insert()
  end

  @dialyzer {:nowarn_function, update_tracker: 2}
  def update_tracker(tracker, attrs) do
    changeset = CrossPostTracker.changeset(tracker, attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:cross_post_tracker, changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{cross_post_tracker: tracker}} -> {:ok, tracker}
      {:error, :cross_post_tracker, changeset, _} -> {:error, changeset}
    end
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  def start do
    start_app()
    track_posts()
  end

  defp track_posts do
    Tr.Blog.all_posts()
    |> Enum.filter(&(&1.lang == "en"))
    |> Enum.each(&track_post/1)
  end

  defp track_post(post) do
    unless get_by_slug(post.id) do
      insert_tracker(%{slug: post.id})
    end
  end
end
