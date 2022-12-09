defmodule TrWeb.BlogLive do
  use TrWeb, :live_view
  alias Tr.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:posts, Blog.all_posts())}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <%= for post <- Blog.all_posts() do %>
      <div id="<%= post.id %>" style="margin-bottom: 3rem;">
      <h2>
        <%= link post.title, to: Routes.post_path(@socket, :show, post) %>
      </h2>

      <p>
        <time><%= post.date %></time> by <%= post.author %>
      </p>

      <p>
        Tagged as <%= Enum.join(post.tags, ", ") %>
      </p>

      <%= raw post.description %>
      </div>
    <% end %>
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
