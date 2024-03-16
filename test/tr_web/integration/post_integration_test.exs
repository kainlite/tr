defmodule TrWeb.Integration.PostIntegrationTest do
  use TrWeb.FeatureCase, async: false
  use Wallaby.Feature
  use Phoenix.VerifiedRoutes, router: TrWeb.Router, endpoint: TrWeb.Endpoint

  import Wallaby.Query

  import TrWeb.TestHelpers

  @send_button button("Send")

  describe "Blog articles" do
    test "has a big hero section", %{session: session} do
      session
      |> visit("/")
      |> find(css("section", count: 3))
      |> Enum.at(1)
      |> assert_has(css("h1", text: "Welcome to the laboratory"))
    end

    test "has some articles", %{session: session} do
      session
      |> visit("/blog")
      |> find(css("div #upgrading-k3s-with-system-upgrade-controller", count: 1))
      |> assert_has(css("h2", text: "Upgrading K3S with system-upgrade-controller"))
    end

    def message(msg), do: css("li", text: msg)

    @sessions 2
    feature "That users can send messages to each other", %{sessions: [user1, user2]} do
      page = ~p"/blog/upgrading-k3s-with-system-upgrade-controller"

      user1
      |> log_in()

      user1
      |> visit(page)

      user1
      |> fill_in(Query.text_field("Message"), with: "Hello user2!")

      user1
      |> click(@send_button)

      user2
      |> log_in()

      user2
      |> visit(page)

      user2
      |> click(Query.link("Reply"))

      user2
      |> fill_in(Query.text_field("Message"), with: "Hello user1!")

      user2
      |> click(@send_button)

      user1
      |> assert_has(message("Hello user1!"))
      |> assert_has(css("p", text: "Online: 2"))

      user2
      |> assert_has(message("Hello user2!"))
      |> assert_has(css("p", text: "Online: 2"))
    end
  end
end
