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

  @dialyzer {:nowarn_function, update_post_status: 2}
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

    if get_unannounced_posts() != [] do
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

    # Don't mark posts as announced if there are no users to notify
    if notifiable_users == [] do
      require Logger
      Logger.warning("No notifiable users found, skipping announcement to retry later")
      :ok
    else
      send_and_mark(unanounced_posts, notifiable_users)
    end
  end

  defp send_and_mark(unanounced_posts, notifiable_users) do
    require Logger
    {subject, body, url} = build_announcement(unanounced_posts)

    # Send emails first, only mark as announced if at least one email succeeds
    case notify_users(notifiable_users, subject, body, url) do
      {:ok, _results} ->
        mark_as_announced(unanounced_posts)

      {:error, reason} ->
        Logger.error("Failed to send post notifications: #{inspect(reason)}")
    end
  end

  defp mark_as_announced(posts) do
    Enum.each(posts, fn post ->
      update_post_status(post, %{announced: true})
    end)
  end

  defp build_announcement(unanounced_posts) when length(unanounced_posts) > 1 do
    url = TrWeb.Endpoint.url() <> "/en/blog/"
    subject = "This is what you have missed so far..."

    # Fetch all posts, filtering out any that no longer exist
    post_pairs =
      unanounced_posts
      |> Enum.map(fn p -> {p.slug, Tr.Blog.get_post_by_slug(p.slug)} end)
      |> Enum.reject(fn {_slug, post} -> is_nil(post) end)

    body =
      Enum.map_join(post_pairs, fn {slug, post} ->
        slug <> "\n" <> post.description <> "\n" <> url <> slug <> "\n\n"
      end)

    {subject, body, url}
  end

  defp build_announcement(unanounced_posts) do
    unannounced_post = hd(unanounced_posts)
    post = Tr.Blog.get_post_by_slug(unannounced_post.slug)

    if post do
      url = TrWeb.Endpoint.url() <> "/en/blog/" <> post.id
      subject = post.title
      body = post.title <> "\n" <> post.description <> "\n" <> url
      {subject, body, url}
    else
      require Logger
      Logger.warning("Post not found for slug: #{unannounced_post.slug}")
      url = TrWeb.Endpoint.url() <> "/en/blog/"
      {"New article on segfault.pw", "A new article has been published!", url}
    end
  end

  defp notify_users(users, subject, body, url) do
    require Logger

    results =
      Enum.map(users, fn user ->
        try do
          task =
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

          case Task.yield(task, 15_000) || Task.shutdown(task) do
            {:ok, {:ok, _email}} ->
              Logger.info("Post notification sent to #{user.email}")
              :ok

            {:ok, {:error, reason}} ->
              Logger.error("Failed to send notification to #{user.email}: #{inspect(reason)}")
              {:error, reason}

            nil ->
              Logger.error("Timeout sending notification to #{user.email}")
              {:error, :timeout}
          end
        rescue
          e ->
            Logger.error("Exception sending notification to #{user.email}: #{inspect(e)}")
            {:error, e}
        end
      end)

    if Enum.any?(results, &(&1 == :ok)) do
      {:ok, results}
    else
      {:error, :all_failed}
    end
  end
end
