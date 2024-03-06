defmodule TrWeb.DonationLive do
  use TrWeb, :live_view
  alias Tr.Donation

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:posts, Donation.all())}
  end

  @impl true
  def render(assigns) do
    ~H"""
      Donation lala
    """
  end
end
