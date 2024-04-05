defmodule TrWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :tr,
    pubsub_server: Tr.PubSub

  def list_connected_users() do
    active_rooms =
      Enum.filter(Tr.Blog.all_slugs(), fn p ->
        t = TrWeb.Presence.list(p)
        t != %{}
      end)

    metadatas = Enum.map(active_rooms, fn p -> TrWeb.Presence.list(p) end)

    total_connections =
      Enum.reduce(metadatas, 0, fn md, acc ->
        acc + length(Kernel.get_in(md, ["users:connected", :metas]))
      end)

    total_per_room =
      Enum.map(active_rooms, fn room ->
        {room, length(Kernel.get_in(TrWeb.Presence.list(room), ["users:connected", :metas]))}
      end)

    %{per_room: total_per_room, total: total_connections}
  end
end
