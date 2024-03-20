defmodule Tr.Ollama do
  @moduledoc """
  Ollama o llama 
  """

  # defp model do
  #   ~s"""
  #   FROM orca-mini

  #   PARAMETER temperature 0.2

  #   MESSAGE user thank you, this was really useful for me
  #   MESSAGE assistant POSITIVE
  #   MESSAGE user you should do something else, this is really bad
  #   MESSAGE assistant NEGATIVE
  #   MESSAGE user this has nothing to do with this post
  #   MESSAGE assistant NEUTRAL

  #   SYSTEM You are a sentiment analyzer. You will receive text and output only one word, either POSITIVE or NEGATIVE or NEUTRAL, depending on the sentiment of the text
  #   """
  # end

  def api do
    Ollamex.API.new(System.get_env("OLLAMA_ENDPOINT", "http://localhost:11434/api"))
  end

  def send(message) do
    api = api()
    p = %Ollamex.PromptRequest{model: "sentiments:latest", prompt: "MESSAGE " <> message}

    case Ollamex.generate_with_timeout(p, api) do
      {:error, :timeout} -> false
      {:ok, r} -> parse(r.response)
    end
  end

  defp parse(r) do
    clean = r |> String.downcase() |> String.trim()

    clean =
      cond do
        String.contains?(clean, ":") ->
          String.split(clean, ":") |> List.last() |> String.trim()

        String.contains?(clean, ".") ->
          String.split(clean, ".") |> List.first() |> String.trim()
      end

    case clean do
      "neutral" -> true
      "positive" -> true
      "negative" -> false
    end
  end
end
