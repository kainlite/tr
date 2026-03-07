%{
  title: "SRE: Dependency Management and Graceful Degradation",
  author: "Gabriel Garrido",
  description: "We will explore how to manage service dependencies reliably, from circuit breakers and bulkhead patterns to graceful degradation strategies and dependency SLOs with practical Elixir and Kubernetes examples...",
  tags: ~w(sre reliability patterns elixir kubernetes),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In the previous articles we covered [SLIs and SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[incident management](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observability](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[capacity planning](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[secrets management](/blog/sre-secrets-management-in-kubernetes), and
[cost optimization](/blog/sre-cost-optimization-in-the-cloud). All of those focus on your own systems, your
own code, your own infrastructure. But here is the thing: your service does not exist in isolation.

<br />

Every HTTP call to another service, every database query, every message published to a queue, every third-party
API integration is a dependency. And every dependency is a potential failure point. When that payment gateway
goes down at 2am or that internal auth service starts returning 500s under load, what happens to your service?
Does it crash? Does it hang? Or does it gracefully handle the situation and keep serving users with reduced
functionality?

<br />

In this article we will cover how to think about dependencies as risk, implement circuit breakers, apply the
bulkhead pattern, handle timeouts and retries properly, build fallback strategies, set up dependency health
checks, map your dependency graph, define SLOs for your dependencies, and implement graceful degradation
using feature flags. All with practical Elixir and Kubernetes examples.

<br />

Let's get into it.

<br />

##### **Dependencies as risk**
Not all dependencies are created equal. The first step in managing them is understanding what kind of
dependency you are dealing with and what happens when it fails.

<br />

There are two fundamental types of dependencies:

<br />

> * **Hard dependencies**: Your service cannot function at all without them. If your database is down, you probably cannot serve any requests. If the auth service is unreachable, nobody can log in.
> * **Soft dependencies**: Your service can still function without them, possibly in a degraded state. If the recommendation engine is down, you can still show the product page without recommendations. If the analytics service is slow, you can fire and forget.

<br />

The danger comes from cascading failures. Consider this scenario: Service A calls Service B, which calls
Service C. Service C starts responding slowly because of a database issue. Service B's threads are now blocked
waiting for Service C. Service B's response times increase. Service A's threads are now blocked waiting for
Service B. Pretty soon, all three services are effectively down because of one slow database query in
Service C.

<br />

This is why dependency management matters so much. A single misbehaving dependency can take down your entire
system if you do not have the right protections in place. Let's look at the patterns that prevent this.

<br />

##### **Circuit breakers**
The circuit breaker pattern is borrowed from electrical engineering. When too much current flows through
a circuit, the breaker trips and stops the flow to prevent damage. In software, when a dependency starts
failing, the circuit breaker trips and stops sending requests to it, giving it time to recover.

<br />

A circuit breaker has three states:

<br />

> * **Closed**: Everything is normal. Requests flow through to the dependency. The breaker monitors failure rates.
> * **Open**: The dependency is failing. Requests are immediately rejected without calling the dependency. A timer starts.
> * **Half-open**: The timer has expired. A limited number of test requests are sent through. If they succeed, the breaker closes. If they fail, the breaker opens again.

<br />

Here is a practical implementation in Elixir using a GenServer:

```yaml
defmodule MyApp.CircuitBreaker do
  use GenServer

  @failure_threshold 5
  @reset_timeout_ms 30_000
  @half_open_max_calls 3

  defstruct [
    :name,
    state: :closed,
    failure_count: 0,
    success_count: 0,
    last_failure_time: nil,
    half_open_calls: 0
  ]

  # Client API

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, %__MODULE__{name: name}, name: name)
  end

  def call(name, func) when is_function(func, 0) do
    case GenServer.call(name, :check_state) do
      :ok ->
        try do
          result = func.()
          GenServer.cast(name, :record_success)
          {:ok, result}
        rescue
          error ->
            GenServer.cast(name, :record_failure)
            {:error, :dependency_error, error}
        end

      :open ->
        {:error, :circuit_open}
    end
  end

  # Server callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:check_state, _from, %{state: :closed} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:check_state, _from, %{state: :open} = state) do
    if time_since_last_failure(state) >= @reset_timeout_ms do
      {:reply, :ok, %{state | state: :half_open, half_open_calls: 0}}
    else
      {:reply, :open, state}
    end
  end

  def handle_call(:check_state, _from, %{state: :half_open} = state) do
    if state.half_open_calls < @half_open_max_calls do
      {:reply, :ok, %{state | half_open_calls: state.half_open_calls + 1}}
    else
      {:reply, :open, state}
    end
  end

  @impl true
  def handle_cast(:record_success, %{state: :half_open} = state) do
    {:noreply, %{state | state: :closed, failure_count: 0, success_count: 0}}
  end

  def handle_cast(:record_success, state) do
    {:noreply, %{state | success_count: state.success_count + 1}}
  end

  def handle_cast(:record_failure, state) do
    new_count = state.failure_count + 1
    now = System.monotonic_time(:millisecond)

    new_state =
      if new_count >= @failure_threshold do
        %{state | state: :open, failure_count: new_count, last_failure_time: now}
      else
        %{state | failure_count: new_count, last_failure_time: now}
      end

    {:noreply, new_state}
  end

  defp time_since_last_failure(%{last_failure_time: nil}), do: :infinity

  defp time_since_last_failure(%{last_failure_time: time}) do
    System.monotonic_time(:millisecond) - time
  end
end
```

<br />

And here is how you would use it in your application:

```yaml
# In your application supervision tree
children = [
  {MyApp.CircuitBreaker, name: :payment_service},
  {MyApp.CircuitBreaker, name: :auth_service},
  {MyApp.CircuitBreaker, name: :recommendation_engine}
]

# When making a call to a dependency
case MyApp.CircuitBreaker.call(:payment_service, fn ->
  HTTPoison.post("https://payments.internal/charge", body, headers)
end) do
  {:ok, %{status_code: 200, body: body}} ->
    {:ok, Jason.decode!(body)}

  {:error, :circuit_open} ->
    Logger.warning("Payment service circuit is open, using fallback")
    {:error, :service_unavailable}

  {:error, :dependency_error, error} ->
    Logger.error("Payment service error: #{inspect(error)}")
    {:error, :payment_failed}
end
```

<br />

The key insight here is that when the circuit is open, you fail fast. Instead of waiting 30 seconds for
a timeout from a dead service, you get an immediate response and can execute your fallback logic. This
protects both your service and the failing dependency, since you are not piling on more requests while
it is trying to recover.

<br />

##### **Bulkhead pattern**
The bulkhead pattern comes from ship design. Ships have compartments (bulkheads) so that if one section
floods, the rest of the ship stays afloat. In software, the idea is to isolate failure domains so that
a problem in one area does not affect everything else.

<br />

Elixir and the BEAM VM are particularly good at this because of process isolation. Each process is
independent, has its own memory, and if it crashes, other processes are unaffected. You can use this
to create natural bulkheads:

```yaml
defmodule MyApp.DependencyPool do
  @moduledoc """
  Manages separate process pools for each dependency,
  preventing one slow dependency from consuming all resources.
  """

  def child_spec(_opts) do
    children = [
      # Each dependency gets its own pool with its own limits
      pool_spec(:payment_pool, MyApp.PaymentWorker, size: 10, max_overflow: 5),
      pool_spec(:auth_pool, MyApp.AuthWorker, size: 20, max_overflow: 10),
      pool_spec(:recommendation_pool, MyApp.RecommendationWorker, size: 5, max_overflow: 2),
      pool_spec(:notification_pool, MyApp.NotificationWorker, size: 5, max_overflow: 5)
    ]

    %{
      id: __MODULE__,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end

  defp pool_spec(name, worker, opts) do
    pool_opts = [
      name: {:local, name},
      worker_module: worker,
      size: Keyword.fetch!(opts, :size),
      max_overflow: Keyword.fetch!(opts, :max_overflow)
    ]

    :poolboy.child_spec(name, pool_opts)
  end

  def call_dependency(pool_name, request, timeout \\ 5_000) do
    try do
      :poolboy.transaction(
        pool_name,
        fn worker -> GenServer.call(worker, {:request, request}, timeout) end,
        timeout
      )
    catch
      :exit, {:timeout, _} ->
        {:error, :pool_timeout}

      :exit, {:noproc, _} ->
        {:error, :pool_unavailable}
    end
  end
end
```

<br />

In Kubernetes, you get another layer of bulkheading through resource limits. Each service gets its own
CPU and memory budget, so a runaway dependency cannot starve other services:

```hcl
# k8s/deployment-with-bulkheads.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: app
          image: myapp:latest
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
---
# Separate resource quotas per namespace act as bulkheads
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dependency-quota
  namespace: payment-service
spec:
  hard:
    requests.cpu: "2"
    requests.memory: "4Gi"
    limits.cpu: "4"
    limits.memory: "8Gi"
    pods: "20"
---
# Network policies as another form of bulkhead
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: payment-service-policy
  namespace: payment-service
spec:
  podSelector:
    matchLabels:
      app: payment-service
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: my-app
      ports:
        - port: 8080
          protocol: TCP
```

<br />

The combination of Elixir process isolation, connection pools, Kubernetes resource limits, and network
policies gives you multiple layers of bulkheading. If the payment service goes haywire, it cannot
consume all the CPU on the node, cannot exhaust your application's connection pool for other services,
and cannot affect processes handling requests that do not need payments.

<br />

##### **Timeouts and retries**
Timeouts and retries seem straightforward, but getting them wrong is one of the most common causes of
cascading failures. Let's start with what not to do.

<br />

The naive approach looks like this:

```elixir
# DON'T do this - unbounded retries with no backoff
def fetch_user(user_id) do
  case HTTPoison.get("https://auth.internal/users/#{user_id}") do
    {:ok, response} -> {:ok, response}
    {:error, _} -> fetch_user(user_id)  # infinite retry loop!
  end
end
```

<br />

This creates a retry storm. If the auth service is down, every single request to your service will
generate infinite retries, making the problem worse. Here is the right way to do it with exponential
backoff and jitter:

```elixir
defmodule MyApp.Retry do
  @moduledoc """
  Retry with exponential backoff and jitter.
  """

  @default_opts [
    max_retries: 3,
    base_delay_ms: 100,
    max_delay_ms: 5_000,
    jitter: true
  ]

  def with_retry(func, opts \\ []) when is_function(func, 0) do
    opts = Keyword.merge(@default_opts, opts)
    do_retry(func, 0, opts)
  end

  defp do_retry(func, attempt, opts) do
    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} when attempt < opts[:max_retries] ->
        delay = calculate_delay(attempt, opts)
        Logger.info("Retry attempt #{attempt + 1} after #{delay}ms, reason: #{inspect(reason)}")
        Process.sleep(delay)
        do_retry(func, attempt + 1, opts)

      {:error, reason} ->
        Logger.warning("All #{opts[:max_retries]} retries exhausted, reason: #{inspect(reason)}")
        {:error, :retries_exhausted, reason}
    end
  end

  defp calculate_delay(attempt, opts) do
    # Exponential backoff: base * 2^attempt
    base_delay = opts[:base_delay_ms] * Integer.pow(2, attempt)

    # Cap at max delay
    capped_delay = min(base_delay, opts[:max_delay_ms])

    # Add jitter to prevent thundering herd
    if opts[:jitter] do
      jitter_range = div(capped_delay, 2)
      capped_delay - jitter_range + :rand.uniform(jitter_range * 2)
    else
      capped_delay
    end
  end
end
```

<br />

And here is how you combine retries with the circuit breaker:

```elixir
defmodule MyApp.ResilientClient do
  alias MyApp.{CircuitBreaker, Retry}

  def call_service(circuit_name, request_fn, opts \\ []) do
    CircuitBreaker.call(circuit_name, fn ->
      Retry.with_retry(fn ->
        case request_fn.() do
          {:ok, %{status_code: status} = resp} when status in 200..299 ->
            {:ok, resp}

          {:ok, %{status_code: status}} when status in [429, 503] ->
            # Retryable server errors
            {:error, :retryable}

          {:ok, %{status_code: status} = resp} ->
            # Non-retryable client errors
            {:ok, resp}

          {:error, %HTTPoison.Error{reason: reason}} ->
            {:error, reason}
        end
      end, opts)
    end)
  end
end

# Usage
MyApp.ResilientClient.call_service(:payment_service, fn ->
  HTTPoison.post(url, body, headers, recv_timeout: 5_000)
end, max_retries: 2, base_delay_ms: 200)
```

<br />

There are a few important things to note here:

<br />

> * **Always set timeouts**: Never make a network call without a timeout. A default timeout of 5 seconds is a reasonable starting point.
> * **Jitter is essential**: Without jitter, all retries happen at the same time, creating a thundering herd. Adding randomness spreads them out.
> * **Not everything is retryable**: Only retry on transient errors (timeouts, 503s, connection resets). Do not retry on 400s or 404s.
> * **Set a retry budget**: Limit the total number of retries across all requests, not just per request. If 50% of your requests are retrying, something is very wrong.
> * **Combine with circuit breakers**: Retries without a circuit breaker can make a bad situation worse. The circuit breaker stops the bleeding when retries are not helping.

<br />

##### **Fallback strategies**
When a dependency fails and the circuit breaker is open, you need a plan B. Fallback strategies define
what your service does when it cannot reach a dependency. The right strategy depends on the dependency
and what your users expect.

<br />

Here are the most common fallback patterns:

<br />

**1. Cache fallback**

Serve stale data from a local cache when the source is unavailable:

```hcl
defmodule MyApp.CacheFallback do
  use GenServer

  @cache_ttl_ms 300_000  # 5 minutes
  @stale_ttl_ms 3_600_000  # 1 hour - stale data is better than no data

  def get_user_profile(user_id) do
    case MyApp.ResilientClient.call_service(:user_service, fn ->
      HTTPoison.get("https://users.internal/profiles/#{user_id}", [],
        recv_timeout: 3_000
      )
    end) do
      {:ok, %{status_code: 200, body: body}} ->
        profile = Jason.decode!(body)
        cache_put(user_id, profile)
        {:ok, profile}

      {:error, _reason} ->
        case cache_get(user_id) do
          {:ok, profile, :fresh} ->
            {:ok, profile}

          {:ok, profile, :stale} ->
            Logger.info("Serving stale profile for user #{user_id}")
            {:ok, Map.put(profile, :_stale, true)}

          :miss ->
            {:error, :unavailable}
        end
    end
  end

  defp cache_put(key, value) do
    :ets.insert(:profile_cache, {key, value, System.monotonic_time(:millisecond)})
  end

  defp cache_get(key) do
    case :ets.lookup(:profile_cache, key) do
      [{^key, value, cached_at}] ->
        age = System.monotonic_time(:millisecond) - cached_at

        cond do
          age < @cache_ttl_ms -> {:ok, value, :fresh}
          age < @stale_ttl_ms -> {:ok, value, :stale}
          true -> :miss
        end

      [] ->
        :miss
    end
  end
end
```

<br />

**2. Default response fallback**

Return a sensible default when the dependency is unavailable:

```elixir
defmodule MyApp.RecommendationService do
  @default_recommendations [
    %{id: "popular-1", title: "Most Popular Item", reason: "trending"},
    %{id: "popular-2", title: "Editor's Pick", reason: "curated"},
    %{id: "popular-3", title: "New Arrival", reason: "new"}
  ]

  def get_recommendations(user_id) do
    case MyApp.ResilientClient.call_service(:recommendation_engine, fn ->
      HTTPoison.get("https://recommendations.internal/for/#{user_id}", [],
        recv_timeout: 2_000
      )
    end) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:error, _reason} ->
        Logger.info("Recommendation engine unavailable, using defaults")
        {:ok, @default_recommendations}
    end
  end
end
```

<br />

**3. Degraded mode fallback**

Disable non-essential features and communicate the degraded state to users:

```yaml
defmodule MyApp.DegradedMode do
  @moduledoc """
  Tracks which features are operating in degraded mode
  and provides appropriate responses.
  """

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def mark_degraded(feature, reason) do
    GenServer.cast(__MODULE__, {:mark_degraded, feature, reason})
  end

  def mark_healthy(feature) do
    GenServer.cast(__MODULE__, {:mark_healthy, feature})
  end

  def degraded?(feature) do
    GenServer.call(__MODULE__, {:degraded?, feature})
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:mark_degraded, feature, reason}, state) do
    Logger.warning("Feature #{feature} entering degraded mode: #{reason}")
    {:noreply, Map.put(state, feature, %{reason: reason, since: DateTime.utc_now()})}
  end

  def handle_cast({:mark_healthy, feature}, state) do
    if Map.has_key?(state, feature) do
      Logger.info("Feature #{feature} recovered from degraded mode")
    end

    {:noreply, Map.delete(state, feature)}
  end

  @impl true
  def handle_call({:degraded?, feature}, _from, state) do
    {:reply, Map.has_key?(state, feature), state}
  end

  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end
end
```

<br />

**4. Static fallback**

For read-heavy services, pre-compute static responses that can be served when everything else fails:

```elixir
defmodule MyApp.StaticFallback do
  @moduledoc """
  Serves pre-computed static content when dynamic services fail.
  Updated periodically by a background job.
  """

  @static_dir "priv/static/fallbacks"

  def get_homepage_data do
    case fetch_dynamic_homepage() do
      {:ok, data} -> {:ok, data}
      {:error, _} -> load_static_fallback("homepage.json")
    end
  end

  defp load_static_fallback(filename) do
    path = Path.join(@static_dir, filename)

    case File.read(path) do
      {:ok, content} ->
        Logger.info("Serving static fallback: #{filename}")
        {:ok, Jason.decode!(content)}

      {:error, _} ->
        {:error, :no_fallback_available}
    end
  end
end
```

<br />

The important thing is to plan your fallbacks before you need them. During an incident is not the time
to figure out what your service should do when the recommendation engine is down. Document your fallback
strategy for each dependency and test it regularly.

<br />

##### **Health checks for dependencies**
Kubernetes gives you three types of probes, and understanding when to use each one is critical for
dependency management:

<br />

> * **Liveness probes**: "Is this process alive?" If it fails, Kubernetes restarts the container. This should check your process, not your dependencies. If your database is down, restarting your app will not fix it.
> * **Readiness probes**: "Can this pod serve traffic?" If it fails, Kubernetes removes the pod from the service endpoints. This is where you check dependencies. If you cannot reach the database, you should not receive traffic.
> * **Startup probes**: "Has this pod finished starting up?" Gives slow-starting containers time to initialize before liveness and readiness checks kick in.

<br />

Here is a dependency-aware health check implementation:

```elixir
defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  @hard_dependencies [:database, :cache]
  @soft_dependencies [:recommendation_engine, :notification_service]

  # Liveness: only checks if the process is alive
  def liveness(conn, _params) do
    json(conn, %{status: "alive", timestamp: DateTime.utc_now()})
  end

  # Readiness: checks hard dependencies
  def readiness(conn, _params) do
    checks =
      @hard_dependencies
      |> Enum.map(fn dep -> {dep, check_dependency(dep)} end)
      |> Map.new()

    all_healthy = Enum.all?(checks, fn {_dep, status} -> status == :ok end)

    if all_healthy do
      conn
      |> put_status(200)
      |> json(%{status: "ready", checks: format_checks(checks)})
    else
      conn
      |> put_status(503)
      |> json(%{status: "not_ready", checks: format_checks(checks)})
    end
  end

  # Full status: checks everything including soft dependencies
  def status(conn, _params) do
    hard_checks =
      @hard_dependencies
      |> Enum.map(fn dep -> {dep, check_dependency(dep)} end)
      |> Map.new()

    soft_checks =
      @soft_dependencies
      |> Enum.map(fn dep -> {dep, check_dependency(dep)} end)
      |> Map.new()

    degraded_features = MyApp.DegradedMode.status()

    all_hard_healthy = Enum.all?(hard_checks, fn {_dep, s} -> s == :ok end)
    all_soft_healthy = Enum.all?(soft_checks, fn {_dep, s} -> s == :ok end)

    overall =
      cond do
        not all_hard_healthy -> "unhealthy"
        not all_soft_healthy -> "degraded"
        true -> "healthy"
      end

    conn
    |> put_status(if(all_hard_healthy, do: 200, else: 503))
    |> json(%{
      status: overall,
      hard_dependencies: format_checks(hard_checks),
      soft_dependencies: format_checks(soft_checks),
      degraded_features: degraded_features
    })
  end

  defp check_dependency(:database) do
    case Ecto.Adapters.SQL.query(MyApp.Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  defp check_dependency(:cache) do
    case Redix.command(:redix, ["PING"]) do
      {:ok, "PONG"} -> :ok
      _ -> :error
    end
  end

  defp check_dependency(name) do
    case MyApp.CircuitBreaker.call(name, fn ->
      HTTPoison.get("https://#{name}.internal/health", [], recv_timeout: 2_000)
    end) do
      {:ok, %{status_code: 200}} -> :ok
      _ -> :error
    end
  end

  defp format_checks(checks) do
    Map.new(checks, fn {dep, status} ->
      {dep, %{status: status, checked_at: DateTime.utc_now()}}
    end)
  end
end
```

<br />

And the corresponding Kubernetes probe configuration:

```yaml
# k8s/deployment-with-probes.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: app
          image: myapp:latest
          ports:
            - containerPort: 4000
          livenessProbe:
            httpGet:
              path: /health/live
              port: 4000
            initialDelaySeconds: 10
            periodSeconds: 15
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 4000
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 2
          startupProbe:
            httpGet:
              path: /health/live
              port: 4000
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 30
```

<br />

The critical mistake people make is putting dependency checks in liveness probes. If your database goes
down and your liveness probe checks the database, Kubernetes will restart all your pods. Now you have a
database outage and an application restart storm happening at the same time. Keep liveness probes simple
and use readiness probes for dependency checks.

<br />

##### **Dependency mapping**
Before you can manage your dependencies, you need to see them. A dependency map is a visual representation
of all the services in your system and how they connect. This sounds obvious, but you would be surprised
how many teams do not have a clear picture of their dependency graph.

<br />

Here is a simple way to document your dependencies:

```yaml
defmodule MyApp.DependencyMap do
  @moduledoc """
  Declares all service dependencies with their properties.
  This serves as living documentation and powers runtime decisions.
  """

  @dependencies %{
    database: %{
      type: :hard,
      url: "postgresql://db.internal:5432/myapp",
      timeout_ms: 5_000,
      circuit_breaker: false,  # managed by Ecto pool
      fallback: :none,
      slo_target: 0.999,
      owner_team: "platform",
      criticality: :critical
    },
    cache: %{
      type: :hard,
      url: "redis://cache.internal:6379",
      timeout_ms: 1_000,
      circuit_breaker: true,
      fallback: :bypass,  # skip cache, hit database directly
      slo_target: 0.999,
      owner_team: "platform",
      criticality: :critical
    },
    auth_service: %{
      type: :hard,
      url: "https://auth.internal:8443",
      timeout_ms: 3_000,
      circuit_breaker: true,
      fallback: :cached_tokens,
      slo_target: 0.999,
      owner_team: "identity",
      criticality: :critical
    },
    payment_service: %{
      type: :hard,
      url: "https://payments.internal:8080",
      timeout_ms: 10_000,
      circuit_breaker: true,
      fallback: :queue_for_retry,
      slo_target: 0.999,
      owner_team: "payments",
      criticality: :high
    },
    recommendation_engine: %{
      type: :soft,
      url: "https://recommendations.internal:8080",
      timeout_ms: 2_000,
      circuit_breaker: true,
      fallback: :static_defaults,
      slo_target: 0.99,
      owner_team: "ml",
      criticality: :low
    },
    notification_service: %{
      type: :soft,
      url: "https://notifications.internal:8080",
      timeout_ms: 5_000,
      circuit_breaker: true,
      fallback: :queue_for_retry,
      slo_target: 0.99,
      owner_team: "comms",
      criticality: :medium
    },
    analytics_service: %{
      type: :soft,
      url: "https://analytics.internal:8080",
      timeout_ms: 1_000,
      circuit_breaker: true,
      fallback: :fire_and_forget,
      slo_target: 0.95,
      owner_team: "data",
      criticality: :low
    }
  }

  def all, do: @dependencies

  def hard_dependencies do
    @dependencies
    |> Enum.filter(fn {_name, config} -> config.type == :hard end)
    |> Map.new()
  end

  def soft_dependencies do
    @dependencies
    |> Enum.filter(fn {_name, config} -> config.type == :soft end)
    |> Map.new()
  end

  def get(name), do: Map.get(@dependencies, name)

  def critical_path do
    @dependencies
    |> Enum.filter(fn {_name, config} -> config.criticality in [:critical, :high] end)
    |> Enum.sort_by(fn {_name, config} -> config.criticality end)
    |> Map.new()
  end
end
```

<br />

This kind of declarative dependency map serves multiple purposes: it documents what you depend on, it
powers your circuit breaker configuration, it informs your health checks, and it tells on-call engineers
which team to contact when a dependency fails.

<br />

You can also generate a visual graph from this data:

```elixir
defmodule MyApp.DependencyGraph do
  @moduledoc """
  Generates a Mermaid diagram from the dependency map.
  """

  def to_mermaid do
    deps = MyApp.DependencyMap.all()

    nodes =
      deps
      |> Enum.map(fn {name, config} ->
        style = if config.type == :hard, do: ":::critical", else: ":::optional"
        "  #{name}[#{name}]#{style}"
      end)
      |> Enum.join("\n")

    edges =
      deps
      |> Enum.map(fn {name, config} ->
        arrow = if config.type == :hard, do: "==>", else: "-->"
        "  my_app #{arrow} #{name}"
      end)
      |> Enum.join("\n")

    """
    graph LR
      my_app[My App]
    #{nodes}
    #{edges}
      classDef critical fill:#ff6b6b,stroke:#333
      classDef optional fill:#4ecdc4,stroke:#333
    """
  end
end
```

<br />

##### **SLOs for dependencies**
Just as you set SLOs for your own services, you should track the reliability of your dependencies. This
gives you data to make decisions about architecture, fallback strategies, and even vendor selection.

<br />

Here is how to think about dependency SLOs:

<br />

> * **Internal dependencies**: You can usually negotiate SLOs with the team that owns the service. "We need your auth service to have 99.9% availability and p99 latency under 200ms."
> * **External dependencies**: You are at the mercy of the provider's SLA. Track actual performance against their stated SLA, because reality often differs.
> * **Your effective SLO**: Your service's SLO cannot be higher than the SLO of your weakest hard dependency. If your database SLO is 99.9%, your service SLO cannot realistically be 99.95%.

<br />

Here is a Prometheus-based approach to tracking dependency SLOs:

```yaml
# prometheus-rules-dependency-slos.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dependency-slos
  namespace: monitoring
spec:
  groups:
    - name: dependency.slos
      interval: 30s
      rules:
        # Track success rate per dependency
        - record: dependency:requests:success_rate5m
          expr: |
            sum by (dependency) (
              rate(dependency_requests_total{status="success"}[5m])
            ) /
            sum by (dependency) (
              rate(dependency_requests_total[5m])
            )

        # Track latency per dependency
        - record: dependency:latency:p99_5m
          expr: |
            histogram_quantile(0.99,
              sum by (dependency, le) (
                rate(dependency_request_duration_seconds_bucket[5m])
              )
            )

        # Dependency error budget remaining (30-day window)
        - record: dependency:error_budget:remaining
          expr: |
            1 - (
              (1 - avg_over_time(dependency:requests:success_rate5m[30d]))
              /
              (1 - 0.999)
            )

    - name: dependency.alerts
      rules:
        - alert: DependencyErrorBudgetBurning
          expr: dependency:error_budget:remaining < 0.5
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Dependency {{ $labels.dependency }} has consumed 50% of error budget"
            description: "Error budget remaining: {{ $value | humanizePercentage }}"

        - alert: DependencyErrorBudgetExhausted
          expr: dependency:error_budget:remaining < 0.1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Dependency {{ $labels.dependency }} error budget nearly exhausted"
            description: "Error budget remaining: {{ $value | humanizePercentage }}"
```

<br />

To emit these metrics from your Elixir application, instrument your dependency calls:

```elixir
defmodule MyApp.DependencyTelemetry do
  @moduledoc """
  Emits telemetry events for all dependency calls,
  which are then exposed as Prometheus metrics.
  """

  def track_call(dependency, func) when is_function(func, 0) do
    start_time = System.monotonic_time()

    result =
      try do
        func.()
      rescue
        error ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:dependency, :call, :exception],
            %{duration: duration},
            %{dependency: dependency, error: inspect(error)}
          )

          reraise error, __STACKTRACE__
      end

    duration = System.monotonic_time() - start_time
    status = if match?({:ok, _}, result), do: "success", else: "failure"

    :telemetry.execute(
      [:dependency, :call, :stop],
      %{duration: duration},
      %{dependency: dependency, status: status}
    )

    result
  end
end
```

<br />

When you track dependency SLOs over time, you start seeing patterns. Maybe your recommendation engine
drops below its SLO every Monday morning when the ML team runs batch jobs. Maybe the payment gateway
has reliability dips on the last day of the month. These patterns help you plan better fallback
strategies and have informed conversations with dependency owners.

<br />

##### **Graceful degradation patterns**
Graceful degradation is the art of doing less, well, instead of doing everything, poorly. When your
system is under stress or a dependency is failing, you intentionally reduce functionality to protect
the core user experience.

<br />

Think of it as progressive levels of degradation:

<br />

> 1. **Level 0 - Normal**: All features working, all dependencies healthy
> 2. **Level 1 - Reduced**: Non-essential features disabled (recommendations, analytics, personalization)
> 3. **Level 2 - Core only**: Only critical path features remain (browse, search, purchase)
> 4. **Level 3 - Minimal**: Read-only mode or static content only
> 5. **Level 4 - Maintenance**: Service is down, show a maintenance page

<br />

Here is how to implement progressive degradation:

```yaml
defmodule MyApp.DegradationLevel do
  @moduledoc """
  Manages the current degradation level based on
  dependency health and system load.
  """

  use GenServer

  @levels [:normal, :reduced, :core_only, :minimal, :maintenance]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :normal, name: __MODULE__)
  end

  def current_level do
    GenServer.call(__MODULE__, :current_level)
  end

  def set_level(level) when level in @levels do
    GenServer.call(__MODULE__, {:set_level, level})
  end

  def feature_available?(feature) do
    level = current_level()
    feature_level = feature_minimum_level(feature)
    level_index(level) <= level_index(feature_level)
  end

  @impl true
  def init(level), do: {:ok, level}

  @impl true
  def handle_call(:current_level, _from, level), do: {:reply, level, level}

  def handle_call({:set_level, new_level}, _from, old_level) do
    if new_level != old_level do
      Logger.warning(
        "Degradation level changed: #{old_level} -> #{new_level}"
      )

      :telemetry.execute(
        [:app, :degradation, :level_change],
        %{},
        %{old_level: old_level, new_level: new_level}
      )
    end

    {:reply, :ok, new_level}
  end

  # Define which features are available at each level
  defp feature_minimum_level(:recommendations), do: :normal
  defp feature_minimum_level(:analytics_tracking), do: :normal
  defp feature_minimum_level(:personalization), do: :normal
  defp feature_minimum_level(:search_suggestions), do: :reduced
  defp feature_minimum_level(:user_reviews), do: :reduced
  defp feature_minimum_level(:search), do: :core_only
  defp feature_minimum_level(:browse_catalog), do: :core_only
  defp feature_minimum_level(:checkout), do: :core_only
  defp feature_minimum_level(:static_content), do: :minimal
  defp feature_minimum_level(_), do: :normal

  defp level_index(:normal), do: 0
  defp level_index(:reduced), do: 1
  defp level_index(:core_only), do: 2
  defp level_index(:minimal), do: 3
  defp level_index(:maintenance), do: 4
end
```

<br />

You can then use this in your controllers and LiveViews:

```elixir
defmodule MyAppWeb.ProductLive do
  use MyAppWeb, :live_view

  alias MyApp.DegradationLevel

  def mount(%{"id" => id}, _session, socket) do
    product = MyApp.Catalog.get_product!(id)

    socket =
      socket
      |> assign(:product, product)
      |> assign(:degradation_level, DegradationLevel.current_level())
      |> maybe_load_recommendations(id)
      |> maybe_load_reviews(id)

    {:ok, socket}
  end

  defp maybe_load_recommendations(socket, product_id) do
    if DegradationLevel.feature_available?(:recommendations) do
      case MyApp.RecommendationService.get_recommendations(product_id) do
        {:ok, recs} -> assign(socket, :recommendations, recs)
        {:error, _} -> assign(socket, :recommendations, [])
      end
    else
      assign(socket, :recommendations, [])
    end
  end

  defp maybe_load_reviews(socket, product_id) do
    if DegradationLevel.feature_available?(:user_reviews) do
      case MyApp.Reviews.list_for_product(product_id) do
        {:ok, reviews} -> assign(socket, :reviews, reviews)
        {:error, _} -> assign(socket, :reviews, [])
      end
    else
      assign(socket, :reviews, [])
    end
  end
end
```

<br />

##### **Feature flags for degradation**
Feature flags are the mechanism that makes graceful degradation practical at runtime. Instead of deploying
new code to disable a feature, you flip a flag and the change takes effect immediately.

<br />

Here is a simple but effective feature flag implementation in Elixir:

```yaml
defmodule MyApp.FeatureFlags do
  @moduledoc """
  Simple ETS-based feature flags for runtime toggling.
  Supports boolean flags and percentage rollouts.
  """

  use GenServer

  @table :feature_flags

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    # Load default flags
    load_defaults()

    {:ok, %{}}
  end

  # Check if a feature is enabled
  def enabled?(flag) do
    case :ets.lookup(@table, flag) do
      [{^flag, true}] -> true
      [{^flag, false}] -> false
      [{^flag, percentage}] when is_integer(percentage) ->
        :rand.uniform(100) <= percentage
      [] -> true  # default to enabled if flag not found
    end
  end

  # Enable a feature
  def enable(flag) do
    :ets.insert(@table, {flag, true})
    Logger.info("Feature flag enabled: #{flag}")
    :ok
  end

  # Disable a feature
  def disable(flag) do
    :ets.insert(@table, {flag, false})
    Logger.warning("Feature flag disabled: #{flag}")
    :ok
  end

  # Set percentage rollout
  def set_percentage(flag, percentage) when percentage in 0..100 do
    :ets.insert(@table, {flag, percentage})
    Logger.info("Feature flag #{flag} set to #{percentage}%")
    :ok
  end

  # List all flags and their states
  def list_all do
    :ets.tab2list(@table)
    |> Map.new()
  end

  defp load_defaults do
    defaults = [
      {:recommendations, true},
      {:analytics_tracking, true},
      {:personalization, true},
      {:search_suggestions, true},
      {:user_reviews, true},
      {:new_checkout_flow, false},
      {:experimental_search, 10}  # 10% rollout
    ]

    Enum.each(defaults, fn {flag, value} ->
      :ets.insert(@table, {flag, value})
    end)
  end
end
```

<br />

And a Phoenix LiveDashboard page to manage flags at runtime:

```elixir
defmodule MyAppWeb.FeatureFlagController do
  use MyAppWeb, :controller

  plug :require_admin

  def index(conn, _params) do
    flags = MyApp.FeatureFlags.list_all()
    json(conn, %{flags: flags})
  end

  def update(conn, %{"flag" => flag, "value" => "true"}) do
    MyApp.FeatureFlags.enable(String.to_existing_atom(flag))
    json(conn, %{status: "ok", flag: flag, value: true})
  end

  def update(conn, %{"flag" => flag, "value" => "false"}) do
    MyApp.FeatureFlags.disable(String.to_existing_atom(flag))
    json(conn, %{status: "ok", flag: flag, value: false})
  end

  def update(conn, %{"flag" => flag, "value" => value}) do
    case Integer.parse(value) do
      {percentage, ""} when percentage in 0..100 ->
        MyApp.FeatureFlags.set_percentage(
          String.to_existing_atom(flag),
          percentage
        )
        json(conn, %{status: "ok", flag: flag, value: percentage})

      _ ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid value"})
    end
  end

  defp require_admin(conn, _opts) do
    # Your admin authentication logic here
    conn
  end
end
```

<br />

The beauty of combining feature flags with the degradation level system is that you can automate the
response to dependency failures. When the circuit breaker for the recommendation engine opens, you
automatically disable the recommendations feature flag. When it recovers, you re-enable it:

```yaml
defmodule MyApp.DegradationAutomation do
  @moduledoc """
  Automatically adjusts feature flags and degradation level
  based on dependency health signals.
  """

  use GenServer

  @check_interval_ms 10_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_dependencies, state) do
    deps = MyApp.DependencyMap.all()

    Enum.each(deps, fn {name, config} ->
      case check_health(name) do
        :healthy ->
          maybe_restore_features(name, config)

        :unhealthy ->
          maybe_degrade_features(name, config)
      end
    end)

    update_overall_degradation_level()
    schedule_check()
    {:noreply, state}
  end

  defp check_health(dep_name) do
    case MyApp.CircuitBreaker.call(dep_name, fn ->
      # lightweight health check
      :ok
    end) do
      {:ok, _} -> :healthy
      {:error, :circuit_open} -> :unhealthy
      {:error, _, _} -> :unhealthy
    end
  end

  defp maybe_degrade_features(dep_name, _config) do
    features_for_dependency(dep_name)
    |> Enum.each(fn feature ->
      MyApp.FeatureFlags.disable(feature)
      MyApp.DegradedMode.mark_degraded(feature, "dependency #{dep_name} unhealthy")
    end)
  end

  defp maybe_restore_features(dep_name, _config) do
    features_for_dependency(dep_name)
    |> Enum.each(fn feature ->
      MyApp.FeatureFlags.enable(feature)
      MyApp.DegradedMode.mark_healthy(feature)
    end)
  end

  defp features_for_dependency(:recommendation_engine), do: [:recommendations]
  defp features_for_dependency(:notification_service), do: [:email_notifications]
  defp features_for_dependency(:analytics_service), do: [:analytics_tracking]
  defp features_for_dependency(_), do: []

  defp update_overall_degradation_level do
    hard_deps = MyApp.DependencyMap.hard_dependencies()
    soft_deps = MyApp.DependencyMap.soft_dependencies()

    hard_healthy = Enum.all?(hard_deps, fn {name, _} -> check_health(name) == :healthy end)
    soft_healthy = Enum.all?(soft_deps, fn {name, _} -> check_health(name) == :healthy end)

    level =
      cond do
        not hard_healthy -> :core_only
        not soft_healthy -> :reduced
        true -> :normal
      end

    MyApp.DegradationLevel.set_level(level)
  end

  defp schedule_check do
    Process.send_after(self(), :check_dependencies, @check_interval_ms)
  end
end
```

<br />

##### **Closing notes**
Dependency management and graceful degradation are not optional for any service that aims to be reliable.
Every external call is a risk, and the patterns we covered (circuit breakers, bulkheads, timeouts with
backoff, fallback strategies, dependency health checks, dependency mapping, dependency SLOs, progressive
degradation levels, and feature flags) give you a comprehensive toolkit to manage that risk.

<br />

The key takeaways are:

<br />

> 1. **Know your dependencies**: Map them, classify them as hard or soft, and document your fallback strategy for each one
> 2. **Fail fast**: Use circuit breakers and timeouts so that a slow dependency does not become your problem
> 3. **Isolate failures**: Use bulkheads (process pools, resource limits, network policies) to contain the blast radius
> 4. **Have a plan B**: Implement fallback strategies before you need them, not during an incident
> 5. **Degrade gracefully**: It is better to serve a product page without recommendations than to serve a 500 error
> 6. **Automate the response**: Use feature flags and automation to respond to dependency failures in seconds, not minutes

<br />

Start with the most critical path in your system. Identify the hard dependencies, add circuit breakers
and timeouts, implement one fallback strategy, and test it. You do not need to implement everything at
once. Incremental improvements compound over time.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Gestión de Dependencias y Degradación Elegante",
  author: "Gabriel Garrido",
  description: "Vamos a explorar cómo gestionar dependencias de servicios de forma confiable, desde circuit breakers y patrones bulkhead hasta estrategias de degradación elegante y SLOs de dependencias con ejemplos prácticos en Elixir y Kubernetes...",
  tags: ~w(sre reliability patterns elixir kubernetes),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En los artículos anteriores cubrimos [SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[gestión de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observabilidad](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[ingeniería del caos](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[planificación de capacidad](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[gestión de secretos](/blog/sre-secrets-management-in-kubernetes) y
[optimización de costos](/blog/sre-cost-optimization-in-the-cloud). Todos esos se enfocan en tus propios
sistemas, tu propio código, tu propia infraestructura. Pero la cosa es así: tu servicio no existe de forma
aislada.

<br />

Cada llamada HTTP a otro servicio, cada consulta a la base de datos, cada mensaje publicado a una cola, cada
integración con una API de terceros es una dependencia. Y cada dependencia es un punto potencial de falla.
Cuando ese gateway de pagos se cae a las 2 de la mañana o ese servicio interno de autenticación empieza a
devolver 500s bajo carga, ¿qué le pasa a tu servicio? ¿Se cae? ¿Se cuelga? ¿O maneja la situación de forma
elegante y sigue atendiendo usuarios con funcionalidad reducida?

<br />

En este artículo vamos a cubrir cómo pensar en las dependencias como riesgo, implementar circuit breakers,
aplicar el patrón bulkhead, manejar timeouts y reintentos correctamente, construir estrategias de fallback,
configurar health checks de dependencias, mapear tu grafo de dependencias, definir SLOs para tus
dependencias e implementar degradación elegante usando feature flags. Todo con ejemplos prácticos en Elixir
y Kubernetes.

<br />

Vamos al tema.

<br />

##### **Dependencias como riesgo**
No todas las dependencias son iguales. El primer paso para gestionarlas es entender con qué tipo de
dependencia estás tratando y qué pasa cuando falla.

<br />

Hay dos tipos fundamentales de dependencias:

<br />

> * **Dependencias duras**: Tu servicio no puede funcionar en absoluto sin ellas. Si tu base de datos se cae, probablemente no podés servir ninguna request. Si el servicio de autenticación no responde, nadie puede iniciar sesión.
> * **Dependencias blandas**: Tu servicio puede seguir funcionando sin ellas, posiblemente en un estado degradado. Si el motor de recomendaciones se cae, igual podés mostrar la página del producto sin recomendaciones. Si el servicio de analytics anda lento, podés hacer fire and forget.

<br />

El peligro viene de las fallas en cascada. Considerá este escenario: el Servicio A llama al Servicio B, que
llama al Servicio C. El Servicio C empieza a responder lento por un problema en la base de datos. Los threads
del Servicio B quedan bloqueados esperando al Servicio C. Los tiempos de respuesta del Servicio B aumentan.
Los threads del Servicio A quedan bloqueados esperando al Servicio B. En poco tiempo, los tres servicios
están efectivamente caídos por una sola consulta lenta en la base de datos del Servicio C.

<br />

Por eso la gestión de dependencias importa tanto. Una sola dependencia que se porta mal puede tirar abajo
todo tu sistema si no tenés las protecciones adecuadas. Veamos los patrones que previenen esto.

<br />

##### **Circuit breakers**
El patrón circuit breaker viene de la ingeniería eléctrica. Cuando fluye demasiada corriente por un
circuito, el interruptor se dispara y corta el flujo para prevenir daños. En software, cuando una
dependencia empieza a fallar, el circuit breaker se dispara y deja de enviar requests, dándole tiempo
para recuperarse.

<br />

Un circuit breaker tiene tres estados:

<br />

> * **Cerrado**: Todo normal. Las requests fluyen hacia la dependencia. El breaker monitorea tasas de error.
> * **Abierto**: La dependencia está fallando. Las requests se rechazan inmediatamente sin llamar a la dependencia. Se inicia un timer.
> * **Semi-abierto**: El timer expiró. Se envía un número limitado de requests de prueba. Si tienen éxito, el breaker se cierra. Si fallan, el breaker se abre de nuevo.

<br />

Acá hay una implementación práctica en Elixir usando un GenServer:

```yaml
defmodule MyApp.CircuitBreaker do
  use GenServer

  @failure_threshold 5
  @reset_timeout_ms 30_000
  @half_open_max_calls 3

  defstruct [
    :name,
    state: :closed,
    failure_count: 0,
    success_count: 0,
    last_failure_time: nil,
    half_open_calls: 0
  ]

  # API del cliente

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, %__MODULE__{name: name}, name: name)
  end

  def call(name, func) when is_function(func, 0) do
    case GenServer.call(name, :check_state) do
      :ok ->
        try do
          result = func.()
          GenServer.cast(name, :record_success)
          {:ok, result}
        rescue
          error ->
            GenServer.cast(name, :record_failure)
            {:error, :dependency_error, error}
        end

      :open ->
        {:error, :circuit_open}
    end
  end

  # Callbacks del servidor

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:check_state, _from, %{state: :closed} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:check_state, _from, %{state: :open} = state) do
    if time_since_last_failure(state) >= @reset_timeout_ms do
      {:reply, :ok, %{state | state: :half_open, half_open_calls: 0}}
    else
      {:reply, :open, state}
    end
  end

  def handle_call(:check_state, _from, %{state: :half_open} = state) do
    if state.half_open_calls < @half_open_max_calls do
      {:reply, :ok, %{state | half_open_calls: state.half_open_calls + 1}}
    else
      {:reply, :open, state}
    end
  end

  @impl true
  def handle_cast(:record_success, %{state: :half_open} = state) do
    {:noreply, %{state | state: :closed, failure_count: 0, success_count: 0}}
  end

  def handle_cast(:record_success, state) do
    {:noreply, %{state | success_count: state.success_count + 1}}
  end

  def handle_cast(:record_failure, state) do
    new_count = state.failure_count + 1
    now = System.monotonic_time(:millisecond)

    new_state =
      if new_count >= @failure_threshold do
        %{state | state: :open, failure_count: new_count, last_failure_time: now}
      else
        %{state | failure_count: new_count, last_failure_time: now}
      end

    {:noreply, new_state}
  end

  defp time_since_last_failure(%{last_failure_time: nil}), do: :infinity

  defp time_since_last_failure(%{last_failure_time: time}) do
    System.monotonic_time(:millisecond) - time
  end
end
```

<br />

Y acá está cómo lo usarías en tu aplicación:

```yaml
# En tu árbol de supervisión
children = [
  {MyApp.CircuitBreaker, name: :payment_service},
  {MyApp.CircuitBreaker, name: :auth_service},
  {MyApp.CircuitBreaker, name: :recommendation_engine}
]

# Cuando hacés una llamada a una dependencia
case MyApp.CircuitBreaker.call(:payment_service, fn ->
  HTTPoison.post("https://payments.internal/charge", body, headers)
end) do
  {:ok, %{status_code: 200, body: body}} ->
    {:ok, Jason.decode!(body)}

  {:error, :circuit_open} ->
    Logger.warning("Circuito del servicio de pagos abierto, usando fallback")
    {:error, :service_unavailable}

  {:error, :dependency_error, error} ->
    Logger.error("Error del servicio de pagos: #{inspect(error)}")
    {:error, :payment_failed}
end
```

<br />

La idea clave acá es que cuando el circuito está abierto, fallás rápido. En vez de esperar 30 segundos
por un timeout de un servicio muerto, obtenés una respuesta inmediata y podés ejecutar tu lógica de
fallback. Esto protege tanto a tu servicio como a la dependencia que está fallando, ya que no le estás
apilando más requests mientras intenta recuperarse.

<br />

##### **Patrón bulkhead**
El patrón bulkhead viene del diseño de barcos. Los barcos tienen compartimentos (mamparos) para que si
una sección se inunda, el resto del barco se mantenga a flote. En software, la idea es aislar dominios de
falla para que un problema en un área no afecte todo lo demás.

<br />

Elixir y la VM BEAM son particularmente buenos para esto por el aislamiento de procesos. Cada proceso es
independiente, tiene su propia memoria, y si se cae, otros procesos no se ven afectados. Podés usar esto
para crear bulkheads naturales:

```yaml
defmodule MyApp.DependencyPool do
  @moduledoc """
  Gestiona pools de procesos separados para cada dependencia,
  previniendo que una dependencia lenta consuma todos los recursos.
  """

  def child_spec(_opts) do
    children = [
      # Cada dependencia tiene su propio pool con sus propios límites
      pool_spec(:payment_pool, MyApp.PaymentWorker, size: 10, max_overflow: 5),
      pool_spec(:auth_pool, MyApp.AuthWorker, size: 20, max_overflow: 10),
      pool_spec(:recommendation_pool, MyApp.RecommendationWorker, size: 5, max_overflow: 2),
      pool_spec(:notification_pool, MyApp.NotificationWorker, size: 5, max_overflow: 5)
    ]

    %{
      id: __MODULE__,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end

  defp pool_spec(name, worker, opts) do
    pool_opts = [
      name: {:local, name},
      worker_module: worker,
      size: Keyword.fetch!(opts, :size),
      max_overflow: Keyword.fetch!(opts, :max_overflow)
    ]

    :poolboy.child_spec(name, pool_opts)
  end

  def call_dependency(pool_name, request, timeout \\ 5_000) do
    try do
      :poolboy.transaction(
        pool_name,
        fn worker -> GenServer.call(worker, {:request, request}, timeout) end,
        timeout
      )
    catch
      :exit, {:timeout, _} ->
        {:error, :pool_timeout}

      :exit, {:noproc, _} ->
        {:error, :pool_unavailable}
    end
  end
end
```

<br />

En Kubernetes, tenés otra capa de aislamiento a través de límites de recursos. Cada servicio tiene su
propio presupuesto de CPU y memoria, así que una dependencia descontrolada no puede dejar sin recursos a
otros servicios:

```yaml
# k8s/deployment-con-bulkheads.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: app
          image: myapp:latest
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
---
# Cuotas de recursos separadas por namespace actúan como bulkheads
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dependency-quota
  namespace: payment-service
spec:
  hard:
    requests.cpu: "2"
    requests.memory: "4Gi"
    limits.cpu: "4"
    limits.memory: "8Gi"
    pods: "20"
---
# Network policies como otra forma de bulkhead
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: payment-service-policy
  namespace: payment-service
spec:
  podSelector:
    matchLabels:
      app: payment-service
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: my-app
      ports:
        - port: 8080
          protocol: TCP
```

<br />

La combinación de aislamiento de procesos de Elixir, pools de conexiones, límites de recursos de
Kubernetes y network policies te da múltiples capas de aislamiento. Si el servicio de pagos se descontrola,
no puede consumir toda la CPU del nodo, no puede agotar el pool de conexiones de tu aplicación para otros
servicios, y no puede afectar procesos que manejan requests que no necesitan pagos.

<br />

##### **Timeouts y reintentos**
Los timeouts y reintentos parecen simples, pero hacerlos mal es una de las causas más comunes de fallas
en cascada. Empecemos con lo que no hay que hacer.

<br />

El enfoque ingenuo se ve así:

```elixir
# NO hagas esto - reintentos infinitos sin backoff
def fetch_user(user_id) do
  case HTTPoison.get("https://auth.internal/users/#{user_id}") do
    {:ok, response} -> {:ok, response}
    {:error, _} -> fetch_user(user_id)  # loop de reintentos infinito!
  end
end
```

<br />

Esto crea una tormenta de reintentos. Si el servicio de autenticación se cae, cada request a tu servicio
va a generar reintentos infinitos, empeorando el problema. Acá está la forma correcta de hacerlo con
backoff exponencial y jitter:

```elixir
defmodule MyApp.Retry do
  @moduledoc """
  Reintentos con backoff exponencial y jitter.
  """

  @default_opts [
    max_retries: 3,
    base_delay_ms: 100,
    max_delay_ms: 5_000,
    jitter: true
  ]

  def with_retry(func, opts \\ []) when is_function(func, 0) do
    opts = Keyword.merge(@default_opts, opts)
    do_retry(func, 0, opts)
  end

  defp do_retry(func, attempt, opts) do
    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} when attempt < opts[:max_retries] ->
        delay = calculate_delay(attempt, opts)
        Logger.info("Reintento #{attempt + 1} después de #{delay}ms, razón: #{inspect(reason)}")
        Process.sleep(delay)
        do_retry(func, attempt + 1, opts)

      {:error, reason} ->
        Logger.warning("Los #{opts[:max_retries]} reintentos se agotaron, razón: #{inspect(reason)}")
        {:error, :retries_exhausted, reason}
    end
  end

  defp calculate_delay(attempt, opts) do
    # Backoff exponencial: base * 2^intento
    base_delay = opts[:base_delay_ms] * Integer.pow(2, attempt)

    # Tope en el delay máximo
    capped_delay = min(base_delay, opts[:max_delay_ms])

    # Agregar jitter para prevenir thundering herd
    if opts[:jitter] do
      jitter_range = div(capped_delay, 2)
      capped_delay - jitter_range + :rand.uniform(jitter_range * 2)
    else
      capped_delay
    end
  end
end
```

<br />

Y acá está cómo combinás los reintentos con el circuit breaker:

```elixir
defmodule MyApp.ResilientClient do
  alias MyApp.{CircuitBreaker, Retry}

  def call_service(circuit_name, request_fn, opts \\ []) do
    CircuitBreaker.call(circuit_name, fn ->
      Retry.with_retry(fn ->
        case request_fn.() do
          {:ok, %{status_code: status} = resp} when status in 200..299 ->
            {:ok, resp}

          {:ok, %{status_code: status}} when status in [429, 503] ->
            # Errores de servidor reintentables
            {:error, :retryable}

          {:ok, %{status_code: status} = resp} ->
            # Errores de cliente no reintentables
            {:ok, resp}

          {:error, %HTTPoison.Error{reason: reason}} ->
            {:error, reason}
        end
      end, opts)
    end)
  end
end

# Uso
MyApp.ResilientClient.call_service(:payment_service, fn ->
  HTTPoison.post(url, body, headers, recv_timeout: 5_000)
end, max_retries: 2, base_delay_ms: 200)
```

<br />

Hay algunas cosas importantes para tener en cuenta acá:

<br />

> * **Siempre poné timeouts**: Nunca hagas una llamada de red sin timeout. Un timeout por defecto de 5 segundos es un punto de partida razonable.
> * **El jitter es esencial**: Sin jitter, todos los reintentos pasan al mismo tiempo, creando un thundering herd. Agregar aleatoriedad los distribuye.
> * **No todo es reintentable**: Solo reintentá en errores transitorios (timeouts, 503s, resets de conexión). No reintentes en 400s o 404s.
> * **Poné un presupuesto de reintentos**: Limitá el número total de reintentos a través de todas las requests, no solo por request. Si el 50% de tus requests están reintentando, algo está muy mal.
> * **Combiná con circuit breakers**: Reintentos sin circuit breaker pueden empeorar una situación mala. El circuit breaker para la hemorragia cuando los reintentos no ayudan.

<br />

##### **Estrategias de fallback**
Cuando una dependencia falla y el circuit breaker está abierto, necesitás un plan B. Las estrategias de
fallback definen qué hace tu servicio cuando no puede alcanzar una dependencia. La estrategia correcta
depende de la dependencia y de lo que tus usuarios esperan.

<br />

Acá están los patrones de fallback más comunes:

<br />

**1. Fallback de caché**

Servir datos desactualizados desde un caché local cuando la fuente no está disponible:

```elixir
defmodule MyApp.CacheFallback do
  use GenServer

  @cache_ttl_ms 300_000  # 5 minutos
  @stale_ttl_ms 3_600_000  # 1 hora - datos viejos son mejor que ningún dato

  def get_user_profile(user_id) do
    case MyApp.ResilientClient.call_service(:user_service, fn ->
      HTTPoison.get("https://users.internal/profiles/#{user_id}", [],
        recv_timeout: 3_000
      )
    end) do
      {:ok, %{status_code: 200, body: body}} ->
        profile = Jason.decode!(body)
        cache_put(user_id, profile)
        {:ok, profile}

      {:error, _reason} ->
        case cache_get(user_id) do
          {:ok, profile, :fresh} ->
            {:ok, profile}

          {:ok, profile, :stale} ->
            Logger.info("Sirviendo perfil desactualizado para usuario #{user_id}")
            {:ok, Map.put(profile, :_stale, true)}

          :miss ->
            {:error, :unavailable}
        end
    end
  end

  defp cache_put(key, value) do
    :ets.insert(:profile_cache, {key, value, System.monotonic_time(:millisecond)})
  end

  defp cache_get(key) do
    case :ets.lookup(:profile_cache, key) do
      [{^key, value, cached_at}] ->
        age = System.monotonic_time(:millisecond) - cached_at

        cond do
          age < @cache_ttl_ms -> {:ok, value, :fresh}
          age < @stale_ttl_ms -> {:ok, value, :stale}
          true -> :miss
        end

      [] ->
        :miss
    end
  end
end
```

<br />

**2. Fallback de respuesta por defecto**

Devolver un valor sensato por defecto cuando la dependencia no está disponible:

```elixir
defmodule MyApp.RecommendationService do
  @default_recommendations [
    %{id: "popular-1", title: "Artículo Más Popular", reason: "trending"},
    %{id: "popular-2", title: "Selección del Editor", reason: "curated"},
    %{id: "popular-3", title: "Recién Llegado", reason: "new"}
  ]

  def get_recommendations(user_id) do
    case MyApp.ResilientClient.call_service(:recommendation_engine, fn ->
      HTTPoison.get("https://recommendations.internal/for/#{user_id}", [],
        recv_timeout: 2_000
      )
    end) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:error, _reason} ->
        Logger.info("Motor de recomendaciones no disponible, usando defaults")
        {:ok, @default_recommendations}
    end
  end
end
```

<br />

**3. Fallback de modo degradado**

Deshabilitar funcionalidades no esenciales y comunicar el estado degradado a los usuarios:

```yaml
defmodule MyApp.DegradedMode do
  @moduledoc """
  Rastrea qué funcionalidades están operando en modo degradado
  y provee respuestas apropiadas.
  """

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def mark_degraded(feature, reason) do
    GenServer.cast(__MODULE__, {:mark_degraded, feature, reason})
  end

  def mark_healthy(feature) do
    GenServer.cast(__MODULE__, {:mark_healthy, feature})
  end

  def degraded?(feature) do
    GenServer.call(__MODULE__, {:degraded?, feature})
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:mark_degraded, feature, reason}, state) do
    Logger.warning("Funcionalidad #{feature} entrando en modo degradado: #{reason}")
    {:noreply, Map.put(state, feature, %{reason: reason, since: DateTime.utc_now()})}
  end

  def handle_cast({:mark_healthy, feature}, state) do
    if Map.has_key?(state, feature) do
      Logger.info("Funcionalidad #{feature} recuperada del modo degradado")
    end

    {:noreply, Map.delete(state, feature)}
  end

  @impl true
  def handle_call({:degraded?, feature}, _from, state) do
    {:reply, Map.has_key?(state, feature), state}
  end

  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end
end
```

<br />

**4. Fallback estático**

Para servicios con mucha lectura, pre-computar respuestas estáticas que se puedan servir cuando todo lo
demás falla:

```elixir
defmodule MyApp.StaticFallback do
  @moduledoc """
  Sirve contenido estático pre-computado cuando los servicios dinámicos fallan.
  Actualizado periódicamente por un job en segundo plano.
  """

  @static_dir "priv/static/fallbacks"

  def get_homepage_data do
    case fetch_dynamic_homepage() do
      {:ok, data} -> {:ok, data}
      {:error, _} -> load_static_fallback("homepage.json")
    end
  end

  defp load_static_fallback(filename) do
    path = Path.join(@static_dir, filename)

    case File.read(path) do
      {:ok, content} ->
        Logger.info("Sirviendo fallback estático: #{filename}")
        {:ok, Jason.decode!(content)}

      {:error, _} ->
        {:error, :no_fallback_available}
    end
  end
end
```

<br />

Lo importante es planificar tus fallbacks antes de necesitarlos. Durante un incidente no es el momento de
ponerte a pensar qué debería hacer tu servicio cuando el motor de recomendaciones se cae. Documentá tu
estrategia de fallback para cada dependencia y probala regularmente.

<br />

##### **Health checks para dependencias**
Kubernetes te da tres tipos de probes, y entender cuándo usar cada uno es crítico para la gestión de
dependencias:

<br />

> * **Liveness probes**: "¿Está vivo este proceso?" Si falla, Kubernetes reinicia el container. Esto debería verificar tu proceso, no tus dependencias. Si tu base de datos se cae, reiniciar tu app no lo va a arreglar.
> * **Readiness probes**: "¿Puede este pod servir tráfico?" Si falla, Kubernetes remueve el pod de los endpoints del servicio. Acá es donde verificás dependencias. Si no podés alcanzar la base de datos, no deberías recibir tráfico.
> * **Startup probes**: "¿Este pod terminó de arrancar?" Le da tiempo a containers que arrancan lento para inicializarse antes de que empiecen los checks de liveness y readiness.

<br />

Acá hay una implementación de health check con consciencia de dependencias:

```elixir
defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  @hard_dependencies [:database, :cache]
  @soft_dependencies [:recommendation_engine, :notification_service]

  # Liveness: solo verifica si el proceso está vivo
  def liveness(conn, _params) do
    json(conn, %{status: "alive", timestamp: DateTime.utc_now()})
  end

  # Readiness: verifica dependencias duras
  def readiness(conn, _params) do
    checks =
      @hard_dependencies
      |> Enum.map(fn dep -> {dep, check_dependency(dep)} end)
      |> Map.new()

    all_healthy = Enum.all?(checks, fn {_dep, status} -> status == :ok end)

    if all_healthy do
      conn
      |> put_status(200)
      |> json(%{status: "ready", checks: format_checks(checks)})
    else
      conn
      |> put_status(503)
      |> json(%{status: "not_ready", checks: format_checks(checks)})
    end
  end

  # Estado completo: verifica todo incluyendo dependencias blandas
  def status(conn, _params) do
    hard_checks =
      @hard_dependencies
      |> Enum.map(fn dep -> {dep, check_dependency(dep)} end)
      |> Map.new()

    soft_checks =
      @soft_dependencies
      |> Enum.map(fn dep -> {dep, check_dependency(dep)} end)
      |> Map.new()

    degraded_features = MyApp.DegradedMode.status()

    all_hard_healthy = Enum.all?(hard_checks, fn {_dep, s} -> s == :ok end)
    all_soft_healthy = Enum.all?(soft_checks, fn {_dep, s} -> s == :ok end)

    overall =
      cond do
        not all_hard_healthy -> "unhealthy"
        not all_soft_healthy -> "degraded"
        true -> "healthy"
      end

    conn
    |> put_status(if(all_hard_healthy, do: 200, else: 503))
    |> json(%{
      status: overall,
      hard_dependencies: format_checks(hard_checks),
      soft_dependencies: format_checks(soft_checks),
      degraded_features: degraded_features
    })
  end

  defp check_dependency(:database) do
    case Ecto.Adapters.SQL.query(MyApp.Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  defp check_dependency(:cache) do
    case Redix.command(:redix, ["PING"]) do
      {:ok, "PONG"} -> :ok
      _ -> :error
    end
  end

  defp check_dependency(name) do
    case MyApp.CircuitBreaker.call(name, fn ->
      HTTPoison.get("https://#{name}.internal/health", [], recv_timeout: 2_000)
    end) do
      {:ok, %{status_code: 200}} -> :ok
      _ -> :error
    end
  end

  defp format_checks(checks) do
    Map.new(checks, fn {dep, status} ->
      {dep, %{status: status, checked_at: DateTime.utc_now()}}
    end)
  end
end
```

<br />

Y la configuración correspondiente de probes en Kubernetes:

```yaml
# k8s/deployment-con-probes.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: app
          image: myapp:latest
          ports:
            - containerPort: 4000
          livenessProbe:
            httpGet:
              path: /health/live
              port: 4000
            initialDelaySeconds: 10
            periodSeconds: 15
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 4000
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 2
          startupProbe:
            httpGet:
              path: /health/live
              port: 4000
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 30
```

<br />

El error crítico que la gente comete es poner verificaciones de dependencias en los liveness probes. Si tu
base de datos se cae y tu liveness probe verifica la base de datos, Kubernetes va a reiniciar todos tus
pods. Ahora tenés una caída de base de datos y una tormenta de reinicios de aplicación pasando al mismo
tiempo. Mantené los liveness probes simples y usá readiness probes para verificar dependencias.

<br />

##### **Mapeo de dependencias**
Antes de poder gestionar tus dependencias, necesitás verlas. Un mapa de dependencias es una representación
visual de todos los servicios en tu sistema y cómo se conectan. Esto suena obvio, pero te sorprendería
cuántos equipos no tienen una imagen clara de su grafo de dependencias.

<br />

Acá hay una forma simple de documentar tus dependencias:

```yaml
defmodule MyApp.DependencyMap do
  @moduledoc """
  Declara todas las dependencias de servicio con sus propiedades.
  Esto sirve como documentación viva y alimenta decisiones en runtime.
  """

  @dependencies %{
    database: %{
      type: :hard,
      url: "postgresql://db.internal:5432/myapp",
      timeout_ms: 5_000,
      circuit_breaker: false,  # gestionado por el pool de Ecto
      fallback: :none,
      slo_target: 0.999,
      owner_team: "platform",
      criticality: :critical
    },
    cache: %{
      type: :hard,
      url: "redis://cache.internal:6379",
      timeout_ms: 1_000,
      circuit_breaker: true,
      fallback: :bypass,  # saltear caché, ir directo a la base de datos
      slo_target: 0.999,
      owner_team: "platform",
      criticality: :critical
    },
    auth_service: %{
      type: :hard,
      url: "https://auth.internal:8443",
      timeout_ms: 3_000,
      circuit_breaker: true,
      fallback: :cached_tokens,
      slo_target: 0.999,
      owner_team: "identity",
      criticality: :critical
    },
    payment_service: %{
      type: :hard,
      url: "https://payments.internal:8080",
      timeout_ms: 10_000,
      circuit_breaker: true,
      fallback: :queue_for_retry,
      slo_target: 0.999,
      owner_team: "payments",
      criticality: :high
    },
    recommendation_engine: %{
      type: :soft,
      url: "https://recommendations.internal:8080",
      timeout_ms: 2_000,
      circuit_breaker: true,
      fallback: :static_defaults,
      slo_target: 0.99,
      owner_team: "ml",
      criticality: :low
    },
    notification_service: %{
      type: :soft,
      url: "https://notifications.internal:8080",
      timeout_ms: 5_000,
      circuit_breaker: true,
      fallback: :queue_for_retry,
      slo_target: 0.99,
      owner_team: "comms",
      criticality: :medium
    },
    analytics_service: %{
      type: :soft,
      url: "https://analytics.internal:8080",
      timeout_ms: 1_000,
      circuit_breaker: true,
      fallback: :fire_and_forget,
      slo_target: 0.95,
      owner_team: "data",
      criticality: :low
    }
  }

  def all, do: @dependencies

  def hard_dependencies do
    @dependencies
    |> Enum.filter(fn {_name, config} -> config.type == :hard end)
    |> Map.new()
  end

  def soft_dependencies do
    @dependencies
    |> Enum.filter(fn {_name, config} -> config.type == :soft end)
    |> Map.new()
  end

  def get(name), do: Map.get(@dependencies, name)

  def critical_path do
    @dependencies
    |> Enum.filter(fn {_name, config} -> config.criticality in [:critical, :high] end)
    |> Enum.sort_by(fn {_name, config} -> config.criticality end)
    |> Map.new()
  end
end
```

<br />

Este tipo de mapa de dependencias declarativo sirve para múltiples propósitos: documenta de qué dependés,
alimenta la configuración de tus circuit breakers, informa a tus health checks, y le dice a los ingenieros
de guardia a qué equipo contactar cuando una dependencia falla.

<br />

También podés generar un grafo visual a partir de estos datos:

```elixir
defmodule MyApp.DependencyGraph do
  @moduledoc """
  Genera un diagrama Mermaid a partir del mapa de dependencias.
  """

  def to_mermaid do
    deps = MyApp.DependencyMap.all()

    nodes =
      deps
      |> Enum.map(fn {name, config} ->
        style = if config.type == :hard, do: ":::critical", else: ":::optional"
        "  #{name}[#{name}]#{style}"
      end)
      |> Enum.join("\n")

    edges =
      deps
      |> Enum.map(fn {name, config} ->
        arrow = if config.type == :hard, do: "==>", else: "-->"
        "  my_app #{arrow} #{name}"
      end)
      |> Enum.join("\n")

    """
    graph LR
      my_app[My App]
    #{nodes}
    #{edges}
      classDef critical fill:#ff6b6b,stroke:#333
      classDef optional fill:#4ecdc4,stroke:#333
    """
  end
end
```

<br />

##### **SLOs para dependencias**
Así como definís SLOs para tus propios servicios, deberías rastrear la confiabilidad de tus dependencias.
Esto te da datos para tomar decisiones sobre arquitectura, estrategias de fallback, e incluso selección de
proveedores.

<br />

Acá está cómo pensar sobre SLOs de dependencias:

<br />

> * **Dependencias internas**: Generalmente podés negociar SLOs con el equipo que es dueño del servicio. "Necesitamos que tu servicio de autenticación tenga 99.9% de disponibilidad y latencia p99 menor a 200ms."
> * **Dependencias externas**: Estás a merced del SLA del proveedor. Rastreá el rendimiento real contra su SLA declarado, porque la realidad suele diferir.
> * **Tu SLO efectivo**: El SLO de tu servicio no puede ser más alto que el SLO de tu dependencia dura más débil. Si el SLO de tu base de datos es 99.9%, el SLO de tu servicio no puede ser de forma realista 99.95%.

<br />

Acá hay un enfoque basado en Prometheus para rastrear SLOs de dependencias:

```yaml
# prometheus-rules-dependency-slos.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dependency-slos
  namespace: monitoring
spec:
  groups:
    - name: dependency.slos
      interval: 30s
      rules:
        # Rastrear tasa de éxito por dependencia
        - record: dependency:requests:success_rate5m
          expr: |
            sum by (dependency) (
              rate(dependency_requests_total{status="success"}[5m])
            ) /
            sum by (dependency) (
              rate(dependency_requests_total[5m])
            )

        # Rastrear latencia por dependencia
        - record: dependency:latency:p99_5m
          expr: |
            histogram_quantile(0.99,
              sum by (dependency, le) (
                rate(dependency_request_duration_seconds_bucket[5m])
              )
            )

        # Presupuesto de error restante de dependencia (ventana de 30 días)
        - record: dependency:error_budget:remaining
          expr: |
            1 - (
              (1 - avg_over_time(dependency:requests:success_rate5m[30d]))
              /
              (1 - 0.999)
            )

    - name: dependency.alerts
      rules:
        - alert: DependencyErrorBudgetBurning
          expr: dependency:error_budget:remaining < 0.5
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "La dependencia {{ $labels.dependency }} consumió 50% del presupuesto de error"
            description: "Presupuesto de error restante: {{ $value | humanizePercentage }}"

        - alert: DependencyErrorBudgetExhausted
          expr: dependency:error_budget:remaining < 0.1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Presupuesto de error de dependencia {{ $labels.dependency }} casi agotado"
            description: "Presupuesto de error restante: {{ $value | humanizePercentage }}"
```

<br />

Para emitir estas métricas desde tu aplicación Elixir, instrumentá tus llamadas a dependencias:

```elixir
defmodule MyApp.DependencyTelemetry do
  @moduledoc """
  Emite eventos de telemetría para todas las llamadas a dependencias,
  que luego se exponen como métricas de Prometheus.
  """

  def track_call(dependency, func) when is_function(func, 0) do
    start_time = System.monotonic_time()

    result =
      try do
        func.()
      rescue
        error ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:dependency, :call, :exception],
            %{duration: duration},
            %{dependency: dependency, error: inspect(error)}
          )

          reraise error, __STACKTRACE__
      end

    duration = System.monotonic_time() - start_time
    status = if match?({:ok, _}, result), do: "success", else: "failure"

    :telemetry.execute(
      [:dependency, :call, :stop],
      %{duration: duration},
      %{dependency: dependency, status: status}
    )

    result
  end
end
```

<br />

Cuando rastreás SLOs de dependencias a lo largo del tiempo, empezás a ver patrones. Quizás tu motor de
recomendaciones cae por debajo de su SLO todos los lunes a la mañana cuando el equipo de ML corre jobs
batch. Quizás el gateway de pagos tiene caídas de confiabilidad el último día del mes. Estos patrones te
ayudan a planificar mejores estrategias de fallback y a tener conversaciones informadas con los dueños de
las dependencias.

<br />

##### **Patrones de degradación elegante**
La degradación elegante es el arte de hacer menos, bien, en vez de hacer todo, mal. Cuando tu sistema está
bajo estrés o una dependencia está fallando, reducís intencionalmente la funcionalidad para proteger la
experiencia central del usuario.

<br />

Pensalo como niveles progresivos de degradación:

<br />

> 1. **Nivel 0 - Normal**: Todas las funcionalidades andando, todas las dependencias sanas
> 2. **Nivel 1 - Reducido**: Funcionalidades no esenciales deshabilitadas (recomendaciones, analytics, personalización)
> 3. **Nivel 2 - Solo lo central**: Solo quedan las funcionalidades del camino crítico (navegar, buscar, comprar)
> 4. **Nivel 3 - Mínimo**: Modo solo lectura o solo contenido estático
> 5. **Nivel 4 - Mantenimiento**: Servicio caído, mostrar página de mantenimiento

<br />

Acá está cómo implementar degradación progresiva:

```yaml
defmodule MyApp.DegradationLevel do
  @moduledoc """
  Gestiona el nivel de degradación actual basado en
  la salud de dependencias y la carga del sistema.
  """

  use GenServer

  @levels [:normal, :reduced, :core_only, :minimal, :maintenance]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :normal, name: __MODULE__)
  end

  def current_level do
    GenServer.call(__MODULE__, :current_level)
  end

  def set_level(level) when level in @levels do
    GenServer.call(__MODULE__, {:set_level, level})
  end

  def feature_available?(feature) do
    level = current_level()
    feature_level = feature_minimum_level(feature)
    level_index(level) <= level_index(feature_level)
  end

  @impl true
  def init(level), do: {:ok, level}

  @impl true
  def handle_call(:current_level, _from, level), do: {:reply, level, level}

  def handle_call({:set_level, new_level}, _from, old_level) do
    if new_level != old_level do
      Logger.warning(
        "Nivel de degradación cambió: #{old_level} -> #{new_level}"
      )

      :telemetry.execute(
        [:app, :degradation, :level_change],
        %{},
        %{old_level: old_level, new_level: new_level}
      )
    end

    {:reply, :ok, new_level}
  end

  # Definir qué funcionalidades están disponibles en cada nivel
  defp feature_minimum_level(:recommendations), do: :normal
  defp feature_minimum_level(:analytics_tracking), do: :normal
  defp feature_minimum_level(:personalization), do: :normal
  defp feature_minimum_level(:search_suggestions), do: :reduced
  defp feature_minimum_level(:user_reviews), do: :reduced
  defp feature_minimum_level(:search), do: :core_only
  defp feature_minimum_level(:browse_catalog), do: :core_only
  defp feature_minimum_level(:checkout), do: :core_only
  defp feature_minimum_level(:static_content), do: :minimal
  defp feature_minimum_level(_), do: :normal

  defp level_index(:normal), do: 0
  defp level_index(:reduced), do: 1
  defp level_index(:core_only), do: 2
  defp level_index(:minimal), do: 3
  defp level_index(:maintenance), do: 4
end
```

<br />

Después podés usar esto en tus controllers y LiveViews:

```elixir
defmodule MyAppWeb.ProductLive do
  use MyAppWeb, :live_view

  alias MyApp.DegradationLevel

  def mount(%{"id" => id}, _session, socket) do
    product = MyApp.Catalog.get_product!(id)

    socket =
      socket
      |> assign(:product, product)
      |> assign(:degradation_level, DegradationLevel.current_level())
      |> maybe_load_recommendations(id)
      |> maybe_load_reviews(id)

    {:ok, socket}
  end

  defp maybe_load_recommendations(socket, product_id) do
    if DegradationLevel.feature_available?(:recommendations) do
      case MyApp.RecommendationService.get_recommendations(product_id) do
        {:ok, recs} -> assign(socket, :recommendations, recs)
        {:error, _} -> assign(socket, :recommendations, [])
      end
    else
      assign(socket, :recommendations, [])
    end
  end

  defp maybe_load_reviews(socket, product_id) do
    if DegradationLevel.feature_available?(:user_reviews) do
      case MyApp.Reviews.list_for_product(product_id) do
        {:ok, reviews} -> assign(socket, :reviews, reviews)
        {:error, _} -> assign(socket, :reviews, [])
      end
    else
      assign(socket, :reviews, [])
    end
  end
end
```

<br />

##### **Feature flags para degradación**
Los feature flags son el mecanismo que hace que la degradación elegante sea práctica en runtime. En vez de
deployar código nuevo para deshabilitar una funcionalidad, girás un flag y el cambio toma efecto de inmediato.

<br />

Acá hay una implementación de feature flags simple pero efectiva en Elixir:

```yaml
defmodule MyApp.FeatureFlags do
  @moduledoc """
  Feature flags basados en ETS para toggling en runtime.
  Soporta flags booleanos y rollouts por porcentaje.
  """

  use GenServer

  @table :feature_flags

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    # Cargar flags por defecto
    load_defaults()

    {:ok, %{}}
  end

  # Verificar si una funcionalidad está habilitada
  def enabled?(flag) do
    case :ets.lookup(@table, flag) do
      [{^flag, true}] -> true
      [{^flag, false}] -> false
      [{^flag, percentage}] when is_integer(percentage) ->
        :rand.uniform(100) <= percentage
      [] -> true  # habilitado por defecto si el flag no existe
    end
  end

  # Habilitar una funcionalidad
  def enable(flag) do
    :ets.insert(@table, {flag, true})
    Logger.info("Feature flag habilitado: #{flag}")
    :ok
  end

  # Deshabilitar una funcionalidad
  def disable(flag) do
    :ets.insert(@table, {flag, false})
    Logger.warning("Feature flag deshabilitado: #{flag}")
    :ok
  end

  # Configurar rollout por porcentaje
  def set_percentage(flag, percentage) when percentage in 0..100 do
    :ets.insert(@table, {flag, percentage})
    Logger.info("Feature flag #{flag} configurado al #{percentage}%")
    :ok
  end

  # Listar todos los flags y sus estados
  def list_all do
    :ets.tab2list(@table)
    |> Map.new()
  end

  defp load_defaults do
    defaults = [
      {:recommendations, true},
      {:analytics_tracking, true},
      {:personalization, true},
      {:search_suggestions, true},
      {:user_reviews, true},
      {:new_checkout_flow, false},
      {:experimental_search, 10}  # rollout al 10%
    ]

    Enum.each(defaults, fn {flag, value} ->
      :ets.insert(@table, {flag, value})
    end)
  end
end
```

<br />

Y una página de Phoenix LiveDashboard para gestionar flags en runtime:

```elixir
defmodule MyAppWeb.FeatureFlagController do
  use MyAppWeb, :controller

  plug :require_admin

  def index(conn, _params) do
    flags = MyApp.FeatureFlags.list_all()
    json(conn, %{flags: flags})
  end

  def update(conn, %{"flag" => flag, "value" => "true"}) do
    MyApp.FeatureFlags.enable(String.to_existing_atom(flag))
    json(conn, %{status: "ok", flag: flag, value: true})
  end

  def update(conn, %{"flag" => flag, "value" => "false"}) do
    MyApp.FeatureFlags.disable(String.to_existing_atom(flag))
    json(conn, %{status: "ok", flag: flag, value: false})
  end

  def update(conn, %{"flag" => flag, "value" => value}) do
    case Integer.parse(value) do
      {percentage, ""} when percentage in 0..100 ->
        MyApp.FeatureFlags.set_percentage(
          String.to_existing_atom(flag),
          percentage
        )
        json(conn, %{status: "ok", flag: flag, value: percentage})

      _ ->
        conn
        |> put_status(400)
        |> json(%{error: "Valor inválido"})
    end
  end

  defp require_admin(conn, _opts) do
    # Tu lógica de autenticación de admin acá
    conn
  end
end
```

<br />

Lo lindo de combinar feature flags con el sistema de niveles de degradación es que podés automatizar la
respuesta a fallas de dependencias. Cuando el circuit breaker del motor de recomendaciones se abre,
automáticamente deshabilitás el feature flag de recomendaciones. Cuando se recupera, lo volvés a habilitar:

```yaml
defmodule MyApp.DegradationAutomation do
  @moduledoc """
  Ajusta automáticamente feature flags y nivel de degradación
  basado en señales de salud de dependencias.
  """

  use GenServer

  @check_interval_ms 10_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_dependencies, state) do
    deps = MyApp.DependencyMap.all()

    Enum.each(deps, fn {name, config} ->
      case check_health(name) do
        :healthy ->
          maybe_restore_features(name, config)

        :unhealthy ->
          maybe_degrade_features(name, config)
      end
    end)

    update_overall_degradation_level()
    schedule_check()
    {:noreply, state}
  end

  defp check_health(dep_name) do
    case MyApp.CircuitBreaker.call(dep_name, fn ->
      # health check liviano
      :ok
    end) do
      {:ok, _} -> :healthy
      {:error, :circuit_open} -> :unhealthy
      {:error, _, _} -> :unhealthy
    end
  end

  defp maybe_degrade_features(dep_name, _config) do
    features_for_dependency(dep_name)
    |> Enum.each(fn feature ->
      MyApp.FeatureFlags.disable(feature)
      MyApp.DegradedMode.mark_degraded(feature, "dependencia #{dep_name} no saludable")
    end)
  end

  defp maybe_restore_features(dep_name, _config) do
    features_for_dependency(dep_name)
    |> Enum.each(fn feature ->
      MyApp.FeatureFlags.enable(feature)
      MyApp.DegradedMode.mark_healthy(feature)
    end)
  end

  defp features_for_dependency(:recommendation_engine), do: [:recommendations]
  defp features_for_dependency(:notification_service), do: [:email_notifications]
  defp features_for_dependency(:analytics_service), do: [:analytics_tracking]
  defp features_for_dependency(_), do: []

  defp update_overall_degradation_level do
    hard_deps = MyApp.DependencyMap.hard_dependencies()
    soft_deps = MyApp.DependencyMap.soft_dependencies()

    hard_healthy = Enum.all?(hard_deps, fn {name, _} -> check_health(name) == :healthy end)
    soft_healthy = Enum.all?(soft_deps, fn {name, _} -> check_health(name) == :healthy end)

    level =
      cond do
        not hard_healthy -> :core_only
        not soft_healthy -> :reduced
        true -> :normal
      end

    MyApp.DegradationLevel.set_level(level)
  end

  defp schedule_check do
    Process.send_after(self(), :check_dependencies, @check_interval_ms)
  end
end
```

<br />

##### **Notas finales**
La gestión de dependencias y la degradación elegante no son opcionales para cualquier servicio que apunte
a ser confiable. Cada llamada externa es un riesgo, y los patrones que cubrimos (circuit breakers,
bulkheads, timeouts con backoff, estrategias de fallback, health checks de dependencias, mapeo de
dependencias, SLOs de dependencias, niveles de degradación progresiva y feature flags) te dan un toolkit
completo para gestionar ese riesgo.

<br />

Las conclusiones clave son:

<br />

> 1. **Conocé tus dependencias**: Mapealas, clasificalas como duras o blandas, y documentá tu estrategia de fallback para cada una
> 2. **Fallá rápido**: Usá circuit breakers y timeouts para que una dependencia lenta no se convierta en tu problema
> 3. **Aislá las fallas**: Usá bulkheads (pools de procesos, límites de recursos, network policies) para contener el radio de explosión
> 4. **Tené un plan B**: Implementá estrategias de fallback antes de necesitarlas, no durante un incidente
> 5. **Degradá con elegancia**: Es mejor servir una página de producto sin recomendaciones que devolver un error 500
> 6. **Automatizá la respuesta**: Usá feature flags y automatización para responder a fallas de dependencias en segundos, no minutos

<br />

Empezá por el camino más crítico de tu sistema. Identificá las dependencias duras, agregá circuit breakers
y timeouts, implementá una estrategia de fallback, y probala. No necesitás implementar todo de una. Las
mejoras incrementales se acumulan con el tiempo.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
