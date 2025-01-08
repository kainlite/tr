defmodule MultiParserTest do
  use ExUnit.Case

  describe "parse/2" do
    test "parses single language (English) content" do
      content = """
      %{
        title: "Test Post",
        author: "John Doe",
        tags: ["test"],
        date: ~D[2023-01-01],
        published: true,
        lang: "en"
      }
      ---
      This is the content of the post.
      """

      assert [en1, en2] = MultiParser.parse("test.md", content)
      assert {attrs, body} = en1
      assert {attrs2, body2} = en2

      # Both versions should be identical for English-only content
      assert attrs == attrs2
      assert body == body2

      assert attrs.title == "Test Post"
      assert attrs.author == "John Doe"
      assert attrs.tags == ["test"]
      assert attrs.date == ~D[2023-01-01]
      assert attrs.published == true
      assert attrs.lang == "en"
      assert body == "This is the content of the post.\n"
    end

    test "parses bilingual (English/Spanish) content" do
      content = """
      %{
        title: "Test Post",
        author: "John Doe",
        tags: ["test"],
        date: ~D[2023-01-01],
        published: true,
        lang: "en"
      }
      ---
      This is the English content.

      ---lang---
      %{
        title: "Post de Prueba",
        author: "John Doe",
        tags: ["test"],
        date: ~D[2023-01-01],
        published: true,
        lang: "es"
      }
      ---
      Este es el contenido en Español.
      """

      assert [en, es] = MultiParser.parse("test.md", content)
      assert {en_attrs, en_body} = en
      assert {es_attrs, es_body} = es

      # Check English version
      assert en_attrs.title == "Test Post"
      assert en_attrs.lang == "en"
      assert en_body == "This is the English content.\n"

      # Check Spanish version
      assert es_attrs.title == "Post de Prueba"
      assert es_attrs.lang == "es"
      assert es_body == "Este es el contenido en Español.\n"
    end

    test "returns error when separator is missing" do
      content = """
      %{
        title: "Test Post",
        author: "John Doe"
      }
      This is invalid content without separator
      """

      assert [{:error, "could not find separator ---"}, {:error, "could not find separator ---"}] =
               MultiParser.parse("test.md", content)
    end

    test "returns error when attributes are not a map" do
      content = """
      "invalid attributes"
      ---
      Some content
      """

      assert [
               {:error, "expected attributes to return a map, got: \"invalid attributes\""},
               {:error, "expected attributes to return a map, got: \"invalid attributes\""}
             ] = MultiParser.parse("test.md", content)
    end
  end
end
