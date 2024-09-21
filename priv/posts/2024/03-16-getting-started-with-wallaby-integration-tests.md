%{
  title: "Getting started with Wallaby integration tests",
  author: "Gabriel Garrido",
  description: "Wallaby is a concurrent feature testing library, also known as integration testing libraries, it can be
  configured with chromedriver, geckodriver, etc, to spin up a browser and interact with your site, run some assertions 
  and also validate your application as a real user would do.",
  tags: ~w(elixir phoenix wallaby),
  published: true,
  image: "wallaby.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![Wallaby](/images/wallaby.png){:class="mx-auto"}

##### **Introduction**

For developers building web applications with Elixir, robust testing is essential for a smooth development process and user experience. Wallaby is a powerful library that elevates your Elixir testing capabilities.

* https://hexdocs.pm/wallaby/Wallaby.html

<br />

If you cannot wait to read the code, this pull requests illustrates all the changes needed for it to work well.
* https://github.com/kainlite/tr/pull/10

<br />

##### **Understanding Wallaby**

Wallaby operates by automating interactions within a real web browser. This allows you to simulate user actions like clicking buttons, filling out forms, and verifying that the correct elements are displayed on the page. This end-to-end testing approach complements traditional unit and integration tests.
<br />

##### **Advantages of Wallaby**

**Efficiency**: Wallaby's support for concurrent test execution significantly speeds up your test suite, providing faster feedback.

**Confidence**: By testing within real browsers, you can catch browser-specific compatibility issues early on, ensuring your application functions as expected for your users.
<br />

##### **Installation**

Add Wallaby as a dependency in your `mix.exs` file:
```elixir
{:wallaby, "~> 0.30", runtime: false, only: :test}
```
Then install it with `mix deps.get`
<br />

##### **Configuration**

To use Wallaby, adjust the following settings in your `config/test.exs` file:
* Endpoint: Set `server: true` to enable your Phoenix endpoint in testing.
* SQL Sandbox: Set `sql_sandbox: true` for isolated database testing.
* Wallaby Configuration: Add a Wallaby configuration block, replacing `tr` with your application's name:
<br />

```elixir
config :tr, TrWeb.Endpoint,
  ...
  server: true

config :tr, sql_sandbox: true

config :wallaby,
  screenshot_on_failure: false,
  opt_app: :tr,
  driver: Wallaby.Chrome,
  chromedriver: [headless: true, binary: "/usr/bin/google-chrome-stable"]
```
<br />

**Instrumenting Your Endpoint** `lib/tr_web/endpoint.ex`

* **Add Wallaby Configuration:** Near the top of your `lib/tr_web/endpoint.ex` file, insert the following configuration block. Be sure to replace `tr` with your actual application name.
* **Modify Socket Configuration:** Within the socket function of your endpoint, add a `user_agent` field to establish a link between the browser session and the database.

```elixir
 if Application.compile_env(:tr, :sql_sandbox) do
    plug Phoenix.Ecto.SQL.Sandbox
  end

 socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:user_agent, session: @session_options]]
```
The `user_agent` setting within the socket configuration ensures Wallaby can correctly associate each test browser session with the appropriate database interactions.
<br />

**Router**

The next step is to setup the router, basically we need to setup the `on_mount` hook in live_session, there are two ways
to do it, and we will see both because this application uses the phoenix generated authentication.

The first block makes sure that all the default LiveView sessions uses the hook.
```elixir
  live_session :default, on_mount: TrWeb.Hooks.AllowEctoSandbox do
    scope "/blog", TrWeb do
      pipe_through :browser


      live "/", BlogLive, :index
      live "/:id", PostLive, :show
    end
  end
```
<br />

The second block adds the same hook for all the remaining LiveViews, specifying it in the `on_mount`.
```elixir
  ## Authentication routes
  scope "/", TrWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [
        {TrWeb.UserAuth, :redirect_if_user_is_authenticated},
        {TrWeb.Hooks.AllowEctoSandbox, :default}
      ] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", TrWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {TrWeb.UserAuth, :ensure_authenticated},
        {TrWeb.Hooks.AllowEctoSandbox, :default}
      ] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", TrWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{TrWeb.UserAuth, :mount_current_user}, {TrWeb.Hooks.AllowEctoSandbox, :default}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
```
<br />

**Understanding the Hook's Purpose**

You might be curious about the "hook" we're about to add. This piece of code plays a key role in setting up the testing environment for Wallaby.  While there are a few places you could put it, we'll use `lib/tr_web/sandbox.ex` for simplicity.

What Does the Hook Do?

Think of the hook as a helper that performs these important tasks:

* **Prepares the Database:** It ensures each Wallaby test starts with a fresh, isolated database, preventing conflicts.
* **Connects Wallaby to Your App:** The hook creates a bridge between Wallaby's test browser sessions and your application, allowing Wallaby to interact with your code correctly.
<br />

```elixir
defmodule TrWeb.Hooks.AllowEctoSandbox do
  @moduledoc """
  Sandbox configuration for integration tests
  """
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    allow_ecto_sandbox(socket)
    {:cont, socket}
  end

  defp allow_ecto_sandbox(socket) do
    %{assigns: %{phoenix_ecto_sandbox: metadata}} =
      assign_new(socket, :phoenix_ecto_sandbox, fn ->
        if connected?(socket), do: get_connect_info(socket, :user_agent)
      end)

    Phoenix.Ecto.SQL.Sandbox.allow(metadata, Application.get_env(:your_app, :sandbox))
  end
end
```
<br />

One of the last steps before we can run a test is to set the right case for us `test/support/feature_case.ex`: 
```elixir
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

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Tr.Repo)

    Ecto.Adapters.SQL.Sandbox.mode(Tr.Repo, {:shared, self()})

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Tr.Repo, self())

    {:ok, session} = Wallaby.start_session(metadata: metadata)

    {:ok, session: session}
  end
end
```
<br />

**Up next:** `test/test_helper.exs`:

by defining a login helper function here, you create a convenient way to simulate  logged-in user sessions directly within your tests. This is crucial for testing features that require authentication.

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Tr.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, TrWeb.Endpoint.url())

