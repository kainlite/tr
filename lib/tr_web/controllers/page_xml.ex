defmodule TrWeb.PageXML do
  @moduledoc """
  Module to support xml rendering
  """
  use TrWeb, :html

  embed_templates "page_xml/*"

  defp format_date(date) do
    date
    |> to_string()
  end
end
