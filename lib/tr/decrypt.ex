defmodule Tr.Decrypt do
  @moduledoc """
  This module can encrypt all files in the decrypted folder.
  """

  @app :tr

  alias Tr.Blog
  alias Tr.CryptUtils

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  def start() do
    start_app()

    Enum.each(["en", "es"], fn locale -> get_and_decrypt_all_posts(locale) end)
  end

  defp get_and_decrypt_all_posts(locale) do
    posts = Blog.encrypted_posts(locale)

    Enum.each(posts, fn post -> CryptUtils.save_decrypted(locale, post.id) end)
  end
end
