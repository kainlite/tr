defmodule TrWeb.LoggerPlug do
  @moduledoc """
  Provide standardize logfmt output on request
  """
  require Logger
  alias Plug.Conn
  @behaviour Plug

  def init(opts) do
    Keyword.get(opts, :log, :info)
  end

  def call(conn, level) do
    start = System.monotonic_time()

    conn
    |> Conn.register_before_send(fn conn ->
      Logger.log(level, fn ->
        stop = System.monotonic_time()
        diff = System.convert_time_unit(stop - start, :native, :microsecond)

        Logfmt.encode(
          level: level,
          time: Poison.encode!(DateTime.utc_now()),
          elapsed: formatted_diff(diff),
          method: conn.method,
          path: conn.request_path,
          status: conn.status,
          remote_ip: formatted_ip(conn.remote_ip)
        )
      end)

      conn
    end)
  end

  defp formatted_diff(diff) when diff > 1000,
    do: [diff |> div(1000) |> Integer.to_string(), "ms"] |> Enum.join(" ")

  defp formatted_diff(diff), do: [Integer.to_string(diff), "µs"] |> Enum.join(" ")

  defp formatted_ip(ip) do
    to_string(:inet_parse.ntoa(ip))
  end
end
