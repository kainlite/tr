defmodule TrWeb.Integration.PostIntegrationTest do
  use TrWeb.FeatureCase, async: false
  use Wallaby.Feature
  use Phoenix.VerifiedRoutes, router: TrWeb.Router, endpoint: TrWeb.Endpoint

  import Wallaby.Query

  import TrWeb.TestHelpers
  import Tr.AccountsFixtures

  @send_button button("Send")

  describe "Blog articles" do
    setup %{} do
      password = valid_user_password()
      admin_user_fixture(%{password: password})

      :ok
    end

    test "has a big hero section", %{session: session} do
      post = Tr.Blog.get_latest_post("en", 1)

      session
      |> visit("/en/blog")
      |> find(css("div ##{Map.get(post, :id)}", count: 1))
      |> assert_has(css("h2 a", text: post.title))
    end

    test "has some articles", %{session: session} do
      session
      |> visit("/blog")
      |> find(css("div #upgrading-k3s-with-system-upgrade-controller", count: 1))
      |> assert_has(css("h2", text: "Upgrading K3S with system-upgrade-controller"))
    end

    def message(msg), do: css("li", text: msg)

    @sessions 3
    feature "That users can send messages to each other", %{sessions: [user1, user2, user3]} do
      page = ~p"/blog/upgrading-k3s-with-system-upgrade-controller"

      log_in({:normal, user1})

      user1
      |> visit(page)

      user1
      |> fill_in(Query.text_field("Message"), with: "Hello user2!")

      user1
      |> click(@send_button)

      log_in({:normal, user2})

      user2
      |> visit(page)

      user2
      |> click(Query.link("Reply"))

      user2
      |> fill_in(Query.text_field("Message"), with: "Hello user1!")

      user2
      |> click(@send_button)

      user3
      |> visit(page)

      user1
      |> assert_has(Query.css("li", text: "Comment hidden, awaiting moderation...", count: 2))
      |> assert_has(css("p", text: "Online: 3"))

      comments = Tr.Post.get_unapproved_comments()

      for coment <- comments do
        Tr.Post.approve_comment(coment)
      end

      user2
      |> visit(page)
      |> assert_has(message("Hello user2!"))
      |> assert_has(css("p", text: "Online: 3"))

      user3
      |> visit(page)
      |> assert_has(message("Hello user1!"))
      |> assert_has(message("Hello user2!"))
      |> assert_has(css("p", text: "Please sign in to be able to write comments"))
      |> assert_has(css("p", text: "Online: 3"))
    end

    test "an user can react to a post", %{session: session} do
      page = ~p"/blog/upgrading-k3s-with-system-upgrade-controller"

      log_in({:normal, session})

      session
      |> visit(page)
      |> click(link("hero-heart-link"))
      |> assert_has(css(".float-right span.font-semibold", text: "1"))
    end

    test "an user can remove their reaction to a post", %{session: session} do
      page = ~p"/blog/upgrading-k3s-with-system-upgrade-controller"

      log_in({:normal, session})

      session
      |> visit(page)
      |> click(link("hero-heart-link"))
      |> assert_has(css(".float-right span.font-semibold", text: "1"))
      |> click(link("hero-heart-link"))
      |> assert_has(css(".float-right span.font-semibold", text: "0", count: 3))
    end
  end
end
