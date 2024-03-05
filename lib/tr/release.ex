defmodule Tr.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :tr

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def start_tracker() do
    load_app()
    track_posts()
    announce_posts()
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp track_posts do
    posts = Tr.Blog.all_posts() 

    posts 
      |> Enum.each(fn row -> track_post(row) end)
  end

  defp track_post(row) do
    post = Tr.Tracker.get_post_by_slug(row.id)

    unless post do
      Tr.Tracker.track_post(%{ slug: row.id, announced: false })
    end
  end

  defp announce_posts() do
    unanounced_posts = Tr.Tracker.get_unannounced_posts()
    notifiable_users = Tr.Accounts.get_all_notifiable_users()

    IO.inspect(unanounced_posts)
    IO.inspect(notifiable_users)
  end
end
