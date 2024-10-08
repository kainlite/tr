# This file is responsible for configuring your applicationconfig
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
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: TrWeb.ErrorHTML, json: TrWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Tr.PubSub,
  live_view: [signing_salt: "XF0oI1yw"]

config :tr, TrWeb.Endpoint,
  render_errors: [
    view: TrWeb.ErrorView,
    accepts: ~w(html),
    root_layout: {TrWeb.ErrorHTML, :root}
  ]

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
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
# config :remote_ip, debug: true

config :logger, :console,
  format: "$time $metadata $message\n",
  metadata: [:request_id, :remote_ip]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Locale
config :tr, TrWeb.Gettext, locales: ~w(en es), default_locale: "en"

config :tr, Tr.Scheduler,
  jobs: [
    # Every 30 minutes
    {"*/30 * * * *", {Tr.Tracker, :start, []}},
    # Every 15 minutes
    {"*/15 * * * *", {Tr.Approver, :start, []}},
    # Every 5 minutes
    {"*/5 * * * *", {Tr.Sponsors, :start, []}}
  ]

config :tr, metrics_port: 9091

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
