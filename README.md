# TR

[![github](https://github.com/kainlite/tr/actions/workflows/coverage.yaml/badge.svg)](https://github.com/kainlite/tr/actions/workflows/coverage.yaml)
[![codecov](https://codecov.io/gh/kainlite/tr/branch/master/graph/badge.svg)](https://codecov.io/gh/kainlite/tr)

This is the source code for my blog, you can check it out [here](https://segfault.pw/blog)

# Development

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`
  * Start the dev PG instance `docker-compose up -d`.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Contact form

The site has no public email address; visitors reach the author through the
form at `/contact` (also `/en/contact` and `/es/contact`). Submissions are
validated and forwarded through the configured Swoosh mailer with `Reply-To`
set to the sender, so answering the email replies to the visitor directly.

Abuse controls, all in-process and without third-party captchas:

  * a hidden honeypot field and a minimum time between page load and submit
    (`config :tr, :contact_min_fill_ms`, default 3 seconds); bots that trip
    either get a fake success and nothing is sent
  * per-client-address and global hourly caps enforced by `Tr.RateLimiter`
    (`config :tr, :contact_rate_limit`, default 3 per address and 30 overall
    per node per hour)

Configuration:

  * `CONTACT_EMAIL` (production, required): destination address for the
    messages. It is deliberately not in the repository; when unset the form
    still renders but every submission fails with a generic error and a log
    line. Development and test deliver to `contact@example.com` (dev uses the
    local Swoosh mailbox at `/dev/mailbox`).
  * `BREVO_API_KEY` (production): API key for the Brevo adapter that sends
    all outgoing email.

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix

