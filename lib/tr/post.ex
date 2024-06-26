defmodule Tr.Post do
  @moduledoc """
  The Post context.
  """

  import Ecto.Query, warn: false
  alias Tr.Repo

  alias Tr.Post.Comment
  alias Tr.Post.Reaction

  def subscribe(slug) do
    channel = "post-" <> slug
    Phoenix.PubSub.subscribe(Tr.PubSub, channel)
  end

  def broadcast({:ok, message}, tag) do
    channel = "post-" <> message.slug
    Phoenix.PubSub.broadcast(Tr.PubSub, channel, {tag, message})

    {:ok, message}
  end

  def broadcast({:error, _changeset} = error, _), do: error

  @doc """
  Returns the list of comments for a post

  ## Examples

      iex> get_comments_for_post(1)
      [%Comment{}, ...]
  """
  def get_comments_for_post(slug) do
    query = from(Tr.Post.Comment, where: [slug: ^slug], order_by: [desc: :inserted_at])
    comments = Repo.all(query)
    Repo.preload(comments, :user)
  end

  @doc """
  Returns the list of parent comments for a post

  ## Examples

      iex> get_parent_comments_for_post(1)
      [%Comment{}, ...]
  """
  def get_parent_comments_for_post(slug) do
    query =
      from p in Tr.Post.Comment,
        where: is_nil(p.parent_comment_id) and p.slug == ^slug,
        order_by: [asc: :inserted_at]

    comments = Repo.all(query)
    Repo.preload(comments, :user)
  end

  @doc """
  Returns the list of children comments for a post

  ## Examples

      iex> get_children_comments_for_post(1)
      %{15 => [%Comment{}, ...]}
  """
  def get_children_comments_for_post(slug) do
    query =
      from p in Tr.Post.Comment,
        where: p.slug == ^slug and not is_nil(p.parent_comment_id),
        order_by: [asc: :inserted_at]

    comments = Repo.all(query)
    Repo.preload(comments, :user)

    comments
    |> Enum.group_by(& &1.parent_comment_id)
  end

  @doc """
  Returns the reaction for a slug, value and user

  ## Examples

      iex> get_reaction("slug", "rocket", 1)
      true
  """
  def get_reaction(slug, value, user_id) do
    query =
      from p in Tr.Post.Reaction,
        where: p.slug == ^slug and p.value == ^value and p.user_id == ^user_id

    Repo.one(query)
  end

  @doc """
  Returns true/false if the reaction for a slug, value and user exists

  ## Examples

      iex> reaction_exists?("slug", "rocket", 1)
      true
  """
  def reaction_exists?(slug, value, user_id) do
    query =
      from p in Tr.Post.Reaction,
        where: p.slug == ^slug and p.value == ^value and p.user_id == ^user_id

    Repo.exists?(query)
  end

  @doc """
  Returns the list of reactions for a post

  ## Examples

      iex> get_reactions("slug")
      %{15 => [%Reaction{}, ...]}
  """
  def get_reactions(slug) do
    query =
      from p in Tr.Post.Reaction,
        where: p.slug == ^slug

    Repo.all(query)
    |> Enum.group_by(& &1.value)
    |> Enum.map(fn {k, v} -> {k, Enum.count(v)} end)
    |> Enum.into(%{})
  end

  @doc """
  Returns the list of comments.

  ## Examples

      iex> list_comments()
      [%Comment{}, ...]

  """
  def list_comments do
    comments = Repo.all(Comment)
    Repo.preload(comments, :user)
  end

  @doc """
  Gets comments count.

  ## Examples

      iex> get_comments_count()
      42

  """
  def get_comments_count do
    Repo.one(from u in Tr.Post.Comment, select: count(u.id))
  end

  @doc """
  Returns the list of unapproved comments.

  ## Examples

      iex> get_unapproved_comments()
      [%Comment{}, ...]

  """
  def get_unapproved_comments do
    query =
      from p in Tr.Post.Comment,
        where: not p.approved

    comments = Repo.all(query)
    Repo.preload(comments, :user)
  end

  @doc """
  Gets a single comment.

  ## Examples

      iex> get_comment(123)
      %Comment{}

      iex> get_comment(456)

  """
  def get_comment(id) do
    Repo.get(Comment, id)
  end

  @doc """
  Gets a single comment.

  Raises `Ecto.NoResultsError` if the Comment does not exist.

  ## Examples

      iex> get_comment!(123)
      %Comment{}

      iex> get_comment!(456)
      ** (Ecto.NoResultsError)

  """
  def get_comment!(id) do
    Repo.get!(Comment, id)
  end

  @doc """
  Creates a comment.

  ## Examples

      iex> create_comment(%{field: value})
      {:ok, %Comment{}}

      iex> create_comment(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_comment(attrs \\ %{}) do
    %Comment{}
    |> Comment.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:comment_created)
  end

  @doc """
  Creates a reaction.

  ## Examples

      iex> create_reaction(%{field: value})
      {:ok, %Reaction{}}

      iex> create_reaction(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_reaction(attrs \\ %{}) do
    %Reaction{}
    |> Reaction.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:reaction_created)
  end

  @doc """
  Updates a comment.

  ## Examples

      iex> update_comment(comment, %{field: new_value})
      {:ok, %Comment{}}

      iex> update_comment(comment, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_comment(%Comment{} = comment, attrs) do
    comment
    |> Comment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a comment.

  ## Examples

      iex> delete_comment(comment)
      {:ok, %Comment{}}

      iex> delete_comment(comment)
      {:error, %Ecto.Changeset{}}

  """
  def delete_comment(%Comment{} = comment) do
    Repo.delete(comment)
  end

  @doc """
  Deletes a reaction.

  ## Examples

      iex> delete_reaction(reaction)
      {:ok, %Reaction{}}

      iex> delete_reaction(reaction)
      {:error, %Ecto.Changeset{}}

  """
  def delete_reaction(%Reaction{} = reaction) do
    Repo.delete(reaction)
    |> broadcast(:reaction_deleted)
  end

  @doc """
  Approve a comment.

  ## Examples

      iex> approve_comment(comment)
      {:ok, %Comment{}}

      iex> approve_comment(comment)
      {:error, %Ecto.Changeset{}}

  """
  def approve_comment(%Comment{} = comment) do
    update_comment(comment, %{approved: true})
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking comment changes.

  ## Examples

      iex> change_comment(comment)
      %Ecto.Changeset{data: %Comment{}}

  """
  def change_comment(%Comment{} = comment, attrs \\ %{}) do
    Comment.changeset(comment, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking reaction changes.

  ## Examples

      iex> change_reaction(reaction)
      %Ecto.Changeset{data: %Reaction{}}

  """
  def change_reaction(%Reaction{} = reaction, attrs \\ %{}) do
    Reaction.changeset(reaction, attrs)
  end
end
