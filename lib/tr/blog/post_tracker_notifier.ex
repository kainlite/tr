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
  def deliver_new_post_notification(user, subject, body, url) do
    deliver(user.email, subject, """

    ==============================

    Hi #{user.email},

    A new article was just added:

    #{Earmark.as_html!(body)}

    To read the full post or the blog go to: 
    #{url}

    You can disable this notification at any time from your settings page.

    ==============================
    """)
  end

  def deliver_new_comment_notification(user, subject, body, url) do
    deliver(user.email, subject, """

    ==============================

    Hi #{user.email},

    A new comment was just added to a post you are following:

    #{Earmark.as_html!(body)}

    To read the full post or the blog go to: 
    #{url}

    You can disable this notification at any time from your settings page.

    ==============================
    """)
  end
end
