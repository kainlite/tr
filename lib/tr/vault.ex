defmodule Tr.Vault do
  @moduledoc """
  This module is responsible for interfacing with the vault
  """
  use Cloak.Vault, otp_app: :tr

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1", key: decode_env!("CLOAK_KEY"), iv_length: 12
        }
      )

    {:ok, config}
  end

  # Fail closed: raise at boot if the key is missing rather than silently falling
  # back to a hardcoded key. Dev/test supply CLOAK_KEY via config before boot.
  defp decode_env!(var) do
    var
    |> System.fetch_env!()
    |> Base.decode64!()
  end
end
