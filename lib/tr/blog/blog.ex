defmodule Tr.Blog do
  alias Tr.Blog.Post

  @topic inspect(__MODULE__)

  use NimblePublisher,
    build: Post,
    from: Application.app_dir(:tr, "priv/posts/**/*.md"),
    as: :posts,
    highlighters: [:makeup_elixir, :makeup_erlang, :makeup_http, :makeup_diff, :makeup_eex]

  def subscribe do
    Phoenix.PubSub.subscribe(Blog, @topic)
  end

  defp broadcast_change({:ok, result}, event) do
    Phoenix.PubSub.broadcast(Blog, @topic, {__MODULE__, event, result})
    {:ok, result}
  end

  # The @posts variable is first defined by NimblePublisher.
  # Let's further modify it by sorting all posts by descending date.
  @posts Enum.sort_by(@posts, & &1.date, {:desc, Date})

  # Let's also get all tags
  @tags @posts |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()

  # And finally export them
  def all_posts, do: @posts
  def all_tags, do: @tags
  def published_posts, do: Enum.filter(all_posts(), &(&1.published == true))
  def recent_posts(num \\ 5), do: Enum.take(published_posts(), num)

  defmodule NotFoundError, do: defexception([:message, plug_status: 404])

  def get_post_by_id!(id) do
    Enum.find(all_posts(), &(&1.id == id)) ||
      raise NotFoundError, "post with id=#{id} not found"
  end

  def get_posts_by_tag!(tag) do
    case Enum.filter(all_posts(), &(tag in &1.tags)) do
      [] -> raise NotFoundError, "posts with tag=#{tag} not found"
      posts -> posts
    end
  end
end
