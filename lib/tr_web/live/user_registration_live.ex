defmodule TrWeb.UserRegistrationLive do
  use TrWeb, :live_view

  alias Tr.Accounts
  alias Tr.Accounts.User

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        <%= gettext("Register for an account") %>
        <:subtitle>
          <%= gettext("Already registered?") %>
          <.link
            navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/users/log_in"}
            class="font-semibold text-brand hover:underline"
          >
            <%= gettext("Sign in") %>
          </.link>
          <%= gettext("to your account now.") %>
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/users/log_in?_action=registered"}
        method="post"
      >
        <.error :if={@check_errors}>
          <%= gettext("Oops, something went wrong! Please check the errors below.") %>
        </.error>

        <.input
          field={@form[:display_name]}
          type="text"
          label="Superhero name (Used for comments)"
          value={@display_name}
          required
        />
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Password" required />

        <:actions>
          <.button phx-disable-with="Creating account..." class="w-full">Create an account</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_new(:display_name, fn -> get_display_name() end)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    user_params = Map.put(user_params, "avatar_url", Faker.Avatar.image_url())

    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp get_display_name() do
    faker = Faker.Superhero

    faker.prefix() <> " " <> faker.name() <> " " <> faker.suffix()
  end
end
