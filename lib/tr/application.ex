defmodule Tr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies, [])

    children = [
      # Start the Cluster supervisor for libcluster
      {Cluster.Supervisor, [topologies, [name: Tr.ClusterSupervisor]]},
      # Start the Telemetry supervisor
      TrWeb.Telemetry,
      # Start the Ecto repository
      Tr.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Tr.PubSub},
      # Start Finch
      {Finch, name: Tr.Finch},
      # Task supervisor
      {Task.Supervisor, name: Tr.TaskSupervisor},
      # Start the Presence app 
      TrWeb.Presence,
      # Start haystack
      {Haystack.Storage.ETS, storage: Tr.Search.storage()},
      # Initialize the vault
      Tr.Vault,
      # Start the scheduler
      Tr.Scheduler,
      # Start the Endpoint (http/https)
      TrWeb.Endpoint
      # Start a worker by calling: Tr.Worker.start_link(arg)
      # {Tr.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tr.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TrWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
