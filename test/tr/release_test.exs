defmodule Tr.ReleaseTest do
  use Tr.DataCase

  alias Tr.Release

  describe "Release" do
    test "Runs migrations" do
      [{:ok, _, _} | _] = Release.migrate()
    end
  end
end
