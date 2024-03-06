defmodule TrWeb.DonationController do
  use TrWeb, :controller

  alias Tr.Donation

  def index(conn, _params) do
    render(conn, :index, posts: Donation.all())
  end
end
