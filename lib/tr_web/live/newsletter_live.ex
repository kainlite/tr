defmodule TrWeb.NewsletterLive do
  use TrWeb, :live_view
  
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:subscribers, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="margin-bottom: 3rem;">
      No one 
    </div>
    """
  end
end
