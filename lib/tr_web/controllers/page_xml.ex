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

  # Rewrites root-relative links and images (e.g. /images/foo.webp) to absolute
  # URLs so the post body renders correctly when consumed off-site (RSS readers,
  # Substack import, etc). Protocol-relative (//) and absolute URLs are left as-is.
  defp absolutize(html) do
    base = TrWeb.Endpoint.url()
    String.replace(html, ~r/\b(href|src)="\/(?!\/)/, "\\1=\"#{base}/")
  end
end
