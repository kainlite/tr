defmodule TrWeb.MetamaskLive do
  use TrWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    IO.inspect(params)

    if id = Map.get(params, :id) do
      {:ok,
       socket
       |> assign_new(:connected, fn -> false end)
       |> assign_new(:current_wallet_address, fn -> nil end)
       |> assign_new(:signed, fn -> false end)
       |> assign_new(:verify_signature, fn -> false end)}
    end

  end

  @impl true
  def render(assigns) do
    ~L"""
    <span title="Metamask" id="metamask-button" phx-hook="Metamask">
      <%= cond do %>
        <% @connected  == "metamask-connect" -> %>
          <.button
            icon
            disabled
            color="success"
            variant="outline"
            class="w-full inline-flex justify-center py-2 px-4"
          >
            <.icon icon="metamask" size="lg" />
            <%= gettext("Metamask Connected!") %>
          </.button>
        <% not @connected == "metamask-connect" -> %>
          <.button
            icon
            color="white"
            variant="outline"
            class="w-full inline-flex justify-center py-2 px-4 !border-gray-300 !text-gray-500 hover:bg-gray-50"
            id={@id}
            phx-click="connect-metamask"
          >
            <.icon icon="metamask" size="lg" />
            <%= @text %>
          </.button>
        <% true -> %>
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
    # {:noreply, push_event(socket, "connect-metamask", %{id: socket.assigns.id})}
  end

  @impl true
  def handle_event("wallet-connected", params, socket) do
    # {status, _user_struct_or_changeset} =
    #   Accounts.add_wallet_and_signature(socket.assigns.user_token, params)

    # connected = if status == :ok, do: true, else: false
    # {:noreply, assign(socket, :connected, connected)}
  end
end
