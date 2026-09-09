defmodule Tr.ContactTest do
  use ExUnit.Case, async: false

  import Swoosh.TestAssertions

  alias Tr.Contact

  @valid %{
    "name" => "Ada Lovelace",
    "email" => "ada@example.com",
    "message" => "Hello, I enjoyed the post about Kubernetes upgrades."
  }

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "change_message/1" do
    test "is valid with a name, a well formed email and a message" do
      changeset = Contact.change_message(@valid)

      assert changeset.valid?
    end

    test "requires every field" do
      changeset = Contact.change_message(%{})

      assert %{name: ["can't be blank"], email: ["can't be blank"], message: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "rejects a malformed email" do
      changeset = Contact.change_message(%{@valid | "email" => "not-an-email"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "rejects a name that is too short or too long" do
      short = Contact.change_message(%{@valid | "name" => "A"})
      long = Contact.change_message(%{@valid | "name" => String.duplicate("a", 101)})

      assert %{name: ["should be at least 2 character(s)"]} = errors_on(short)
      assert %{name: ["should be at most 100 character(s)"]} = errors_on(long)
    end

    test "rejects a message that is too short or too long" do
      short = Contact.change_message(%{@valid | "message" => "hi"})
      long = Contact.change_message(%{@valid | "message" => String.duplicate("a", 5001)})

      assert %{message: ["should be at least 10 character(s)"]} = errors_on(short)
      assert %{message: ["should be at most 5000 character(s)"]} = errors_on(long)
    end
  end

  describe "deliver_message/1" do
    test "sends the message to the configured recipient with reply-to set to the sender" do
      assert {:ok, email} = Contact.deliver_message(@valid)

      assert email.to == [{"", "contact@example.com"}]
      assert email.from == {"segfault", "noreply@segfault.pw"}
      assert email.reply_to == {"Ada Lovelace", "ada@example.com"}
      assert email.subject =~ "Ada Lovelace"
      assert email.text_body =~ "I enjoyed the post about Kubernetes upgrades"
      assert email.text_body =~ "ada@example.com"

      assert_email_sent(email)
    end

    test "returns the invalid changeset and sends nothing when validation fails" do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Contact.deliver_message(%{@valid | "email" => "nope"})

      assert_no_email_sent()
    end

    test "fails closed when no recipient is configured" do
      previous = Application.fetch_env!(:tr, :contact_email)
      Application.delete_env(:tr, :contact_email)
      on_exit(fn -> Application.put_env(:tr, :contact_email, previous) end)

      assert {:error, :not_configured} = Contact.deliver_message(@valid)
      assert_no_email_sent()
    end
  end
end
