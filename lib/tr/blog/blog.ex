defmodule MultiParser do
  @moduledoc """
    Custom parser for the blog posts
  """
  def parse(_path, contents) do
    parse_lang(contents)
  end

  defp parse_lang(contents) do
    case :binary.split(contents, ["\n---lang---\n", "\r\n---lang---\r\n"]) do
      [en] -> [convert(en), convert(en)]
      [en, es] -> [convert(en), convert(es)]
    end
  end

  defp convert(contents) do
    case :binary.split(contents, ["\n---\n", "\r\n---\r\n"]) do
      [_] ->
        {:error, "could not find separator ---"}

      [code, body] ->
        case Code.eval_string(code, []) do
          {%{} = attrs, _} ->
            {attrs, body}

          {other, _} ->
            {:error, "expected attributes to return a map, got: #{inspect(other)}"}
        end
    end
  end
end

defmodule Tr.Blog do
  @moduledoc """
    This module is responsible for managing the blog posts
  """
  alias Tr.Blog.Post
  alias Tr.Telemetry.Spans

  use NimblePublisher,
    build: Post,
    from: Application.app_dir(:tr, "priv/posts/**/*.md"),
    as: :posts,
    highlighters: [:makeup_elixir, :makeup_erlang],
    parser: MultiParser

  @published_posts @posts
                   |> Enum.filter(
                     &(Date.before?(&1.date, Date.add(Date.utc_today(), 1)) &&
                         &1.published == true)
                   )

  @en_posts Enum.sort_by(@published_posts, & &1.date, {:desc, Date})
            |> Enum.filter(&(&1.lang == "en"))

  @es_posts Enum.sort_by(@published_posts, & &1.date, {:desc, Date})
            |> Enum.filter(&(&1.lang == "es"))

  # Group all the ids or URL slugs
  @slugs @en_posts
         |> Enum.filter(&(&1.lang == "en"))
         |> Enum.map(& &1.id)
         |> Enum.sort()

  # Let's also get all tags
  @tags @en_posts |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()

  # And finally export them
  def posts(locale) do
    if locale == "en", do: @en_posts, else: @es_posts
  end

  def all_posts, do: @published_posts
  def all_slugs, do: @slugs
  def all_tags, do: @tags

  def by_tag(locale, tag), do: get_posts_by_tag!(locale, tag)
  def recent_posts(locale \\ "en", num \\ 5), do: Enum.take(posts(locale), num)
  def get_latest_post(locale \\ "en", num \\ 1), do: Enum.at(Enum.take(posts(locale), num), 0)

  def encrypted_posts(locale),
    do: Enum.filter(all_posts(), &(&1.encrypted_content == true && &1.lang == locale))

  defmodule NotFoundError, do: defexception([:message, plug_status: 404])

  def get_post_by_id!(id) do
    Spans.trace("blog.get_post", %{"post.id" => id}, fn ->
      Enum.find(all_posts(), &(&1.id == id)) ||
        raise NotFoundError, "post with id=#{id} not found"
    end)
  end

  def get_post_by_slug(slug) do
    Spans.trace("blog.get_post_by_slug", %{"post.slug" => slug}, fn ->
      Enum.find(all_posts(), &(&1.id == slug)) || nil
    end)
  end

  def get_posts_by_tag!(locale, tag) do
    case Enum.filter(all_posts(), &(tag in &1.tags && &1.lang == locale)) do
      [] -> raise NotFoundError, "posts with tag=#{tag} not found"
      posts -> posts
    end
  end

  def get_post_by_id!(locale, id) do
    Spans.trace("blog.get_post", %{"post.id" => id, "locale" => locale}, fn ->
      Enum.find(all_posts(), &(&1.id == id && &1.lang == locale)) ||
        raise NotFoundError, "post with id=#{id} not found"
    end)
  end

  def get_post_by_slug(locale, slug) do
    Spans.trace("blog.get_post_by_slug", %{"post.slug" => slug, "locale" => locale}, fn ->
      Enum.find(all_posts(), &(&1.id == slug && &1.lang == locale)) || nil
    end)
  end

  def take(ids) do
    Spans.trace("blog.take", %{}, fn ->
      Enum.map(ids, fn id ->
        Enum.find(all_posts(), &(&1.id == id))
      end)
    end)
  end

  @doc """
  Returns the estimated reading time in minutes for a post.
  Strips HTML tags, counts words, divides by 200 words per minute.
  Returns at least 1.
  """
  def reading_time(post) do
    word_count =
      post.body
      |> String.replace(~r/<[^>]+>/, " ")
      |> String.split(~r/\s+/, trim: true)
      |> length()

    max(div(word_count, 200), 1)
  end

  @doc """
  Returns up to `count` related posts ranked by tag overlap.
  Excludes the given post itself.
  """
  def related_posts(post, locale, count \\ 3) do
    Spans.trace("blog.related_posts", %{"post.id" => post.id}, fn ->
      posts(locale)
      |> Enum.reject(&(&1.id == post.id))
      |> Enum.map(fn p ->
        overlap = length(post.tags -- (post.tags -- p.tags))
        {p, overlap}
      end)
      |> Enum.sort_by(fn {_, overlap} -> overlap end, :desc)
      |> Enum.take(count)
      |> Enum.map(fn {p, _} -> p end)
    end)
  end
end
