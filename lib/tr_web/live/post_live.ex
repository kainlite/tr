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

    socket =
      socket
      |> assign(:params, params)
      |> assign(:post, Blog.get_post_by_id!(post_id))
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_form(changeset)
      |> assign(:comments, Tr.Post.get_parent_comments_for_post(post_id))
      |> assign(:children, Tr.Post.get_children_comments_for_post(post_id))
      |> assign(:parent_comment_id, nil)
      |> assign(:connected_users, connected_users)
      |> assign(:diff, nil)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="float-left">
      <h2><%= @post.title %></h2>
    </div>
    <div class="float-right">
      <h5>
        <.link navigate={~p"/blog"}>
          ← All posts
        </.link>
        <p class="clear-both"></p>
      </h5>
    </div>

    <p class="clear-both"></p>

    <div class="mx-auto">
      <ul class="space-y-4 list-none">
        <li class="px-1">
          <h5 class="font-bold py-0">Tags</h5>
        </li>
        <%= for tag <- @post.tags do %>
          <li class="bg-white shadow-md p-4 rounded-lg border-l-solid border-l-[5px] border-l-gray-700 float-left">
            <.link navigate={~p"/blog?tag=#{tag}"}>
              <%= tag %>
            </.link>
          </li>
        <% end %>
      </ul>
    </div>

    <p class="clear-both"></p>

    <%= raw(@post.body) %>

    <div class="mx-auto max-w-4xl">
      <%= unless @current_user do %>
        <.header class="text-center">
          No account? Register
          <.link navigate={~p"/users/register"} class="font-semibold text-brand hover:underline">
            here
          </.link>
          <:subtitle>
            Already registered?
            <.link navigate={~p"/users/log_in"} class="font-semibold text-brand hover:underline">
              Sign in
            </.link>
            to your account now.
          </:subtitle>
        </.header>
      <% end %>

      <div class="mx-auto">
        <ul class="list-none mb-0">
          <li class="px-1 mb-0">
            <h4 class="font-bold  float-left">Comments</h4>
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
              "bg-white shadow-md p-4 rounded-lg border-l-solid border-l-[5px] border-l-gray-700" %>
            <CommentComponent.render_comment
              avatar_url={user.avatar_url}
              display_name={get_display_name(user)}
              comment={comment}
              link_id={link_id}
              classes={parent_classes}
            >
            </CommentComponent.render_comment>

            <%= for child <- Map.get(@children, comment.id, []) do %>
              <% user = Tr.Repo.preload(child, :user).user %>
              <% link_id = "child-comment-#{comment.id}-#{:rand.uniform(100_000)}" %>
              <% child_classes =
                "bg-white shadow-md p-4 rounded-lg ml-[40px] border-l-solid border-l-[5px] border-l-teal-300" %>

              <CommentComponent.render_comment
                avatar_url={user.avatar_url}
                display_name={get_display_name(user)}
                comment={child}
                link_id={link_id}
                classes={child_classes}
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
          Please complete your account verification to be able to write comments
        </p>
      <% end %>

      <div class="text-center">
        <time><%= @post.date %></time> by <%= @post.author %>
      </div>
    </div>
    """
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
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(trigger_submit: true)
           |> put_flash(:info, "Comment saved successfully.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(check_errors: true)
           |> assign_form(changeset)
           |> put_flash(:error, "There is been an error saving your comment.")}
      end
    else
      {:noreply, socket |> put_flash(:error, "You need to validate your account")}
    end
  end

  @impl true
  def handle_event(
        "prepare_comment_form",
        %{"slug" => _, "comment-id" => parent_comment_id},
        socket
      ) do
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
end
