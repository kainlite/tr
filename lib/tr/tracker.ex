defmodule Tr.Tracker do
  @moduledoc """
  The Tracker context.
  """

  @app :tr

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
  def insert_post(attrs) do
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

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  def start() do
    start_app()
    track_posts()

    if length(get_unannounced_posts()) > 0 do
      announce_posts()
    end
  end

  defp track_posts do
    posts = Tr.Blog.all_posts()

    posts
    |> Enum.each(fn row -> track_post(row) end)
  end

  defp track_post(row) do
    post = get_post_by_slug(row.id)

    unless post do
      insert_post(%{slug: row.id, announced: false})
    end
  end

  defp announce_posts do
    unanounced_posts = get_unannounced_posts()
    notifiable_users = Tr.Accounts.get_all_notifiable_users()

    if length(unanounced_posts) > 1 do
      url = TrWeb.Endpoint.url() <> "/en/blog/"
      subject = "This is what you have missed so far..."
      titles = Enum.map(unanounced_posts, fn p -> p.slug end)

      # Fetch all posts
      posts =
        Enum.map(unanounced_posts, fn p -> Tr.Blog.get_post_by_slug(p.slug) end)

      descriptions =
        Enum.map(posts, fn p ->
          Map.get(p, :description)
        end)

      # Create the body based in the title and descriptions
      body =
        Enum.join(
          Enum.map(List.zip([titles, descriptions]), fn p ->
            elem(p, 0) <> "\n" <> elem(p, 1) <> "\n" <> url <> elem(p, 0) <> "\n\n"
          end)
        )

      Enum.each(unanounced_posts, fn post ->
        # Mark posts as already announced
        update_post_status(post, %{announced: true})
      end)

      notify_users(notifiable_users, subject, body, url)
    else
      unannounced_post = hd(unanounced_posts)
      post = Tr.Blog.get_post_by_slug(unannounced_post.slug)
      url = TrWeb.Endpoint.url() <> "/en/blog/" <> post.id
      subject = post.title
      body = post.title <> "\n" <> post.description <> "\n" <> url

      # Mark post as already announced
      update_post_status(unannounced_post, %{announced: true})

      # Fire in the hole
      notify_users(notifiable_users, subject, body, url)
    end
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
