defmodule TrWeb.ContactLive do
  use TrWeb, :live_view

  alias Tr.Contact
  alias Tr.RateLimiter

  require Logger

  @window :timer.hours(1)

  @doc """
  Session builder used by the router's `live_session`. Carries the client
  address resolved by `RemoteIp` on the HTTP request into the LiveView.
  """
  @spec session(Plug.Conn.t()) :: map()
  def session(conn), do: %{"remote_ip" => conn.remote_ip |> :inet.ntoa() |> to_string()}

  @impl true
  def mount(_params, session, socket) do
    locale = Gettext.get_locale(TrWeb.Gettext)

    {:ok,
     socket
     |> assign(:page_title, "SegFault - Contact")
     |> assign(:og_url, TrWeb.Endpoint.url() <> "/#{locale}/contact")
     |> assign(:og_hreflang_en, TrWeb.Endpoint.url() <> "/en/contact")
     |> assign(:og_hreflang_es, TrWeb.Endpoint.url() <> "/es/contact")
     |> assign(:remote_ip, Map.get(session, "remote_ip", "unknown"))
     |> assign(:mounted_at, System.monotonic_time(:millisecond))
     |> assign_form(Contact.change_message())}
  end

  @impl true
  def handle_event("validate", %{"contact" => params}, socket) do
    changeset = params |> Contact.change_message() |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("submit", %{"contact" => params}, socket) do
    cond do
      bot?(params, socket) ->
        Logger.info("contact form: dropped bot submission from #{socket.assigns.remote_ip}")
        {:noreply, sent(socket)}

      rate_limited?(socket.assigns.remote_ip) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Too many messages from your network, please try again in an hour.")
         )}

      true ->
        deliver(socket, params)
    end
  end

  defp deliver(socket, params) do
    case Contact.deliver_message(params) do
      {:ok, _email} ->
        {:noreply, sent(socket)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, reason} ->
        Logger.error("contact form: delivery failed: #{inspect(reason)}")

        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Your message could not be sent right now, please try again later.")
         )}
    end
  end

  defp sent(socket) do
    socket
    |> put_flash(:info, gettext("Thank you! Your message has been sent."))
    |> assign_form(Contact.change_message())
  end

  # A filled honeypot or a submission faster than a human could type both mark
  # a bot; those get the same success response so scripts learn nothing.
  defp bot?(params, socket) do
    honeypot_filled? = String.trim(Map.get(params, "extra", "")) != ""
    elapsed = System.monotonic_time(:millisecond) - socket.assigns.mounted_at

    honeypot_filled? or elapsed < Application.fetch_env!(:tr, :contact_min_fill_ms)
  end

  defp rate_limited?(remote_ip) do
    limits = Application.fetch_env!(:tr, :contact_rate_limit)

    with :ok <- RateLimiter.check({:contact, remote_ip}, limits[:per_ip], @window),
         :ok <- RateLimiter.check(:contact_global, limits[:global], @window) do
      false
    else
      {:error, :rate_limited} ->
        Logger.warning("contact form: rate limited #{remote_ip}")
        true
    end
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "contact"))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="font-mono text-accent-light dark:text-accent mb-6">$ mail -s "hello" segfault</div>
      <.header>
        {gettext("Get in touch")}
        <:subtitle>
          {gettext(
            "Questions, corrections, or just want to say hi? Fill in the form and it lands in my inbox. I answer every real message, usually within a few days."
          )}
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="contact_form"
        phx-change="validate"
        phx-submit="submit"
        autocomplete="on"
      >
        <.input field={@form[:name]} type="text" label={gettext("Name")} required maxlength="100" />
        <.input field={@form[:email]} type="email" label={gettext("Email")} required maxlength="160" />
        <.input
          field={@form[:message]}
          type="textarea"
          label={gettext("Message")}
          required
          rows="8"
          maxlength="5000"
        />
        <div class="absolute -left-[9999px] top-auto w-px h-px overflow-hidden" aria-hidden="true">
          <label for="contact_extra">Leave this field empty</label>
          <input
            type="text"
            id="contact_extra"
            name="contact[extra]"
            value=""
            tabindex="-1"
            autocomplete="off"
          />
        </div>
        <:actions>
          <.button phx-disable-with={gettext("Sending...")} class="w-full">
            {gettext("Send message")}
          </.button>
        </:actions>
      </.simple_form>

      <p class="mt-8 text-sm text-zinc-500 dark:text-zinc-400">
        <span>{gettext("You can also find me on")}</span>
        <a
          href="https://github.com/kainlite"
          class="text-accent-light dark:text-accent hover:text-accent-dim dark:hover:text-accent-muted"
        >
          GitHub
        </a>
        <span>,</span>
        <a
          href="https://www.linkedin.com/in/gabrielgarrido/"
          class="text-accent-light dark:text-accent hover:text-accent-dim dark:hover:text-accent-muted"
        >
          LinkedIn
        </a>
        <span>{gettext("and")}</span>
        <a
          href="https://twitter.com/kainlite"
          class="text-accent-light dark:text-accent hover:text-accent-dim dark:hover:text-accent-muted"
        >
          Twitter
        </a>
        <span>.</span>
      </p>
    </div>
    """
  end
end
