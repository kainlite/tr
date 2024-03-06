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
    start_app()
    track_posts()

    if length(Tr.Tracker.get_unannounced_posts()) > 0 do
      announce_posts()
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  defp track_posts do
    posts = Tr.Blog.all_posts()

    posts
    |> Enum.each(fn row -> track_post(row) end)
  end

  defp track_post(row) do
    post = Tr.Tracker.get_post_by_slug(row.id)

    unless post do
      Tr.Tracker.track_post(%{slug: row.id, announced: false})
    end
  end

  defp announce_posts do
    unanounced_posts = Tr.Tracker.get_unannounced_posts()
    notifiable_users = Tr.Accounts.get_all_notifiable_users()

    if length(unanounced_posts) > 1 do
      url = TrWeb.Endpoint.url() <> "/blog/"
      subject = "This is what you have missed so far..."
      titles = Enum.map(unanounced_posts, fn p -> p.slug end)

      # Fetch all posts
      posts =
        Enum.map(unanounced_posts, fn p -> Tr.Blog.get_post_by_slug(p.slug) end)

      # IO.inspect(posts)
      descriptions =
        Enum.map(posts, fn p ->
          Map.get(p, :description)
        end)

      # Create the body based in the title and descriptions
      body =
        Enum.join(
          Enum.map(List.zip([titles, descriptions]), fn p ->
            elem(p, 0) <> "\n\n" <> elem(p, 1) <> "\n" <> url <> elem(p, 0) <> "\n\n\n\n"
          end)
        )

      Enum.each(unanounced_posts, fn post ->
        # Mark posts as already announced
        Tr.Tracker.update_post_status(post, %{announced: true})
      end)

      notify_users(notifiable_users, subject, body, url)
    else
      unannounced_post = hd(unanounced_posts)
      post = Tr.Blog.get_post_by_slug(unannounced_post.slug)
      url = TrWeb.Endpoint.url() <> "/blog/" <> post.id
      subject = post.title
      body = post.title <> "\n\n" <> post.description <> "\n\n" <> url

      # Mark post as already announced
      Tr.Tracker.update_post_status(unannounced_post, %{announced: true})

      # Fire in the hole
      notify_users(notifiable_users, subject, body, url)
    end

    IO.inspect(Task.Supervisor.children(Tr.TaskSupervisor))
  end

  defp notify_users(users, subject, body, url) do
    tasks =
      Enum.map(users, fn user ->
        # Fire in the hole
        Task.Supervisor.async_nolink(
          Tr.TaskSupervisor,
          fn ->
            Tr.PostTracker.Notifier.deliver_new_post_notification(
              user,
              subject,
              body,
              url
            )
          end
        )
      end)

    tasks
    |> Enum.map(&Task.await/1)
  end
end
