defmodule Tr.LabsTest do
  use ExUnit.Case, async: true

  alias Tr.Labs

  test "registry has embedded labs" do
    assert Labs.count() > 0
    assert is_list(Labs.all_labs())
    assert length(Labs.all_labs()) == Labs.count()
  end

  test "every lab carries metadata and an embed location" do
    for lab <- Labs.all_labs() do
      assert is_binary(lab.id)
      assert is_binary(lab.title)
      assert lab.mode in ["scripted", "v86"]
      assert is_binary(lab.post_id)
      assert is_binary(lab.div_id)
    end
  end

  test "tracks resolve to embedded labs only" do
    tracks = Labs.tracks()
    assert length(tracks) > 0

    for track <- tracks do
      assert is_binary(track.title)
      assert is_binary(track.slug)
      assert track.labs != []
      for lab <- track.labs, do: assert(is_binary(lab.id))
    end
  end

  test "labs_in_post returns the labs embedded in a known post" do
    ids = "my_local_environment" |> Labs.labs_in_post() |> Enum.map(& &1.id)
    assert "linux-permissions" in ids
    assert "linux-process" in ids
  end

  test "labs_in_post is empty for a post without labs" do
    assert Labs.labs_in_post("a-post-id-that-does-not-exist") == []
  end

  test "by_post groups labs under their post" do
    groups = Labs.by_post()
    assert Enum.any?(groups, &(&1.post_id == "my_local_environment"))

    for group <- groups do
      assert is_binary(group.post_title)
      assert group.labs != []
    end
  end

  test "lab/1 returns nil for an unknown id" do
    assert Labs.lab("not-a-real-challenge") == nil
  end
end
