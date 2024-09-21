defmodule TrWeb.UserSettingsLive do
  use TrWeb, :live_view

  alias Tr.Accounts

  def render(assigns) do
    ~H"""
    <.header class="text-center  dark:invert">
      <%= gettext("Account Settings") %>
      <:subtitle><%= gettext("Manage your account email address and password settings") %></:subtitle>
    </.header>

    <div class="space-y-12 divide-y">
      <div>
        <.simple_form for={@display_name_form} id="display_name_form" phx-submit="update_display_name">
          <.input
            field={@email_form[:display_name]}
            type="text"
            label={gettext("Display Name")}
            value={@current_user.display_name}
            required
          />
          <:actions>
            <.button phx-disable-with="Changing..."><%= gettext("Change display name") %></.button>
          </:actions>
        </.simple_form>
      </div>
      <div>
        <.simple_form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <.input field={@email_form[:email]} type="email" label="Email" required />
          <.input
            field={@email_form[:current_password]}
            name="current_password"
            id="current_password_for_email"
            type="password"
            label="Current password"
            value={@email_form_current_password}
            required
          />
          <:actions>
            <.button phx-disable-with="Changing..."><%= gettext("Change Email") %></.button>
          </:actions>
        </.simple_form>
      </div>
      <div>
        <.simple_form
          for={@password_form}
          id="password_form"
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            field={@password_form[:email]}
            type="hidden"
            id="hidden_user_email"
            value={@current_email}
          />
          <.input field={@password_form[:password]} type="password" label="New password" required />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
          />
          <.input
            field={@password_form[:current_password]}
            name="current_password"
            type="password"
            label="Current password"
            id="current_password_for_password"
            value={@current_password}
            required
          />
          <:actions>
            <.button phx-disable-with="Changing..."><%= gettext("Change Password") %></.button>
          </:actions>
        </.simple_form>
      </div>
      <div>
        <.simple_form
          for={@accept_emails_form}
          id="accept_emails_form"
          phx-submit="update_accept_emails"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            field={@accept_emails_form[:accept_emails_toggle]}
            type="checkbox"
            label="Accept Emails"
            checked={@current_user.accept_emails}
          />
          <:actions>
            <.button phx-disable-with="Changing..."><%= gettext("Change Accept Emails") %></.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok ->
          put_flash(socket, :info, gettext("Email changed successfully."))

        :error ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/#{Gettext.get_locale(TrWeb.Gettext)}/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)
    accept_emails_changeset = Accounts.change_user_accept_emails(user)
    display_name_changeset = Accounts.change_user_display_name(user)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:accept_emails_form, to_form(accept_emails_changeset))
      |> assign(:display_name_form, to_form(display_name_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_display_name", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_display_name(user, user_params) do
      {:ok, applied_user} ->
        display_name_form =
          applied_user
          |> Accounts.change_user_display_name(params)
          |> to_form()

        info = gettext("Display name changed successfully.")

        {:noreply,
         socket
         |> assign(display_name_form: display_name_form)
         |> assign(current_user: applied_user)
         |> put_flash(:info, info)}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :display_name_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/#{Gettext.get_locale(TrWeb.Gettext)}/users/settings/confirm_email/#{&1}")
        )

        info = gettext("A link to confirm your email change has been sent to the new address.")
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  def handle_event("update_accept_emails", %{"user" => params}, socket) do
    %{"accept_emails_toggle" => accept_emails} = params

    user = socket.assigns.current_user

    case Accounts.update_user_accept_emails(user, %{"accept_emails" => accept_emails}) do
      {:ok, user} ->
        accept_emails_form =
          user
          |> Accounts.change_user_accept_emails(params)
          |> to_form()

        {:noreply,
         socket
         |> assign(trigger_submit: true, accept_emails_form: accept_emails_form)
         |> put_flash(:info, gettext("Accept emails changed successfully."))}

      {:error, changeset} ->
        {:noreply, assign(socket, accept_emails_form: to_form(changeset))}
    end
  end
end
