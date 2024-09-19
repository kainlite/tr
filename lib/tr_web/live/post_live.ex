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

    post = Blog.get_post_by_id!(post_id)

    socket =
      socket
      |> assign(:page_title, post.title)
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
    <div class="float-left">
      <h2><%= @post.title %></h2>
    </div>
    <div class="float-right dark:invert py-6">
      <.link
        phx-click="react"
        phx-value-value="rocket-launch"
        phx-value-slug={@post.id}
        aria-label="awesome"
        id="hero-rocket-launch-link"
      >
        <.icon name={@rocket_launch} class="w-10 h-10 bg-black" />
        <span class="font-semibold"><%= Map.get(@reactions, "rocket-launch", 0) %></span>
      </.link>
      <.link
        phx-click="react"
        phx-value-value="heart"
        phx-value-slug={@post.id}
        aria-label="love it"
        id="hero-heart-link"
      >
        <.icon name={@heart} class="w-10 h-10 bg-red-500 dark:bg-black" />
        <span class="font-semibold">
          <%= Map.get(@reactions, "heart", 0) %>
        </span>
      </.link>
      <.link
        phx-click="react"
        phx-value-value="hand-thumb-up"
        phx-value-slug={@post.id}
        aria-label="like it"
        id="hero-hand-thumb-up-link"
      >
        <.icon name={@hand_thumb_up} class="w-10 h-10 bg-black" />
        <span class="font-semibold"><%= Map.get(@reactions, "hand-thumb-up", 0) %></span>
      </.link>
    </div>

    <p class="clear-both"></p>

    <div class="mx-auto">
      <ul class="space-y-6 list-none">
        <div class="flex flex-row flex-wrap">
          <%= for tag <- @post.tags do %>
            <%= TrWeb.PostComponent.render_tag_card(%{tag: tag}) %>
          <% end %>
        </div>
      </ul>
    </div>

    <p class="clear-both"></p>

    <%= TrWeb.AdsComponent.render_large_ad(assigns) %>

    <%= raw(@post.body) %>

    <%= cond do %>
      <% @post.sponsored && @current_user && Tr.SponsorsCache.sponsor?(@current_user.github_username) -> %>
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
        <%= raw(Earmark.as_html!(decrypt(@post.encrypted_content))) %>
      <% @post.sponsored && @current_user && !Tr.SponsorsCache.sponsor?(@current_user.github_username) -> %>
        <br /> <%= gettext("To see this article, please visit the
        ") %><.link href="https://github.com/sponsors/kainlite#sponsors" class="">
          <%= gettext "sponsor's page.
          " %></.link>
        <br />
        <br />
        <br />
      <% @post.sponsored && is_nil(@current_user) -> %>
        <br /> <%= gettext("To see this article, please visit the") %>
        <.link href="https://github.com/sponsors/kainlite#sponsors" class="">
          <%= gettext("sponsor's page.") %>
        </.link>
        <br />
        <br />
        <br />
      <% true -> %>
      
    <% end %>

    <div class="mx-auto max-w-4xl">
      <%= unless @current_user do %>
        <.header class="text-center">
          <%= gettext("No account? Register") %>
          <.link navigate={~p"/users/register"} class="font-semibold text-brand hover:underline">
            <%= gettext("here") %>
          </.link>
          <:subtitle>
            <%= gettext("Already registered?") %>
            <.link navigate={~p"/users/log_in"} class="font-semibold text-brand hover:underline">
              <%= gettext("Sign in") %>
            </.link>
            <%= gettext("to your account now.") %>
          </:subtitle>
        </.header>

        <div style="display:flex; flex-direction:column; width:368px; text-center items-center justify-center">
          <link href="https://fonts.googleapis.com/css?family=Roboto&display=swap" />
          <a
            href={@oauth_github_url}
            style="display:inline-flex; align-items:center; min-height:30px;
            background-color:#24292e; font-family:'Roboto',sans-serif;
            font-size:14px; color:white; text-decoration:none;"
            class="rounded-lg text-center items-center relative left-[42%] mb-[10px]"
          >
            <div style="margin: 1px; padding-top:5px; min-height:30px;">
              <svg height="18" viewBox="0 0 16 16" width="32px" style="fill:white;">
                <path
                  fill-rule="evenodd"
                  d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38
              0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01
              1.08.58 1.23.82.72 1.21 1.87.87
              2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12
              0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08
              2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0
              .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"
                />
              </svg>
            </div>
            <div style="margin-left: 5px;"><%= gettext("Sign in with GitHub") %></div>
          </a>
        </div>

        <div style="display:flex; flex-direction:column; width:368px; text-center items-center justify-center">
          <link href="https://fonts.googleapis.com/css?family=Roboto&display=swap" />

          <a
            href={@oauth_google_url}
            style="display:inline-flex; align-items:center; min-height:50px;
              background-color:#4285F4; font-family:'Roboto',sans-serif;
              font-size:28px; color:white; text-decoration:none;
              margin-top: 12px;"
            class="rounded-lg text-center items-center relative left-[42%] mb-[10px]"
          >
            <div style="background-color: white; margin:2px;  padding-bottom:6px; min-height:30px; width:72px">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 533.5 544.3"
                width="52px"
                height="35"
                style="display:inline-flex; align-items:center;"
              >
                <path
                  d="M533.5 278.4c0-18.5-1.5-37.1-4.7-55.3H272.1v104.8h147c-6.1 33.8-25.7 63.7-54.4 82.7v68h87.7c51.5-47.4 81.1-117.4 81.1-200.2z"
                  fill="#4285f4"
                />
                <path
                  d="M272.1 544.3c73.4 0 135.3-24.1 180.4-65.7l-87.7-68c-24.4 16.6-55.9 26-92.6 26-71 0-131.2-47.9-152.8-112.3H28.9v70.1c46.2 91.9 140.3 149.9 243.2 149.9z"
                  fill="#34a853"
                />
                <path
                  d="M119.3 324.3c-11.4-33.8-11.4-70.4 0-104.2V150H28.9c-38.6 76.9-38.6 167.5 0 244.4l90.4-70.1z"
                  fill="#fbbc04"
                />
                <path
                  d="M272.1 107.7c38.8-.6 76.3 14 104.4 40.8l77.7-77.7C405 24.6 339.7-.8 272.1 0 169.2 0 75.1 58 28.9 150l90.4 70.1c21.5-64.5 81.8-112.4 152.8-112.4z"
                  fill="#ea4335"
                />
              </svg>
            </div>
            <div style="margin-left: 27px;">
              <%= gettext("Sign in with Google") %>
            </div>
          </a>
        </div>
      <% end %>

      <div class="mx-auto">
        <ul class="list-none mb-0">
          <li class="px-1 mb-0">
            <h4 class="font-bold  float-left"><%= gettext("Comments") %></h4>
            <p class="text-sm float-right mb-0 p-0 font-bold ">
              Online: <%= @connected_users %>
              <span class="flex w-3 h-3 me-3 bg-green-500 rounded-full float-right mr-[5px]"></span>
              <p class="clear-both my-0 mb-0 p-0"></p>
            </p>
          </li>
          <%= for comment <- @comments do %>
            <% user = Tr.Repo.preload(comment, :user).user %>
            <% link_id = "comment-#{comment.id}-#{:rand.uniform(100_000)}" %>
            <% parent_classes =
              "bg-white dark:bg-zinc-800 dark:text-white shadow-md p-4 rounded-lg border-l-solid border-l-[5px]
              border-l-gray-700 text-base min-h-24 font-medium" %>
            <CommentComponent.render_comment
              avatar_url={user.avatar_url}
              display_name={get_display_name(user)}
              comment={comment}
              link_id={link_id}
              classes={parent_classes}
              approved={comment.approved}
            >
            </CommentComponent.render_comment>

            <%= for child <- Map.get(@children, comment.id, []) do %>
              <% user = Tr.Repo.preload(child, :user).user %>
              <% link_id = "child-comment-#{comment.id}-#{:rand.uniform(100_000)}" %>
              <% child_classes =
                "bg-white dark:bg-zinc-800 dark:text-white shadow-md p-4 min-h-24 text-base font-medium rounded-lg ml-[40px] border-l-solid border-l-[5px] border-l-teal-300" %>

              <CommentComponent.render_comment
                avatar_url={user.avatar_url}
                display_name={get_display_name(user)}
                comment={child}
                link_id={link_id}
                classes={child_classes}
                approved={child.approved}
              >
              </CommentComponent.render_comment>
            <% end %>
          <% end %>
        </ul>
      </div>

      <%= if @current_user && @current_user.confirmed_at do %>
        <CommentComponent.render_comment_input
          form={@form}
          parent_comment_id={@parent_comment_id}
          display_name={get_display_name(@current_user)}
          post={@post}
          check_errors={@check_errors}
        >
        </CommentComponent.render_comment_input>
      <% else %>
        <p class="text-sm font-bold text-center">
          <%= gettext("Please sign in to be able to write comments.") %>
        </p>
      <% end %>

      <div class="text-center">
        <time><%= @post.date %></time> by <%= @post.author %>
      </div>
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
              "#{TrWeb.Endpoint.url()}/blog/#{comment.slug}"
            )
          end

          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          if is_nil(comment.parent_comment_id) do
            Tr.PostTracker.Notifier.deliver_new_comment_notification(
              Tr.Accounts.get_admin_user(),
              comment.body,
              "#{TrWeb.Endpoint.url()}/blog/#{comment.slug}"
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
    {:ok, b64dec} = Base.decode64(b64cipher)
    {:ok, dec} = Tr.Vault.decrypt(b64dec)

    dec
  end
end
