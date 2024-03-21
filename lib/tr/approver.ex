defmodule Tr.Approver do
  @moduledoc """
  Basic task runner to approve comments if they pass sentiment analysis
  """
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
    ollama_sentiment = Tr.Ollama.send(comment.body)

    ollama_sentiment
  end

  def start do
    start_app()

    comments = Tr.Post.get_unapproved_comments()

    Enum.each(comments, fn comment ->
      if check_comment_sentiment(comment) do
        Tr.Post.approve_comment(comment)
      end
    end)
  end
end
