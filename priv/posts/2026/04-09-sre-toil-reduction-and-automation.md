%{
  title: "SRE: Toil Reduction and Automation",
  author: "Gabriel Garrido",
  description: "We will explore toil reduction strategies from the Google SRE book, from identifying and measuring toil to building self-healing systems, internal tooling with Elixir, automation safety patterns, and the 50 percent rule...",
  tags: ~w(sre automation platform-engineering toil elixir),
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
[secrets management](/blog/sre-secrets-management-in-kubernetes),
[cost optimization](/blog/sre-cost-optimization-in-the-cloud),
[dependency management](/blog/sre-dependency-management-and-graceful-degradation),
[database reliability](/blog/sre-database-reliability),
[release engineering](/blog/sre-release-engineering-and-progressive-delivery),
[security as code](/blog/sre-security-as-code), and
[disaster recovery](/blog/sre-disaster-recovery-and-business-continuity). That is thirteen articles covering
the core practices of Site Reliability Engineering.

<br />

In this final article of the series, we are going to talk about toil. Toil is the work that keeps the
lights on but does not move things forward. It is the manual, repetitive, automatable work that scales
linearly with service size and provides no lasting value. Every SRE team deals with it, and how you
manage it determines whether your team can actually do engineering work or just fight fires all day.

<br />

The Google SRE book has a famous rule: SREs should spend no more than 50% of their time on toil. The
rest should go to engineering work that reduces future toil. In practice, many teams spend far more
than 50% on toil and never get around to the automation that would free them.

<br />

Let's get into it.

<br />

##### **What is toil?**
Not all operational work is toil. Google defines toil very specifically. For work to qualify as toil,
it must have these characteristics:

<br />

> * **Manual**: A human has to do it. If a script does it, it is not toil.
> * **Repetitive**: You do it over and over. A one-time task is not toil, even if it is manual.
> * **Automatable**: A machine could do it. If it requires human judgment every time, it is not toil (it might be engineering work).
> * **Tactical**: It is reactive, not proactive. You do it in response to something happening.
> * **No lasting value**: Once done, it does not improve the system. The next time it happens, you do the same thing again.
> * **Scales linearly**: As the service grows, the work grows proportionally.

<br />

Here are some common examples of toil:

<br />

> * **Manually restarting pods** when they get into a bad state
> * **Manually scaling services** before known traffic spikes
> * **Processing ticket requests** for environment access, database permissions, or namespace creation
> * **Manually running database migrations** or backup restores
> * **Manually rotating secrets** or certificates
> * **Copy-pasting configuration** between environments
> * **Manually checking dashboards** to verify deployments succeeded
> * **Responding to alerts that always require the same fix** (restart, clear cache, increase limits)

<br />

If you read that list and thought "I do half of those every week," you are not alone. The first step
to reducing toil is recognizing it for what it is.

<br />

##### **Identifying toil**
You cannot reduce what you do not measure. The first step is to systematically track how your team
spends its time. This does not need to be fancy. A simple spreadsheet or form works fine.

<br />

Here is a basic toil tracking template:

<br />

```yaml
# toil-tracking.yaml
# Have each team member fill this out weekly

categories:
  - name: "Access requests"
    description: "Granting permissions, creating accounts, namespace access"
    examples:
      - "Create namespace for team X"
      - "Grant read access to production logs"
      - "Add user to kubectl RBAC"

  - name: "Deployment support"
    description: "Manual deployment steps, rollbacks, verification"
    examples:
      - "Run database migration for service Y"
      - "Manually verify deployment health"
      - "Rollback failed deployment"

  - name: "Incident response"
    description: "Reactive fixes for known issues"
    examples:
      - "Restart pod stuck in CrashLoopBackOff"
      - "Clear full disk on node"
      - "Increase memory limit for OOM-killed pod"

  - name: "Configuration changes"
    description: "Manual config updates"
    examples:
      - "Update environment variables"
      - "Rotate expired certificate"
      - "Update DNS record"

  - name: "Monitoring and alerting"
    description: "Dashboard checks, alert tuning"
    examples:
      - "Silence known noisy alert"
      - "Manually check deployment dashboard"
      - "Investigate false positive alert"

tracking_fields:
  - task_description: "What did you do?"
  - category: "Which category?"
  - time_spent_minutes: "How long did it take?"
  - frequency: "How often does this happen? (daily/weekly/monthly)"
  - automatable: "Could a machine do this? (yes/no/partially)"
  - impact_if_not_done: "What happens if you skip it? (outage/degradation/nothing)"
```

<br />

After a few weeks of tracking, you will have a clear picture of where time goes. Sort by time spent
and frequency, and you have your prioritized automation backlog.

<br />

Here is an Elixir module to aggregate toil data programmatically:

<br />

```yaml
defmodule ToilTracker do
  @moduledoc """
  Tracks and analyzes toil across the team.
  Uses ETS for fast in-memory storage.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    table = :ets.new(:toil_entries, [:bag, :named_table, :public])
    {:ok, %{table: table}}
  end

  def log_toil(entry) do
    :ets.insert(:toil_entries, {
      entry.category,
      entry.description,
      entry.time_minutes,
      entry.engineer,
      DateTime.utc_now()
    })
  end

  def weekly_summary do
    :ets.tab2list(:toil_entries)
    |> Enum.filter(fn {_, _, _, _, timestamp} ->
      DateTime.diff(DateTime.utc_now(), timestamp, :day) <= 7
    end)
    |> Enum.group_by(fn {category, _, _, _, _} -> category end)
    |> Enum.map(fn {category, entries} ->
      total_minutes = entries |> Enum.map(fn {_, _, mins, _, _} -> mins end) |> Enum.sum()
      count = length(entries)
      %{
        category: category,
        total_minutes: total_minutes,
        occurrences: count,
        avg_minutes: Float.round(total_minutes / count, 1)
      }
    end)
    |> Enum.sort_by(& &1.total_minutes, :desc)
  end

  def toil_percentage(total_work_hours \\ 40) do
    summary = weekly_summary()
    toil_hours = Enum.reduce(summary, 0, fn entry, acc -> acc + entry.total_minutes end) / 60
    Float.round(toil_hours / total_work_hours * 100, 1)
  end
end
```

<br />

##### **Self-healing systems**
The best way to eliminate toil is to make it unnecessary. Self-healing systems detect and recover from
common failure modes without human intervention. Kubernetes already provides several self-healing
mechanisms out of the box.

<br />

**Liveness probes** restart containers that are stuck:

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: my-app:latest
          livenessProbe:
            httpGet:
              path: /healthz
              port: 4000
            initialDelaySeconds: 15
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /readyz
              port: 4000
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 2
          startupProbe:
            httpGet:
              path: /healthz
              port: 4000
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 30
```

<br />

**PodDisruptionBudgets** prevent too many pods from going down at once:

<br />

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: my-app
```

<br />

**Horizontal Pod Autoscaler** handles scaling automatically:

<br />

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Percent
          value: 50
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 10
          periodSeconds: 120
```

<br />

For more advanced self-healing, you can build custom Kubernetes operators. Here is a simple example
of a controller that automatically restarts pods that have been in CrashLoopBackOff for too long:

<br />

```yaml
# A CronJob that cleans up stuck pods
apiVersion: batch/v1
kind: CronJob
metadata:
  name: stuck-pod-cleaner
  namespace: kube-system
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: pod-cleaner
          containers:
            - name: cleaner
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  # Find pods in CrashLoopBackOff for more than 30 minutes
                  kubectl get pods --all-namespaces -o json | \
                    jq -r '.items[] |
                      select(.status.containerStatuses[]?.state.waiting?.reason == "CrashLoopBackOff") |
                      select(
                        (.status.containerStatuses[0].state.waiting.reason == "CrashLoopBackOff") and
                        (.status.containerStatuses[0].restartCount > 10)
                      ) |
                      "\(.metadata.namespace) \(.metadata.name)"' | \
                  while read ns pod; do
                    echo "Deleting stuck pod $pod in namespace $ns"
                    kubectl delete pod "$pod" -n "$ns"
                  done
          restartPolicy: OnFailure
```

<br />

##### **Automation ROI calculation**
Not everything should be automated. Automation has a cost: the time to build it, the time to maintain
it, and the risk of bugs in the automation itself. You need a simple framework to decide what is
worth automating.

<br />

The classic reference is the XKCD "Is It Worth the Time?" chart. Here is a practical version:

<br />

```elixir
defmodule AutomationROI do
  @moduledoc """
  Calculate whether automating a task is worth the investment.
  """

  @doc """
  Calculate break-even point for automation.

  ## Parameters
    - manual_time_minutes: How long the manual task takes
    - frequency_per_month: How often the task occurs per month
    - automation_hours: Estimated hours to build the automation
    - maintenance_hours_per_month: Estimated monthly maintenance

  ## Returns
    Map with break-even analysis
  """
  def calculate(manual_time_minutes, frequency_per_month, automation_hours, maintenance_hours_per_month \\ 0.5) do
    monthly_savings_hours = manual_time_minutes * frequency_per_month / 60
    net_monthly_savings = monthly_savings_hours - maintenance_hours_per_month

    break_even_months = if net_monthly_savings > 0 do
      Float.round(automation_hours / net_monthly_savings, 1)
    else
      :never
    end

    yearly_savings = net_monthly_savings * 12

    %{
      manual_time_per_month_hours: Float.round(monthly_savings_hours, 1),
      automation_cost_hours: automation_hours,
      maintenance_per_month_hours: maintenance_hours_per_month,
      net_savings_per_month_hours: Float.round(net_monthly_savings, 1),
      break_even_months: break_even_months,
      yearly_savings_hours: Float.round(yearly_savings, 1),
      recommendation: recommendation(break_even_months, yearly_savings)
    }
  end

  defp recommendation(:never, _), do: "Do not automate. Maintenance cost exceeds savings."
  defp recommendation(months, _) when months > 24, do: "Low priority. Consider simpler alternatives."
  defp recommendation(months, savings) when months <= 3 and savings > 20, do: "Automate immediately. High impact, fast payback."
  defp recommendation(months, _) when months <= 6, do: "Automate soon. Good return on investment."
  defp recommendation(months, _) when months <= 12, do: "Automate when you have time. Moderate ROI."
  defp recommendation(_, _), do: "Consider partial automation or process improvement instead."
end
```

<br />

Here is how you would use it:

<br />

```bash
# Example: Manually creating namespaces
# Takes 15 minutes, happens 8 times per month, 4 hours to automate
AutomationROI.calculate(15, 8, 4)
# => %{
#   manual_time_per_month_hours: 2.0,
#   automation_cost_hours: 4,
#   net_savings_per_month_hours: 1.5,
#   break_even_months: 2.7,
#   yearly_savings_hours: 18.0,
#   recommendation: "Automate immediately. High impact, fast payback."
# }

# Example: Rotating a certificate quarterly
# Takes 30 minutes, happens 0.33 times per month, 8 hours to automate
AutomationROI.calculate(30, 0.33, 8)
# => %{
#   manual_time_per_month_hours: 0.2,
#   automation_cost_hours: 8,
#   break_even_months: :never,
#   recommendation: "Do not automate. Maintenance cost exceeds savings."
# }
# But wait: cert rotation has risk (forgetting = outage), so automate anyway!
```

<br />

The ROI calculation is a starting point, not the final answer. Some tasks should be automated even
if the raw time savings do not justify it:

<br />

> * **Tasks where forgetting causes outages** (certificate rotation, backup verification)
> * **Tasks that are error-prone** when done manually (configuration changes, DNS updates)
> * **Tasks that block other people** (access requests, environment provisioning)
> * **Tasks that interrupt deep work** (even 5-minute tasks break flow for 30 minutes)

<br />

##### **Building internal tooling with Elixir**
Elixir is a great choice for building internal SRE tools. OTP gives you supervision trees for
reliability, GenServers for stateful automation, and the BEAM VM handles concurrency beautifully.

<br />

Here is a Mix task for common SRE operations:

<br />

```yaml
defmodule Mix.Tasks.Sre.Namespace do
  @moduledoc """
  Create a new Kubernetes namespace with standard configuration.

  Usage:
    mix sre.namespace create --name my-namespace --team backend --env staging
    mix sre.namespace list
    mix sre.namespace delete --name my-namespace
  """
  use Mix.Task

  @shortdoc "Manage Kubernetes namespaces"

  def run(args) do
    {opts, [action], _} = OptionParser.parse(args,
      strict: [name: :string, team: :string, env: :string],
      aliases: [n: :name, t: :team, e: :env]
    )

    case action do
      "create" -> create_namespace(opts)
      "list" -> list_namespaces()
      "delete" -> delete_namespace(opts)
    end
  end

  defp create_namespace(opts) do
    name = Keyword.fetch!(opts, :name)
    team = Keyword.fetch!(opts, :team)
    env = Keyword.get(opts, :env, "staging")

    manifest = """
    apiVersion: v1
    kind: Namespace
    metadata:
      name: #{name}
      labels:
        team: #{team}
        environment: #{env}
        managed-by: sre-tools
    ---
    apiVersion: v1
    kind: ResourceQuota
    metadata:
      name: default-quota
      namespace: #{name}
    spec:
      hard:
        requests.cpu: "4"
        requests.memory: 8Gi
        limits.cpu: "8"
        limits.memory: 16Gi
        pods: "50"
    ---
    apiVersion: v1
    kind: LimitRange
    metadata:
      name: default-limits
      namespace: #{name}
    spec:
      limits:
        - default:
            cpu: 500m
            memory: 512Mi
          defaultRequest:
            cpu: 100m
            memory: 128Mi
          type: Container
    ---
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: #{name}
    spec:
      podSelector: {}
      policyTypes:
        - Ingress
    """

    File.write!("/tmp/namespace-#{name}.yaml", manifest)
    {output, 0} = System.cmd("kubectl", ["apply", "-f", "/tmp/namespace-#{name}.yaml"])
    Mix.shell().info("Created namespace #{name} with standard config")
    Mix.shell().info(output)
  end

  defp list_namespaces do
    {output, 0} = System.cmd("kubectl", [
      "get", "namespaces",
      "-l", "managed-by=sre-tools",
      "-o", "custom-columns=NAME:.metadata.name,TEAM:.metadata.labels.team,ENV:.metadata.labels.environment,AGE:.metadata.creationTimestamp"
    ])
    Mix.shell().info(output)
  end

  defp delete_namespace(opts) do
    name = Keyword.fetch!(opts, :name)
    Mix.shell().info("Are you sure you want to delete namespace #{name}? (yes/no)")
    case IO.gets("") |> String.trim() do
      "yes" ->
        {output, 0} = System.cmd("kubectl", ["delete", "namespace", name])
        Mix.shell().info("Deleted namespace #{name}")
        Mix.shell().info(output)
      _ ->
        Mix.shell().info("Cancelled")
    end
  end
end
```

<br />

Here is a GenServer-based automation agent that watches for conditions and takes action:

<br />

```yaml
defmodule SreBot.DiskWatcher do
  @moduledoc """
  Watches node disk usage and automatically cleans up
  when usage exceeds thresholds.
  """
  use GenServer
  require Logger

  @check_interval :timer.minutes(5)
  @warning_threshold 80
  @critical_threshold 90

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_check()
    {:ok, %{last_alert: nil}}
  end

  def handle_info(:check_disk, state) do
    state = check_all_nodes(state)
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_disk, @check_interval)
  end

  defp check_all_nodes(state) do
    case get_node_disk_usage() do
      {:ok, nodes} ->
        Enum.reduce(nodes, state, fn node, acc ->
          handle_node_disk(node, acc)
        end)
      {:error, reason} ->
        Logger.error("Failed to check disk usage: #{inspect(reason)}")
        state
    end
  end

  defp handle_node_disk(%{name: name, usage_percent: usage}, state) when usage >= @critical_threshold do
    Logger.warning("Node #{name} disk at #{usage}% - running cleanup")
    run_cleanup(name)
    send_alert(name, usage, :critical)
    state
  end

  defp handle_node_disk(%{name: name, usage_percent: usage}, state) when usage >= @warning_threshold do
    Logger.info("Node #{name} disk at #{usage}% - warning threshold")
    send_alert(name, usage, :warning)
    state
  end

  defp handle_node_disk(_node, state), do: state

  defp run_cleanup(node_name) do
    # Clean up old container images
    System.cmd("kubectl", [
      "debug", "node/#{node_name}", "--",
      "crictl", "rmi", "--prune"
    ])

    # Clean up old logs
    System.cmd("kubectl", [
      "debug", "node/#{node_name}", "--",
      "find", "/var/log/containers", "-mtime", "+7", "-delete"
    ])

    Logger.info("Cleanup completed on node #{node_name}")
  end

  defp get_node_disk_usage do
    case System.cmd("kubectl", ["get", "nodes", "-o", "json"]) do
      {output, 0} ->
        nodes = output
        |> Jason.decode!()
        |> Map.get("items", [])
        |> Enum.map(fn node ->
          name = get_in(node, ["metadata", "name"])
          # In a real implementation, you would query node metrics
          %{name: name, usage_percent: get_disk_usage_for_node(name)}
        end)
        {:ok, nodes}
      {_, code} ->
        {:error, "kubectl exited with code #{code}"}
    end
  end

  defp get_disk_usage_for_node(_name), do: Enum.random(50..95)

  defp send_alert(node, usage, severity) do
    Logger.info("[#{severity}] Node #{node} disk usage: #{usage}%")
  end
