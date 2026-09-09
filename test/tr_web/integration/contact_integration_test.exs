defmodule TrWeb.Integration.ContactIntegrationTest do
  use TrWeb.FeatureCase, async: false
  use Wallaby.Feature

  import Wallaby.Query

  describe "Contact form" do
    test "is reachable from the about page and sends a message", %{session: session} do
      previous = Application.fetch_env!(:tr, :contact_min_fill_ms)
      Application.put_env(:tr, :contact_min_fill_ms, 0)
      on_exit(fn -> Application.put_env(:tr, :contact_min_fill_ms, previous) end)

      session
      |> visit("/en/about")
      |> click(link("contact form"))
      |> assert_has(css("h1", text: "Get in touch"))
      |> fill_in(css("#contact_form input[name='contact[name]']"), with: "Ada Lovelace")
      |> fill_in(css("#contact_form input[name='contact[email]']"), with: "ada@example.com")
      |> fill_in(css("#contact_form textarea[name='contact[message]']"),
        with: "Hello from the browser, I enjoyed the post about Kubernetes upgrades."
      )
      |> click(button("Send message"))
      |> assert_has(css("[role=alert]", text: "Your message has been sent", wait: 10_000))
    end

    test "shows validation errors for a malformed email", %{session: session} do
      session
      |> visit("/en/contact")
      |> fill_in(css("#contact_form input[name='contact[name]']"), with: "Ada Lovelace")
      |> fill_in(css("#contact_form input[name='contact[email]']"), with: "not-an-email")
      |> fill_in(css("#contact_form textarea[name='contact[message]']"),
        with: "Hello from the browser, this is long enough."
      )
      |> assert_has(css("#contact_form", text: "must have the @ sign and no spaces", wait: 5_000))
    end
  end
end
