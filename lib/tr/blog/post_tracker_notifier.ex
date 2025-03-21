defmodule Tr.PostTracker.Notifier do
  @moduledoc """
    Email notifier for posts and comments
  """
  import Swoosh.Email

  alias Tr.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"segfault", "noreply@segfault.pw"})
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
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>New Article on segfault.pw</title>
    <style>
    body {
      font-family: 'Courier New', monospace;
      line-height: 1.6;
      color: #333;
      max-width: 600px;
      margin: 0 auto;
      padding: 20px;
      background-color: #f9f9f9;
    }
    .container {
      background-color: #ffffff;
      border: 1px solid #ddd;
      border-radius: 5px;
      padding: 20px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.05);
    }
    .header {
      border-bottom: 2px solid #dc3545;
      padding-bottom: 15px;
      margin-bottom: 20px;
    }
    .logo {
      font-size: 28px;
      font-weight: bold;
      color: #dc3545;
      text-decoration: none;
    }
    .terminal-line {
      display: block;
      margin-bottom: 5px;
    }
    .terminal-prompt::before {
      content: "$ ";
      color: #dc3545;
      font-weight: bold;
    }
    .article-preview {
      background-color: #f7f7f7;
      border-left: 3px solid #dc3545;
      padding: 15px;
      margin: 20px 0;
    }
    .btn {
      display: inline-block;
      background-color: #dc3545;
      color: white;
      padding: 10px 20px;
      text-decoration: none;
      border-radius: 4px;
      margin-top: 15px;
      font-weight: bold;
    }
    .btn:hover {
      background-color: #c82333;
    }
    .footer {
      margin-top: 30px;
      font-size: 12px;
      color: #777;
      text-align: center;
      border-top: 1px solid #ddd;
      padding-top: 15px;
    }
    .footer a {
      color: #555;
      text-decoration: underline;
    }
    code {
      font-family: 'Courier New', monospace;
      background-color: #f0f0f0;
      padding: 2px 4px;
      border-radius: 3px;
    }
    </style>
    </head>
    <body>
    <div class="container">
    <div class="header">
      <a href="https://segfault.pw" class="logo">segfault.pw</a>
      <span class="terminal-line terminal-prompt">cat new_article.md</span>
    </div>

    <p>Hello #{user.email},</p>

    <p>A new article has been published on <strong>segfault.pw</strong>:</p>

    <div class="article-preview">
      #{Earmark.as_html!(body)}
    </div>

    <a href="#{url}" class="btn">Read Full Article</a>

    <div class="footer">
      <p>You're receiving this because you subscribed to updates from segfault.pw</p>
      <p>You can <a href="https://segfault.pw/settings">unsubscribe</a> at any time from your settings page.</p>
      <p>&copy; segfault.pw | <code>root@segfault:~#</code></p>
    </div>
    </div>
    </body>
    </html>
    """)
  end

  def deliver_new_comment_notification(user, body, url) do
    deliver(user.email, "You have a new message in #{url}", """

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

  def deliver_new_reply_notification(user, body, url) do
    deliver(user.email, "You have a new reply in #{url}", """
    ==============================
    Hi #{user.email},

    A new reply was just added to a comment you are following:

    #{Earmark.as_html!(body)}

    To read the full post or the blog go to: 
    #{url}

    You can disable this notification at any time from your settings page.
    ==============================
    """)
  end
end
