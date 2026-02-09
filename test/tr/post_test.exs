defmodule Tr.PostTest do
  use Tr.DataCase

  alias Tr.Post

  describe "comments" do
    alias Tr.Post.Comment

    import Tr.PostFixtures

    @invalid_attrs %{body: nil, slug: nil, user_id: nil, parent_comment_id: nil}

    test "list_comments/0 returns all comments" do
      comment = Tr.Repo.preload(comment_fixture(), :user)
      assert Post.list_comments() == [comment]
    end

    test "get_comment!/1 returns the comment with given id" do
      comment = comment_fixture()
      assert Post.get_comment!(comment.id) == comment
    end

    test "get_comments_for_post/1" do
      comment = comment_fixture()
      assert length(Post.get_comments_for_post(comment.slug)) == length([comment])
    end

    test "get_parent_comments_for_post/1" do
      comment = comment_fixture(%{parent_comment_id: nil})
      assert length(Post.get_parent_comments_for_post(comment.slug)) == length([comment])
    end

    test "create_comment/1 with valid data creates a comment" do
      valid_attrs = %{
        body: "some body",
        slug: "some-slug",
        user_id: 42,
        parent_comment_id: nil
      }

      assert {:ok, %Comment{} = comment} = Post.create_comment(valid_attrs)
      assert comment.body == "some body"
      assert comment.slug == "some-slug"
      assert comment.user_id == 42
      assert comment.parent_comment_id == nil
    end

    test "create_comment/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Post.create_comment(@invalid_attrs)
    end

    test "update_comment/2 with valid data updates the comment" do
      comment = comment_fixture()

      update_attrs = %{
        body: "some updated body",
        slug: "some-updated-slug",
        user_id: 43,
        parent_comment_id: 2
      }

      assert {:ok, %Comment{} = comment} = Post.update_comment(comment, update_attrs)
      assert comment.body == "some updated body"
      assert comment.slug == "some-updated-slug"
      assert comment.user_id == 43
      assert comment.parent_comment_id == 2
    end

    test "update_comment/2 with invalid data returns error changeset" do
      comment = comment_fixture()
      assert {:error, %Ecto.Changeset{}} = Post.update_comment(comment, @invalid_attrs)
      assert comment == Post.get_comment!(comment.id)
    end

    test "delete_comment/1 deletes the comment" do
      comment = comment_fixture()
      assert {:ok, %Comment{}} = Post.delete_comment(comment)
      assert_raise Ecto.NoResultsError, fn -> Post.get_comment!(comment.id) end
    end

    test "change_comment/1 returns a comment changeset" do
      comment = comment_fixture()
      assert %Ecto.Changeset{} = Post.change_comment(comment)
    end

    test "get_unapproved_comments/0 returns only unapproved comments" do
      comment = comment_fixture()
      unapproved = Post.get_unapproved_comments()
      assert Enum.any?(unapproved, &(&1.id == comment.id))
      assert Enum.all?(unapproved, &(&1.approved == false))
    end

    test "approve_comment/1 marks comment as approved" do
      comment = comment_fixture()
      refute comment.approved
      assert {:ok, approved} = Post.approve_comment(comment)
      assert approved.approved
    end

    test "get_comments_count/0 returns correct count" do
      comment_fixture()
      comment_fixture()
      assert Post.get_comments_count() >= 2
    end

    test "get_comment/1 returns nil for non-existent" do
      assert is_nil(Post.get_comment(-1))
    end

    test "get_children_comments_for_post/1 groups by parent_comment_id" do
      parent = comment_fixture(%{parent_comment_id: nil})
      user = Tr.AccountsFixtures.confirmed_user_fixture()

      {:ok, child} =
        Post.create_comment(%{
          body: "child comment",
          slug: parent.slug,
          user_id: user.id,
          parent_comment_id: parent.id
        })

      children = Post.get_children_comments_for_post(parent.slug)
      assert Map.has_key?(children, parent.id)
      assert Enum.any?(children[parent.id], &(&1.id == child.id))
    end

    test "broadcast/2 handles error tuples gracefully" do
      changeset = Post.change_comment(%Tr.Post.Comment{}, %{})
      assert {:error, ^changeset} = Post.broadcast({:error, changeset}, :comment_created)
    end
  end
end
