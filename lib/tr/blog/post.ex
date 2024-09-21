defmodule Tr.Blog.Post do
  @moduledoc """
    Transforms markdown into nice HTML blog posts
  """
  @enforce_keys [
    :id,
    :author,
    :title,
    :body,
    :description,
    :tags,
    :date,
    :published,
    :image,
    :sponsored,
    :video
  ]
  defstruct [
    :lang,
    :id,
    :author,
    :title,
    :body,
    :description,
    :tags,
    :date,
    :published,
    :image,
    :sponsored,
    :video,
    :encrypted_content
  ]

  def build(filename, attrs, body) do
    [year, month_day_id] = filename |> Path.rootname() |> Path.split() |> Enum.take(-2)
    [month, day, id] = String.split(month_day_id, "-", parts: 3)
    date = Date.from_iso8601!("#{year}-#{month}-#{day}")
    struct!(__MODULE__, [id: id, date: date, body: body, lang: "en"] ++ Map.to_list(attrs))
  end
end
