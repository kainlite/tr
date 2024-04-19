defmodule TrWeb.PageJSON do
  @moduledoc """
  Module to support json rendering
  """
  use TrWeb, :html

  embed_templates "page_json/*"
end
