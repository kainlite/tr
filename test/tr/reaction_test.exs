defmodule Tr.ReactionTest do
  use Tr.DataCase

  alias Tr.Post
  alias Tr.Post.Reaction

  import Tr.PostFixtures
  import Tr.AccountsFixtures

  describe "Reaction changeset" do
    test "valid changeset with required fields" do
      changeset =
        Reaction.changeset(%Reaction{}, %{value: "heart", slug: "test-slug", user_id: 1})

      assert changeset.valid?
    end

    test "validates required fields" do
      changeset = Reaction.changeset(%Reaction{}, %{})
      refute changeset.valid?

      assert %{value: ["can't be blank"], slug: ["can't be blank"], user_id: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "validates inclusion of value" do
      for valid_value <- ["rocket-launch", "hand-thumb-up", "heart"] do
        changeset =
          Reaction.changeset(%Reaction{}, %{value: valid_value, slug: "test", user_id: 1})

        assert changeset.valid?, "Expected #{valid_value} to be valid"
      end
    end

    test "rejects invalid reaction values" do
      changeset = Reaction.changeset(%Reaction{}, %{value: "invalid", slug: "test", user_id: 1})
      refute changeset.valid?
      assert %{value: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "Reaction CRUD" do
    test "create_reaction/1 with valid attrs" do
      user = confirmed_user_fixture()

      assert {:ok, %Reaction{} = reaction} =
               Post.create_reaction(%{value: "heart", slug: "test-slug", user_id: user.id})

      assert reaction.value == "heart"
      assert reaction.slug == "test-slug"
      assert reaction.user_id == user.id
    end

    test "create_reaction/1 with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Post.create_reaction(%{value: "invalid"})
    end

    test "delete_reaction/1 deletes a reaction" do
      reaction = reaction_fixture()
      assert {:ok, %Reaction{}} = Post.delete_reaction(reaction)
    end

    test "get_reaction/3 returns the reaction" do
      reaction = reaction_fixture()
      found = Post.get_reaction(reaction.slug, reaction.value, reaction.user_id)
      assert found.id == reaction.id
    end

    test "get_reaction/3 returns nil when not found" do
      assert is_nil(Post.get_reaction("nonexistent", "heart", 0))
    end

    test "reaction_exists?/3 returns true for existing reaction" do
      reaction = reaction_fixture()
      assert Post.reaction_exists?(reaction.slug, reaction.value, reaction.user_id)
    end

    test "reaction_exists?/3 returns false when not found" do
      refute Post.reaction_exists?("nonexistent", "heart", 0)
    end

    test "get_reactions/1 returns grouped counts" do
      user1 = confirmed_user_fixture()
      user2 = confirmed_user_fixture()
      slug = "reaction-test-slug"

      Post.create_reaction(%{value: "heart", slug: slug, user_id: user1.id})
      Post.create_reaction(%{value: "heart", slug: slug, user_id: user2.id})
      Post.create_reaction(%{value: "rocket-launch", slug: slug, user_id: user1.id})

      reactions = Post.get_reactions(slug)
      assert reactions["heart"] == 2
      assert reactions["rocket-launch"] == 1
    end

    test "change_reaction/2 returns a changeset" do
      reaction = reaction_fixture()
      assert %Ecto.Changeset{} = Post.change_reaction(reaction)
    end
  end
end