import Tr.AccountsFixtures
import TrWeb.FeatureCase
import Wallaby.Browser

defmodule TrWeb.TestHelpers do
  @moduledoc """
  Helper module for tests
  """
  def log_in(session) do
    user_remember_me = "_tr_web_user_remember_me"

    user = confirmed_user_fixture()
    user_token = Tr.Accounts.generate_user_session_token(user)

    endpoint_opts = Application.get_env(:tr, TrWeb.Endpoint)
    secret_key_base = Keyword.fetch!(endpoint_opts, :secret_key_base)

    conn =
      %Plug.Conn{secret_key_base: secret_key_base}
      |> Plug.Conn.put_resp_cookie(user_remember_me, user_token, sign: true)

    session
    |> visit("/")
    |> set_cookie(user_remember_me, conn.resp_cookies[user_remember_me][:value])

    {:ok, %{session: session, user: user}}
  end
end
```

**Fine-tuning LiveView Tests:**  The Importance of `async: false`

Remember how we set the sandbox mode to shared in your feature case file? This setting is a smart move for test efficiency, but it has a small impact on how we write LiveView tests.

Why the Change?

**Sandbox Sharing:** The shared sandbox mode means multiple Wallaby tests reuse the same database environment. This is great for speed, but it requires a bit of coordination with LiveView.

**Ensuring Consistency:** Setting `async: false` for LiveView tests helps guarantee that each LiveView test sees a consistent view of the database. This prevents unexpected outcomes that could happen with multiple concurrent LiveView tests.

```elixir
  use TrWeb.ConnCase, async: false
