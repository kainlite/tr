defmodule Tr.OllamaTest do
  use Tr.DataCase
  use Mimic

  alias Tr.Ollama

  describe "Ollama" do
    test "sends a message to the Ollama API" do
      # Result from ollama
      # " Sentiment: Positive"
      # " Sentiment: Neutral"
      # " Output: Negative"
      # assert Ollama.send("thank you, this was really useful for me") == true
      # assert Ollama.send("just some random thought") == true
      # assert Ollama.send("this sucks, this is really bad") == false

      Ollama
      |> stub(:send, fn _m -> :stub end)
      |> expect(:send, fn _m -> true end)
      |> expect(:send, fn _m -> true end)
      |> expect(:send, fn _m -> false end)

      # Positive 
      assert Ollama.send("Thank you, this was really useful for me") == true

      # Neutral
      assert Ollama.send("just some random thought") == true

      # Negative
      assert Ollama.send("this sucks, this is really bad") == false
    end
  end
end
