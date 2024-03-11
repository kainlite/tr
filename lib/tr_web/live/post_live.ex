defmodule TrWeb.PostLive do
  use TrWeb, :live_view
  alias Tr.Blog

  on_mount {TrWeb.UserAuth, :mount_current_user}

  @impl true
  def mount(params, _session, socket) do
    changeset = Tr.Post.change_comment(%Tr.Post.Comment{})

    socket =
      socket
      |> assign(:params, params)
      |> assign(:post, Blog.get_post_by_id!(Map.get(params, "id")))
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_form(changeset)
      |> assign(:comments, Tr.Post.get_comments_for_post(Map.get(params, "id")))

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.link navigate={~p"/blog"}>
      ← All posts
    </.link>

    <h2><%= @post.title %></h2>
    <h5>
      <time><%= @post.date %></time> by <%= @post.author %>
    </h5>

    <p>
      Tagged as <%= Enum.join(@post.tags, ", ") %>
    </p>
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

      <div class="mx-auto py-8">
        <h1 class="text-3xl font-bold mb-6">Comments</h1>
        <ul class="space-y-4 list-none">
          <%= for comment <- @comments do %>
            <li class="bg-white shadow-md p-4 rounded-lg">
              <div class="flex items-start">
                <img
                  class="w-12 h-12 rounded-full mr-4"
                  src={Faker.Avatar.image_url()}
                  alt="User Avatar"
                />
                <div class="flex-1 max-w-3xl">
                  <div class="flex justify-between items-center">
                    <h2 class="text-lg font-semibold">
                      <%= get_display_name(Tr.Repo.preload(comment, :user).user) %>
                    </h2>
                    <span class="text-gray-500 text-sm"><%= comment.updated_at %></span>
                  </div>
                  <p class="text-gray-800 mt-2 comment-text text-clip md:text-clip break-words line-clamp-1 max-w-3xl">
                    <%= comment.body %>
                  </p>
                  <.link
                    navigate={~p"/blog/#{comment.id}/comment"}
                    class="font-semibold text-sm float-right"
                  >
                    Reply
                  </.link>
                </div>
              </div>
            </li>
          <% end %>
        </ul>
      </div>

      <%= # if @current_user && @current_user.confirmed_at do %>
      <.simple_form for={@form} id="comment_form" phx-submit="save">
        <.error :if={@check_errors}>
          Oops, something went wrong! Please check the errors below.
        </.error>

        <.input field={@form[:body]} type="textarea" label="Message" required />
        <.input field={@form[:parent_id]} type="hidden" id="hidden_comment_parent_id" />
        <.input field={@form[:slug]} type="hidden" id="hidden_post_slug" value={@post.id} />

        <:actions>
          <.button phx-disable-with="Saving..." class="w-full">Send</.button>
        </:actions>
      </.simple_form>
      <% # else %>
      <p>Please complete your account verification to be able to write comments</p>
      <% # end %>
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
        {:ok, comment} ->
          {:noreply,
           socket
           |> assign(trigger_submit: true)
           |> assign(:comments, socket.assigns.comments ++ [comment])
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
      name
    else
      user.display_name
    end
  end
end
