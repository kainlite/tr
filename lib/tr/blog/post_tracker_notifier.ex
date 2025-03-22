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
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>New Article on segfault.pw</title>
    </head>
    <body style="font-family: 'Courier New', monospace; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f9f9f9;">
      <div style="background-color: #ffffff; border: 1px solid #ddd; border-radius: 5px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.05);">
        <!-- Header -->
        <div style="border-bottom: 2px solid #dc3545; padding-bottom: 15px; margin-bottom: 20px;">
          <a href="https://segfault.pw" style="font-size: 28px; font-weight: bold; color: #dc3545; text-decoration: none;">segfault.pw</a>
          <div style="display: block; margin-bottom: 5px;">
            <span style="color: #dc3545; font-weight: bold;">$ </span>cat new_article.md
          </div>
        </div>
        
        <p>Hello #{user.email},</p>
        
        <p>A new article has been published on <strong>segfault.pw</strong>:</p>
        
        <!-- Article Preview -->
        <div style="background-color: #f7f7f7; border-left: 3px solid #dc3545; padding: 15px; margin: 20px 0;">
          #{Earmark.as_html!(body)}
        </div>
        
        <!-- CTA Button -->
        <table cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td align="left" style="padding: 15px 0;">
              <a href="#{url}" style="background-color: #dc3545; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; font-weight: bold; display: inline-block;">Read Full Article</a>
            </td>
          </tr>
        </table>
        
        <!-- Footer -->
        <div style="margin-top: 30px; font-size: 12px; color: #777; text-align: center; border-top: 1px solid #ddd; padding-top: 15px;">
          <p>You're receiving this because you subscribed to updates from segfault.pw</p>
          <p>You can <a href="https://segfault.pw/settings" style="color: #555; text-decoration: underline;">unsubscribe</a> at any time from your settings page.</p>
          <p>&copy; segfault.pw | <span style="font-family: 'Courier New', monospace; background-color: #f0f0f0; padding: 2px 4px; border-radius: 3px;">root@segfault:~#</span></p>
        </div>
      </div>
    </body>
    </html>
    """)
  end

  def deliver_new_comment_notification(user, body, url) do
    deliver(user.email, "You have a new message in #{url}", """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>New comment on segfault.pw</title>
    </head>
    <body style="font-family: 'Courier New', monospace; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f9f9f9;">
      <div style="background-color: #ffffff; border: 1px solid #ddd; border-radius: 5px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.05);">
        <!-- Header -->
        <div style="border-bottom: 2px solid #dc3545; padding-bottom: 15px; margin-bottom: 20px;">
          <a href="https://segfault.pw" style="font-size: 28px; font-weight: bold; color: #dc3545; text-decoration: none;">segfault.pw</a>
          <div style="display: block; margin-bottom: 5px;">
            <span style="color: #dc3545; font-weight: bold;">$ </span>cat new_article.md
          </div>
        </div>
        
        <p>Hello #{user.email},</p>
        
        <p>A new comment was just added to a post you are following:</p>
        
        <div style="background-color: #f7f7f7; border-left: 3px solid #dc3545; padding: 15px; margin: 20px 0;">
          #{Earmark.as_html!(body)}
        </div>
        
        <table cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td align="left" style="padding: 15px 0;">
              <a href="#{url}" style="background-color: #dc3545; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; font-weight: bold; display: inline-block;">Read comment</a>
            </td>
          </tr>
        </table>
        
        <!-- Footer -->
        <div style="margin-top: 30px; font-size: 12px; color: #777; text-align: center; border-top: 1px solid #ddd; padding-top: 15px;">
          <p>You're receiving this because you subscribed to updates from segfault.pw</p>
          <p>You can <a href="https://segfault.pw/settings" style="color: #555; text-decoration: underline;">unsubscribe</a> at any time from your settings page.</p>
          <p>&copy; segfault.pw | <span style="font-family: 'Courier New', monospace; background-color: #f0f0f0; padding: 2px 4px; border-radius: 3px;">root@segfault:~#</span></p>
        </div>
      </div>
    </body>
    </html>
    """)
  end

  def deliver_new_reply_notification(user, body, url) do
    deliver(user.email, "You have a new reply in #{url}", """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>New reply on segfault.pw</title>
    </head>
    <body style="font-family: 'Courier New', monospace; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f9f9f9;">
      <div style="background-color: #ffffff; border: 1px solid #ddd; border-radius: 5px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.05);">
        <!-- Header -->
        <div style="border-bottom: 2px solid #dc3545; padding-bottom: 15px; margin-bottom: 20px;">
          <a href="https://segfault.pw" style="font-size: 28px; font-weight: bold; color: #dc3545; text-decoration: none;">segfault.pw</a>
          <div style="display: block; margin-bottom: 5px;">
            <span style="color: #dc3545; font-weight: bold;">$ </span>cat new_article.md
          </div>
        </div>
        
        <p>Hello #{user.email},</p>
        
        <p>A new reply was just added to a comment you are following:</p>
        
        <div style="background-color: #f7f7f7; border-left: 3px solid #dc3545; padding: 15px; margin: 20px 0;">
          #{Earmark.as_html!(body)}
        </div>
        
        <table cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td align="left" style="padding: 15px 0;">
              <a href="#{url}" style="background-color: #dc3545; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; font-weight: bold; display: inline-block;">Read comment</a>
            </td>
          </tr>
        </table>
        
        <!-- Footer -->
        <div style="margin-top: 30px; font-size: 12px; color: #777; text-align: center; border-top: 1px solid #ddd; padding-top: 15px;">
          <p>You're receiving this because you subscribed to updates from segfault.pw</p>
          <p>You can <a href="https://segfault.pw/settings" style="color: #555; text-decoration: underline;">unsubscribe</a> at any time from your settings page.</p>
          <p>&copy; segfault.pw | <span style="font-family: 'Courier New', monospace; background-color: #f0f0f0; padding: 2px 4px; border-radius: 3px;">root@segfault:~#</span></p>
        </div>
      </div>
    </body>
    </html>
    """)
  end
end
