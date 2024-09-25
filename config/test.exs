import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :tr, Tr.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "tr_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tr, TrWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "JnCErsnzXelkHZyMNrvHSomPSngAlkX/PrXXfI3LB9TKsIAwsw1tgkoS5U5N0ovQ",
  server: true

# In test we don't send emails.
config :tr, Tr.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

config :tr, sql_sandbox: true

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :wallaby,
  screenshot_on_failure: false,
  opt_app: :tr,
  driver: Wallaby.Chrome,
  chromedriver: [headless: true, binary: "/usr/bin/google-chrome-stable"]

config :floki, :encode_raw_html, false

config :tr, metrics_port: 9092