```
<br />

##### **Running a test** 

In this example we run 2 browsers with logged in users and verify that they can send a message and receive it in real
time, you will also see examples how to select and interact with different elements and run some assertions.

```elixir
defmodule TrWeb.Integration.PostIntegrationTest do
  use TrWeb.FeatureCase, async: false
  use Wallaby.Feature
  use Phoenix.VerifiedRoutes, router: TrWeb.Router, endpoint: TrWeb.Endpoint

  import Wallaby.Query

  import TrWeb.TestHelpers

  @send_button button("Send")

  describe "Blog articles" do
    test "has some articles", %{session: session} do
      session
      |> visit("/blog")
      |> find(css("div #upgrading-k3s-with-system-upgrade-controller", count: 1))
      |> assert_has(css("h2", text: "Upgrading K3S with system-upgrade-controller"))
    end

    def message(msg), do: css("li", text: msg)

    @sessions 2
    feature "That users can send messages to each other", %{sessions: [user1, user2]} do
      page = ~p"/blog/upgrading-k3s-with-system-upgrade-controller"

      user1
      |> log_in()

      user1
      |> visit(page)

      user1
      |> fill_in(Query.text_field("Message"), with: "Hello user2!")

      user1
      |> click(@send_button)

      user2
      |> log_in()

      user2
      |> visit(page)

      user2
      |> click(Query.link("Reply"))

      user2
      |> fill_in(Query.text_field("Message"), with: "Hello user1!")

      user2
      |> click(@send_button)

      user1
      |> assert_has(message("Hello user1!"))
      |> assert_has(css("p", text: "Online: 2"))

      user2
      |> assert_has(message("Hello user2!"))
      |> assert_has(css("p", text: "Online: 2"))
    end
  end
end
```

To see the results head over to the checks page [here](https://github.com/kainlite/tr/actions/runs/8310299885/job/22742643890)
<br />

##### **Running it in github actions** 

When you want Wallaby tests to run automatically as part of your continuous integration (CI) system, there's one important setup step: **installing browser drivers.**

```elixir
      - uses: nanasess/setup-chromedriver@v2
      - run: |
          export DISPLAY=:99
          chromedriver --url-base=/wd/hub &
          sudo Xvfb -ac :99 -screen 0 1920x1080x24 > /dev/null 2>&1 & # optional
```
see the full file [here](https://github.com/kainlite/tr/blob/master/.github/workflows/coverage.yaml#L38)
<br />

##### **The Journey Continues** 

This is a foundational introduction to Wallaby. In subsequent articles, we'll explore advanced features, best practices, and ways to streamline your testing process. if you found this tutorial useful please leave a comment.
<br />

##### **Closing notes**
Let me know if there is anything that you would like to see implemented or tested, explored and what not in here...
<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
---lang---
%{
  title: "Getting started with Wallaby integration tests",
  author: "Gabriel Garrido",
  description: "Wallaby is a concurrent feature testing library, also known as integration testing libraries, it can be
  configured with chromedriver, geckodriver, etc, to spin up a browser and interact with your site, run some assertions 
  and also validate your application as a real user would do.",
  tags: ~w(elixir phoenix wallaby),
  published: true,
  image: "wallaby.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### Traduccion en proceso

![Wallaby](/images/wallaby.png){:class="mx-auto"}

##### **Introduction**

For developers building web applications with Elixir, robust testing is essential for a smooth development process and user experience. Wallaby is a powerful library that elevates your Elixir testing capabilities.

* https://hexdocs.pm/wallaby/Wallaby.html

<br />

If you cannot wait to read the code, this pull requests illustrates all the changes needed for it to work well.
* https://github.com/kainlite/tr/pull/10

<br />

##### **Understanding Wallaby**

Wallaby operates by automating interactions within a real web browser. This allows you to simulate user actions like clicking buttons, filling out forms, and verifying that the correct elements are displayed on the page. This end-to-end testing approach complements traditional unit and integration tests.
<br />

##### **Advantages of Wallaby**

**Efficiency**: Wallaby's support for concurrent test execution significantly speeds up your test suite, providing faster feedback.

**Confidence**: By testing within real browsers, you can catch browser-specific compatibility issues early on, ensuring your application functions as expected for your users.
<br />

##### **Installation**

Add Wallaby as a dependency in your `mix.exs` file:
```elixir
{:wallaby, "~> 0.30", runtime: false, only: :test}
```
Then install it with `mix deps.get`
<br />

##### **Configuration**

To use Wallaby, adjust the following settings in your `config/test.exs` file:
* Endpoint: Set `server: true` to enable your Phoenix endpoint in testing.
* SQL Sandbox: Set `sql_sandbox: true` for isolated database testing.
* Wallaby Configuration: Add a Wallaby configuration block, replacing `tr` with your application's name:
<br />

```elixir
config :tr, TrWeb.Endpoint,
  ...
  server: true

