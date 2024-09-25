defmodule TrWeb.Telemetry.PeepPlug do
  @moduledoc """
    This module exports metrics for prometheus
  """
  use Plug.Router
  alias Plug.Conn

  plug :match
  plug Plug.Telemetry, event_prefix: [TrWebPeep, :plug]
  plug :dispatch

  get "/metrics" do
    name = TrWebPeep
    metrics = name |> Peep.get_all_metrics() |> Peep.Prometheus.export()

    conn
    |> Conn.put_private(:prometheus_metrics_name, name)
    |> Conn.put_resp_content_type("text/plain")
    |> Conn.send_resp(200, metrics)
  end

  match _ do
    Conn.send_resp(conn, 404, "Not Found")
  end
end