end
```

<br />

##### **Platform engineering principles**
Platform engineering is the practice of building self-service platforms that reduce toil for the
entire organization, not just the SRE team. The key principles are:

<br />

> * **Golden paths**: Provide well-paved, opinionated defaults that work for 80% of use cases
> * **Self-service**: Developers should be able to do common tasks without filing tickets
> * **Guardrails, not gates**: Make the right thing easy and the wrong thing hard, but do not block people
> * **Documentation as code**: Keep docs next to the code they describe, version them together
> * **Feedback loops**: Measure how your platform is used and iterate based on real data

<br />

Here is an example of a self-service namespace provisioning system using a Kubernetes custom resource:

<br />

```yaml
# Self-service namespace request CRD
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: namespacerequests.platform.example.com
spec:
  group: platform.example.com
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: ["team", "environment"]
              properties:
                team:
                  type: string
                environment:
                  type: string
                  enum: ["dev", "staging", "production"]
                cpu_quota:
                  type: string
                  default: "4"
                memory_quota:
                  type: string
                  default: "8Gi"
            status:
              type: object
              properties:
                phase:
                  type: string
                message:
                  type: string
  scope: Cluster
  names:
    plural: namespacerequests
    singular: namespacerequest
    kind: NamespaceRequest
    shortNames:
      - nsr
