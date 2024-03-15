defmodule Tr.PostTrackerFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tr.Post` context.
  """

  @doc """
  Generates a PostTracker entry
  """
  def post_tracker_fixture(attrs \\ %{}) do
    post =
      attrs
      |> Enum.into(%{
        slug: "some-body",
        announced: true
      })

    post
  end
end
