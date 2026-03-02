defmodule Tr.Approver do
  @moduledoc """
  Basic task runner to approve comments if they pass sentiment analysis
  """
  alias Tr.Telemetry.Spans

  @app :tr

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  @doc """
  If the llama agrees upon the sentiment then the comment can be automatically approved
  """
  def check_comment_sentiment(comment) do
    Spans.trace("approver.check_sentiment", %{"comment.id" => comment.id}, fn ->
      ollama_sentiment = Tr.Ollama.send(comment.body)

      ollama_sentiment
    end)
  end

  def start do
    Spans.trace("approver.start", %{}, fn ->
      start_app()

      Tr.Post.get_unapproved_comments()
      |> Enum.each(&maybe_approve/1)
    end)
  end

  defp maybe_approve(comment) do
    if check_comment_sentiment(comment) do
      Tr.Post.approve_comment(comment)
    end
  end
end