```

<br />

Developers create a simple YAML file and submit a PR:

<br />

```yaml
# Request a new namespace
apiVersion: platform.example.com/v1
kind: NamespaceRequest
metadata:
  name: backend-staging
spec:
  team: backend
  environment: staging
  cpu_quota: "8"
  memory_quota: "16Gi"
```

<br />

A controller (or ArgoCD with hooks) picks up the request and creates the namespace with all the
standard configuration: resource quotas, limit ranges, network policies, RBAC, and monitoring.

<br />

##### **Reducing ticket-driven work**
Ticket-driven work is one of the biggest sources of toil. Every "please create X for me" ticket
is a signal that your platform is missing a self-service capability.

<br />

Here is a systematic approach to reducing ticket volume:

<br />

> 1. **Categorize your tickets**: Group them by type (access, provisioning, configuration, troubleshooting)
> 2. **Identify the top 3**: Focus on the categories that generate the most tickets
> 3. **Build self-service for each**: Create automation, documentation, or tooling
> 4. **Measure the impact**: Track ticket volume by category over time
> 5. **Repeat**: Move to the next top 3

<br />

For ChatOps-style automation, you can build Slack commands that trigger common operations:

<br />

```elixir
defmodule SreBot.SlackHandler do
  @moduledoc """
  Handles Slack slash commands for common SRE operations.
  """

  def handle_command("/sre-scale", %{text: text, user: user}) do
    case parse_scale_command(text) do
      {:ok, deployment, replicas} ->
        if authorized?(user, :scale) do
          case scale_deployment(deployment, replicas) do
            :ok ->
              {:ok, "Scaled #{deployment} to #{replicas} replicas. Use `/sre-scale #{deployment} status` to check."}
            {:error, reason} ->
              {:error, "Failed to scale #{deployment}: #{reason}"}
          end
        else
          {:error, "You are not authorized to scale deployments. Ask your team lead for access."}
        end
      {:error, :invalid} ->
        {:error, "Usage: `/sre-scale <deployment> <replicas>` or `/sre-scale <deployment> status`"}
    end
  end

  def handle_command("/sre-restart", %{text: text, user: user}) do
    deployment = String.trim(text)
    if authorized?(user, :restart) do
      case restart_deployment(deployment) do
        :ok ->
          {:ok, "Rolling restart initiated for #{deployment}. Pods will restart one at a time."}
        {:error, reason} ->
          {:error, "Failed to restart #{deployment}: #{reason}"}
      end
    else
      {:error, "You are not authorized to restart deployments."}
    end
  end

  defp parse_scale_command(text) do
    case String.split(String.trim(text)) do
      [deployment, replicas] ->
        case Integer.parse(replicas) do
          {n, ""} when n > 0 and n <= 50 -> {:ok, deployment, n}
          _ -> {:error, :invalid}
        end
      _ -> {:error, :invalid}
    end
  end

  defp authorized?(_user, _action), do: true
  defp scale_deployment(_deployment, _replicas), do: :ok
  defp restart_deployment(_deployment), do: :ok
end
```

<br />

##### **Automation safety**
Automation without safety is a recipe for automated disasters. Every automation should include
guardrails that prevent it from causing more damage than the problem it solves.

<br />

Key safety patterns:

<br />

> * **Dry-run mode**: Every automation should support a dry-run that shows what would happen without actually doing it
> * **Blast radius limits**: Limit the scope of automated actions (e.g., never delete more than 5 pods at once)
> * **Confirmation prompts**: For destructive actions, require explicit confirmation
> * **Rate limiting**: Prevent automation from running too frequently
> * **Circuit breakers**: If automation fails too many times, stop and alert a human
> * **Audit logging**: Record every automated action with who triggered it and what happened
> * **Rollback capability**: Every automated change should be reversible

<br />

Here is a safe automation wrapper:

<br />

```yaml
defmodule SreBot.SafeAction do
  @moduledoc """
  Wrapper for safe automated actions with dry-run,
  rate limiting, and circuit breaker support.
  """
  require Logger

  defstruct [
    :name,
    :action,
    :dry_run,
    :max_blast_radius,
    :rate_limit_per_hour,
    :circuit_breaker_threshold
  ]

  @doc """
  Execute an action with safety guardrails.
  """
  def execute(%__MODULE__{} = config, targets, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, config.dry_run)

    with :ok <- check_blast_radius(config, targets),
         :ok <- check_rate_limit(config),
         :ok <- check_circuit_breaker(config) do
      if dry_run do
        Logger.info("[DRY RUN] #{config.name}: Would affect #{length(targets)} targets")
        {:ok, :dry_run, targets}
      else
        results = Enum.map(targets, fn target ->
          try do
            result = config.action.(target)
            log_action(config.name, target, result)
            result
          rescue
            e ->
              record_failure(config.name)
              {:error, Exception.message(e)}
          end
        end)

        failures = Enum.filter(results, &match?({:error, _}, &1))
        if length(failures) > 0 do
          Logger.warning("#{config.name}: #{length(failures)}/#{length(targets)} actions failed")
        end

        {:ok, :executed, results}
      end
    end
  end

  defp check_blast_radius(config, targets) do
    if length(targets) > config.max_blast_radius do
      {:error, "Blast radius exceeded: #{length(targets)} targets > max #{config.max_blast_radius}"}
    else
      :ok
    end
  end

  defp check_rate_limit(config) do
    key = "rate:#{config.name}"
    count = get_counter(key)
    if count >= config.rate_limit_per_hour do
      {:error, "Rate limit exceeded: #{count} executions in the last hour"}
    else
      increment_counter(key)
      :ok
    end
  end

  defp check_circuit_breaker(config) do
    failures = get_failure_count(config.name)
    if failures >= config.circuit_breaker_threshold do
      {:error, "Circuit breaker open: #{failures} consecutive failures"}
    else
      :ok
    end
  end

  defp log_action(name, target, result) do
    Logger.info("Action #{name} on #{inspect(target)}: #{inspect(result)}")
  end

  defp record_failure(_name), do: :ok
  defp get_counter(_key), do: 0
  defp increment_counter(_key), do: :ok
  defp get_failure_count(_name), do: 0
end
```

<br />

Usage example:

<br />

```yaml
# Define a safe pod restart action
restart_action = %SreBot.SafeAction{
  name: "pod-restart",
  action: fn pod -> System.cmd("kubectl", ["delete", "pod", pod]) end,
  dry_run: false,
  max_blast_radius: 5,
  rate_limit_per_hour: 10,
  circuit_breaker_threshold: 3
}

# Execute with safety guardrails
SreBot.SafeAction.execute(restart_action, ["pod-1", "pod-2", "pod-3"])

