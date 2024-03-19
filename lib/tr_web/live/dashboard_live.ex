defmodule TrWeb.DashboardLive do
  @moduledoc """
  This module is responsible for managing the admin dashboard
  """

  use TrWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tr.PubSub, "#admin-dashboard")
    end

    {:ok, assign(socket, :comments, Tr.Post.get_unapproved_comments())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto">
      <h2>Admin Dashboard</h2>

      <table>
        <tr>
          <th>Email</th>
          <th>Post</th>
          <th>Body</th>
          <th>Actions</th>
        </tr>
        <%= for {record, index} <- Enum.with_index(@comments) do %>
          <tr>
            <td><%= index %></td>
            <td><%= record.user.email %></td>
            <td><%= record.slug %></td>
            <td><%= record.body %></td>
            <td>
              <.link
                class="text-[1.25rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
                phx-click="approve_comment"
                phx-value-slug={record.slug}
                phx-value-comment-id={record.id}
                data-confirm="Are you sure?"
              >
                ✔️
              </.link>
              <.link
                class="text-[1.25rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
                phx-click="delete_comment"
                phx-value-slug={record.slug}
                phx-value-comment-id={record.id}
                data-confirm="Are you sure?"
              >
                ❌
              </.link>
            </td>
          </tr>
        <% end %>
      </table>
    </div>
    """
  end

  @impl true
  def handle_event("approve_comment", params, socket) do
    comment_id = Map.get(params, "comment-id")
    comment = Tr.Post.get_comment(comment_id)

    broadcast(Tr.Post.approve_comment(comment))
    {:noreply, socket |> put_flash(:info, "Comment approved successfully.")}
  end

  @impl true
  def handle_event("delete_comment", params, socket) do
    comment_id = Map.get(params, "comment-id")
    comment = Tr.Post.get_comment(comment_id)
    broadcast(Tr.Post.delete_comment(comment))

    {:noreply, socket |> put_flash(:info, "Comment deleted successfully.")}
  end

  @impl true
  def handle_info(comment, socket) do
    comments =
      Enum.filter(socket.assigns.comments, fn item ->
        item.id != comment.id
      end)

    {:noreply, assign(socket, :comments, comments)}
  end

  defp broadcast({:ok, message}) do
    Phoenix.PubSub.broadcast(Tr.PubSub, "#admin-dashboard", message)

    {:ok, message}
  end
end
