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
     |> assign_dashboard_stats()
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
     |> assign_dashboard_stats()
     |> assign_cross_post_data()}
  end

  defp assign_dashboard_stats(socket) do
    en_posts = Tr.Blog.posts("en")
    es_posts = Tr.Blog.posts("es")

    avg_reading =
      (fn posts ->
         total = Enum.reduce(posts, 0, fn p, acc -> acc + Tr.Blog.reading_time(p) end)
         div(total, length(posts))
       end).(en_posts)

    socket
    |> assign(:user_stats, TrWeb.Presence.list_connected_users())
    |> assign(:users, Tr.Accounts.get_users(10))
    |> assign(:total_posts_en, length(en_posts))
    |> assign(:total_posts_es, length(es_posts))
    |> assign(:total_tags, length(Tr.Blog.all_tags()))
    |> assign(:avg_reading_time, avg_reading)
    |> assign(:total_reactions, Tr.Post.get_total_reactions_count())
    |> assign(:approved_comments, Tr.Post.get_approved_comments_count())
    |> assign(:pending_comments, Tr.Post.get_unapproved_comments_count())
    |> assign(:subscribers_count, Tr.Accounts.get_subscribers_count())
    |> assign(:top_reacted, Tr.Post.get_top_reacted_posts(5))
    |> assign(:most_commented, Tr.Post.get_most_commented_posts(5))
    |> assign(:unannounced_posts, Tr.Tracker.get_unannounced_posts())
  end

  defp assign_cross_post_data(socket) do
    socket
    |> assign(:cross_post_pending, Tr.CrossPoster.get_all_pending())
    |> assign(:linkedin_configured, Tr.CrossPoster.LinkedIn.configured?())
    |> assign(:substack_configured, Tr.CrossPoster.Substack.draft_api_configured?())
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="card-tech p-4 flex flex-col gap-1">
      <span class="text-sm text-zinc-500 dark:text-zinc-400">{@label}</span>
      <span class="text-2xl font-bold text-zinc-900 dark:text-zinc-100">{@value}</span>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto space-y-8">
      <h2>{gettext("Admin Dashboard")}</h2>

      <%!-- Stats Grid --%>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <.stat_card label="Registered Users" value={Tr.Accounts.get_users_count()} />
        <.stat_card label="Connected Users" value={@user_stats.total} />
        <.stat_card label="Total Comments" value={Tr.Post.get_comments_count()} />
        <.stat_card label="Total Reactions" value={@total_reactions} />
        <.stat_card label="Posts (EN)" value={@total_posts_en} />
        <.stat_card label="Posts (ES)" value={@total_posts_es} />
        <.stat_card label="Tags" value={@total_tags} />
        <.stat_card label="Avg Reading Time" value={"#{@avg_reading_time} min"} />
        <.stat_card label="Approved Comments" value={@approved_comments} />
        <.stat_card label="Pending Comments" value={@pending_comments} />
        <.stat_card label="Subscribers" value={@subscribers_count} />
        <.stat_card label="Unannounced Posts" value={length(@unannounced_posts)} />
      </div>

      <%!-- Active Rooms --%>
      <div class="card-tech p-6">
        <h3 class="text-lg font-semibold mb-4 text-zinc-900 dark:text-zinc-100">
          {gettext("Active Rooms")}
        </h3>
        <%= if @user_stats.per_room == %{} do %>
          <p class="text-sm text-zinc-500 dark:text-zinc-400">No active rooms</p>
        <% else %>
          <ul class="list-none space-y-2">
            <%= for {room, count} <- @user_stats.per_room do %>
              <li class="flex justify-between items-center py-2 border-b border-gray-200 dark:border-surface-600">
                <.link
                  href={"/en/blog/#{room}"}
                  class="text-brand-500 hover:text-brand-600 dark:text-brand-400 dark:hover:text-brand-300"
                >
                  {room}
                </.link>
                <span class="text-sm text-zinc-500 dark:text-zinc-400">{count} users</span>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <%!-- Top Posts --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="card-tech p-6">
          <h3 class="text-lg font-semibold mb-4 text-zinc-900 dark:text-zinc-100">
            Most Reacted Posts
          </h3>
          <%= if @top_reacted == [] do %>
            <p class="text-sm text-zinc-500 dark:text-zinc-400">No reactions yet</p>
          <% else %>
            <ul class="list-none space-y-2">
              <%= for {slug, count} <- @top_reacted do %>
                <li class="flex justify-between items-center py-2 border-b border-gray-200 dark:border-surface-600">
                  <.link
                    href={"/en/blog/#{slug}"}
                    class="text-brand-500 hover:text-brand-600 dark:text-brand-400 dark:hover:text-brand-300 truncate mr-2"
                  >
                    {slug}
                  </.link>
                  <span class="text-sm text-zinc-500 dark:text-zinc-400 whitespace-nowrap">
                    {count} reactions
                  </span>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>

        <div class="card-tech p-6">
          <h3 class="text-lg font-semibold mb-4 text-zinc-900 dark:text-zinc-100">
            Most Commented Posts
          </h3>
          <%= if @most_commented == [] do %>
            <p class="text-sm text-zinc-500 dark:text-zinc-400">No comments yet</p>
          <% else %>
            <ul class="list-none space-y-2">
              <%= for {slug, count} <- @most_commented do %>
                <li class="flex justify-between items-center py-2 border-b border-gray-200 dark:border-surface-600">
                  <.link
                    href={"/en/blog/#{slug}"}
                    class="text-brand-500 hover:text-brand-600 dark:text-brand-400 dark:hover:text-brand-300 truncate mr-2"
                  >
                    {slug}
                  </.link>
                  <span class="text-sm text-zinc-500 dark:text-zinc-400 whitespace-nowrap">
                    {count} comments
                  </span>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>

      <%!-- Comment Moderation --%>
      <div class="card-tech p-6">
        <h3 class="text-lg font-semibold mb-4 text-zinc-900 dark:text-zinc-100">
          Comment Moderation
        </h3>

        <div class="flex gap-4 mb-4">
          <.link
            href={~p"/admin/dashboard?comments=all"}
            class="text-[1.25rem] leading-6 text-zinc-900 dark:text-zinc-100 font-semibold hover:text-brand-500 dark:hover:text-brand-400"
          >
            {gettext("All comments")}
          </.link>
          <span class="text-zinc-400">|</span>
          <.link
            href={~p"/admin/dashboard?comments=unapproved"}
            class="text-[1.25rem] leading-6 text-zinc-900 dark:text-zinc-100 font-semibold hover:text-brand-500 dark:hover:text-brand-400"
          >
            {gettext("Unapproved comments")}
          </.link>
        </div>

        <.table id="comments" rows={@comments}>
          <:col :let={comment} label="id">{comment.id}</:col>
          <:col :let={comment} label="slug">
            <.link
              href={"/en/blog/#{comment.slug}"}
              class="text-brand-500 hover:text-brand-600 dark:text-brand-400 dark:hover:text-brand-300"
            >
              {comment.slug}
            </.link>
          </:col>
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
              Approve
            </.link>
            <.link
              class="text-[1.25rem] leading-6 text-zinc-700 font-semibold hover:text-zinc-700"
              phx-click="delete_comment"
              phx-value-slug={comment.slug}
              phx-value-comment-id={comment.id}
              data-confirm="Are you sure?"
            >
              Delete
            </.link>
          </:col>
        </.table>
      </div>

      <%!-- Recent Users --%>
      <div class="card-tech p-6">
        <h3 class="text-lg font-semibold mb-4 text-zinc-900 dark:text-zinc-100">
          Recent Users
        </h3>

        <.table id="users" rows={@users}>
          <:col :let={user} label="id">{user.id}</:col>
          <:col :let={user} label="email">{user.email}</:col>
          <:col :let={user} label="github_username">{user.github_username}</:col>
          <:col :let={user} label="display_name">{user.display_name}</:col>
          <:col :let={user} label="confirmed">
            <%= if user.confirmed_at do %>
              <span class="inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-green-600/20 ring-inset dark:bg-green-500/10 dark:text-green-400 dark:ring-green-500/20">
                Yes
              </span>
            <% else %>
              <span class="inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-red-600/10 ring-inset dark:bg-red-400/10 dark:text-red-400 dark:ring-red-400/20">
                No
              </span>
            <% end %>
          </:col>
          <:col :let={user} label="subscribed">
            <%= if user.accept_emails do %>
              <span class="inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-green-600/20 ring-inset dark:bg-green-500/10 dark:text-green-400 dark:ring-green-500/20">
                Yes
              </span>
            <% else %>
              <span class="inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-red-600/10 ring-inset dark:bg-red-400/10 dark:text-red-400 dark:ring-red-400/20">
                No
              </span>
            <% end %>
          </:col>
        </.table>
      </div>

      <%!-- Cross-Posting --%>
      <div class="card-tech p-6">
        <h3 class="text-lg font-semibold mb-4 text-zinc-900 dark:text-zinc-100">
          Cross-Posting
        </h3>

        <%= unless @linkedin_configured do %>
          <p class="text-sm text-yellow-600 dark:text-yellow-400 mb-4">
            LinkedIn not configured (set LINKEDIN_ACCESS_TOKEN and LINKEDIN_PERSON_URN)
          </p>
        <% end %>

        <.table id="cross-posts" rows={@cross_post_pending}>
          <:col :let={tracker} label="Slug">
            <.link
              href={"/en/blog/#{tracker.slug}"}
              class="text-brand-500 hover:text-brand-600 dark:text-brand-400 dark:hover:text-brand-300"
            >
              {tracker.slug}
            </.link>
          </:col>
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
        {:noreply,
         push_event(socket, "copy_to_clipboard", %{
           text: content.body_html,
           target: "copy-html-" <> slug
         })}

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
     |> assign_dashboard_stats()
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
