defmodule Tr.PostTracker.Notifier do
  import Swoosh.Email

  alias Tr.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"TechSquad Blog", "noreply@tr.techsquad.rocks"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_new_post_notification(email, subject, body, url) do
    deliver(email, subject, """

    ==============================

    Hi #{email},

    A new article was just added:

    > #{body}

    To read the full post go to: #{url}

    You can disable this notification at any time from your settings page.

    ==============================
    """)
  end
end
