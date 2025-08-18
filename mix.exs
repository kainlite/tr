defmodule Tr.MixProject do
  use Mix.Project

  def project do
    [
      app: :tr,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Tr.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.7.2"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.6"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.4"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:floki, ">= 0.30.0", only: :test},
      {:esbuild, "~> 0.6", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3.1", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.9"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.6"},
      {:earmark, "~> 1.4.27"},
      {:yamerl, "~> 0.10.0"},
      {:html_sanitize_ex, "~> 1.4.2"},
      {:nimble_publisher, "~> 1.1.0"},
      {:makeup, ">= 0.0.0"},
      {:makeup_elixir, ">= 0.0.0"},
      {:makeup_erlang, ">= 0.0.0"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:libcluster, "~> 3.3"},
      {:remote_ip, "~> 1.1"},
      {:logfmt, "~> 3.3"},
      {:poison, "~> 6.0"},
      {:faker, "~> 0.18"},
      {:excoveralls, "~> 0.18", only: :test},
      {:git_hooks, "~> 0.8.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:wallaby, "~> 0.30", runtime: false, only: :test},
      {:ollamex, "0.2.0"},
      {:mimic, "~> 1.7", only: :test},
      {:bandit, "~> 1.0"},
      {:haystack, "~> 0.1.0"},
      {:quantum, "~> 3.5"},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:elixir_auth_google, "~> 1.6"},
      {:elixir_auth_github, "~> 1.6"},
      {:neuron, "~> 5.1.0"},
      {:cloak, "1.1.4"},
      {:peep, "~> 3.3"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"],
      test: ["esbuild default", "ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end
end
