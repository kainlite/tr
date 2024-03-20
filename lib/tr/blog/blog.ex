defmodule Tr.Blog do
  @moduledoc """
    This module is responsible for managing the blog posts
  """
  alias Tr.Blog.Post

  use NimblePublisher,
    build: Post,
    from: Application.app_dir(:tr, "priv/posts/**/*.md"),
    as: :posts,
    highlighters: [:makeup_elixir, :makeup_erlang]

  # The @posts variable is first defined by NimblePublisher.
  # Let's further modify it by sorting all posts by descending date.
  # We add 1 day so the comparison returns true on the given release date
  @posts Enum.sort_by(@posts, & &1.date, {:desc, Date})
         |> Enum.filter(
           &(Date.before?(&1.date, Date.add(Date.utc_today(), 1)) && &1.published == true)
         )

  # Group all the ids or URL slugs
  @slugs @posts
         |> Enum.map(& &1.id)
         |> Enum.sort()

  # Let's also get all tags
  @tags @posts |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()

  # And finally export them
  def posts, do: @posts
  def all_posts, do: @posts
  def all_slugs, do: @slugs
  def all_tags, do: @tags

  def by_tag(tag), do: get_posts_by_tag!(tag)
  def recent_posts(num \\ 5), do: Enum.take(posts(), num)

  defmodule NotFoundError, do: defexception([:message, plug_status: 404])

  def get_post_by_id!(id) do
    Enum.find(all_posts(), &(&1.id == id)) ||
      raise NotFoundError, "post with id=#{id} not found"
  end

  def get_post_by_slug(slug) do
    Enum.find(all_posts(), &(&1.id == slug)) || nil
  end

  def get_posts_by_tag!(tag) do
    case Enum.filter(all_posts(), &(tag in &1.tags)) do
      [] -> raise NotFoundError, "posts with tag=#{tag} not found"
      posts -> posts
    end
  end
end
