defmodule Tr.PostFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tr.Post` context.
  """
  import Tr.AccountsFixtures

  @doc """
  Generate a comment.
  """
  def comment_fixture(attrs \\ %{}) do
    user = confirmed_user_fixture()

    {:ok, comment} =
      attrs
      |> Enum.into(%{
        body: "some body",
        parent_comment_id: 1,
        slug: "some-slug",
        user_id: user.id
      })
      |> Tr.Post.create_comment()

    comment
  end
end
