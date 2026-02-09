defmodule Tr.ApproverTest do
  use Tr.DataCase
  use Mimic

  describe "Approver" do
    test "approves a comment if it pass on sentiment analysis" do
      comment =
        Tr.PostFixtures.comment_fixture(%{body: "Thank you, this was really useful for me"})

      Tr.Ollama
      |> stub(:send, fn _m -> :stub end)
      |> expect(:send, fn _m -> true end)

      Tr.Approver.start()
      comment = Tr.Post.get_comment(comment.id)
      assert comment.approved
    end

    test "ignores a comment if it doesn't pass on sentiment analysis" do
      comment =
        Tr.PostFixtures.comment_fixture(%{body: "This sucks!"})

      Tr.Ollama
      |> stub(:send, fn _m -> :stub end)
      |> expect(:send, fn _m -> false end)

      Tr.Approver.start()
      comment = Tr.Post.get_comment(comment.id)
      refute comment.approved
    end

    test "start/0 with no unapproved comments doesn't error" do
      Tr.Ollama
      |> stub(:send, fn _m -> :stub end)

      assert Tr.Approver.start() == :ok
    end

    test "start/0 processes multiple comments with mixed sentiment" do
      comment1 =
        Tr.PostFixtures.comment_fixture(%{body: "Great article!"})

      comment2 =
        Tr.PostFixtures.comment_fixture(%{body: "Terrible post!"})

      comment3 =
        Tr.PostFixtures.comment_fixture(%{body: "Very helpful, thanks"})

      Tr.Ollama
      |> stub(:send, fn _m -> :stub end)
      |> expect(:send, 3, fn body ->
        if body =~ "Terrible", do: false, else: true
      end)

      Tr.Approver.start()

      assert Tr.Post.get_comment(comment1.id).approved
      refute Tr.Post.get_comment(comment2.id).approved
      assert Tr.Post.get_comment(comment3.id).approved
    end

    test "check_comment_sentiment/1 returns the Ollama result directly" do
      comment =
        Tr.PostFixtures.comment_fixture(%{body: "Nice work"})

      Tr.Ollama
      |> stub(:send, fn _m -> :stub end)
      |> expect(:send, fn _m -> true end)

      assert Tr.Approver.check_comment_sentiment(comment) == true
    end
  end
end
