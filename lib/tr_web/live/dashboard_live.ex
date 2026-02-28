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
     |> assign(:users, Tr.Accounts.get_users(5))
     |> assign_cross_post_data()}
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
     |> assign(:users, Tr.Accounts.get_users(5))
     |> assign_cross_post_data()}
  end

  defp assign_cross_post_data(socket) do
    socket
    |> assign(:cross_post_pending, Tr.CrossPoster.get_all_pending())
    |> assign(:linkedin_configured, Tr.CrossPoster.LinkedIn.configured?())
    |> assign(:substack_configured, Tr.CrossPoster.Substack.draft_api_configured?())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto">
      <div class="float-right">
        <div class="flex flex-col">
          <span>{gettext("Registered users:")} {Tr.Accounts.get_users_count()}</span>
          <span>{gettext("Total comments:")} {Tr.Post.get_comments_count()}</span>
          <span>{gettext("Connected users:")} {@user_stats.total}</span>
        </div>
        <ul class="list-none text-base bg-gray-100 dark:bg-surface-800 rounded-lg p-4 shadow-md dark:text-zinc-200">
          <%= for {room, count} <- @user_stats.per_room do %>
            <li class="py-2 border-b border-gray-200 dark:border-surface-600">{room}: {count}</li>
          <% end %>
        </ul>
      </div>

      <h2>{gettext("Admin Dashboard")}</h2>

      <.link
        href={~p"/admin/dashboard?comments=all"}
        class="text-[1.25rem] leading-6 text-zinc-900 dark:text-zinc-100 font-semibold hover:text-brand-500 dark:hover:text-brand-400"
      >
        {gettext("All comments")}
      </.link>
      |
      <.link
        href={~p"/admin/dashboard?comments=unapproved"}
        class="text-[1.25rem] leading-6 text-zinc-900 dark:text-zinc-100 font-semibold hover:text-brand-500 dark:hover:text-brand-400"
      >
        {gettext("Unapproved comments")}
      </.link>

      <.table id="comments" rows={@comments}>
        <:col :let={comment} label="id">{comment.id}</:col>
        <:col :let={comment} label="slug">{comment.slug}</:col>
        <:col :let={comment} label="email">{comment.user.email}</:col>
        <:col :let={comment} label="body">{comment.body}</:col>
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
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="email">{user.email}</:col>
        <:col :let={user} label="github_username">{user.github_username}</:col>
      </.table>

      <br />

      <h3>{gettext("Cross-Posting")}</h3>

      <%= unless @linkedin_configured do %>
        <p class="text-sm text-yellow-600 dark:text-yellow-400">
          LinkedIn not configured (set LINKEDIN_ACCESS_TOKEN and LINKEDIN_PERSON_URN)
        </p>
      <% end %>

      <.table id="cross-posts" rows={@cross_post_pending}>
        <:col :let={tracker} label="Slug">{tracker.slug}</:col>
        <:col :let={tracker} label="LinkedIn">
          <%= if tracker.linkedin_posted do %>
            <span class="text-green-600">Posted</span>
          <% else %>
            <button
              phx-click="linkedin_post"
              phx-value-slug={tracker.slug}
              disabled={!@linkedin_configured}
              class="rounded bg-blue-600 px-2 py-1 text-sm text-white hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
              data-confirm="Post to LinkedIn?"
            >
              Post to LinkedIn
            </button>
          <% end %>
        </:col>
        <:col :let={tracker} label="Substack">
          <%= if tracker.substack_drafted do %>
            <span class="text-green-600">Drafted</span>
          <% else %>
            <div class="flex gap-2">
              <button
                phx-click="substack_draft"
                phx-value-slug={tracker.slug}
                disabled={!@substack_configured}
                class="rounded bg-orange-600 px-2 py-1 text-sm text-white hover:bg-orange-700 disabled:opacity-50 disabled:cursor-not-allowed"
                data-confirm="Push draft to Substack?"
              >
                Push Draft
              </button>
              <button
                id={"copy-html-" <> tracker.slug}
                phx-hook="CopyHtml"
                phx-click="substack_content"
                phx-value-slug={tracker.slug}
                class="rounded bg-gray-600 px-2 py-1 text-sm text-white hover:bg-gray-700"
              >
                Copy HTML
              </button>
            </div>
          <% end %>
        </:col>
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
  def handle_event("linkedin_post", %{"slug" => slug}, socket) do
    case Tr.CrossPoster.LinkedIn.share_post(slug) do
      {:ok, post_id} ->
        tracker = Tr.CrossPoster.get_by_slug(slug)

        Tr.CrossPoster.update_tracker(tracker, %{
          linkedin_posted: true,
          linkedin_post_id: post_id,
          linkedin_posted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        {:noreply,
         socket
         |> put_flash(:info, "Posted to LinkedIn successfully.")
         |> assign(:cross_post_pending, Tr.CrossPoster.get_all_pending())}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "LinkedIn post failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("substack_draft", %{"slug" => slug}, socket) do
    case Tr.CrossPoster.Substack.create_draft(slug) do
      {:ok, draft_url} ->
        tracker = Tr.CrossPoster.get_by_slug(slug)

        Tr.CrossPoster.update_tracker(tracker, %{
          substack_drafted: true,
          substack_post_url: draft_url,
          substack_drafted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        {:noreply,
         socket
         |> put_flash(:info, "Substack draft created successfully.")
         |> assign(:cross_post_pending, Tr.CrossPoster.get_all_pending())}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Substack draft failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("substack_content", %{"slug" => slug}, socket) do
    case Tr.CrossPoster.Substack.generate_content(slug) do
      {:ok, content} ->
        {:noreply, push_event(socket, "copy_to_clipboard", %{text: content.body_html})}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to generate content: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 5000)

    {:noreply,
     socket
     |> assign(:comments, Tr.Post.get_unapproved_comments())
     |> assign(:user_stats, TrWeb.Presence.list_connected_users())
     |> assign(:cross_post_pending, Tr.CrossPoster.get_all_pending())}
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
