defmodule Tr.Telemetry.Spans do
  @moduledoc """
  Thin wrapper around OpenTelemetry.Tracer for consistent span creation
  across business logic modules.

  Usage:
      Spans.trace("accounts.register_user", %{"user.email" => email}, fn ->
        # business logic
      end)
  """

  require OpenTelemetry.Tracer

  @doc """
  Wraps a function in an OpenTelemetry span with the given name and attributes.
  Returns whatever the function returns. Propagates exceptions.
  """
  def trace(span_name, attributes \\ %{}, fun) do
    OpenTelemetry.Tracer.with_span span_name, %{attributes: attributes} do
      fun.()
    end
  end
end
