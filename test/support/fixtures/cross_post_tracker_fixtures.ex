defmodule Tr.CrossPostTrackerFixtures do
  @moduledoc """
  Test helpers for creating CrossPostTracker entities.
  """

  def cross_post_tracker_fixture(attrs \\ %{}) do
    attrs
    |> Enum.into(%{
      slug: "some-cross-post-slug",
      linkedin_posted: false,
      substack_drafted: false
    })
  end
end
