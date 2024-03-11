defmodule Tr.PostTest do
  use Tr.DataCase

  alias Tr.Post

  describe "comments" do
    alias Tr.Post.Comment

    import Tr.PostFixtures

    @invalid_attrs %{body: nil, slug: nil, user_id: nil, source_ip: nil, parent_comment_id: nil}

    test "list_comments/0 returns all comments" do
      comment = comment_fixture()
      assert Post.list_comments() == [comment]
    end

    test "get_comment!/1 returns the comment with given id" do
      comment = comment_fixture()
      assert Post.get_comment!(comment.id) == comment
    end

    test "create_comment/1 with valid data creates a comment" do
      valid_attrs = %{body: "some body", slug: "some slug", user_id: 42, source_ip: "some source_ip", parent_comment_id: "some parent_comment_id"}

      assert {:ok, %Comment{} = comment} = Post.create_comment(valid_attrs)
      assert comment.body == "some body"
      assert comment.slug == "some slug"
      assert comment.user_id == 42
      assert comment.source_ip == "some source_ip"
      assert comment.parent_comment_id == "some parent_comment_id"
    end

    test "create_comment/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Post.create_comment(@invalid_attrs)
    end

    test "update_comment/2 with valid data updates the comment" do
      comment = comment_fixture()
      update_attrs = %{body: "some updated body", slug: "some updated slug", user_id: 43, source_ip: "some updated source_ip", parent_comment_id: "some updated parent_comment_id"}

      assert {:ok, %Comment{} = comment} = Post.update_comment(comment, update_attrs)
      assert comment.body == "some updated body"
      assert comment.slug == "some updated slug"
      assert comment.user_id == 43
      assert comment.source_ip == "some updated source_ip"
      assert comment.parent_comment_id == "some updated parent_comment_id"
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
  end
end
