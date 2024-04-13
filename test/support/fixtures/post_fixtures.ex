defmodule Tr.PostFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tr.Post` context.
  """
  import Tr.AccountsFixtures

  @doc """
  Generate a post.
  """
  def post_fixture(attrs \\ %{}) do
    post =
      attrs
      |> Enum.into(%{
        id: "some-slug",
        title: "some title",
        body: "some body",
        tags: ["elixir", "phoenix"],
        published: true,
        author: "some author",
        description: "some description",
        date: ~D[2020-01-01],
        image: "terraform.png"
      })

    post
  end

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
        user_id: user.id,
        image: "terraform.png"
      })
      |> Tr.Post.create_comment()

    comment
  end
end
