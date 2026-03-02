defmodule Tr.Telemetry.SpansTest do
  use ExUnit.Case, async: true

  alias Tr.Telemetry.Spans

  describe "trace/3" do
    test "executes the wrapped function and returns its result" do
      result = Spans.trace("test.span", %{key: "value"}, fn -> {:ok, 42} end)
      assert result == {:ok, 42}
    end

    test "propagates exceptions from the wrapped function" do
      assert_raise RuntimeError, "boom", fn ->
        Spans.trace("test.span", %{}, fn -> raise "boom" end)
      end
    end

    test "works with default empty attributes" do
      result = Spans.trace("test.span", fn -> :hello end)
      assert result == :hello
    end
  end
end
