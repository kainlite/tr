defmodule TrWeb.Integration.SearchIntegrationTest do
  use TrWeb.FeatureCase, async: false
  use Wallaby.Feature
  use Phoenix.VerifiedRoutes, router: TrWeb.Router, endpoint: TrWeb.Endpoint

  import Wallaby.Query

  describe "Search page" do
    setup do
      # We need to give the search index some time to be ready as it is populating an ETS table
      assert :ok = Tr.Search.await_ready()
      :ok
    end

    test "has a big search input", %{session: session} do
      session
      |> visit("/blog/search")
      |> assert_has(css("#search_form input"))
    end

    test "can search some articles", %{session: session} do
      session
      |> visit("/blog/search")
      |> fill_in(css("#search_form input"), with: "linux")
      |> assert_has(Query.css("a", minimum: 4))
      |> assert_has(Query.css("div h2 a", text: "What exactly is a container?", count: 1))
    end
  end
end
