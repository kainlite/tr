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
    assert tracks != []

    for track <- tracks do
      assert is_binary(track.title)
      assert is_binary(track.slug)
      assert track.labs != []
      for lab <- track.labs, do: assert(is_binary(lab.id))
    end
  end

  test "docker track resolves all eight labs in learning order" do
    docker = Enum.find(Labs.tracks(), &(&1.slug == "docker"))
    assert docker, "the docker track should be present"

    assert Enum.map(docker.labs, & &1.id) == [
             "docker-basics",
             "container-chroot",
             "container-namespaces",
             "docker-images",
             "dockerfile-build",
             "docker-volumes",
             "docker-compose",
             "docker-networking"
           ]
  end

  test "the container-internals labs are real-VM (v86) labs in the docker-course chapter" do
    for id <- ~w(container-chroot container-namespaces) do
      lab = Labs.lab(id)
      assert lab, "#{id} should be registered (needs both metadata and a post embed)"
      assert lab.mode == "v86"
      assert lab.div_id == "ch-#{id}"
    end
  end

  test "the git track pairs scripted drills with real-VM labs" do
    git = Enum.find(Labs.tracks(), &(&1.slug == "git"))
    assert git, "the git track should be present"

    assert Enum.map(git.labs, & &1.id) == [
             "git-basics",
             "git-workflow-real",
             "git-reflog-recovery",
             "git-reflog-real"
           ]

    for id <- ~w(git-workflow-real git-reflog-real) do
      lab = Labs.lab(id)
      assert lab, "#{id} should be registered (needs both metadata and a post embed)"
      assert lab.mode == "v86"
    end
  end

  test "each new docker lab is a scripted lab embedded under its ch- div" do
    for id <- ~w(docker-images dockerfile-build docker-volumes docker-compose docker-networking) do
      lab = Labs.lab(id)
      assert lab, "#{id} should be registered (needs both metadata and a post embed)"
      assert lab.mode == "scripted"
      assert is_binary(lab.post_id)
      assert lab.div_id == "ch-#{id}"
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
