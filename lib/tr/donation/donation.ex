defmodule Tr.Donation do
  @topic inspect(__MODULE__)

  def subscribe do
    Phoenix.PubSub.subscribe(Blog, @topic)
  end

  defp broadcast_change({:ok, result}, event) do
    Phoenix.PubSub.broadcast(Blog, @topic, {__MODULE__, event, result})
    {:ok, result}
  end

  def all, do: {:ok, [:all]}

  defmodule NotFoundError, do: defexception([:message, plug_status: 404])
end
