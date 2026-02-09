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

    test "unique constraint on slug" do
      attrs = %{slug: "unique-constraint-test", announced: false}

      assert {:ok, _} =
               %PostTracker{}
               |> PostTracker.changeset(attrs)
               |> Tr.Repo.insert()

      assert {:error, changeset} =
               %PostTracker{}
               |> PostTracker.changeset(attrs)
               |> Tr.Repo.insert()

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "default announced is false" do
      changeset = PostTracker.changeset(%PostTracker{}, %{slug: "default-test", announced: false})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :announced) == false
    end
  end
end
