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

  defp decode_env!(var) do
    var
    |> System.get_env("oKm5YrZmbh8kS34n3fXLiAHLbDFEmC+H+z8TEseGQFs=")
    |> Base.decode64!()
  end
end
