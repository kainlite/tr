defmodule Tr.Post do
  @moduledoc """
  The Post context.
  """

  import Ecto.Query, warn: false
  alias Tr.Repo

  alias Tr.Post.Comment

  @doc """
  Returns the list of comments for a post

  ## Examples

      iex> get_comments_for_post(1)
      [%Comment{}, ...]
  """
  def get_comments_for_post(slug) do
    query = from(Tr.Post.Comment, where: [slug: ^slug])
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
        where: is_nil(p.parent_comment_id) and p.slug == ^slug

    comments = Repo.all(query)
    Repo.preload(comments, :user)
  end

  @doc """
  Returns the list of children comments for a comment

  ## Examples

      iex> get_children_comments_for_comment(1)
      [%Comment{}, ...]
  """
  def get_children_comments_for_comment(comment_id) do
    query =
      from p in Tr.Post.Comment,
        where: p.parent_comment_id == ^comment_id

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
        where: p.slug == ^slug and not is_nil(p.parent_comment_id)

    comments = Repo.all(query)
    Repo.preload(comments, :user)

    comments
    |> Enum.group_by(& &1.parent_comment_id)
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
  Returns an `%Ecto.Changeset{}` for tracking comment changes.

  ## Examples

      iex> change_comment(comment)
      %Ecto.Changeset{data: %Comment{}}

  """
  def change_comment(%Comment{} = comment, attrs \\ %{}) do
    Comment.changeset(comment, attrs)
  end
end