# Execute in dry-run mode
SreBot.SafeAction.execute(restart_action, ["pod-1", "pod-2"], dry_run: true)
```

<br />

##### **Measuring toil reduction**
You cannot improve what you do not measure. Here are the key metrics to track:

<br />

> * **Toil percentage**: Hours spent on toil / total work hours. Target: below 50%.
> * **Ticket volume**: Number of operational tickets per week. Should trend down over time.
> * **Mean time to resolve tickets**: If you cannot eliminate tickets, at least make them faster.
> * **Manual intervention count**: How many times a human had to step in for something automated.
> * **Self-service adoption**: Percentage of provisioning done through self-service vs tickets.
> * **Automation coverage**: Percentage of known toil categories that have automation.

<br />

Here is a Prometheus metrics setup for tracking toil:

<br />

```yaml
# PrometheusRule for toil metrics
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: toil-metrics
  namespace: monitoring
spec:
  groups:
    - name: toil.tracking
      rules:
        # Track automation executions
        - record: sre:automation_executions:total
          expr: sum(automation_executions_total) by (action_name, result)

        # Track manual interventions
        - record: sre:manual_interventions:rate1w
          expr: sum(increase(manual_intervention_total[1w])) by (category)

        # Track ticket volume
        - record: sre:tickets:rate1w
          expr: sum(increase(sre_tickets_total[1w])) by (category, priority)

        # Self-service vs ticket ratio
        - record: sre:self_service_ratio
          expr: |
            sum(increase(self_service_requests_total[1w]))
            /
            (sum(increase(self_service_requests_total[1w])) + sum(increase(sre_tickets_total[1w])))

    - name: toil.alerts
      rules:
        - alert: ToilPercentageHigh
          expr: sre:toil_percentage > 50
          for: 1w
          labels:
            severity: warning
          annotations:
            summary: "Toil percentage exceeds 50% for the week"
            description: "The team is spending {{ $value }}% of time on toil. Review automation backlog."

        - alert: TicketVolumeSpike
          expr: sre:tickets:rate1w > 2 * avg_over_time(sre:tickets:rate1w[4w])
          for: 1d
          labels:
            severity: warning
          annotations:
            summary: "Ticket volume has doubled compared to 4-week average"
```

<br />

Build a Grafana dashboard that shows these metrics over time. Seeing the trend line go down is
incredibly motivating for the team.

<br />

##### **The 50 percent rule**
Google's SRE book states that SREs should spend no more than 50% of their time on toil. The remaining
50% should be spent on engineering work that improves the system and reduces future toil.

<br />

This is not just a nice idea. It is a structural requirement for a healthy SRE team. Here is why:

<br />

> * **Above 50% toil**: The team is drowning. They never have time to automate, so toil keeps growing. This is a death spiral.
> * **At 50% toil**: Barely sustainable. The team can maintain current automation but cannot make meaningful improvements.
> * **Below 50% toil**: The team has capacity to invest in engineering work. Toil decreases over time. This is the virtuous cycle you want.

<br />

How to enforce the 50% rule in practice:

<br />

> 1. **Track it weekly**: Use the toil tracking system described earlier. Make it visible.
> 2. **Set toil budgets**: Each team member gets a toil budget. When it is exceeded, escalate.
> 3. **Protect engineering time**: Block calendar time for engineering work. Do not let toil fill the gaps.
> 4. **Rotate toil**: Do not let the same person do all the toil. Rotate on-call and ticket duty.
> 5. **Escalate violations**: If toil exceeds 50% for two consecutive weeks, it is a management issue. Escalate to get resources or reduce scope.

<br />

When the 50% threshold is exceeded, here is the escalation process:

<br />

```yaml
# toil-escalation-policy.yaml
escalation_policy:
  thresholds:
    - level: "green"
      toil_percent: 0-30
      action: "Normal operations. Continue investing in automation."

    - level: "yellow"
      toil_percent: 30-50
      action: "Review automation backlog. Prioritize top toil reducers."

    - level: "orange"
      toil_percent: 50-65
      action: |
        Escalate to engineering manager.
        Pause non-critical feature work.
        Dedicate 1 engineer full-time to automation.
        Review if team is understaffed.

    - level: "red"
      toil_percent: 65-80
      action: |
        Escalate to director level.
        Pause all feature work.
        Entire team focuses on toil reduction.
        Consider temporary headcount increase.

    - level: "critical"
      toil_percent: 80-100
      action: |
        Escalate to VP level.
        Service reliability is at risk.
        Cross-team support needed.
        Emergency automation sprint.

  review_cadence: "Weekly at team standup"
  tracking: "Shared spreadsheet visible to management"
```

<br />

##### **Putting it all together**
Here is a practical roadmap for reducing toil in your organization:

<br />

> 1. **Week 1-2**: Start tracking toil. Have everyone log their work for two weeks.
> 2. **Week 3**: Analyze the data. Identify the top 5 toil categories by time spent.
> 3. **Week 4-6**: Automate the #1 toil category. Start with the quickest win.
> 4. **Week 7-8**: Measure the impact. Did ticket volume or time spent decrease?
> 5. **Week 9-12**: Automate #2 and #3. Build self-service where applicable.
> 6. **Ongoing**: Continue measuring, automating, and iterating. Make toil reduction a permanent sprint goal.

<br />

The key insight from the Google SRE book is this: toil is not just annoying, it is dangerous. Teams
buried in toil do not have time to improve systems, which means systems get less reliable, which means
more incidents, which means more toil. Breaking this cycle requires deliberate investment in
automation, and the discipline to protect that investment from being consumed by the next urgent ticket.

<br />

##### **Closing notes**
This wraps up our fourteen-part SRE series. We started with measuring reliability through
[SLIs and SLOs](/blog/sre-slis-slos-and-automations-that-actually-help) and ended here with reducing the
toil that prevents teams from doing meaningful engineering work. Along the way we covered incident
management, observability, chaos engineering, capacity planning, GitOps, secrets management, cost
optimization, dependency management, database reliability, release engineering, security as code,
and disaster recovery.

<br />

The common thread through all of these practices is this: treat operations as an engineering problem.
Measure what matters, automate what repeats, and invest in systems that get better over time instead
of requiring more human effort as they grow.

<br />

If you only take one thing from this series, let it be the 50% rule. Protect your team's time for
engineering work. The automation you build today is what keeps you from drowning tomorrow.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Reduccion de Toil y Automatizacion",
  author: "Gabriel Garrido",
  description: "Vamos a explorar estrategias de reduccion de toil del libro de Google SRE, desde identificar y medir el toil hasta construir sistemas auto-reparables, herramientas internas con Elixir, patrones de seguridad en automatizacion, y la regla del 50 por ciento...",
  tags: ~w(sre automation platform-engineering toil elixir),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
En los articulos anteriores cubrimos [SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[gestion de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observabilidad](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[planificacion de capacidad](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[gestion de secretos](/blog/sre-secrets-management-in-kubernetes),
[optimizacion de costos](/blog/sre-cost-optimization-in-the-cloud),
[gestion de dependencias](/blog/sre-dependency-management-and-graceful-degradation),
[confiabilidad de bases de datos](/blog/sre-database-reliability),
[ingenieria de releases](/blog/sre-release-engineering-and-progressive-delivery),
[seguridad como codigo](/blog/sre-security-as-code), y
[recuperacion ante desastres](/blog/sre-disaster-recovery-and-business-continuity). Son trece articulos
cubriendo las practicas fundamentales de Site Reliability Engineering.

<br />

En este articulo final de la serie, vamos a hablar sobre toil. El toil es el trabajo que mantiene
las luces encendidas pero no mueve las cosas hacia adelante. Es el trabajo manual, repetitivo,
automatizable que escala linealmente con el tamanio del servicio y no provee valor duradero. Todos
los equipos de SRE lo enfrentan, y como lo manejes determina si tu equipo puede realmente hacer
trabajo de ingenieria o solo apagar incendios todo el dia.

<br />

El libro de Google SRE tiene una regla famosa: los SREs no deberian gastar mas del 50% de su
tiempo en toil. El resto deberia ir a trabajo de ingenieria que reduzca el toil futuro. En la
practica, muchos equipos gastan mucho mas del 50% en toil y nunca llegan a la automatizacion que
los liberaria.

<br />

Vamos al tema.

<br />

##### **Que es el toil?**
No todo el trabajo operativo es toil. Google define el toil de manera muy especifica. Para que el
trabajo califique como toil, debe tener estas caracteristicas:

<br />

> * **Manual**: Un humano tiene que hacerlo. Si un script lo hace, no es toil.
> * **Repetitivo**: Lo haces una y otra vez. Una tarea unica no es toil, incluso si es manual.
> * **Automatizable**: Una maquina podria hacerlo. Si requiere juicio humano cada vez, no es toil (podria ser trabajo de ingenieria).
> * **Tactico**: Es reactivo, no proactivo. Lo haces en respuesta a algo que paso.
> * **Sin valor duradero**: Una vez hecho, no mejora el sistema. La proxima vez que pase, haces lo mismo de nuevo.
> * **Escala linealmente**: A medida que el servicio crece, el trabajo crece proporcionalmente.

<br />

Aca hay algunos ejemplos comunes de toil:

<br />

> * **Reiniciar pods manualmente** cuando se quedan en un mal estado
> * **Escalar servicios manualmente** antes de picos de trafico conocidos
> * **Procesar tickets de solicitud** para acceso a entornos, permisos de base de datos, o creacion de namespaces
> * **Correr migraciones de base de datos manualmente** o restauraciones de backup
> * **Rotar secretos manualmente** o certificados
> * **Copiar y pegar configuracion** entre entornos
> * **Revisar dashboards manualmente** para verificar que los deployments funcionaron
> * **Responder a alertas que siempre requieren el mismo fix** (reiniciar, limpiar cache, aumentar limites)

<br />

Si leiste esa lista y pensaste "hago la mitad de esas todas las semanas," no sos el unico. El
primer paso para reducir el toil es reconocerlo por lo que es.

<br />

##### **Identificando el toil**
No podes reducir lo que no medis. El primer paso es hacer un seguimiento sistematico de como tu
equipo gasta su tiempo. Esto no necesita ser sofisticado. Una planilla o formulario simple funciona
bien.

<br />

Aca hay una plantilla basica para rastrear toil:

<br />

```yaml
# toil-tracking.yaml
# Cada miembro del equipo completa esto semanalmente