config :tr, sql_sandbox: true

config :wallaby,
  screenshot_on_failure: false,
  opt_app: :tr,
  driver: Wallaby.Chrome,
  chromedriver: [headless: true, binary: "/usr/bin/google-chrome-stable"]
```
<br />

**Instrumenting Your Endpoint** `lib/tr_web/endpoint.ex`

* **Add Wallaby Configuration:** Near the top of your `lib/tr_web/endpoint.ex` file, insert the following configuration block. Be sure to replace `tr` with your actual application name.
* **Modify Socket Configuration:** Within the socket function of your endpoint, add a `user_agent` field to establish a link between the browser session and the database.

```elixir
 if Application.compile_env(:tr, :sql_sandbox) do
    plug Phoenix.Ecto.SQL.Sandbox
  end

 socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:user_agent, session: @session_options]]
```
The `user_agent` setting within the socket configuration ensures Wallaby can correctly associate each test browser session with the appropriate database interactions.
<br />

**Router**

The next step is to setup the router, basically we need to setup the `on_mount` hook in live_session, there are two ways
to do it, and we will see both because this application uses the phoenix generated authentication.

The first block makes sure that all the default LiveView sessions uses the hook.
```elixir
  live_session :default, on_mount: TrWeb.Hooks.AllowEctoSandbox do
    scope "/blog", TrWeb do
      pipe_through :browser


      live "/", BlogLive, :index
      live "/:id", PostLive, :show
    end
  end
```
<br />

The second block adds the same hook for all the remaining LiveViews, specifying it in the `on_mount`.
```elixir
  ## Authentication routes
  scope "/", TrWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [
        {TrWeb.UserAuth, :redirect_if_user_is_authenticated},
        {TrWeb.Hooks.AllowEctoSandbox, :default}
      ] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", TrWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {TrWeb.UserAuth, :ensure_authenticated},
        {TrWeb.Hooks.AllowEctoSandbox, :default}
      ] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", TrWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{TrWeb.UserAuth, :mount_current_user}, {TrWeb.Hooks.AllowEctoSandbox, :default}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
```
<br />

**Understanding the Hook's Purpose**

You might be curious about the "hook" we're about to add. This piece of code plays a key role in setting up the testing environment for Wallaby.  While there are a few places you could put it, we'll use `lib/tr_web/sandbox.ex` for simplicity.

What Does the Hook Do?

Think of the hook as a helper that performs these important tasks:

* **Prepares the Database:** It ensures each Wallaby test starts with a fresh, isolated database, preventing conflicts.
* **Connects Wallaby to Your App:** The hook creates a bridge between Wallaby's test browser sessions and your application, allowing Wallaby to interact with your code correctly.
<br />

```elixir
defmodule TrWeb.Hooks.AllowEctoSandbox do
  @moduledoc """
  Sandbox configuration for integration tests
  """
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    allow_ecto_sandbox(socket)
    {:cont, socket}
  end

  defp allow_ecto_sandbox(socket) do
    %{assigns: %{phoenix_ecto_sandbox: metadata}} =
      assign_new(socket, :phoenix_ecto_sandbox, fn ->
        if connected?(socket), do: get_connect_info(socket, :user_agent)
      end)

    Phoenix.Ecto.SQL.Sandbox.allow(metadata, Application.get_env(:your_app, :sandbox))
  end
end
```
<br />

One of the last steps before we can run a test is to set the right case for us `test/support/feature_case.ex`: 
```elixir
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

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Tr.Repo)

    Ecto.Adapters.SQL.Sandbox.mode(Tr.Repo, {:shared, self()})

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Tr.Repo, self())

    {:ok, session} = Wallaby.start_session(metadata: metadata)

    {:ok, session: session}
  end
