defmodule TrWeb.PostLive do
  use TrWeb, :live_view

  alias Tr.Blog
  alias Tr.Post
  alias TrWeb.CommentComponent
  alias TrWeb.Presence

  @topic "users:connected"

  @impl true
  def mount(params, _session, socket) do
    changeset = Tr.Post.change_comment(%Tr.Post.Comment{})
    post_id = Map.get(params, "id")

    if connected?(socket) do
      # Comments PubSub
      Post.subscribe(post_id)

      # Presence PubSub
      Phoenix.PubSub.subscribe(Tr.PubSub, post_id)

      # Track browser session
      {:ok, _} =
        Presence.track(self(), post_id, @topic, %{})
    end

    connected_users = calculate_connected_users(post_id)

    post = Blog.get_post_by_id!(Gettext.get_locale(TrWeb.Gettext), post_id)

    socket =
      socket
      |> assign(:page_title, post.title)
      |> assign(:og_description, post.description)
      |> assign(
        :og_image,
        TrWeb.Endpoint.url() <> "/images/" <> post.image
      )
      |> assign(
        :og_url,
        TrWeb.Endpoint.url() <>
          "/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{post.id}"
      )
      |> assign(:og_type, "article")
      |> assign(:og_tags, post.tags)
      |> assign(:og_date_published, Date.to_iso8601(post.date))
      |> assign(:og_hreflang_en, TrWeb.Endpoint.url() <> "/en/blog/#{post.id}")
      |> assign(:og_hreflang_es, TrWeb.Endpoint.url() <> "/es/blog/#{post.id}")
      |> assign(:reading_time, Blog.reading_time(post))
      |> assign(
        :related_posts,
        Blog.related_posts(post, Gettext.get_locale(TrWeb.Gettext))
      )
      |> assign(:params, params)
      |> assign(:post, post)
      |> assign(check_errors: false)
      |> assign_form(changeset)
      |> assign(:comments, Tr.Post.get_parent_comments_for_post(post_id))
      |> assign(:children, Tr.Post.get_children_comments_for_post(post_id))
      |> assign(:parent_comment_id, nil)
      |> assign(:connected_users, connected_users)
      |> assign(:diff, nil)
      |> assign(:reactions, Tr.Post.get_reactions(post_id))
      |> assign(
        :rocket_launch,
        get_styled_reaction(post.id, "rocket-launch", socket.assigns.current_user)
      )
      |> assign(
        :hand_thumb_up,
        get_styled_reaction(post.id, "hand-thumb-up", socket.assigns.current_user)
      )
      |> assign(
        :heart,
        get_styled_reaction(post.id, "heart", socket.assigns.current_user)
      )
      |> assign(
        :oauth_google_url,
        ElixirAuthGoogle.generate_oauth_url(TrWeb.Endpoint.url())
      )
      |> assign(
        :oauth_github_url,
        ElixirAuthGithub.login_url(%{scopes: ["user:email"]})
      )

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <!-- Post header -->
      <div class="mb-6">
        <h1 class="text-2xl sm:text-3xl font-bold font-mono text-zinc-900 dark:text-zinc-100">
          {@post.title}
        </h1>
        <div class="font-mono text-sm text-terminal-400 mt-2">
          {@post.date} | {@post.author} | {@reading_time} {gettext("min read")}
        </div>
        <div class="flex flex-wrap gap-2 mt-3">
          <%= for tag <- @post.tags do %>
            {TrWeb.PostComponent.render_tag_card(%{tag: tag})}
          <% end %>
        </div>
      </div>
      
    <!-- Reactions -->
      <div class="flex items-center gap-4 font-mono text-sm mb-4 border-b border-terminal-300 dark:border-terminal-600 pb-4">
        <.link
          phx-click="react"
          phx-value-value="rocket-launch"
          phx-value-slug={@post.id}
          aria-label="awesome"
          id="hero-rocket-launch-link"
          class="flex items-center gap-1 text-terminal-400 hover:text-accent-light dark:hover:text-accent transition-colors no-underline"
        >
          <.icon name={@rocket_launch} class="w-5 h-5" />
          <span>{Map.get(@reactions, "rocket-launch", 0)}</span>
        </.link>
        <.link
          phx-click="react"
          phx-value-value="heart"
          phx-value-slug={@post.id}
          aria-label="love it"
          id="hero-heart-link"
          class="flex items-center gap-1 text-terminal-400 hover:text-danger dark:hover:text-danger transition-colors no-underline"
        >
          <.icon name={@heart} class="w-5 h-5" />
          <span>{Map.get(@reactions, "heart", 0)}</span>
        </.link>
        <.link
          phx-click="react"
          phx-value-value="hand-thumb-up"
          phx-value-slug={@post.id}
          aria-label="like it"
          id="hero-hand-thumb-up-link"
          class="flex items-center gap-1 text-terminal-400 hover:text-accent-light dark:hover:text-accent transition-colors no-underline"
        >
          <.icon name={@hand_thumb_up} class="w-5 h-5" />
          <span>{Map.get(@reactions, "hand-thumb-up", 0)}</span>
        </.link>
      </div>
      
    <!-- Share -->
      <div class="flex items-center gap-3 mb-6 text-terminal-400">
        <span class="font-mono text-xs">{gettext("Share")}:</span>
        <a
          href={"https://twitter.com/intent/tweet?url=#{URI.encode_www_form(@og_url)}&text=#{URI.encode_www_form(@post.title)}"}
          target="_blank"
          rel="noopener noreferrer"
          class="text-terminal-400 hover:text-accent-light dark:hover:text-accent transition-colors"
          aria-label="Share on Twitter"
        >
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
            <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
          </svg>
        </a>
        <a
          href={"https://www.linkedin.com/sharing/share-offsite/?url=#{URI.encode_www_form(@og_url)}"}
          target="_blank"
          rel="noopener noreferrer"
          class="text-terminal-400 hover:text-accent-light dark:hover:text-accent transition-colors"
          aria-label="Share on LinkedIn"
        >
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
            <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z" />
          </svg>
        </a>
        <a
          href={"https://news.ycombinator.com/submitlink?u=#{URI.encode_www_form(@og_url)}&t=#{URI.encode_www_form(@post.title)}"}
          target="_blank"
          rel="noopener noreferrer"
          class="text-terminal-400 hover:text-accent-light dark:hover:text-accent transition-colors"
          aria-label="Share on Hacker News"
        >
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
            <path d="M0 0v24h24V0H0zm12.8 13.7V19h-1.6v-5.3L7.3 5h1.8l3 6.3L15 5h1.7l-3.9 8.7z" />
          </svg>
        </a>
      </div>

      <pre class="hidden" phx-hook="CopyToClipboard" id="hidden-code-block">
        <code class="hidden">
        </code>
      </pre>
      
    <!-- Post body -->
      <%= cond do %>
        <% @post.sponsored && @current_user && Tr.SponsorsCache.sponsor?(@current_user.github_username) -> %>
          {raw(@post.body)}
          <br />
          <p>
            <iframe
              width="100%"
              height="800px"
              src={decrypt(@post.video)}
              title=""
              frameBorder="0"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
              allowFullScreen
            >
            </iframe>
          </p>
          <br />
          {@post.id
          |> decrypt_by_path()
          |> Earmark.as_html!()
          |> raw}
        <% @post.sponsored && @current_user && !Tr.SponsorsCache.sponsor?(@current_user.github_username) -> %>
          <br />
          {render_sponsors_banner(assigns)}
          <div class="font-mono text-sm text-terminal-400">
            {gettext("To see the full page, please visit the")}
            <.link href="https://github.com/sponsors/kainlite#sponsors">
              {gettext("sponsor's page.")}
            </.link>
          </div>
          <br />
        <% @post.sponsored && is_nil(@current_user) -> %>
          <br />
          {render_sponsors_banner(assigns)}
          <div class="font-mono text-sm text-terminal-400">
            {gettext("To see the full page, please visit the")}
            <.link href="https://github.com/sponsors/kainlite#sponsors">
              {gettext("sponsor's page.")}
            </.link>
          </div>
          <br />
        <% true -> %>
          {render_sponsors_banner(assigns)}
      <% end %>
      
    <!-- Comments section -->
      <div class="border-t border-terminal-300 dark:border-terminal-600 pt-6 mt-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-mono text-lg text-accent-light dark:text-accent">
            $ {gettext("Comments")}
          </h3>
          <span class="font-mono text-xs text-terminal-400">
            {gettext("Online")}: {@connected_users}
            <span class="inline-block w-2 h-2 bg-accent rounded-full ml-1"></span>
          </span>
        </div>

        <div class="space-y-0">
          <%= for comment <- @comments do %>
            <% user = Tr.Repo.preload(comment, :user).user %>
            <% link_id = "comment-#{comment.id}-#{:rand.uniform(100_000)}" %>
            <CommentComponent.render_comment
              avatar_url={user.avatar_url}
              display_name={get_display_name(user)}
              comment={comment}
              link_id={link_id}
              classes=""
              approved={comment.approved}
            />

            <%= for child <- Map.get(@children, comment.id, []) do %>
              <% user = Tr.Repo.preload(child, :user).user %>
              <% link_id = "child-comment-#{comment.id}-#{:rand.uniform(100_000)}" %>
              <CommentComponent.render_comment
                avatar_url={user.avatar_url}
                display_name={get_display_name(user)}
                comment={child}
                link_id={link_id}
                classes="ml-8"
                approved={child.approved}
              />
            <% end %>
          <% end %>
        </div>

        <%= if @current_user && @current_user.confirmed_at do %>
          <CommentComponent.render_comment_input
            form={@form}
            parent_comment_id={@parent_comment_id}
            display_name={get_display_name(@current_user)}
            post={@post}
            check_errors={@check_errors}
          />
        <% else %>
          <p class="font-mono text-sm text-terminal-400 text-center mt-4">
            {gettext("Please sign in to be able to write comments.")}
          </p>
        <% end %>
      </div>
      
    <!-- Post footer -->
      <div class="font-mono text-sm text-terminal-400 text-center mt-6 border-t border-terminal-300 dark:border-terminal-600 pt-4">
        {@post.date} | {@post.author}
      </div>
      
    <!-- Related posts -->
      <%= if @related_posts != [] do %>
        <div class="mt-6 border-t border-terminal-300 dark:border-terminal-600 pt-4">
          <h3 class="font-mono text-sm text-accent-light dark:text-accent mb-3">
            $ {gettext("Related Posts")}
          </h3>
          <div class="space-y-1">
            <%= for rp <- @related_posts do %>
              <div class="font-mono text-sm py-1">
                <span class="text-accent-light dark:text-accent">></span>
                <.link
                  navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{rp.id}"}
                  class="ml-2 hover:text-accent-light dark:hover:text-accent transition-colors"
                >
                  {rp.title}
                </.link>
                <span class="text-terminal-400 ml-2">({rp.date})</span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("react", %{"value" => value, "slug" => slug} = params, socket) do
    if is_nil(socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:error, gettext("You need to be logged in to react."))}
    else
      params =
        Map.merge(
          %{
            "user_id" => socket.assigns.current_user.id
          },
          params
        )

      case Tr.Post.reaction_exists?(slug, value, socket.assigns.current_user.id) do
        true ->
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          reaction = Tr.Post.get_reaction(slug, value, socket.assigns.current_user.id)

          case Tr.Post.delete_reaction(reaction) do
            {:ok, _} ->
              {:noreply, socket}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, gettext("There is been an error removing your reaction."))}
          end

        false ->
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          case Tr.Post.create_reaction(params) do
            {:ok, _} ->
              {:noreply, socket}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, gettext("There is been an error saving your reaction."))}
          end
      end
    end
  end

  @impl true
  def handle_event("save", %{"comment" => comment_params}, socket) do
    params =
      Map.merge(
        %{
          "user_id" => socket.assigns.current_user.id
        },
        comment_params
      )

    current_user = socket.assigns.current_user

    if current_user && !is_nil(current_user.confirmed_at) do
      case Tr.Post.create_comment(params) do
        {:ok, comment} ->
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          if !is_nil(comment.parent_comment_id) &&
               Tr.Post.get_comment(comment.parent_comment_id).user_id != current_user.id do
            Tr.PostTracker.Notifier.deliver_new_reply_notification(
              Tr.Accounts.get_user!(Tr.Post.get_comment(comment.parent_comment_id).user_id),
              comment.body,
              "#{TrWeb.Endpoint.url()}/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{comment.slug}"
            )
          end

          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          if is_nil(comment.parent_comment_id) do
            Tr.PostTracker.Notifier.deliver_new_comment_notification(
              Tr.Accounts.get_admin_user(),
              comment.body,
              "#{TrWeb.Endpoint.url()}/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{comment.slug}"
            )
          end

          {:noreply,
           socket
           |> assign_form(Tr.Post.change_comment(%Tr.Post.Comment{}))
           |> put_flash(:info, gettext("Comment saved successfully."))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(check_errors: true)
           |> assign_form(changeset)
           |> put_flash(:error, gettext("There is been an error saving your comment."))}
      end
    else
      {:noreply, socket |> put_flash(:error, gettext("You need to validate your account"))}
    end
  end

  @impl true
  def handle_event(
        "prepare_comment_form",
        %{"slug" => _, "comment-id" => parent_comment_id},
        socket
      ) do
    comment = Tr.Post.get_comment(parent_comment_id)

    parent_comment_id =
      if comment.parent_comment_id, do: comment.parent_comment_id, else: comment.id

    {:noreply, assign(socket, :parent_comment_id, parent_comment_id)}
  end

  @impl true
  def handle_event(
        "clear_comment_form",
        _,
        socket
      ) do
    {:noreply, assign(socket, :parent_comment_id, nil)}
  end

  @impl true
  def handle_info({:reaction_created, reaction}, socket) do
    {:noreply,
     socket
     |> assign(:reactions, Tr.Post.get_reactions(reaction.slug))
     |> assign(
       :rocket_launch,
       get_styled_reaction(reaction.slug, "rocket-launch", socket.assigns.current_user)
     )
     |> assign(
       :hand_thumb_up,
       get_styled_reaction(reaction.slug, "hand-thumb-up", socket.assigns.current_user)
     )
     |> assign(:heart, get_styled_reaction(reaction.slug, "heart", socket.assigns.current_user))}
  end

  @impl true
  def handle_info({:reaction_deleted, reaction}, socket) do
    {:noreply,
     socket
     |> assign(:reactions, Tr.Post.get_reactions(reaction.slug))
     |> assign(
       :rocket_launch,
       get_styled_reaction(reaction.slug, "rocket-launch", socket.assigns.current_user)
     )
     |> assign(
       :hand_thumb_up,
       get_styled_reaction(reaction.slug, "hand-thumb-up", socket.assigns.current_user)
     )
     |> assign(:heart, get_styled_reaction(reaction.slug, "heart", socket.assigns.current_user))}
  end

  @impl true
  def handle_info({:comment_created, comment}, socket) do
    comments =
      if is_nil(comment.parent_comment_id) do
        socket.assigns.comments ++ [comment]
      else
        socket.assigns.comments
      end

    children =
      if is_nil(comment.parent_comment_id) do
        socket.assigns.children
      else
        Map.put(
          socket.assigns.children,
          comment.parent_comment_id,
          Map.get(socket.assigns.children, comment.parent_comment_id, []) ++ [comment]
        )
      end

    {:noreply,
     socket
     |> assign(:comments, comments)
     |> assign(:children, children)}
  end

  @impl true
  def handle_info(
        %{
          topic: topic,
          event: "presence_diff",
          payload: %{joins: _joins, leaves: _leaves}
        },
        socket
      ) do
    {:noreply, socket |> assign(:connected_users, calculate_connected_users(topic))}
  end

  @impl true
  def handle_info({:email, _}, socket) do
    {:noreply, socket}
  end

  defp calculate_connected_users(post_id) do
    connected_users = Map.get(Presence.list(post_id), @topic, %{})
    metas = Map.get(connected_users, :metas, [])
    Enum.count(metas)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "comment")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp get_display_name(user) do
    faker = Faker.Superhero

    name = faker.prefix() <> " " <> faker.name() <> " " <> faker.suffix()

    if user && !is_nil(user.display_name) do
      user.display_name
    else
      name
    end
  end

  defp get_styled_reaction(_, value, current_user) when is_nil(current_user) do
    "hero-#{value}"
  end

  defp get_styled_reaction(post_id, value, current_user) when not is_nil(current_user) do
    reaction = Tr.Post.reaction_exists?(post_id, value, current_user.id)

    if reaction do
      "hero-#{value}-solid"
    else
      "hero-#{value}"
    end
  end

  defp decrypt(b64cipher) do
    {:ok, b64dec} = Base.decode64(b64cipher, ignore: :whitespace)
    {:ok, dec} = Tr.Vault.decrypt(b64dec)

    dec
  end

  defp decrypt_by_path(slug) do
    path =
      Path.join([
        Application.app_dir(:tr),
        "./priv/encrypted/#{Gettext.get_locale(TrWeb.Gettext)}",
        "#{slug}.md"
      ])

    file = File.read!(path)

    decrypt(file)
  end

  defp render_sponsors_banner(assigns) do
    ~H"""
    <div class="mx-auto items-center justify-center">
      <div class="text-center mb-4">
        <h3 class="text-lg font-mono font-bold mb-2 text-accent-light dark:text-accent">
          {gettext("Support this blog")}
        </h3>
        <p class="text-sm text-terminal-400">
          {gettext("If you find this content useful, consider supporting the blog.")}
        </p>
      </div>
      <div class="flex flex-wrap gap-4 justify-center items-center mb-4">
        <div class="w-full overflow-x-auto">
          <iframe
            src="https://github.com/sponsors/kainlite/card"
            title="Sponsor kainlite"
            height="225"
            style="border: 0; width: 100%; max-width: 600px;"
            class="mx-auto justify-center items-center"
          >
          </iframe>
        </div>
        <a
          href="https://buymeacoffee.com/kainlite"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-2 px-4 py-2 bg-accent-light dark:bg-accent text-white dark:!text-terminal-900 font-mono font-semibold rounded-none hover:bg-accent-dark dark:hover:bg-accent-muted transition-colors"
        >
          <svg class="w-5 h-5" viewBox="0 0 884 1279" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path
              d="m791 298c-1 0-2 0-3 0-34-2-183-1-216 0-11 0-20 10-19 21 1 10 9 18 20 18h1l102-1c-1 9-8 124-14 188-7 79-14 159-14 230 0 13 0 26 1 39 2 45 4 97 62 125 20 9 42 14 64 14 26 0 53-7 78-21 45-25 76-72 92-140 6 1 13 2 19 2 50 0 82-24 82-63 0-18-7-43-28-62-17-16-41-25-69-27 0-3 0-5 0-8-1-50-1-100-3-150l-2-79c1 0 2 0 4 1 16 1 33 2 50 2 7 0 13 0 20-1 51-4 89-36 91-77 2-27-13-63-76-72-15-2-30-3-46-3-17 0-34 1-50 2-13 1-26 2-38 2-23 0-45-3-67-5-13-2-26-3-39-4z"
              fill="#0d0c22"
            />
            <path
              d="m474 199c-107 0-127 84-127 84s-21-84-127-84c-75 0-136 61-136 136 0 86 72 180 263 277 191-97 263-191 263-277 0-75-61-136-136-136z"
              fill="#FF813F"
            />
          </svg>
          {gettext("Buy Me a Coffee")}
        </a>
      </div>

      {raw(@post.body)}

      <br />
    </div>
    """
  end
end
