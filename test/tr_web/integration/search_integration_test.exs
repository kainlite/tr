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
      |> fill_in(css("#search_form input"), with: "kubernetes")
      |> assert_has(Query.css("div.flex h2.text-4xl a", minimum: 1, wait: 5_000))
    end
  end
end
