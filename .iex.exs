defmodule Helpers do
  defp decrypt(b64cipher) do
    {:ok, b64dec} = Base.decode64(b64cipher, ignore: :whitespace)
    {:ok, dec} = Tr.Vault.decrypt(b64dec)

    dec
  end

  defp decrypt_by_path(path) do
    file = File.read!(path)

    decrypt(file)
  end

  def save_decrypted(locale, slug) do
    encrypted_path =
      Path.join([Application.app_dir(:tr), "./priv/encrypted/#{locale}", "#{slug}.md"])

    decrypted_path =
      Path.join([Application.app_dir(:tr), "./priv/decrypted/#{locale}", "#{slug}.md"])

    decrypted = decrypt_by_path(encrypted_path)

    File.write!(decrypted_path, decrypted)
  end

  def save_encrypted(locale, slug) do
    encrypted_path =
      Path.join([Application.app_dir(:tr), "./priv/encrypted/#{locale}", "#{slug}.md"])

    decrypted_path =
      Path.join([Application.app_dir(:tr), "./priv/decrypted/#{locale}", "#{slug}.md"])

    decrypted = File.read!(decrypted_path)

    {:ok, ciphertext} = Tr.Vault.encrypt(decrypted)
    b64 = Base.encode64(ciphertext)

    File.write!(encrypted_path, b64)
  end
end
