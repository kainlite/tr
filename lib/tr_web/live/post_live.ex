defmodule TrWeb.PostLive do
  use TrWeb, :live_view
  alias Tr.Blog

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign(socket, :params, params)}
  end

  @impl true
  def render(assigns) do
    ~L"""
      <% id = Map.get(@params, "id") %>
      <% post = Blog.get_post_by_id!(id) %>

      <%= link "← All posts", to: Routes.blog_path(@socket, :index)%>

      <h2><%= post.title %></h2>
      <h5>
        <time><%= post.date %></time> by <%= post.author %>
      </h5>

      <p>
        Tagged as <%= Enum.join(post.tags, ", ") %>
      </p>

      <%= raw post.body %>
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
