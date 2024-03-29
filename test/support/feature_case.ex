defmodule TrWeb.FeatureCase do
  @moduledoc """
  Integration / Feature base configuration
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.DSL
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Tr.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Tr.Repo, {:shared, self()})
    end

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Tr.Repo, self())

    {:ok, session} = Wallaby.start_session(metadata: metadata)

    {:ok, session: session}
  end
end
