defmodule TrWeb.DashboardLive do
  @moduledoc """
  This module is responsible for managing the admin dashboard
  """

  use TrWeb, :live_view

  @impl true
  def mount(%{"comments" => "all"}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tr.PubSub, "#admin-dashboard")
    end

    {:ok,
     socket
     |> assign(:comments, Tr.Post.list_comments())
     |> assign(:user_stats, TrWeb.Presence.list_connected_users())
     |> assign(:users, Tr.Accounts.get_users(5))}
  end

  @impl true
  def mount(_, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tr.PubSub, "#admin-dashboard")
    end

    Process.send_after(self(), :refresh, 5000)

    {:ok,
     socket
     |> assign(:comments, Tr.Post.get_unapproved_comments())
     |> assign(:user_stats, TrWeb.Presence.list_connected_users())
     |> assign(:users, Tr.Accounts.get_users(5))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto">
      <div class="float-right">
        <div class="flex flex-col">
          <span><%= gettext("Registered users:") %> <%= Tr.Accounts.get_users_count() %></span>
          <span><%= gettext("Total comments:") %> <%= Tr.Post.get_comments_count() %></span>
          <span><%= gettext("Connected users:") %> <%= @user_stats.total %></span>
        </div>
        <ul class="list-none text-base bg-gray-100 rounded-lg p-4 shadow-md dark:invert">
          <%= for {room, count} <- @user_stats.per_room do %>
            <li class="py-2 border-b border-gray-200 dark:invert"><%= room %>: <%= count %></li>
          <% end %>
        </ul>
      </div>

      <h2><%= gettext("Admin Dashboard") %></h2>

      <.link
        href={~p"/admin/dashboard?comments=all"}
        class="text-[1.25rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700 dark:invert"
      >
        <%= gettext("All comments") %>
      </.link>
      |
      <.link
        href={~p"/admin/dashboard?comments=unapproved"}
        class="text-[1.25rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700 dark:invert"
      >
        <%= gettext("Unapproved comments") %>
      </.link>

      <.table id="comments" rows={@comments}>
        <:col :let={comment} label="id"><%= comment.id %></:col>
        <:col :let={comment} label="slug"><%= comment.slug %></:col>
        <:col :let={comment} label="email"><%= comment.user.email %></:col>
        <:col :let={comment} label="body"><%= comment.body %></:col>
        <:col :let={comment} label="actions">
          <.link
            class="text-[1.25rem] leading-6 text-zinc-700 font-semibold hover:text-zinc-700"
            phx-click="approve_comment"
            phx-value-slug={comment.slug}
            phx-value-comment-id={comment.id}
            data-confirm="Are you sure?"
          >
            ✔️
          </.link>
          <.link
            class="text-[1.25rem] leading-6 text-zinc-700 font-semibold hover:text-zinc-700"
            phx-click="delete_comment"
            phx-value-slug={comment.slug}
            phx-value-comment-id={comment.id}
            data-confirm="Are you sure?"
          >
            ❌
          </.link>
        </:col>
      </.table>

      <br />

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="email"><%= user.email %></:col>
        <:col :let={user} label="github_username"><%= user.github_username %></:col>
      </.table>
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
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 5000)

    {:noreply,
     socket
     |> assign(:comments, Tr.Post.get_unapproved_comments())
     |> assign(:user_stats, TrWeb.Presence.list_connected_users())}
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