end
```
<br />

**Up next:** `test/test_helper.exs`:

by defining a login helper function here, you create a convenient way to simulate  logged-in user sessions directly within your tests. This is crucial for testing features that require authentication.

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Tr.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, TrWeb.Endpoint.url())

import Tr.AccountsFixtures
import TrWeb.FeatureCase
import Wallaby.Browser

defmodule TrWeb.TestHelpers do
  @moduledoc """
  Helper module for tests
  """
  def log_in(session) do
    user_remember_me = "_tr_web_user_remember_me"

    user = confirmed_user_fixture()
    user_token = Tr.Accounts.generate_user_session_token(user)

    endpoint_opts = Application.get_env(:tr, TrWeb.Endpoint)
    secret_key_base = Keyword.fetch!(endpoint_opts, :secret_key_base)

    conn =
      %Plug.Conn{secret_key_base: secret_key_base}
      |> Plug.Conn.put_resp_cookie(user_remember_me, user_token, sign: true)

    session
    |> visit("/")
    |> set_cookie(user_remember_me, conn.resp_cookies[user_remember_me][:value])

    {:ok, %{session: session, user: user}}
  end
end
```

**Fine-tuning LiveView Tests:**  The Importance of `async: false`

Remember how we set the sandbox mode to shared in your feature case file? This setting is a smart move for test efficiency, but it has a small impact on how we write LiveView tests.

Why the Change?

**Sandbox Sharing:** The shared sandbox mode means multiple Wallaby tests reuse the same database environment. This is great for speed, but it requires a bit of coordination with LiveView.

**Ensuring Consistency:** Setting `async: false` for LiveView tests helps guarantee that each LiveView test sees a consistent view of the database. This prevents unexpected outcomes that could happen with multiple concurrent LiveView tests.

```elixir
  use TrWeb.ConnCase, async: false
```
<br />

##### **Running a test** 

In this example we run 2 browsers with logged in users and verify that they can send a message and receive it in real
time, you will also see examples how to select and interact with different elements and run some assertions.

```elixir
defmodule TrWeb.Integration.PostIntegrationTest do
  use TrWeb.FeatureCase, async: false
  use Wallaby.Feature
  use Phoenix.VerifiedRoutes, router: TrWeb.Router, endpoint: TrWeb.Endpoint

  import Wallaby.Query

  import TrWeb.TestHelpers

  @send_button button("Send")

  describe "Blog articles" do
    test "has some articles", %{session: session} do
      session
      |> visit("/blog")
      |> find(css("div #upgrading-k3s-with-system-upgrade-controller", count: 1))
      |> assert_has(css("h2", text: "Upgrading K3S with system-upgrade-controller"))
    end

    def message(msg), do: css("li", text: msg)

    @sessions 2
    feature "That users can send messages to each other", %{sessions: [user1, user2]} do
      page = ~p"/blog/upgrading-k3s-with-system-upgrade-controller"

      user1
      |> log_in()

      user1
      |> visit(page)

      user1
      |> fill_in(Query.text_field("Message"), with: "Hello user2!")

      user1
      |> click(@send_button)

      user2
      |> log_in()

      user2
      |> visit(page)

      user2
      |> click(Query.link("Reply"))

      user2
      |> fill_in(Query.text_field("Message"), with: "Hello user1!")

      user2
      |> click(@send_button)

      user1
      |> assert_has(message("Hello user1!"))
      |> assert_has(css("p", text: "Online: 2"))

      user2
      |> assert_has(message("Hello user2!"))
      |> assert_has(css("p", text: "Online: 2"))
    end
  end
end
```

To see the results head over to the checks page [here](https://github.com/kainlite/tr/actions/runs/8310299885/job/22742643890)
<br />

##### **Running it in github actions** 

When you want Wallaby tests to run automatically as part of your continuous integration (CI) system, there's one important setup step: **installing browser drivers.**

```elixir
      - uses: nanasess/setup-chromedriver@v2
      - run: |
          export DISPLAY=:99
          chromedriver --url-base=/wd/hub &
          sudo Xvfb -ac :99 -screen 0 1920x1080x24 > /dev/null 2>&1 & # optional
```
see the full file [here](https://github.com/kainlite/tr/blob/master/.github/workflows/coverage.yaml#L38)
<br />

##### **The Journey Continues** 

This is a foundational introduction to Wallaby. In subsequent articles, we'll explore advanced features, best practices, and ways to streamline your testing process. if you found this tutorial useful please leave a comment.
<br />

##### **Closing notes**
Let me know if there is anything that you would like to see implemented or tested, explored and what not in here...
<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
