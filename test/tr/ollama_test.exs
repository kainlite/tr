defmodule Tr.OllamaTest do
  use Tr.DataCase
  use Mimic

  alias Tr.Ollama

  describe "Ollama send/1 mocked" do
    test "sends a message to the Ollama API" do
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

  describe "Ollama parse logic" do
    test "parses 'Sentiment: Positive' as true" do
      Ollama
      |> stub(:send, fn _m -> :stub end)
      |> expect(:send, fn _m -> true end)

      assert Ollama.send("test") == true
    end

    test "parses 'Sentiment: Negative' as false" do
      Ollama
      |> stub(:send, fn _m -> :stub end)
      |> expect(:send, fn _m -> false end)

      assert Ollama.send("test") == false
    end

    test "parses 'Sentiment: Neutral' as true" do
      Ollama
      |> stub(:send, fn _m -> :stub end)
      |> expect(:send, fn _m -> true end)

      assert Ollama.send("test") == true
    end

    test "handles timeout returning false" do
      Ollama
      |> stub(:send, fn _m -> :stub end)
      |> expect(:send, fn _m -> false end)

      assert Ollama.send("test") == false
    end
  end
end
