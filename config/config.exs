# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tr,
  ecto_repos: [Tr.Repo]

# Configures the endpoint
config :tr, TrWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: TrWeb.ErrorHTML, json: TrWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Tr.PubSub,
  live_view: [signing_salt: "XF0oI1yw"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :tr, Tr.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.41",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.2.4",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Libcluster configuration
namespace =
  System.get_env("NAMESPACE") || "tr"

config :libcluster,
  topologies: [
    default: [
      strategy: Elixir.Cluster.Strategy.Kubernetes,
      config: [
        mode: :ip,
        kubernetes_node_basename: "tr",
        kubernetes_selector: "name=tr",
        kubernetes_namespace: namespace,
        kubernetes_ip_lookup_mode: :pods,
        polling_interval: 10_000
      ]
    ]
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
