defmodule Tr.PostTrackerTest do
  use Tr.DataCase

  alias Tr.PostTracker

  describe "PostTracker Schema" do
    test "changeset with valid attributes" do
      changeset = PostTracker.changeset(%PostTracker{}, %{slug: "new-post", announced: false})
      assert changeset.valid?
    end

    test "changeset with invalid attributes" do
      changeset = PostTracker.changeset(%PostTracker{}, %{})
      refute changeset.valid?
    end

    test "changeset with invalid slug" do
      changeset = PostTracker.changeset(%PostTracker{}, %{slug: "", announced: false})
      refute changeset.valid?
    end

    test "changeset with invalid announced" do
      changeset = PostTracker.changeset(%PostTracker{}, %{slug: "new-post", announced: nil})
      refute changeset.valid?
    end
  end
end
