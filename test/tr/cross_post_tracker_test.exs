defmodule Tr.CrossPostTrackerTest do
  use Tr.DataCase

  alias Tr.CrossPostTracker

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = CrossPostTracker.changeset(%CrossPostTracker{}, %{slug: "test-post"})
      assert changeset.valid?
    end

    test "invalid changeset without slug" do
      changeset = CrossPostTracker.changeset(%CrossPostTracker{}, %{})
      refute changeset.valid?
      assert %{slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset with all fields" do
      attrs = %{
        slug: "test-post",
        linkedin_posted: true,
        linkedin_post_id: "urn:li:share:123",
        linkedin_posted_at: ~U[2026-02-28 12:00:00Z],
        substack_drafted: true,
        substack_post_url: "https://example.substack.com/publish/post/123",
        substack_drafted_at: ~U[2026-02-28 12:00:00Z]
      }

      changeset = CrossPostTracker.changeset(%CrossPostTracker{}, attrs)
      assert changeset.valid?
    end

    test "unique constraint on slug" do
      {:ok, _} =
        %CrossPostTracker{}
        |> CrossPostTracker.changeset(%{slug: "unique-slug-test"})
        |> Tr.Repo.insert()

      {:error, changeset} =
        %CrossPostTracker{}
        |> CrossPostTracker.changeset(%{slug: "unique-slug-test"})
        |> Tr.Repo.insert()

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