categories:
  - name: "Solicitudes de acceso"
    description: "Otorgar permisos, crear cuentas, acceso a namespaces"
    examples:
      - "Crear namespace para el equipo X"
      - "Otorgar acceso de lectura a logs de produccion"
      - "Agregar usuario al RBAC de kubectl"

  - name: "Soporte de deployment"
    description: "Pasos manuales de deployment, rollbacks, verificacion"
    examples:
      - "Correr migracion de base de datos para el servicio Y"
      - "Verificar manualmente la salud del deployment"
      - "Hacer rollback de un deployment fallido"

  - name: "Respuesta a incidentes"
    description: "Fixes reactivos para problemas conocidos"
    examples:
      - "Reiniciar pod atascado en CrashLoopBackOff"
      - "Limpiar disco lleno en nodo"
      - "Aumentar limite de memoria para pod con OOM"

  - name: "Cambios de configuracion"
    description: "Actualizaciones manuales de config"
    examples:
      - "Actualizar variables de entorno"
      - "Rotar certificado expirado"
      - "Actualizar registro DNS"

  - name: "Monitoreo y alertas"
    description: "Chequeos de dashboard, ajuste de alertas"
    examples:
      - "Silenciar alerta ruidosa conocida"
      - "Revisar manualmente el dashboard de deployment"
      - "Investigar alerta de falso positivo"

tracking_fields:
  - task_description: "Que hiciste?"
  - category: "Que categoria?"
  - time_spent_minutes: "Cuanto tiempo te llevo?"
  - frequency: "Con que frecuencia pasa? (diario/semanal/mensual)"
  - automatable: "Podria hacerlo una maquina? (si/no/parcialmente)"
  - impact_if_not_done: "Que pasa si no lo haces? (caida/degradacion/nada)"
