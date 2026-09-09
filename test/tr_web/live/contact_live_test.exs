defmodule TrWeb.ContactLiveTest do
  use TrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Tr.RateLimiter

  @valid %{
    "name" => "Ada Lovelace",
    "email" => "ada@example.com",
    "message" => "Hello, I enjoyed the post about Kubernetes upgrades."
  }

  defp unique_ip, do: "203.0.113.#{System.unique_integer([:positive]) |> rem(250) |> Kernel.+(1)}"

  defp from_ip(conn, ip), do: put_req_header(conn, "cf-connecting-ip", ip)

  defp submit(lv, attrs) do
    lv
    |> form("#contact_form", contact: attrs)
    |> render_submit()
  end

  defp override_env(key, value) do
    previous = Application.fetch_env!(:tr, key)
    Application.put_env(:tr, key, value)
    on_exit(fn -> Application.put_env(:tr, key, previous) end)
  end

  setup do
    RateLimiter.reset(:contact_global)
    :ok
  end

  describe "rendering" do
    test "renders the contact form in English", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/contact")

      assert html =~ "Get in touch"
      assert has_element?(lv, "#contact_form input[name='contact[name]']")
      assert has_element?(lv, "#contact_form input[name='contact[email]']")
      assert has_element?(lv, "#contact_form textarea[name='contact[message]']")
      refute html =~ "mailto:"
    end

    test "renders the contact form in Spanish", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/es/contact")

      assert html =~ "Contacto"
      assert html =~ "Enviar mensaje"
    end

    test "keeps the honeypot field out of sight of humans", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/contact")

      assert has_element?(
               lv,
               "#contact_form input[name='contact[extra]'][tabindex='-1'][autocomplete='off']"
             )
    end
  end

  describe "validation" do
    test "shows errors on change without sending anything", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/contact")

      html =
        lv
        |> form("#contact_form", contact: %{@valid | "email" => "nope"})
        |> render_change()

      assert html =~ "must have the @ sign and no spaces"
      assert_no_email_sent()
    end

    test "shows errors on submit without sending anything", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/contact")

      html = submit(lv, %{"name" => "", "email" => "", "message" => ""})

      assert html =~ "can&#39;t be blank"
      assert_no_email_sent()
    end
  end

  describe "submission" do
    test "sends the email and confirms to the visitor", %{conn: conn} do
      {:ok, lv, _html} = live(conn |> from_ip(unique_ip()), ~p"/contact")

      html = submit(lv, @valid)

      assert html =~ "Your message has been sent"

      assert_email_sent(fn email ->
        assert email.to == [{"", "contact@example.com"}]
        assert email.reply_to == {"Ada Lovelace", "ada@example.com"}
        assert email.text_body =~ "I enjoyed the post about Kubernetes upgrades"
      end)

      assert has_element?(lv, "#contact_form textarea[name='contact[message]']", "")
      refute render(lv) =~ "I enjoyed the post"
    end

    test "silently drops submissions that fill the honeypot", %{conn: conn} do
      {:ok, lv, _html} = live(conn |> from_ip(unique_ip()), ~p"/contact")

      html = submit(lv, Map.put(@valid, "extra", "https://spam.example"))

      assert html =~ "Your message has been sent"
      assert_no_email_sent()
    end

    test "silently drops submissions that arrive too fast after mount", %{conn: conn} do
      override_env(:contact_min_fill_ms, :timer.minutes(1))
      {:ok, lv, _html} = live(conn |> from_ip(unique_ip()), ~p"/contact")

      html = submit(lv, @valid)

      assert html =~ "Your message has been sent"
      assert_no_email_sent()
    end

    test "limits messages per client address", %{conn: conn} do
      override_env(:contact_rate_limit, per_ip: 2, global: 100)
      ip = unique_ip()

      for _ <- 1..2 do
        {:ok, lv, _html} = live(conn |> from_ip(ip), ~p"/contact")
        assert submit(lv, @valid) =~ "Your message has been sent"
      end

      assert_email_sent()
      assert_email_sent()

      {:ok, lv, _html} = live(conn |> from_ip(ip), ~p"/contact")
      html = submit(lv, @valid)

      assert html =~ "Too many messages"
      assert_no_email_sent()

      {:ok, lv, _html} = live(conn |> from_ip(unique_ip()), ~p"/contact")
      assert submit(lv, @valid) =~ "Your message has been sent"
      assert_email_sent()
    end

    test "limits messages globally across all addresses", %{conn: conn} do
      override_env(:contact_rate_limit, per_ip: 100, global: 1)

      {:ok, lv, _html} = live(conn |> from_ip(unique_ip()), ~p"/contact")
      assert submit(lv, @valid) =~ "Your message has been sent"
      assert_email_sent()

      {:ok, lv, _html} = live(conn |> from_ip(unique_ip()), ~p"/contact")
      assert submit(lv, @valid) =~ "Too many messages"
      assert_no_email_sent()
    end

    test "tells the visitor when delivery is not possible", %{conn: conn} do
      override_env(:contact_email, nil)
      {:ok, lv, _html} = live(conn |> from_ip(unique_ip()), ~p"/contact")

      html = submit(lv, @valid)

      assert html =~ "could not be sent"
      assert_no_email_sent()
    end
  end
end
