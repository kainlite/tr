defmodule TrWeb.MetamaskComponent do
  use Phoenix.LiveComponent
  import TrWeb.Gettext

  @impl true
  def render(assigns) do
    ~H"""
    <span title="Metamask" id="metamask-button" phx-hook="Metamask">
      <%= cond do %>
        <% @connected == true -> %>
          <button
            icon
            disabled
            color="success"
            variant="outline"
            class="inline-flex justify-center w200px float-right"
          >
            <icon icon="metamask" size="lg" />
            <%= gettext("Connected") %>
          </button>
        <% @connected == false -> %>
          <button
            icon
            color="white"
            variant="outline"
            class="inline-flex justify-center hover:bg-lblue-50 w200px float-right"
            id={@id}
            phx-click="connect-metamask"
          >
            <icon icon="metamask" size="lg" />
            <%= gettext("Connect") %>
          </button>
      <% end %>
    </span>
    """
  end

  @impl true
  def handle_event("account-check", params, socket) do
    {:noreply,
     socket
     |> assign(:connected, params["connected"])
     |> assign(:current_wallet_address, params["current_wallet_address"])}
  end

  @impl true
  def handle_event("get-current-wallet", _params, socket) do
    {:noreply, push_event(socket, "get-current-wallet", %{})}
  end

  @impl true
  def handle_event("verify-signature", params, socket) do
    # user = Accounts.verify_message_signature(params["current_wallet_address"])

    # if user do
    #   {:noreply, socket |> assign(:user, user) |> assign(:verify_signature, true)}
    # else
    #   {:noreply, put_flash(socket, :error, "Unable to verify wallet")}
    # end
  end

  @impl true
  def handle_event("connect-metamask", _params, socket) do
    {:noreply, push_event(socket, "connected", %{connected: true})}
  end

  @impl true
  def handle_event("wallet-connected", params, socket) do
    # {status, _user_struct_or_changeset} =
    #   Accounts.add_wallet_and_signature(socket.assigns.user_token, params)

    # connected = if status == :ok, do: true, else: false
    # {:noreply, assign(socket, :connected, connected)}
  end
end
