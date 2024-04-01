defmodule Tr.Search do
  @moduledoc """
  Search module
  """

  alias Haystack.Index
  alias Haystack.Storage

  @doc """
  Return the Haystack.
  """
  def haystack do
    Haystack.index(Haystack.new(), :posts, fn index ->
      index
      |> Index.ref(Index.Field.term("id"))
      |> Index.field(Index.Field.new("description"))
      |> Index.field(Index.Field.new("body"))
      |> Index.storage(storage())
    end)
  end

  @doc """
  Return the storage.
  """
  def storage do
    Storage.ETS.new(name: :posts, table: :posts, load: &load/0)
  end

  @doc """
  Load the storage.
  """
  def load do
    Task.Supervisor.start_child(Tr.TaskSupervisor, fn ->
      Haystack.index(haystack(), :posts, fn index ->
        Tr.Blog.posts()
        |> Stream.map(&Map.take(&1, ~w{id description body}a))
        |> Enum.each(&Haystack.Index.add(index, [&1]))

        index
      end)
    end)

    []
  end

  @doc """
  Perform a search.
  """
  def search(q) do
    Haystack.index(haystack(), :posts, fn index ->
      Index.search(index, q)
    end)
  end
end
