defmodule Tr.Contact do
  @moduledoc """
  Contact form: validates a submission and forwards it by email to the site
  owner. The recipient address is read from `config :tr, :contact_email` at
  send time so it never has to live in the (public) source tree.
  """

  import Swoosh.Email

  alias Tr.Contact.Message
  alias Tr.Mailer

  @spec change_message(map()) :: Ecto.Changeset.t()
  def change_message(attrs \\ %{}), do: Message.changeset(%Message{}, attrs)

  @spec deliver_message(map()) ::
          {:ok, Swoosh.Email.t()} | {:error, Ecto.Changeset.t() | :not_configured | term()}
  def deliver_message(attrs) do
    changeset = change_message(attrs)

    with {:ok, message} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, recipient} <- recipient() do
      email =
        new()
        |> to(recipient)
        |> from({"segfault", "noreply@segfault.pw"})
        |> reply_to({message.name, message.email})
        |> subject("[segfault.pw] Contact form: #{message.name}")
        |> text_body(body(message))

      with {:ok, _metadata} <- Mailer.deliver(email) do
        {:ok, email}
      end
    end
  end

  defp recipient do
    case Application.get_env(:tr, :contact_email) do
      address when is_binary(address) and address != "" -> {:ok, address}
      _ -> {:error, :not_configured}
    end
  end

  defp body(%Message{} = message) do
    """
    New message from the contact form at segfault.pw

    Name:  #{message.name}
    Email: #{message.email}

    ------------------------------

    #{message.message}

    ------------------------------
    Reply to this email to answer the sender directly.
    """
  end
end