```

<br />

Despues de unas semanas de rastreo, vas a tener una imagen clara de donde va el tiempo. Ordena
por tiempo gastado y frecuencia, y tenes tu backlog priorizado de automatizacion.

<br />

Aca hay un modulo de Elixir para agregar datos de toil programaticamente:

<br />

```yaml
defmodule ToilTracker do
  @moduledoc """
  Rastrea y analiza el toil del equipo.
  Usa ETS para almacenamiento rapido en memoria.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    table = :ets.new(:toil_entries, [:bag, :named_table, :public])
    {:ok, %{table: table}}
  end

  def log_toil(entry) do
    :ets.insert(:toil_entries, {
      entry.category,
      entry.description,
      entry.time_minutes,
      entry.engineer,
      DateTime.utc_now()
    })
  end

  def weekly_summary do
    :ets.tab2list(:toil_entries)
    |> Enum.filter(fn {_, _, _, _, timestamp} ->
      DateTime.diff(DateTime.utc_now(), timestamp, :day) <= 7
    end)
    |> Enum.group_by(fn {category, _, _, _, _} -> category end)
    |> Enum.map(fn {category, entries} ->
      total_minutes = entries |> Enum.map(fn {_, _, mins, _, _} -> mins end) |> Enum.sum()
      count = length(entries)
      %{
        category: category,
        total_minutes: total_minutes,
        occurrences: count,
        avg_minutes: Float.round(total_minutes / count, 1)
      }
    end)
    |> Enum.sort_by(& &1.total_minutes, :desc)
  end

  def toil_percentage(total_work_hours \\ 40) do
    summary = weekly_summary()
    toil_hours = Enum.reduce(summary, 0, fn entry, acc -> acc + entry.total_minutes end) / 60
    Float.round(toil_hours / total_work_hours * 100, 1)
  end
end
```

<br />

##### **Sistemas auto-reparables**
La mejor manera de eliminar el toil es hacerlo innecesario. Los sistemas auto-reparables detectan
y se recuperan de modos de falla comunes sin intervencion humana. Kubernetes ya provee varios
mecanismos de auto-reparacion de fabrica.

<br />

Los **liveness probes** reinician contenedores que estan atascados:

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: my-app:latest
          livenessProbe:
            httpGet:
              path: /healthz
              port: 4000
            initialDelaySeconds: 15
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /readyz
              port: 4000
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 2
          startupProbe:
            httpGet:
              path: /healthz
              port: 4000
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 30
```

<br />

Los **PodDisruptionBudgets** previenen que demasiados pods caigan al mismo tiempo:

<br />

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: my-app
```

<br />

El **Horizontal Pod Autoscaler** maneja el escalado automaticamente:

<br />

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Percent
          value: 50
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 10
          periodSeconds: 120
```

<br />

Para auto-reparacion mas avanzada, podes construir operadores de Kubernetes personalizados. Aca hay
un ejemplo simple de un controlador que automaticamente reinicia pods que estuvieron en
CrashLoopBackOff por mucho tiempo:

<br />

```yaml
# Un CronJob que limpia pods atascados
apiVersion: batch/v1
kind: CronJob
metadata:
  name: stuck-pod-cleaner
  namespace: kube-system
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: pod-cleaner
          containers:
            - name: cleaner
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  # Encontrar pods en CrashLoopBackOff por mas de 30 minutos
                  kubectl get pods --all-namespaces -o json | \
                    jq -r '.items[] |
                      select(.status.containerStatuses[]?.state.waiting?.reason == "CrashLoopBackOff") |
                      select(
                        (.status.containerStatuses[0].state.waiting.reason == "CrashLoopBackOff") and
                        (.status.containerStatuses[0].restartCount > 10)
                      ) |
                      "\(.metadata.namespace) \(.metadata.name)"' | \
                  while read ns pod; do
                    echo "Borrando pod atascado $pod en namespace $ns"
                    kubectl delete pod "$pod" -n "$ns"
                  done
          restartPolicy: OnFailure
```

<br />

##### **Calculo del ROI de automatizacion**
No todo deberia ser automatizado. La automatizacion tiene un costo: el tiempo para construirla,
el tiempo para mantenerla, y el riesgo de bugs en la automatizacion misma. Necesitas un framework
simple para decidir que vale la pena automatizar.

<br />

La referencia clasica es el grafico de XKCD "Is It Worth the Time?". Aca hay una version practica:

<br />

```elixir
defmodule AutomationROI do
  @moduledoc """
  Calcula si automatizar una tarea vale la inversion.
  """

  @doc """
  Calcula el punto de equilibrio para automatizacion.

  ## Parametros
    - manual_time_minutes: Cuanto tarda la tarea manual
    - frequency_per_month: Con que frecuencia ocurre la tarea por mes
    - automation_hours: Horas estimadas para construir la automatizacion
    - maintenance_hours_per_month: Mantenimiento mensual estimado

  ## Retorna
    Mapa con analisis de punto de equilibrio
  """
  def calculate(manual_time_minutes, frequency_per_month, automation_hours, maintenance_hours_per_month \\ 0.5) do
    monthly_savings_hours = manual_time_minutes * frequency_per_month / 60
    net_monthly_savings = monthly_savings_hours - maintenance_hours_per_month

    break_even_months = if net_monthly_savings > 0 do
      Float.round(automation_hours / net_monthly_savings, 1)
    else
      :never
    end

    yearly_savings = net_monthly_savings * 12

    %{
      manual_time_per_month_hours: Float.round(monthly_savings_hours, 1),
      automation_cost_hours: automation_hours,
      maintenance_per_month_hours: maintenance_hours_per_month,
      net_savings_per_month_hours: Float.round(net_monthly_savings, 1),
      break_even_months: break_even_months,
      yearly_savings_hours: Float.round(yearly_savings, 1),
      recommendation: recommendation(break_even_months, yearly_savings)
    }
  end

  defp recommendation(:never, _), do: "No automatizar. El costo de mantenimiento supera el ahorro."
  defp recommendation(months, _) when months > 24, do: "Baja prioridad. Considera alternativas mas simples."
  defp recommendation(months, savings) when months <= 3 and savings > 20, do: "Automatizar ya. Alto impacto, retorno rapido."
  defp recommendation(months, _) when months <= 6, do: "Automatizar pronto. Buen retorno de inversion."
  defp recommendation(months, _) when months <= 12, do: "Automatizar cuando tengas tiempo. ROI moderado."
  defp recommendation(_, _), do: "Considera automatizacion parcial o mejora de procesos."
end
```

<br />

Aca hay como lo usarias:

<br />

```bash
# Ejemplo: Crear namespaces manualmente
# Lleva 15 minutos, pasa 8 veces por mes, 4 horas para automatizar
AutomationROI.calculate(15, 8, 4)
# => %{
#   manual_time_per_month_hours: 2.0,
#   automation_cost_hours: 4,
#   net_savings_per_month_hours: 1.5,
#   break_even_months: 2.7,
#   yearly_savings_hours: 18.0,
#   recommendation: "Automatizar ya. Alto impacto, retorno rapido."
# }

# Ejemplo: Rotar un certificado trimestralmente
# Lleva 30 minutos, pasa 0.33 veces por mes, 8 horas para automatizar
AutomationROI.calculate(30, 0.33, 8)
# => %{
#   manual_time_per_month_hours: 0.2,
#   automation_cost_hours: 8,
#   break_even_months: :never,
#   recommendation: "No automatizar. El costo de mantenimiento supera el ahorro."
# }
# Pero ojo: la rotacion de certs tiene riesgo (olvidarte = caida), asi que automatiza igual!
```

<br />

El calculo de ROI es un punto de partida, no la respuesta final. Algunas tareas deberian
automatizarse incluso si el ahorro de tiempo crudo no lo justifica:

<br />

> * **Tareas donde olvidarte causa caidas** (rotacion de certificados, verificacion de backups)
> * **Tareas que son propensas a errores** cuando se hacen manualmente (cambios de configuracion, actualizaciones de DNS)
> * **Tareas que bloquean a otras personas** (solicitudes de acceso, aprovisionamiento de entornos)
> * **Tareas que interrumpen trabajo profundo** (incluso tareas de 5 minutos rompen el flujo por 30 minutos)

<br />

##### **Construyendo herramientas internas con Elixir**
Elixir es una excelente opcion para construir herramientas internas de SRE. OTP te da arboles de
supervision para confiabilidad, GenServers para automatizacion con estado, y la VM de BEAM maneja
la concurrencia de forma hermosa.

<br />

Aca hay una Mix task para operaciones comunes de SRE:

<br />

```yaml
defmodule Mix.Tasks.Sre.Namespace do
  @moduledoc """
  Crea un nuevo namespace de Kubernetes con configuracion estandar.

  Uso:
    mix sre.namespace create --name mi-namespace --team backend --env staging
    mix sre.namespace list
    mix sre.namespace delete --name mi-namespace
  """
  use Mix.Task

  @shortdoc "Gestionar namespaces de Kubernetes"

  def run(args) do
    {opts, [action], _} = OptionParser.parse(args,
      strict: [name: :string, team: :string, env: :string],
      aliases: [n: :name, t: :team, e: :env]
    )

    case action do
      "create" -> create_namespace(opts)
      "list" -> list_namespaces()
      "delete" -> delete_namespace(opts)
    end
  end

  defp create_namespace(opts) do
    name = Keyword.fetch!(opts, :name)
    team = Keyword.fetch!(opts, :team)
    env = Keyword.get(opts, :env, "staging")

    manifest = """
    apiVersion: v1
    kind: Namespace
    metadata:
      name: #{name}
      labels:
        team: #{team}
        environment: #{env}
        managed-by: sre-tools
    ---
    apiVersion: v1
    kind: ResourceQuota
    metadata:
      name: default-quota
      namespace: #{name}
    spec:
      hard:
        requests.cpu: "4"
        requests.memory: 8Gi
        limits.cpu: "8"
        limits.memory: 16Gi
        pods: "50"
    ---
    apiVersion: v1
    kind: LimitRange
    metadata:
      name: default-limits
      namespace: #{name}
    spec:
      limits:
        - default:
            cpu: 500m
            memory: 512Mi
          defaultRequest:
            cpu: 100m
            memory: 128Mi
          type: Container
    ---
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: #{name}
    spec:
      podSelector: {}
      policyTypes:
        - Ingress
    """

    File.write!("/tmp/namespace-#{name}.yaml", manifest)
    {output, 0} = System.cmd("kubectl", ["apply", "-f", "/tmp/namespace-#{name}.yaml"])
    Mix.shell().info("Namespace #{name} creado con configuracion estandar")
    Mix.shell().info(output)
  end

  defp list_namespaces do
    {output, 0} = System.cmd("kubectl", [
      "get", "namespaces",
      "-l", "managed-by=sre-tools",
      "-o", "custom-columns=NAME:.metadata.name,TEAM:.metadata.labels.team,ENV:.metadata.labels.environment,AGE:.metadata.creationTimestamp"
    ])
    Mix.shell().info(output)
  end

  defp delete_namespace(opts) do
    name = Keyword.fetch!(opts, :name)
    Mix.shell().info("Estas seguro de que queres borrar el namespace #{name}? (si/no)")
    case IO.gets("") |> String.trim() do
      "si" ->
        {output, 0} = System.cmd("kubectl", ["delete", "namespace", name])
        Mix.shell().info("Namespace #{name} borrado")
        Mix.shell().info(output)
      _ ->
        Mix.shell().info("Cancelado")
    end
  end
end
```

<br />

Aca hay un agente de automatizacion basado en GenServer que vigila condiciones y toma accion:

<br />

```yaml
defmodule SreBot.DiskWatcher do
  @moduledoc """
  Vigila el uso de disco de los nodos y automaticamente
  limpia cuando el uso supera los umbrales.
  """
  use GenServer
  require Logger

  @check_interval :timer.minutes(5)
  @warning_threshold 80
  @critical_threshold 90

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_check()
    {:ok, %{last_alert: nil}}
  end

  def handle_info(:check_disk, state) do
    state = check_all_nodes(state)
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_disk, @check_interval)
  end

  defp check_all_nodes(state) do
    case get_node_disk_usage() do
      {:ok, nodes} ->
        Enum.reduce(nodes, state, fn node, acc ->
          handle_node_disk(node, acc)
        end)
      {:error, reason} ->
        Logger.error("Fallo al verificar uso de disco: #{inspect(reason)}")
        state
    end
  end

  defp handle_node_disk(%{name: name, usage_percent: usage}, state) when usage >= @critical_threshold do
    Logger.warning("Nodo #{name} disco al #{usage}% - ejecutando limpieza")
    run_cleanup(name)
    send_alert(name, usage, :critical)
    state
  end

  defp handle_node_disk(%{name: name, usage_percent: usage}, state) when usage >= @warning_threshold do
    Logger.info("Nodo #{name} disco al #{usage}% - umbral de advertencia")
    send_alert(name, usage, :warning)
    state
  end

  defp handle_node_disk(_node, state), do: state

  defp run_cleanup(node_name) do
    System.cmd("kubectl", [
      "debug", "node/#{node_name}", "--",
      "crictl", "rmi", "--prune"
    ])

    System.cmd("kubectl", [
      "debug", "node/#{node_name}", "--",
      "find", "/var/log/containers", "-mtime", "+7", "-delete"
    ])

    Logger.info("Limpieza completada en nodo #{node_name}")
  end

  defp get_node_disk_usage do
    case System.cmd("kubectl", ["get", "nodes", "-o", "json"]) do
      {output, 0} ->
        nodes = output
        |> Jason.decode!()
        |> Map.get("items", [])
        |> Enum.map(fn node ->
          name = get_in(node, ["metadata", "name"])
          %{name: name, usage_percent: get_disk_usage_for_node(name)}
        end)
        {:ok, nodes}
      {_, code} ->
        {:error, "kubectl termino con codigo #{code}"}
    end
  end

  defp get_disk_usage_for_node(_name), do: Enum.random(50..95)

  defp send_alert(node, usage, severity) do
    Logger.info("[#{severity}] Nodo #{node} uso de disco: #{usage}%")
  end
end
```

<br />

##### **Principios de ingenieria de plataformas**
La ingenieria de plataformas es la practica de construir plataformas de autoservicio que reducen
el toil para toda la organizacion, no solo para el equipo de SRE. Los principios clave son:

<br />

> * **Caminos dorados**: Provee defaults bien definidos y con opiniones que funcionan para el 80% de los casos de uso
> * **Autoservicio**: Los desarrolladores deberian poder hacer tareas comunes sin crear tickets
> * **Barandas, no puertas**: Hace que lo correcto sea facil y lo incorrecto sea dificil, pero no bloquees a la gente
> * **Documentacion como codigo**: Mantene los docs junto al codigo que describen, versionandolos juntos
> * **Loops de feedback**: Medi como se usa tu plataforma e itera basandote en datos reales

<br />

Aca hay un ejemplo de un sistema de aprovisionamiento de namespaces por autoservicio usando un
recurso personalizado de Kubernetes:

<br />

```yaml
# CRD de solicitud de namespace por autoservicio
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: namespacerequests.platform.example.com
spec:
  group: platform.example.com
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: ["team", "environment"]
              properties:
                team:
                  type: string
                environment:
                  type: string
                  enum: ["dev", "staging", "production"]
                cpu_quota:
                  type: string
                  default: "4"
                memory_quota:
                  type: string
                  default: "8Gi"
            status:
              type: object
              properties:
                phase:
                  type: string
                message:
                  type: string
  scope: Cluster
  names:
    plural: namespacerequests
    singular: namespacerequest
    kind: NamespaceRequest
    shortNames:
      - nsr
```

<br />

Los desarrolladores crean un archivo YAML simple y envian un PR:

<br />

```yaml
# Solicitar un nuevo namespace
apiVersion: platform.example.com/v1
kind: NamespaceRequest
metadata:
  name: backend-staging
spec:
  team: backend
  environment: staging
  cpu_quota: "8"
  memory_quota: "16Gi"
```

<br />

Un controlador (o ArgoCD con hooks) toma la solicitud y crea el namespace con toda la configuracion
estandar: resource quotas, limit ranges, network policies, RBAC, y monitoreo.

<br />

##### **Reduciendo trabajo por tickets**
El trabajo por tickets es una de las mayores fuentes de toil. Cada ticket de "por favor crea X
para mi" es una senial de que tu plataforma le falta una capacidad de autoservicio.

<br />

Aca hay un enfoque sistematico para reducir el volumen de tickets:

<br />

> 1. **Categoriza tus tickets**: Agrupa por tipo (acceso, aprovisionamiento, configuracion, troubleshooting)
> 2. **Identifica los top 3**: Enfocate en las categorias que generan mas tickets
> 3. **Construi autoservicio para cada una**: Crea automatizacion, documentacion, o herramientas
> 4. **Medi el impacto**: Rastrea el volumen de tickets por categoria a lo largo del tiempo
> 5. **Repeti**: Pasa a los siguientes top 3

<br />

Para automatizacion estilo ChatOps, podes construir comandos de Slack que disparen operaciones comunes:

<br />

```elixir
defmodule SreBot.SlackHandler do
  @moduledoc """
  Maneja comandos slash de Slack para operaciones comunes de SRE.
  """

  def handle_command("/sre-scale", %{text: text, user: user}) do
    case parse_scale_command(text) do
      {:ok, deployment, replicas} ->
        if authorized?(user, :scale) do
          case scale_deployment(deployment, replicas) do
            :ok ->
              {:ok, "Escalado #{deployment} a #{replicas} replicas. Usa `/sre-scale #{deployment} status` para chequear."}
            {:error, reason} ->
              {:error, "Fallo al escalar #{deployment}: #{reason}"}
          end
        else
          {:error, "No tenes autorizacion para escalar deployments. Pedile acceso a tu team lead."}
        end
      {:error, :invalid} ->
        {:error, "Uso: `/sre-scale <deployment> <replicas>` o `/sre-scale <deployment> status`"}
    end
  end

  def handle_command("/sre-restart", %{text: text, user: user}) do
    deployment = String.trim(text)
    if authorized?(user, :restart) do
      case restart_deployment(deployment) do
        :ok ->
          {:ok, "Rolling restart iniciado para #{deployment}. Los pods se van a reiniciar uno a la vez."}
        {:error, reason} ->
          {:error, "Fallo al reiniciar #{deployment}: #{reason}"}
      end
    else
      {:error, "No tenes autorizacion para reiniciar deployments."}
    end
  end

  defp parse_scale_command(text) do
    case String.split(String.trim(text)) do
      [deployment, replicas] ->
        case Integer.parse(replicas) do
          {n, ""} when n > 0 and n <= 50 -> {:ok, deployment, n}
          _ -> {:error, :invalid}
        end
      _ -> {:error, :invalid}
    end
  end

  defp authorized?(_user, _action), do: true
  defp scale_deployment(_deployment, _replicas), do: :ok
  defp restart_deployment(_deployment), do: :ok
end
```

<br />

##### **Seguridad en la automatizacion**
La automatizacion sin seguridad es una receta para desastres automatizados. Cada automatizacion
deberia incluir barandas que prevengan que cause mas dano que el problema que resuelve.

<br />

Patrones clave de seguridad:

<br />

> * **Modo dry-run**: Cada automatizacion deberia soportar un dry-run que muestre que pasaria sin hacerlo realmente
> * **Limites de radio de explosion**: Limita el alcance de acciones automatizadas (ej: nunca borrar mas de 5 pods a la vez)
> * **Prompts de confirmacion**: Para acciones destructivas, requeri confirmacion explicita
> * **Rate limiting**: Preveni que la automatizacion corra demasiado frecuentemente
> * **Circuit breakers**: Si la automatizacion falla demasiadas veces, para y alerta a un humano
> * **Logging de auditoria**: Registra cada accion automatizada con quien la disparo y que paso
> * **Capacidad de rollback**: Cada cambio automatizado deberia ser reversible

<br />

Aca hay un wrapper de automatizacion segura:

<br />

```yaml
defmodule SreBot.SafeAction do
  @moduledoc """
  Wrapper para acciones automatizadas seguras con dry-run,
  rate limiting, y soporte de circuit breaker.
  """
  require Logger

  defstruct [
    :name,
    :action,
    :dry_run,
    :max_blast_radius,
    :rate_limit_per_hour,
    :circuit_breaker_threshold
  ]

  @doc """
  Ejecuta una accion con barandas de seguridad.
  """
  def execute(%__MODULE__{} = config, targets, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, config.dry_run)

    with :ok <- check_blast_radius(config, targets),
         :ok <- check_rate_limit(config),
         :ok <- check_circuit_breaker(config) do
      if dry_run do
        Logger.info("[DRY RUN] #{config.name}: Afectaria #{length(targets)} objetivos")
        {:ok, :dry_run, targets}
      else
        results = Enum.map(targets, fn target ->
          try do
            result = config.action.(target)
            log_action(config.name, target, result)
            result
          rescue
            e ->
              record_failure(config.name)
              {:error, Exception.message(e)}
          end
        end)

        failures = Enum.filter(results, &match?({:error, _}, &1))
        if length(failures) > 0 do
          Logger.warning("#{config.name}: #{length(failures)}/#{length(targets)} acciones fallaron")
        end

        {:ok, :executed, results}
      end
    end
  end

  defp check_blast_radius(config, targets) do
    if length(targets) > config.max_blast_radius do
      {:error, "Radio de explosion excedido: #{length(targets)} objetivos > max #{config.max_blast_radius}"}
    else
      :ok
    end
  end

  defp check_rate_limit(config) do
    key = "rate:#{config.name}"
    count = get_counter(key)
    if count >= config.rate_limit_per_hour do
      {:error, "Rate limit excedido: #{count} ejecuciones en la ultima hora"}
    else
      increment_counter(key)
      :ok
    end
  end

  defp check_circuit_breaker(config) do
    failures = get_failure_count(config.name)
    if failures >= config.circuit_breaker_threshold do
      {:error, "Circuit breaker abierto: #{failures} fallas consecutivas"}
    else
      :ok
    end
  end

  defp log_action(name, target, result) do
    Logger.info("Accion #{name} en #{inspect(target)}: #{inspect(result)}")
  end

  defp record_failure(_name), do: :ok
  defp get_counter(_key), do: 0
  defp increment_counter(_key), do: :ok
  defp get_failure_count(_name), do: 0
end
```

<br />

Ejemplo de uso:

<br />

```yaml
# Definir una accion segura de reinicio de pods
restart_action = %SreBot.SafeAction{
  name: "pod-restart",
  action: fn pod -> System.cmd("kubectl", ["delete", "pod", pod]) end,
  dry_run: false,
  max_blast_radius: 5,
  rate_limit_per_hour: 10,
  circuit_breaker_threshold: 3
}

# Ejecutar con barandas de seguridad
SreBot.SafeAction.execute(restart_action, ["pod-1", "pod-2", "pod-3"])

# Ejecutar en modo dry-run
SreBot.SafeAction.execute(restart_action, ["pod-1", "pod-2"], dry_run: true)
```

<br />

##### **Midiendo la reduccion de toil**
No podes mejorar lo que no medis. Aca estan las metricas clave para rastrear:

<br />

> * **Porcentaje de toil**: Horas gastadas en toil / horas totales de trabajo. Objetivo: por debajo del 50%.
> * **Volumen de tickets**: Numero de tickets operativos por semana. Deberia tender a bajar con el tiempo.
> * **Tiempo promedio de resolucion de tickets**: Si no podes eliminar tickets, al menos hacelos mas rapidos.
> * **Conteo de intervenciones manuales**: Cuantas veces un humano tuvo que intervenir en algo automatizado.
> * **Adopcion del autoservicio**: Porcentaje de aprovisionamiento hecho por autoservicio vs tickets.
> * **Cobertura de automatizacion**: Porcentaje de categorias de toil conocidas que tienen automatizacion.

<br />

Aca hay un setup de metricas de Prometheus para rastrear toil:

<br />

```yaml
# PrometheusRule para metricas de toil
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: toil-metrics
  namespace: monitoring
spec:
  groups:
    - name: toil.tracking
      rules:
        # Rastrear ejecuciones de automatizacion
        - record: sre:automation_executions:total
          expr: sum(automation_executions_total) by (action_name, result)

        # Rastrear intervenciones manuales
        - record: sre:manual_interventions:rate1w
          expr: sum(increase(manual_intervention_total[1w])) by (category)

        # Rastrear volumen de tickets
        - record: sre:tickets:rate1w
          expr: sum(increase(sre_tickets_total[1w])) by (category, priority)

        # Ratio autoservicio vs tickets
        - record: sre:self_service_ratio
          expr: |
            sum(increase(self_service_requests_total[1w]))
            /
            (sum(increase(self_service_requests_total[1w])) + sum(increase(sre_tickets_total[1w])))

    - name: toil.alerts
      rules:
        - alert: ToilPercentageHigh
          expr: sre:toil_percentage > 50
          for: 1w
          labels:
            severity: warning
          annotations:
            summary: "El porcentaje de toil excede el 50% en la semana"
            description: "El equipo esta gastando {{ $value }}% del tiempo en toil. Revisar backlog de automatizacion."

        - alert: TicketVolumeSpike
          expr: sre:tickets:rate1w > 2 * avg_over_time(sre:tickets:rate1w[4w])
          for: 1d
          labels:
            severity: warning
          annotations:
            summary: "El volumen de tickets se duplico comparado con el promedio de 4 semanas"
```

<br />

Construi un dashboard de Grafana que muestre estas metricas a lo largo del tiempo. Ver la linea de
tendencia bajar es increiblemente motivante para el equipo.

<br />

##### **La regla del 50 por ciento**
El libro de Google SRE dice que los SREs no deberian gastar mas del 50% de su tiempo en toil. El
50% restante deberia gastarse en trabajo de ingenieria que mejore el sistema y reduzca el toil futuro.

<br />

Esto no es solo una idea copada. Es un requisito estructural para un equipo de SRE saludable.
Aca esta el por que:

<br />

> * **Mas del 50% de toil**: El equipo se esta ahogando. Nunca tienen tiempo de automatizar, asi que el toil sigue creciendo. Es una espiral de muerte.
> * **Al 50% de toil**: Apenas sostenible. El equipo puede mantener la automatizacion actual pero no puede hacer mejoras significativas.
> * **Menos del 50% de toil**: El equipo tiene capacidad para invertir en trabajo de ingenieria. El toil decrece con el tiempo. Este es el ciclo virtuoso que queres.

<br />

Como enforcar la regla del 50% en la practica:

<br />

> 1. **Rastrealo semanalmente**: Usa el sistema de rastreo de toil descrito antes. Hacelo visible.
> 2. **Asigna presupuestos de toil**: Cada miembro del equipo tiene un presupuesto de toil. Cuando se excede, escala.
> 3. **Protege el tiempo de ingenieria**: Bloquea tiempo en el calendario para trabajo de ingenieria. No dejes que el toil llene los huecos.
> 4. **Rota el toil**: No dejes que la misma persona haga todo el toil. Rota guardia y deber de tickets.
> 5. **Escala violaciones**: Si el toil excede el 50% por dos semanas consecutivas, es un problema de gestion. Escala para conseguir recursos o reducir el alcance.

<br />

Cuando el umbral del 50% se excede, aca esta el proceso de escalamiento:

<br />

```yaml
# toil-escalation-policy.yaml
escalation_policy:
  thresholds:
    - level: "verde"
      toil_percent: 0-30
      action: "Operaciones normales. Segui invirtiendo en automatizacion."

    - level: "amarillo"
      toil_percent: 30-50
      action: "Revisa el backlog de automatizacion. Prioriza los mayores reductores de toil."

    - level: "naranja"
      toil_percent: 50-65
      action: |
        Escala al engineering manager.
        Pausa trabajo de features no criticas.
        Dedica 1 ingeniero full-time a automatizacion.
        Revisa si el equipo esta con poca gente.

    - level: "rojo"
      toil_percent: 65-80
      action: |
        Escala a nivel director.
        Pausa todo el trabajo de features.
        Todo el equipo se enfoca en reduccion de toil.
        Considera aumento temporal de headcount.

    - level: "critico"
      toil_percent: 80-100
      action: |
        Escala a nivel VP.
        La confiabilidad del servicio esta en riesgo.
        Se necesita soporte cross-team.
        Sprint de emergencia de automatizacion.

  review_cadence: "Semanal en la standup del equipo"
  tracking: "Planilla compartida visible para management"
```

<br />

##### **Juntando todo**
Aca hay un roadmap practico para reducir el toil en tu organizacion:

<br />

> 1. **Semana 1-2**: Empieza a rastrear el toil. Que todos registren su trabajo por dos semanas.
> 2. **Semana 3**: Analiza los datos. Identifica las top 5 categorias de toil por tiempo gastado.
> 3. **Semana 4-6**: Automatiza la categoria #1 de toil. Empieza con la ganancia mas rapida.
> 4. **Semana 7-8**: Medi el impacto. Bajo el volumen de tickets o el tiempo gastado?
> 5. **Semana 9-12**: Automatiza #2 y #3. Construi autoservicio donde sea aplicable.
> 6. **Continuo**: Segui midiendo, automatizando, e iterando. Hace la reduccion de toil un objetivo permanente del sprint.

<br />

La idea clave del libro de Google SRE es esta: el toil no es solo molesto, es peligroso. Los
equipos enterrados en toil no tienen tiempo de mejorar los sistemas, lo que significa que los
sistemas se vuelven menos confiables, lo que significa mas incidentes, lo que significa mas toil.
Romper este ciclo requiere inversion deliberada en automatizacion, y la disciplina para proteger
esa inversion de ser consumida por el proximo ticket urgente.

<br />

##### **Notas finales**
Esto cierra nuestra serie de catorce partes sobre SRE. Empezamos midiendo la confiabilidad a traves
de [SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help) y terminamos aca con la
reduccion del toil que previene que los equipos hagan trabajo significativo de ingenieria. En el
camino cubrimos gestion de incidentes, observabilidad, chaos engineering, planificacion de capacidad,
GitOps, gestion de secretos, optimizacion de costos, gestion de dependencias, confiabilidad de
bases de datos, ingenieria de releases, seguridad como codigo, y recuperacion ante desastres.

<br />

El hilo comun a traves de todas estas practicas es este: trata las operaciones como un problema
de ingenieria. Medi lo que importa, automatiza lo que se repite, e inverti en sistemas que mejoren
con el tiempo en lugar de requerir mas esfuerzo humano a medida que crecen.

<br />

Si solo te llevas una cosa de esta serie, que sea la regla del 50%. Protege el tiempo de tu equipo
para trabajo de ingenieria. La automatizacion que construis hoy es lo que te salva de ahogarte
maniana.

<br />

Espero que te haya resultado util y lo hayas disfrutado! Hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en las [fuentes aca](https://github.com/kainlite/tr)

<br />
