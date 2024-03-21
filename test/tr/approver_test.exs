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
  end
end
