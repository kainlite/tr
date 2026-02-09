defmodule Tr.CommentSchemaTest do
  use Tr.DataCase

  alias Tr.Post.Comment

  describe "Comment changeset" do
    test "valid changeset with required fields" do
      changeset =
        Comment.changeset(%Comment{}, %{slug: "test-slug", body: "test body", user_id: 1})

      assert changeset.valid?
    end

    test "validates required fields" do
      changeset = Comment.changeset(%Comment{}, %{})
      refute changeset.valid?

      assert %{
               slug: ["can't be blank"],
               body: ["can't be blank"],
               user_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "allows optional parent_comment_id" do
      changeset =
        Comment.changeset(%Comment{}, %{
          slug: "test-slug",
          body: "test body",
          user_id: 1,
          parent_comment_id: 42
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :parent_comment_id) == 42
    end

    test "default approved is false" do
      comment = %Comment{}
      assert comment.approved == false
    end

    test "rejects empty body" do
      changeset =
        Comment.changeset(%Comment{}, %{slug: "test-slug", body: nil, user_id: 1})

      refute changeset.valid?
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
