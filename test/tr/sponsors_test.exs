defmodule Tr.SponsorsTest do
  use Tr.DataCase
  use Mimic

  describe "get_sponsors/1" do
    test "returns expected structure from mocked Neuron response" do
      mock_body = %{
        "data" => %{
          "user" => %{
            "sponsors" => %{
              "totalCount" => 2,
              "nodes" => [
                %{"login" => "sponsor1"},
                %{"login" => "sponsor2"}
              ]
            }
          }
        }
      }

      Neuron
      |> expect(:query, fn _query, _vars, _opts ->
        {:ok, %Neuron.Response{body: mock_body, status_code: 200, headers: []}}
      end)

      result = Tr.Sponsors.get_sponsors(100)

      assert get_in(result, ["data", "user", "sponsors", "totalCount"]) == 2
      nodes = get_in(result, ["data", "user", "sponsors", "nodes"])
      assert length(nodes) == 2
      assert Enum.at(nodes, 0)["login"] == "sponsor1"
      assert Enum.at(nodes, 1)["login"] == "sponsor2"
    end

    test "returns empty nodes when no sponsors" do
      mock_body = %{
        "data" => %{
          "user" => %{
            "sponsors" => %{
              "totalCount" => 0,
              "nodes" => []
            }
          }
        }
      }

      Neuron
      |> expect(:query, fn _query, _vars, _opts ->
        {:ok, %Neuron.Response{body: mock_body, status_code: 200, headers: []}}
      end)

      result = Tr.Sponsors.get_sponsors(100)

      nodes = get_in(result, ["data", "user", "sponsors", "nodes"])
      assert nodes == []
    end
  end
end
