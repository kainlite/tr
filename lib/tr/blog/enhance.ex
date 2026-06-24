defmodule Tr.Blog.Enhance do
  @moduledoc """
  Compile-time post-processing of a rendered post body (the HTML Earmark
  produced). Adds stable `id`s + hover anchor links to headings, extracts a
  table of contents, and turns GitHub-style alert blockquotes
  (`> [!WARNING]`) into styled callout boxes.

  Pure string work (Floki is test-only here), which is fine for Earmark's
  well-formed output.
  """

  @heading_re ~r{<(h[2-6])([^>]*)>(.*?)</h[2-6]>}s
  @callout_re ~r{<blockquote>\s*<p>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION|DANGER)\]\s*\n?(.*?)</blockquote>}is
  @callout_titles %{
    "note" => "Note",
    "tip" => "Tip",
    "important" => "Important",
    "warning" => "Warning",
    "caution" => "Caution",
    "danger" => "Danger"
  }

  @doc """
  Returns `{enhanced_html, toc}` where `toc` is a list of
  `%{level: integer, text: String.t(), id: String.t()}` in document order.
  """
  def process(html) when is_binary(html) do
    {entries, _used} =
      @heading_re
      |> Regex.scan(html)
      |> Enum.map_reduce(%{}, fn [whole, tag, attrs, inner], used ->
        level = tag |> String.trim_leading("h") |> String.to_integer()
        text = strip_tags(inner)
        {id, used} = unique_id(slugify(text), used)

        new =
          ~s(<#{tag}#{attrs} id="#{id}">#{inner}<a class="tr-anchor" href="##{id}" aria-label="Link to this section">#</a></#{tag}>)

        {%{whole: whole, new: new, level: level, text: text, id: id}, used}
      end)

    body =
      entries
      |> Enum.reduce(html, fn %{whole: w, new: n}, acc ->
        String.replace(acc, w, n, global: false)
      end)
      |> callouts()

    levels = Enum.map(entries, & &1.level)
    min_level = if levels == [], do: 2, else: Enum.min(levels)

    toc =
      Enum.map(entries, fn e ->
        %{level: e.level, indent: min(e.level - min_level, 3), text: e.text, id: e.id}
      end)

    {body, toc}
  end

  def process(html), do: {html, []}

  defp callouts(body) do
    Regex.replace(@callout_re, body, fn _full, type, inner ->
      key = String.downcase(type)
      title = Map.get(@callout_titles, key, "Note")

      ~s(<div class="tr-callout tr-callout-#{key}">) <>
        ~s(<p class="tr-callout-title">#{title}</p>) <>
        ~s(<div class="tr-callout-body"><p>#{inner}</div></div>)
    end)
  end

  @doc "Slugify heading text into a URL fragment."
  def slugify(text) do
    slug =
      text
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/u, "")
      |> String.replace(~r/[\s-]+/, "-")
      |> String.trim("-")

    if slug == "", do: "section", else: slug
  end

  defp unique_id(base, used) do
    case Map.get(used, base) do
      nil -> {base, Map.put(used, base, 1)}
      n -> {"#{base}-#{n + 1}", Map.put(used, base, n + 1)}
    end
  end

  defp strip_tags(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.trim()
  end
end
