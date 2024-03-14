defmodule Tr.PostFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tr.Post` context.
  """

  @doc """
  Generate a comment.
  """
  def comment_fixture(attrs \\ %{}) do
    {:ok, comment} =
      attrs
      |> Enum.into(%{
        body: "some body",
        parent_comment_id: 1,
        slug: "some-slug",
        source_ip: "1.1.1.1",
        user_id: 42
      })
      |> Tr.Post.create_comment()

    comment
  end
end
