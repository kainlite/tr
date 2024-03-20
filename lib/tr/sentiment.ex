defmodule Tr.Sentiment do
  @moduledoc """
  Basic sentiment analysis
  """

  def parse(message) do
    Afinn.score_to_words(message, :en)
  end

  def analyze(message) do
    m =
      case parse(message) do
        :positive -> true
        :neutral -> true
        :negative -> false
      end

    m
  end
end
