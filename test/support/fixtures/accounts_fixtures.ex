defmodule Tr.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tr.Accounts` context.
  """
  alias Tr.Accounts

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello_world!"
  def valid_user_new_password, do: "hello_world123!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def valid_confirmed_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Tr.Accounts.register_user()

    user
  end

  def confirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} = attrs |> valid_confirmed_user_attributes() |> Tr.Accounts.register_user()

    extract_user_token(fn url ->
      Accounts.deliver_user_confirmation_instructions(user, url)
    end)
    |> Tr.Accounts.confirm_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
