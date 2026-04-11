%{
  title: "DevOps from Zero to Hero: Incident Response and On-Call",
  author: "Gabriel Garrido",
  description: "We will cover the fundamentals of incident response, severity levels, on-call rotations, alerting tools, runbooks, blameless postmortems, and how to build a healthy on-call culture that does not burn people out...",
  tags: ~w(devops incident-response on-call reliability beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article nineteen of the DevOps from Zero to Hero series. In the previous articles we set
up observability with Prometheus and Grafana, built dashboards, configured alerts, and deployed
complete CI/CD pipelines. Everything is monitored and automated. But here is the question nobody
wants to ask: what happens at 3am when an alert fires and your API is down?

<br />

That is what incident response is about. It is the human side of reliability. You can have the best
monitoring in the world, but if nobody knows what to do when an alert goes off, it does not matter.
In this article we are going to cover the fundamentals: what incidents are, how to classify them,
how on-call rotations work, how to write runbooks that actually help, and how to learn from failures
without blaming anyone.

<br />

This is a beginner-friendly introduction. If you want to go deeper into topics like incident
commanders, SRE-specific practices, postmortems as code, and advanced on-call automation, check out the
[SRE Incident Management](/blog/sre-incident-management-on-call-and-postmortems-as-code) article
from the SRE series. That article assumes you already understand the basics we cover here.

<br />

Let's get into it.

<br />

##### **What is an incident?**
An incident is any unplanned event that disrupts or degrades a service for your users. Not every bug
is an incident. A typo in a footer is a bug. Your payment processing being down for 500 users is an
incident. The key distinction is user impact.

<br />

Most teams classify incidents by severity levels. The exact definitions vary between organizations,
but here is a common framework:

<br />

> * **SEV1 (Critical)**: Complete service outage or data loss. All or most users are affected. Example: the entire API is returning 500 errors, the database is unreachable, or customer data has been corrupted. This requires all hands on deck, immediately.
> * **SEV2 (Major)**: Significant degradation but the service is partially working. Example: response times are 10x slower than normal, a key feature like checkout is broken, or 30% of requests are failing. This needs immediate attention from the on-call engineer.
> * **SEV3 (Minor)**: A noticeable issue that affects a small number of users or a non-critical feature. Example: search suggestions are not loading, a dashboard widget shows stale data, or image uploads are slow. This should be addressed during business hours.
> * **SEV4 (Low)**: A cosmetic issue or minor inconvenience with minimal user impact. Example: a tooltip has the wrong text, a non-critical background job is retrying more than usual, or a monitoring dashboard has a broken panel. This goes into the normal backlog.

<br />

The severity level determines everything else: who gets paged, how fast you need to respond, whether
you need a status page update, and how much of the team gets pulled in. Getting this classification
right is important because over-escalating burns people out and under-escalating lets problems grow.

<br />

##### **The incident lifecycle**
Every incident, regardless of severity, follows the same basic lifecycle. Understanding these phases
helps you stay organized when things are stressful.

<br />

```plaintext
  Detect ──> Respond ──> Mitigate ──> Resolve ──> Learn
    │           │            │            │           │
    │           │            │            │           │
  Alerts     Page the     Stop the     Fix the     Run a
  fire       on-call      bleeding     root        postmortem
             engineer                  cause
```

<br />

Let's walk through each phase:

<br />

**1. Detect**

<br />

Something tells you there is a problem. Ideally, your monitoring catches it before users do. In
[article fifteen](/blog/devops-from-zero-to-hero-observability) we set up Prometheus alerts that
fire when error rates or latency exceed thresholds. Those alerts are your first line of detection.
Other sources include health check failures, user reports, and automated smoke tests from your CI/CD
pipeline.

<br />

The goal is simple: know about problems before your users tweet about them.

<br />

**2. Respond**

<br />

The alert reaches the on-call engineer through a tool like PagerDuty or OpsGenie. The on-call
engineer acknowledges the alert (so the system knows someone is looking at it), assesses the severity,
and decides if they need to pull in more people. For a SEV1, they might immediately start a war room.
For a SEV3, they might just open a ticket and investigate during normal hours.

<br />

**3. Mitigate**

<br />

This is the most important phase and the one that trips up beginners. Mitigation is not about finding
the root cause. It is about stopping the user impact as fast as possible. If your API is slow because
a bad deployment went out, you roll back first and investigate later. If a database is overwhelmed,
you scale it up or redirect traffic. Fix it enough to stop the pain, then figure out why it happened.

<br />

Common mitigation actions include:

<br />

> * **Rollback**: Revert the last deployment if the issue started after a deploy
> * **Restart**: Sometimes a simple pod restart clears a stuck process
> * **Scale up**: Add more replicas or increase resource limits
> * **Feature flag**: Disable a broken feature without rolling back everything
> * **Traffic shift**: Route users to a healthy region or instance

<br />

**4. Resolve**

<br />

Once users are no longer affected, you can take the time to find and fix the actual root cause. Maybe
the deployment was fine but it exposed a latent bug triggered by a specific data pattern. Maybe the
database needs an index. Maybe the retry logic is creating a thundering herd. This is where you do
the real engineering work.

<br />

**5. Learn**

<br />

After the incident is resolved, you run a postmortem. We will cover this in detail later in the
article, but the short version is: you document what happened, build a timeline, identify the root
cause, and create action items to prevent it from happening again. No blame. Just learning.

<br />

##### **On-call basics**
On-call means you are the designated person who responds when alerts fire outside of normal working
hours (and often during them too). If you have never been on call before, the idea can be intimidating.
Let's break it down.

<br />

**What does being on call actually mean?**

<br />

When you are on call, you carry a phone (or have a laptop nearby) and you commit to responding to
alerts within a defined time window, usually 5 to 15 minutes for critical alerts. You do not need to
be sitting at your computer staring at dashboards. You can go to dinner, watch a movie, or sleep. But
you need to be reachable and able to start investigating within the response time.

<br />

**Rotation schedules**

<br />

No one should be on call all the time. Teams set up rotations where the on-call responsibility passes
from person to person on a regular schedule. Common patterns include:

<br />

> * **Weekly rotation**: Person A is on call Monday to Monday, then Person B takes over. Simple and predictable. Works well for teams of 4 or more.
> * **Daily rotation**: On-call shifts change every day. Less burden per shift but more handoffs. Good for teams that want to spread the load evenly.
> * **Follow-the-sun**: If your team spans time zones, each region covers their daytime hours. Nobody gets woken up at 3am. This is the dream, but requires a globally distributed team.
> * **Primary and secondary**: Two people are on call at the same time. The primary gets paged first. If they do not respond within the escalation window (say 10 minutes), the secondary gets paged. This provides a safety net.

<br />

**Compensation**

<br />

Being on call is work. Good organizations compensate for it. This can take different forms: extra pay
for on-call shifts, time off after a busy on-call week, or a flat per-shift stipend. The specific
approach varies, but the principle is clear: if you are asking someone to be available outside normal
hours, you should recognize and compensate that time. Teams that do not compensate on-call eventually
lose their best engineers.

<br />

**Handoff procedures**

<br />

When your on-call shift ends and someone else takes over, you should do a proper handoff. This means
summarizing any ongoing issues, alerting quirks you noticed, or anything the next person should know.
A quick message in Slack or a shared document works. The worst thing is inheriting an on-call shift
with no context about what has been happening.

<br />

##### **On-call tools**
You need a tool that receives alerts from your monitoring system and routes them to the right person
at the right time through the right channel (phone call, SMS, push notification, Slack). Here are the
most common options:

<br />

> * **PagerDuty**: The most established incident management platform. It handles alert routing, escalation policies, on-call schedules, and incident tracking. It integrates with everything: Prometheus, Grafana, AWS CloudWatch, Datadog, you name it. It is the industry standard but it is also the most expensive option.
> * **OpsGenie (by Atlassian)**: Similar to PagerDuty in features, with strong integrations into the Atlassian ecosystem (Jira, Confluence, Statuspage). A solid choice if your team already uses Atlassian tools. Pricing is more accessible than PagerDuty.
> * **Grafana OnCall**: An open-source option that integrates natively with Grafana. If you already use the Grafana stack for observability (as we set up in article fifteen), this is a natural fit. You can self-host it or use the Grafana Cloud managed version. It handles schedules, escalations, and routing, and it is free for self-hosted.

<br />

All three tools follow the same basic flow:

<br />

```plaintext
Prometheus Alert
    │
    ▼
Alertmanager ──> Webhook ──> PagerDuty / OpsGenie / Grafana OnCall
                                │
                                ▼
                          On-call schedule
                                │
                                ▼
                         Page the on-call engineer
                         (phone, SMS, push, Slack)
                                │
                    ┌───────────┴───────────┐
                    │                       │
              Acknowledged            Not acknowledged
              within SLA              within escalation window
                    │                       │
                    ▼                       ▼
              Engineer works          Page secondary /
              the incident           escalate to manager
```

<br />

##### **Setting up alerting to on-call tools**
In [article fifteen](/blog/devops-from-zero-to-hero-observability) we configured Prometheus alerts
using PrometheusRule resources. Those alerts go to Alertmanager, which is part of the kube-prometheus-stack.
Now we need to connect Alertmanager to an on-call tool so alerts actually reach a human.

<br />

Here is how you configure Alertmanager to send critical alerts to PagerDuty and non-critical alerts
to a Slack channel:

<br />

```yaml
# alertmanager-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m

    route:
      receiver: slack-default
      group_by: [alertname, namespace]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h

      routes:
        # Critical alerts go to PagerDuty
        - receiver: pagerduty-critical
          match:
            severity: critical
          continue: false

        # Warning alerts go to Slack only
        - receiver: slack-warnings
          match:
            severity: warning
          continue: false

    receivers:
      - name: slack-default
        slack_configs:
          - api_url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
            channel: "#alerts"
            title: '{{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

      - name: pagerduty-critical
        pagerduty_configs:
          - routing_key: "YOUR_PAGERDUTY_INTEGRATION_KEY"
            severity: critical
            description: '{{ .GroupLabels.alertname }}'
            details:
              namespace: '{{ .GroupLabels.namespace }}'
              summary: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

      - name: slack-warnings
        slack_configs:
          - api_url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
            channel: "#alerts-low-priority"
            title: '{{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

<br />

For OpsGenie, you would replace the `pagerduty_configs` with:

<br />

```yaml
      - name: opsgenie-critical
        opsgenie_configs:
          - api_key: "YOUR_OPSGENIE_API_KEY"
            message: '{{ .GroupLabels.alertname }}'
            priority: P1
            description: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

<br />

For Grafana OnCall, you typically use a webhook receiver that points to your Grafana OnCall instance:

<br />

```yaml
      - name: grafana-oncall
        webhook_configs:
          - url: "https://oncall.your-grafana.com/integrations/v1/alertmanager/YOUR_ID/"
            send_resolved: true
```

<br />

The key concept is routing. Not every alert should wake someone up. Route by severity: critical alerts
page the on-call, warnings go to Slack, and informational alerts go to a low-priority channel. This
is foundational for avoiding alert fatigue.

<br />

##### **Alert fatigue**
Alert fatigue is the number one killer of on-call programs. It happens when engineers get so many
alerts that they start ignoring them. When you are getting paged 20 times a night, you stop taking
alerts seriously. And when you stop taking alerts seriously, the one real outage that matters gets
lost in the noise.

<br />

Here is the hard truth: too many alerts is worse than too few. With too few alerts, you might miss
something, but at least when an alert fires, people pay attention. With too many alerts, people tune
them out entirely, and you miss everything.

<br />

**Signs of alert fatigue:**

<br />

> * **High acknowledge rate, low action rate**: People click "acknowledge" on alerts just to silence them, without actually investigating.
> * **Duplicate alerts**: The same underlying issue triggers five different alerts, flooding the on-call with noise.
> * **Flapping alerts**: An alert fires, resolves, fires, resolves, all within minutes. Each cycle generates a page.
> * **Low-value alerts**: Alerts for things that do not require human action. "Disk usage at 70%" when you auto-scale at 80% is noise, not signal.
> * **After-hours pages for non-urgent issues**: Getting woken up for a SEV4 that could wait until morning.

<br />

**How to fight alert fatigue:**

<br />

> * **Alert on symptoms, not causes**: Page when users are affected (high error rate, slow responses), not when infrastructure metrics spike (CPU at 80%). We covered this in the observability article.
> * **Set meaningful thresholds**: Do not set a latency alert at 200ms if your p99 is normally 180ms. Set it at a level that indicates a real problem, like 2x your normal p99.
> * **Use severity-based routing**: Only page the on-call for critical alerts. Everything else goes to Slack or a ticket queue.
> * **Group related alerts**: Configure Alertmanager's `group_by` to combine related alerts into a single notification instead of five separate pages.
> * **Add inhibition rules**: If the entire cluster is down, you do not need individual alerts for every service. An inhibition rule suppresses child alerts when a parent alert is firing.
> * **Review alerts regularly**: Once a month, review all alerts that fired. Delete the ones that never led to action. Tune the thresholds on the ones that fire too often. This is ongoing maintenance, not a one-time task.

<br />

A good benchmark: the on-call engineer should get no more than two pages per on-call shift on average.
If your team is consistently above that, you have a tuning problem, not a reliability problem.

<br />

##### **Runbooks**
A runbook is a documented procedure for handling a specific type of incident. When an alert fires
and you are half-asleep at 3am, you do not want to figure out the debugging steps from scratch. You
want a clear, step-by-step guide that tells you exactly what to check and what to do.

<br />

**What makes a good runbook:**

<br />

> * **It is linked from the alert**: The alert annotation includes a URL to the runbook. One click from the page to the instructions.
> * **It starts with quick checks**: The first steps should help you assess the severity and scope in under two minutes.
> * **It has concrete commands**: Not "check the database" but "run this specific query and compare the result to this threshold."
> * **It covers mitigation first, root cause second**: Tell the engineer how to stop the bleeding before asking them to diagnose.
> * **It is kept up to date**: A stale runbook is worse than no runbook because it gives false confidence. Review runbooks after every incident that uses them.

<br />

Here is a template you can use for any runbook:

<br />

```markdown
# Runbook: [Alert Name]

## Overview
- **Alert**: [Name of the alert that links here]
- **Severity**: [SEV1/SEV2/SEV3]
- **Service**: [Which service is affected]
- **Last updated**: [Date]
- **Owner**: [Team or person responsible for this runbook]

## Quick assessment (do this first, under 2 minutes)
1. Check [dashboard link] for the current state
2. Run: `[specific command]` to confirm the issue
3. Determine scope: is it all users, a subset, or a single endpoint?

## Mitigation steps (stop the bleeding)
1. If this started after a recent deploy, rollback:
   `kubectl rollout undo deployment/[service] -n [namespace]`
2. If the issue is load-related, scale up:
   `kubectl scale deployment/[service] --replicas=[N] -n [namespace]`
3. [Any other quick fixes specific to this alert]

## Diagnosis (find the root cause)
1. Check logs: `kubectl logs -l app=[service] -n [namespace] --tail=100`
2. Check metrics: [specific PromQL query]
3. Check recent changes: [link to deploy history or git log]

## Escalation
- If you cannot mitigate within 30 minutes, escalate to [team/person]
- For data loss or security issues, immediately page [team/person]

## Previous incidents
- [Date]: [Brief description and link to postmortem]
```

<br />

The most important part of this template is the "Quick assessment" section. It is what the on-call
engineer reads first, bleary-eyed and trying to figure out if this is a real problem or a false alarm.

<br />

##### **Practical example: API response time runbook**
Let's write a real runbook for one of the most common alerts: API response time exceeding 2 seconds.
This connects directly to the Prometheus alerts we set up in article fifteen.

<br />

First, the alert rule that would trigger this:

<br />

```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: api-latency-alerts
  namespace: monitoring
spec:
  groups:
    - name: api-latency
      rules:
        - alert: APIHighLatency
          expr: |
            histogram_quantile(0.99,
              sum(rate(http_request_duration_seconds_bucket{service="task-api"}[5m]))
              by (le)
            ) > 2
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "API p99 latency is above 2 seconds"
            description: "The task-api p99 latency has been above 2s for 5 minutes."
            runbook_url: "https://wiki.example.com/runbooks/api-high-latency"
```

<br />

Notice the `runbook_url` annotation. When this alert fires and reaches PagerDuty or OpsGenie, the
runbook link is included in the notification. The on-call engineer can click it immediately.

<br />

Now the runbook itself:

<br />

```markdown
# Runbook: APIHighLatency

## Overview
- **Alert**: APIHighLatency
- **Severity**: SEV2 (becomes SEV1 if latency exceeds 10s or error rate rises above 5%)
- **Service**: task-api
- **Last updated**: 2026-06-14
- **Owner**: Platform team

## Quick assessment (under 2 minutes)
1. Open the API dashboard: https://grafana.example.com/d/task-api
2. Check current p99 latency. Is it above 2s? How far above?
3. Check if error rate has also increased (indicates a deeper problem)
4. Check if the issue is isolated to one endpoint or all endpoints:
   Query: histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, route))

## Mitigation steps
### If latency started after a recent deploy:
1. Check the last deploy time:
   kubectl rollout history deployment/task-api -n production
2. If timing matches, roll back:
   kubectl rollout undo deployment/task-api -n production
3. Verify latency is recovering on the dashboard

### If latency is caused by high traffic:
1. Check current replica count and CPU usage:
   kubectl top pods -l app=task-api -n production
2. Scale up if replicas are at resource limits:
   kubectl scale deployment/task-api --replicas=6 -n production
3. Verify new pods are healthy:
   kubectl get pods -l app=task-api -n production

### If latency is caused by slow database queries:
1. Check database connection pool usage:
   Query: pg_stat_activity_count{datname="taskapi"}
2. Check for long-running queries:
   SELECT pid, now() - pg_stat_activity.query_start AS duration, query
   FROM pg_stat_activity
   WHERE state != 'idle' ORDER BY duration DESC LIMIT 10;
3. If a single query is blocking, consider cancelling it:
   SELECT pg_cancel_backend(<pid>);

## Diagnosis
1. Check logs for slow request patterns:
   kubectl logs -l app=task-api -n production --tail=200 | grep -i "slow\|timeout"
2. Check traces in Jaeger/Tempo for high-latency requests
3. Compare with normal baseline: typical p99 is 200-400ms
4. Review recent PRs merged to main for query changes or new endpoints

## Escalation
- If not mitigated within 30 minutes: page the backend team lead
- If database-related: page the DBA or infrastructure team
- If latency exceeds 10s or error rate > 5%: escalate to SEV1

## Previous incidents
- 2026-05-20: Slow queries after migration added missing index. Fixed with CREATE INDEX.
- 2026-04-15: Memory leak caused GC pauses. Fixed with Node.js version upgrade.
```

<br />

This runbook is specific, actionable, and organized by likelihood. The on-call engineer does not need
to guess. They follow the steps, check the relevant data, and take action based on what they find.

<br />

##### **Communication during incidents**
When something is broken, people want to know. Your users, your support team, your leadership. Good
communication during incidents reduces panic, builds trust, and lets you focus on fixing the problem
instead of answering "is it fixed yet?" messages from twelve different people.

<br />

**Status pages**

<br />

A public (or internal) status page is the single source of truth during an incident. Tools like
Statuspage (by Atlassian), Cachet (open source), or even a simple static page give your users a
place to check instead of flooding your support channels.

<br />

A good status update includes:

<br />

> * **What is affected**: "The checkout API is experiencing slow response times"
> * **Current status**: "Investigating / Identified / Monitoring / Resolved"
> * **Impact**: "Some users may experience delays when completing purchases"
> * **Next update**: "We will provide an update in 30 minutes or when we have more information"

<br />

Keep updates factual and concise. Do not speculate about root causes in public updates. Say "we have
identified the issue and are implementing a fix" rather than "we think the database index got
corrupted."

<br />

**Internal communication**

<br />

For your team and stakeholders, you need more detail. Most teams use a dedicated Slack channel per
incident (for example, `#inc-2026-06-14-api-latency`). This keeps the conversation focused and
creates a written record you can reference in the postmortem.

<br />

In the incident channel, post regular updates even if there is nothing new. "Still investigating,
no new findings" is better than silence. Silence makes people nervous.

<br />

**War rooms**

<br />

For SEV1 incidents, teams often open a video call (sometimes called a war room or bridge call) where
everyone working on the incident can communicate in real time. The key rules for war rooms:

<br />

> * **Keep it focused**: Only people actively working on the incident should be in the call. Observers can follow the Slack channel.
> * **Designate a communication lead**: One person handles all external updates so the engineers can focus on fixing things.
> * **Document decisions**: Someone should be writing down what is happening, what has been tried, and what the current plan is. This becomes your postmortem timeline.

<br />

##### **Blameless postmortems**
A postmortem (also called a retrospective or incident review) is a structured analysis of what
happened during an incident. The word "blameless" is the most important part. A blameless postmortem
focuses on systems and processes, not on individuals.

<br />

**Why blameless matters**

<br />

If people are afraid they will be punished for causing an incident, they will hide information, avoid
taking risks, and not report near-misses. Blame creates a culture of fear and silence. Blamelessness
creates a culture of transparency and learning. The person who made the change that caused the outage
is often the person who best understands the system and can help prevent it from happening again. You
want them talking openly, not defending themselves.

<br />

This does not mean ignoring accountability. It means recognizing that most incidents are caused by
system flaws (bad tooling, missing guardrails, unclear processes), not by people being careless.

<br />

**Postmortem template**

<br />

```markdown
# Incident Postmortem: [Title]

## Summary
- **Date**: [When the incident occurred]
- **Duration**: [How long it lasted]
- **Severity**: [SEV level]
- **Impact**: [Who was affected and how]
- **Authors**: [Who wrote this postmortem]

## Timeline (all times in UTC)
- 14:32 - Monitoring alert fires: APIHighLatency
- 14:35 - On-call engineer acknowledges the alert
- 14:38 - Engineer checks dashboard, confirms p99 latency at 4.2s
- 14:42 - Identifies that latency spike started at 14:25, correlating with deploy abc123
- 14:45 - Initiates rollback of deployment
- 14:48 - Rollback complete, latency begins recovering
- 14:55 - Latency back to normal (p99 at 280ms)
- 14:58 - Incident marked as resolved

## Root cause
A database migration in commit abc123 added a new column to the orders table without an index.
The /orders endpoint performs a filter query on this column, which caused a full table scan on
every request. Under normal traffic, this increased p99 latency from 250ms to over 4 seconds.

## What went well
- Alert fired within 7 minutes of the deploy
- On-call engineer responded within 3 minutes
- Rollback was fast and effective (under 5 minutes from decision to recovery)
- Status page was updated within 10 minutes

## What went wrong
- The migration did not include an index for the new column
- No load testing was done against the staging database with realistic data volumes
- The staging database has 1,000 rows; production has 2 million, so the performance difference
  was not visible in staging

## Action items
- [ ] Add an index to the new column (owner: backend team, due: 2026-06-16)
- [ ] Add a CI check that flags migrations without indexes on queried columns (owner: platform team, due: 2026-06-30)
- [ ] Seed staging database with realistic data volumes (owner: platform team, due: 2026-07-15)
- [ ] Add a latency check to the post-deploy smoke tests (owner: platform team, due: 2026-06-30)
```

<br />

Notice the structure. The timeline is factual and precise. The root cause is technical, not personal.
"What went well" is just as important as "what went wrong" because it reinforces the things your
team should keep doing. And the action items are specific, assigned, and have deadlines.

<br />

**Running the postmortem meeting**

<br />

Schedule the postmortem within 48 hours of the incident while memories are fresh. Keep it to 30-60
minutes. The facilitator (usually not someone directly involved in the incident) walks through the
timeline and asks questions:

<br />

> * "What information did you have at this point?"
> * "What did you try and why?"
> * "What would have helped you resolve this faster?"
> * "Were there signals we missed that could have caught this earlier?"

<br />

The goal is to understand the system, not to judge decisions made under pressure. People make
reasonable decisions based on the information they have at the time. If the system made it easy to
deploy a migration without an index, the fix is a better system, not a lecture.

<br />

##### **Building a healthy on-call culture**
On-call does not have to be miserable. I have seen teams where on-call is dreaded and teams where
it is manageable and even rewarding. The difference comes down to culture and investment.

<br />

**Reasonable expectations**

<br />

> * **Frequency**: Nobody should be on call more than one week in four. If your team is too small for that rotation, you need to hire, share the rotation with another team, or reduce your on-call scope.
> * **Workload**: The on-call engineer should be able to do their regular work during calm on-call shifts. If on-call is so busy that they cannot write code during the day, your alerts need tuning.
> * **Sleep**: Getting paged once a night is acceptable occasionally. Getting paged three or four times every night is a systemic problem. Track after-hours pages as a metric and set a goal to reduce them.

<br />

**Practice incidents**

<br />

The worst time to learn incident response is during a real incident. Practice with game days or
tabletop exercises. A game day is a planned exercise where you intentionally break something (in a
controlled way) and practice the response. A tabletop exercise is where you walk through an incident
scenario verbally without actually breaking anything.

<br />

```plaintext
Example tabletop scenario:

"It is 2am on a Tuesday. You get paged for APIHighLatency.
 You check the dashboard and see p99 latency at 8 seconds.
 Error rate is at 12%. The last deploy was 6 hours ago.

 What do you do first?
 What do you check?
 Who do you contact?
 How do you communicate with stakeholders?"
```

<br />

These exercises build muscle memory. When a real incident happens, the on-call engineer is not
thinking "what do I do?" They are thinking "I have done this before, let me follow the process."

<br />

**Handoff quality**

<br />

A good handoff between on-call shifts includes:

<br />

> * **Active incidents**: Anything still ongoing or recently resolved
> * **Recent alerts**: Alerts that fired and were handled, with context
> * **Known issues**: Things that might page you but are already being worked on
> * **Environment changes**: Recent deployments, infrastructure changes, or maintenance windows

<br />

A quick 15-minute call or a structured Slack message at handoff time prevents a lot of confusion.

<br />

**Investing in tooling**

<br />

Every time someone gets paged for something that could have been automated, that is a failure of
tooling. Track your incidents and look for patterns. If the same issue keeps happening and the
runbook is always "restart the pod," automate the restart. If a particular alert always turns out
to be a false positive, fix the alert. On-call should be for problems that genuinely need a human
brain, not for tasks a script could handle.

<br />

##### **Advanced topics**
We have covered the fundamentals of incident response in this article, but there is much more to
explore as your team and systems grow:

<br />

> * **Incident commander role**: For SEV1 incidents, a dedicated incident commander coordinates the response, manages communication, and makes decisions about escalation. This role is separate from the engineers doing the technical work.
> * **SRE practices**: Error budgets, SLO-based alerting, and toil reduction are advanced concepts that build on everything we covered here.
> * **Postmortems as code**: Version-controlled postmortem templates, automated timeline generation, and action item tracking integrated into your project management tool.
> * **Chaos engineering**: Intentionally injecting failures to test your incident response process before real incidents happen.

<br />

For a deep dive into all of these topics, check out the
[SRE Incident Management](/blog/sre-incident-management-on-call-and-postmortems-as-code) article.
It covers incident commander workflows, on-call automation with Kubernetes operators, postmortem
templates as code managed through GitOps, and advanced alerting strategies.

<br />

##### **Closing notes**
Incident response is not just about tools and processes. It is about people. It is about making sure
the person who gets paged at 3am has what they need to solve the problem: clear alerts, good runbooks,
the right access, and the confidence that comes from practice.

<br />

In this article we covered what incidents are and how to classify them with severity levels, the five
phases of the incident lifecycle, how on-call rotations work and how to make them fair, setting up
alerting from Prometheus to PagerDuty or OpsGenie, why alert fatigue is dangerous and how to fight
it, how to write runbooks that actually help, communication best practices during incidents, blameless
postmortems that drive improvement, and building a culture where on-call is sustainable.

<br />

The most important takeaway is this: invest in your incident response process before you need it.
Write the runbooks, tune the alerts, practice the scenarios, and run the postmortems. When the real
incident happens, you will be ready.

<br />

In the next and final article of the series, we will bring everything together and look at what comes
after mastering the fundamentals.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: Respuesta a Incidentes y On-Call",
  author: "Gabriel Garrido",
  description: "Vamos a cubrir los fundamentos de la respuesta a incidentes, niveles de severidad, rotaciones de on-call, herramientas de alertas, runbooks, postmortems sin culpa, y como construir una cultura de on-call saludable que no queme a la gente...",
  tags: ~w(devops incident-response on-call reliability beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo diecinueve de la serie DevOps from Zero to Hero. En los articulos anteriores
configuramos observabilidad con Prometheus y Grafana, construimos dashboards, configuramos alertas
y desplegamos pipelines completos de CI/CD. Todo esta monitoreado y automatizado. Pero aca viene la
pregunta que nadie quiere hacer: que pasa a las 3 de la manana cuando una alerta se dispara y tu
API esta caida?

<br />

De eso se trata la respuesta a incidentes. Es el lado humano de la confiabilidad. Podes tener el
mejor monitoreo del mundo, pero si nadie sabe que hacer cuando suena una alerta, no importa. En
este articulo vamos a cubrir los fundamentos: que son los incidentes, como clasificarlos, como
funcionan las rotaciones de on-call, como escribir runbooks que realmente ayuden, y como aprender
de las fallas sin culpar a nadie.

<br />

Esta es una introduccion para principiantes. Si queres ir mas profundo en temas como incident
commanders, practicas especificas de SRE, postmortems como codigo, y automatizacion avanzada de
on-call, mira el articulo de
[SRE Incident Management](/blog/sre-incident-management-on-call-and-postmortems-as-code) de la
serie de SRE. Ese articulo asume que ya entendes los fundamentos que cubrimos aca.

<br />

Arranquemos.

<br />

##### **Que es un incidente?**
Un incidente es cualquier evento no planificado que interrumpe o degrada un servicio para tus
usuarios. No todo bug es un incidente. Un error de tipeo en un footer es un bug. Que el procesamiento
de pagos este caido para 500 usuarios es un incidente. La distincion clave es el impacto en los
usuarios.

<br />

La mayoria de los equipos clasifican los incidentes por niveles de severidad. Las definiciones exactas
varian entre organizaciones, pero aca tenes un framework comun:

<br />

> * **SEV1 (Critico)**: Caida completa del servicio o perdida de datos. Todos o la mayoria de los usuarios estan afectados. Ejemplo: toda la API esta devolviendo errores 500, la base de datos es inalcanzable, o los datos de los clientes se corrompieron. Esto requiere todas las manos a la obra, inmediatamente.
> * **SEV2 (Mayor)**: Degradacion significativa pero el servicio funciona parcialmente. Ejemplo: los tiempos de respuesta son 10 veces mas lentos de lo normal, una funcionalidad clave como el checkout esta rota, o el 30% de las requests estan fallando. Esto necesita atencion inmediata del ingeniero de on-call.
> * **SEV3 (Menor)**: Un problema notable que afecta a un grupo chico de usuarios o una funcionalidad no critica. Ejemplo: las sugerencias de busqueda no cargan, un widget del dashboard muestra datos desactualizados, o las subidas de imagenes estan lentas. Esto se deberia resolver en horario laboral.
> * **SEV4 (Bajo)**: Un problema cosmetico o una molestia menor con impacto minimo en los usuarios. Ejemplo: un tooltip tiene el texto equivocado, un job de background no critico esta reintentando mas de lo usual, o un panel de monitoreo esta roto. Esto va al backlog normal.

<br />

El nivel de severidad determina todo lo demas: a quien se le manda la alerta, que tan rapido tenes
que responder, si necesitas actualizar la status page, y cuanto del equipo se involucra. Clasificar
bien es importante porque sobre-escalar quema a la gente y sub-escalar deja que los problemas crezcan.

<br />

##### **El ciclo de vida del incidente**
Todo incidente, sin importar la severidad, sigue el mismo ciclo de vida basico. Entender estas fases
te ayuda a mantenerte organizado cuando las cosas estan estresantes.

<br />

```plaintext
  Detectar ──> Responder ──> Mitigar ──> Resolver ──> Aprender
     │             │            │            │            │
     │             │            │            │            │
  Las alertas   Avisar al    Parar la    Arreglar     Hacer un
  se disparan   on-call      hemorragia  la causa     postmortem
                                         raiz
```

<br />

Veamos cada fase:

<br />

**1. Detectar**

<br />

Algo te dice que hay un problema. Idealmente, tu monitoreo lo detecta antes que los usuarios. En
el [articulo quince](/blog/devops-from-zero-to-hero-observability) configuramos alertas de Prometheus
que se disparan cuando las tasas de error o la latencia superan los umbrales. Esas alertas son tu
primera linea de deteccion. Otras fuentes incluyen fallas en health checks, reportes de usuarios,
y smoke tests automatizados de tu pipeline de CI/CD.

<br />

El objetivo es simple: enterarte de los problemas antes de que tus usuarios los tuiteen.

<br />

**2. Responder**

<br />

La alerta llega al ingeniero de on-call a traves de una herramienta como PagerDuty o OpsGenie.
El ingeniero de on-call reconoce la alerta (para que el sistema sepa que alguien la esta viendo),
evalua la severidad, y decide si necesita sumar mas gente. Para un SEV1, podria iniciar un war room
inmediatamente. Para un SEV3, podria simplemente abrir un ticket e investigar en horario normal.

<br />

**3. Mitigar**

<br />

Esta es la fase mas importante y la que mas confunde a los principiantes. Mitigar no se trata de
encontrar la causa raiz. Se trata de detener el impacto en los usuarios lo mas rapido posible. Si
tu API esta lenta porque se desplegó un mal deploy, primero haces rollback e investigas despues. Si
una base de datos esta sobrecargada, la escalas o redirigas el trafico. Arregla lo suficiente para
parar el dolor, despues averiguas por que paso.

<br />

Acciones de mitigacion comunes incluyen:

<br />

> * **Rollback**: Revertir el ultimo despliegue si el problema empezo despues de un deploy
> * **Reiniciar**: A veces un simple reinicio de pod limpia un proceso trabado
> * **Escalar verticalmente**: Agregar mas replicas o aumentar los limites de recursos
> * **Feature flag**: Deshabilitar una funcionalidad rota sin hacer rollback de todo
> * **Desviar trafico**: Redirigir usuarios a una region o instancia saludable

<br />

**4. Resolver**

<br />

Una vez que los usuarios ya no estan afectados, podes tomarte el tiempo para encontrar y arreglar la
causa raiz real. Tal vez el despliegue estaba bien pero expuso un bug latente activado por un patron
de datos especifico. Tal vez la base de datos necesita un indice. Tal vez la logica de reintentos
esta creando un efecto de estampida. Aca es donde haces el trabajo de ingenieria de verdad.

<br />

**5. Aprender**

<br />

Despues de que el incidente se resuelve, haces un postmortem. Lo vamos a cubrir en detalle mas
adelante en el articulo, pero la version corta es: documentas que paso, construis una linea de
tiempo, identificas la causa raiz, y creas items de accion para prevenir que vuelva a pasar. Sin
culpa. Solo aprendizaje.

<br />

##### **Conceptos basicos de on-call**
On-call significa que sos la persona designada que responde cuando las alertas se disparan fuera del
horario laboral (y muchas veces durante el horario tambien). Si nunca estuviste de on-call, la idea
puede intimidar. Vamos a desglosarlo.

<br />

**Que significa realmente estar de on-call?**

<br />

Cuando estas de on-call, llevas un celular (o tenes una laptop cerca) y te comprometes a responder
a las alertas dentro de una ventana de tiempo definida, generalmente 5 a 15 minutos para alertas
criticas. No necesitas estar sentado frente a la computadora mirando dashboards. Podes ir a cenar,
ver una pelicula, o dormir. Pero necesitas estar localizable y poder empezar a investigar dentro
del tiempo de respuesta.

<br />

**Calendarios de rotacion**

<br />

Nadie deberia estar de on-call todo el tiempo. Los equipos configuran rotaciones donde la
responsabilidad de on-call pasa de persona a persona en un calendario regular. Los patrones comunes
incluyen:

<br />

> * **Rotacion semanal**: La persona A esta de on-call de lunes a lunes, luego la persona B toma el relevo. Simple y predecible. Funciona bien para equipos de 4 o mas.
> * **Rotacion diaria**: Los turnos de on-call cambian cada dia. Menos carga por turno pero mas traspasos. Bueno para equipos que quieren distribuir la carga de manera uniforme.
> * **Follow-the-sun**: Si tu equipo abarca zonas horarias, cada region cubre su horario diurno. Nadie se despierta a las 3am. Es el sueno, pero requiere un equipo distribuido globalmente.
> * **Primario y secundario**: Dos personas estan de on-call al mismo tiempo. El primario recibe la alerta primero. Si no responde dentro de la ventana de escalacion (digamos 10 minutos), el secundario recibe la alerta. Esto proporciona una red de seguridad.

<br />

**Compensacion**

<br />

Estar de on-call es trabajo. Las buenas organizaciones lo compensan. Esto puede tomar diferentes
formas: pago extra por turnos de on-call, tiempo libre despues de una semana intensa de on-call, o
un estipendio fijo por turno. El enfoque especifico varia, pero el principio es claro: si le estas
pidiendo a alguien que este disponible fuera del horario normal, deberias reconocer y compensar ese
tiempo. Los equipos que no compensan el on-call eventualmente pierden a sus mejores ingenieros.

<br />

**Procedimientos de traspaso**

<br />

Cuando tu turno de on-call termina y alguien mas toma el relevo, deberias hacer un traspaso adecuado.
Esto significa resumir cualquier problema en curso, alertas raras que notaste, o cualquier cosa que
la siguiente persona deberia saber. Un mensaje rapido en Slack o un documento compartido funciona.
Lo peor es heredar un turno de on-call sin contexto sobre lo que estuvo pasando.

<br />

##### **Herramientas de on-call**
Necesitas una herramienta que reciba alertas de tu sistema de monitoreo y las enrute a la persona
correcta en el momento correcto a traves del canal correcto (llamada telefonica, SMS, notificacion
push, Slack). Aca estan las opciones mas comunes:

<br />

> * **PagerDuty**: La plataforma de gestion de incidentes mas establecida. Maneja enrutamiento de alertas, politicas de escalacion, calendarios de on-call, y seguimiento de incidentes. Se integra con todo: Prometheus, Grafana, AWS CloudWatch, Datadog, lo que se te ocurra. Es el estandar de la industria pero tambien es la opcion mas cara.
> * **OpsGenie (de Atlassian)**: Similar a PagerDuty en funcionalidades, con integraciones fuertes con el ecosistema de Atlassian (Jira, Confluence, Statuspage). Una opcion solida si tu equipo ya usa herramientas de Atlassian. El precio es mas accesible que PagerDuty.
> * **Grafana OnCall**: Una opcion open-source que se integra nativamente con Grafana. Si ya usas el stack de Grafana para observabilidad (como configuramos en el articulo quince), es una opcion natural. Podes auto-hostearlo o usar la version gestionada de Grafana Cloud. Maneja calendarios, escalaciones y enrutamiento, y es gratis para auto-hosting.

<br />

Las tres herramientas siguen el mismo flujo basico:

<br />

```plaintext
Alerta de Prometheus
    │
    ▼
Alertmanager ──> Webhook ──> PagerDuty / OpsGenie / Grafana OnCall
                                │
                                ▼
                          Calendario de on-call
                                │
                                ▼
                         Avisar al ingeniero de on-call
                         (telefono, SMS, push, Slack)
                                │
                    ┌───────────┴───────────┐
                    │                       │
              Reconocida              No reconocida
              dentro del SLA          dentro de la ventana de escalacion
                    │                       │
                    ▼                       ▼
              El ingeniero            Avisar al secundario /
              trabaja el              escalar al manager
              incidente
```

<br />

##### **Configurando alertas hacia herramientas de on-call**
En el [articulo quince](/blog/devops-from-zero-to-hero-observability) configuramos alertas de
Prometheus usando recursos PrometheusRule. Esas alertas van al Alertmanager, que es parte del
kube-prometheus-stack. Ahora necesitamos conectar Alertmanager con una herramienta de on-call
para que las alertas realmente lleguen a un humano.

<br />

Aca tenes como configurar Alertmanager para enviar alertas criticas a PagerDuty y alertas no
criticas a un canal de Slack:

<br />

```yaml
# alertmanager-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m

    route:
      receiver: slack-default
      group_by: [alertname, namespace]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h

      routes:
        # Alertas criticas van a PagerDuty
        - receiver: pagerduty-critical
          match:
            severity: critical
          continue: false

        # Alertas de warning van solo a Slack
        - receiver: slack-warnings
          match:
            severity: warning
          continue: false

    receivers:
      - name: slack-default
        slack_configs:
          - api_url: "https://hooks.slack.com/services/TU/SLACK/WEBHOOK"
            channel: "#alertas"
            title: '{{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

      - name: pagerduty-critical
        pagerduty_configs:
          - routing_key: "TU_CLAVE_DE_INTEGRACION_PAGERDUTY"
            severity: critical
            description: '{{ .GroupLabels.alertname }}'
            details:
              namespace: '{{ .GroupLabels.namespace }}'
              summary: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

      - name: slack-warnings
        slack_configs:
          - api_url: "https://hooks.slack.com/services/TU/SLACK/WEBHOOK"
            channel: "#alertas-baja-prioridad"
            title: '{{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

<br />

Para OpsGenie, reemplazarias el `pagerduty_configs` con:

<br />

```yaml
      - name: opsgenie-critical
        opsgenie_configs:
          - api_key: "TU_API_KEY_DE_OPSGENIE"
            message: '{{ .GroupLabels.alertname }}'
            priority: P1
            description: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

<br />

Para Grafana OnCall, tipicamente usas un receptor webhook que apunta a tu instancia de Grafana OnCall:

<br />

```yaml
      - name: grafana-oncall
        webhook_configs:
          - url: "https://oncall.tu-grafana.com/integrations/v1/alertmanager/TU_ID/"
            send_resolved: true
```

<br />

El concepto clave es el enrutamiento. No toda alerta deberia despertar a alguien. Enruta por
severidad: alertas criticas paginan al on-call, warnings van a Slack, y alertas informativas van
a un canal de baja prioridad. Esto es fundamental para evitar la fatiga de alertas.

<br />

##### **Fatiga de alertas**
La fatiga de alertas es el enemigo numero uno de los programas de on-call. Pasa cuando los
ingenieros reciben tantas alertas que empiezan a ignorarlas. Cuando te estan paginando 20 veces
por noche, dejas de tomarte las alertas en serio. Y cuando dejas de tomar las alertas en serio,
la unica caida real que importa se pierde en el ruido.

<br />

Aca va la verdad dura: demasiadas alertas es peor que muy pocas. Con muy pocas alertas, tal vez te
pierdas algo, pero al menos cuando una alerta se dispara, la gente presta atencion. Con demasiadas
alertas, la gente se desconecta completamente, y te perdes todo.

<br />

**Signos de fatiga de alertas:**

<br />

> * **Alta tasa de reconocimiento, baja tasa de accion**: La gente hace clic en "reconocer" solo para silenciar la alerta, sin investigar realmente.
> * **Alertas duplicadas**: El mismo problema subyacente dispara cinco alertas diferentes, inundando al on-call con ruido.
> * **Alertas que parpadean**: Una alerta se dispara, se resuelve, se dispara, se resuelve, todo en minutos. Cada ciclo genera una paginacion.
> * **Alertas de bajo valor**: Alertas por cosas que no requieren accion humana. "Uso de disco al 70%" cuando auto-escalas al 80% es ruido, no senal.
> * **Paginaciones fuera de horario por temas no urgentes**: Que te despierten por un SEV4 que podria esperar hasta manana.

<br />

**Como combatir la fatiga de alertas:**

<br />

> * **Alertar sobre sintomas, no causas**: Paginar cuando los usuarios estan afectados (alta tasa de error, respuestas lentas), no cuando las metricas de infraestructura suben (CPU al 80%). Cubrimos esto en el articulo de observabilidad.
> * **Establecer umbrales significativos**: No pongas una alerta de latencia a 200ms si tu p99 normalmente esta en 180ms. Ponela en un nivel que indique un problema real, como 2 veces tu p99 normal.
> * **Usar enrutamiento basado en severidad**: Solo paginar al on-call por alertas criticas. Todo lo demas va a Slack o a una cola de tickets.
> * **Agrupar alertas relacionadas**: Configurar el `group_by` de Alertmanager para combinar alertas relacionadas en una sola notificacion en vez de cinco paginaciones separadas.
> * **Agregar reglas de inhibicion**: Si todo el cluster esta caido, no necesitas alertas individuales por cada servicio. Una regla de inhibicion suprime alertas hijas cuando una alerta padre esta activa.
> * **Revisar alertas regularmente**: Una vez al mes, revisa todas las alertas que se dispararon. Elimina las que nunca llevaron a una accion. Ajusta los umbrales de las que se disparan demasiado seguido. Esto es mantenimiento continuo, no una tarea que se hace una sola vez.

<br />

Un buen benchmark: el ingeniero de on-call no deberia recibir mas de dos paginaciones por turno de
on-call en promedio. Si tu equipo esta consistentemente por encima de eso, tenes un problema de
ajuste de alertas, no un problema de confiabilidad.

<br />

##### **Runbooks**
Un runbook es un procedimiento documentado para manejar un tipo especifico de incidente. Cuando una
alerta se dispara y estas medio dormido a las 3am, no queres descubrir los pasos de debugging desde
cero. Queres una guia clara, paso a paso, que te diga exactamente que revisar y que hacer.

<br />

**Que hace un buen runbook:**

<br />

> * **Esta enlazado desde la alerta**: La anotacion de la alerta incluye una URL al runbook. Un clic desde la paginacion a las instrucciones.
> * **Empieza con chequeos rapidos**: Los primeros pasos deberian ayudarte a evaluar la severidad y el alcance en menos de dos minutos.
> * **Tiene comandos concretos**: No "revisar la base de datos" sino "ejecuta esta query especifica y compara el resultado con este umbral."
> * **Cubre mitigacion primero, causa raiz despues**: Decile al ingeniero como parar la hemorragia antes de pedirle que diagnostique.
> * **Se mantiene actualizado**: Un runbook desactualizado es peor que no tener runbook porque da falsa confianza. Revisa los runbooks despues de cada incidente que los use.

<br />

Aca tenes un template que podes usar para cualquier runbook:

<br />

```markdown
# Runbook: [Nombre de la alerta]

## Resumen
- **Alerta**: [Nombre de la alerta que enlaza aca]
- **Severidad**: [SEV1/SEV2/SEV3]
- **Servicio**: [Que servicio esta afectado]
- **Ultima actualizacion**: [Fecha]
- **Responsable**: [Equipo o persona responsable de este runbook]

## Evaluacion rapida (hace esto primero, en menos de 2 minutos)
1. Revisa [link al dashboard] para el estado actual
2. Ejecuta: `[comando especifico]` para confirmar el problema
3. Determina el alcance: son todos los usuarios, un subconjunto, o un solo endpoint?

## Pasos de mitigacion (para la hemorragia)
1. Si esto empezo despues de un deploy reciente, rollback:
   `kubectl rollout undo deployment/[servicio] -n [namespace]`
2. Si el problema es de carga, escalar:
   `kubectl scale deployment/[servicio] --replicas=[N] -n [namespace]`
3. [Cualquier otro arreglo rapido especifico de esta alerta]

## Diagnostico (encontrar la causa raiz)
1. Revisar logs: `kubectl logs -l app=[servicio] -n [namespace] --tail=100`
2. Revisar metricas: [query PromQL especifica]
3. Revisar cambios recientes: [link al historial de deploys o git log]

## Escalacion
- Si no podes mitigar en 30 minutos, escalar a [equipo/persona]
- Para perdida de datos o problemas de seguridad, paginar inmediatamente a [equipo/persona]

## Incidentes anteriores
- [Fecha]: [Descripcion breve y link al postmortem]
```

<br />

La parte mas importante de este template es la seccion de "Evaluacion rapida". Es lo que el ingeniero
de on-call lee primero, con los ojos medio cerrados tratando de averiguar si es un problema real o
una falsa alarma.

<br />

##### **Ejemplo practico: runbook de tiempo de respuesta de la API**
Escribamos un runbook real para una de las alertas mas comunes: tiempo de respuesta de la API
superando los 2 segundos. Esto se conecta directamente con las alertas de Prometheus que configuramos
en el articulo quince.

<br />

Primero, la regla de alerta que dispara esto:

<br />

```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: api-latency-alerts
  namespace: monitoring
spec:
  groups:
    - name: api-latency
      rules:
        - alert: APIHighLatency
          expr: |
            histogram_quantile(0.99,
              sum(rate(http_request_duration_seconds_bucket{service="task-api"}[5m]))
              by (le)
            ) > 2
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "La latencia p99 de la API esta por encima de 2 segundos"
            description: "La latencia p99 del task-api estuvo por encima de 2s durante 5 minutos."
            runbook_url: "https://wiki.example.com/runbooks/api-high-latency"
```

<br />

Fijate la anotacion `runbook_url`. Cuando esta alerta se dispara y llega a PagerDuty o OpsGenie, el
link al runbook se incluye en la notificacion. El ingeniero de on-call puede hacer clic inmediatamente.

<br />

Ahora el runbook en si:

<br />

```markdown
# Runbook: APIHighLatency

## Resumen
- **Alerta**: APIHighLatency
- **Severidad**: SEV2 (se convierte en SEV1 si la latencia supera 10s o la tasa de error sube de 5%)
- **Servicio**: task-api
- **Ultima actualizacion**: 2026-06-14
- **Responsable**: Equipo de plataforma

## Evaluacion rapida (menos de 2 minutos)
1. Abrir el dashboard de la API: https://grafana.example.com/d/task-api
2. Revisar la latencia p99 actual. Esta por encima de 2s? Cuanto por encima?
3. Revisar si la tasa de error tambien aumento (indica un problema mas profundo)
4. Revisar si el problema esta aislado a un endpoint o todos:
   Query: histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, route))

## Pasos de mitigacion
### Si la latencia empezo despues de un deploy reciente:
1. Revisar la hora del ultimo deploy:
   kubectl rollout history deployment/task-api -n production
2. Si el timing coincide, rollback:
   kubectl rollout undo deployment/task-api -n production
3. Verificar que la latencia se esta recuperando en el dashboard

### Si la latencia es causada por trafico alto:
1. Revisar la cantidad actual de replicas y uso de CPU:
   kubectl top pods -l app=task-api -n production
2. Escalar si las replicas estan al limite de recursos:
   kubectl scale deployment/task-api --replicas=6 -n production
3. Verificar que los nuevos pods estan saludables:
   kubectl get pods -l app=task-api -n production

### Si la latencia es causada por queries lentas a la base de datos:
1. Revisar uso del connection pool de la base de datos:
   Query: pg_stat_activity_count{datname="taskapi"}
2. Revisar queries de larga duracion:
   SELECT pid, now() - pg_stat_activity.query_start AS duration, query
   FROM pg_stat_activity
   WHERE state != 'idle' ORDER BY duration DESC LIMIT 10;
3. Si una sola query esta bloqueando, considerar cancelarla:
   SELECT pg_cancel_backend(<pid>);

## Diagnostico
1. Revisar logs buscando patrones de requests lentas:
   kubectl logs -l app=task-api -n production --tail=200 | grep -i "slow\|timeout"
2. Revisar traces en Jaeger/Tempo para requests de alta latencia
3. Comparar con la linea base normal: el p99 tipico es 200-400ms
4. Revisar PRs recientes mergeados a main buscando cambios en queries o endpoints nuevos

## Escalacion
- Si no se mitiga en 30 minutos: paginar al tech lead del equipo de backend
- Si esta relacionado con la base de datos: paginar al DBA o equipo de infraestructura
- Si la latencia supera 10s o la tasa de error > 5%: escalar a SEV1

## Incidentes anteriores
- 2026-05-20: Queries lentas despues de migracion sin indice. Se arreglo con CREATE INDEX.
- 2026-04-15: Memory leak causaba pausas de GC. Se arreglo actualizando la version de Node.js.
```

<br />

Este runbook es especifico, accionable, y organizado por probabilidad. El ingeniero de on-call no
necesita adivinar. Sigue los pasos, revisa los datos relevantes, y toma accion basandose en lo que
encuentra.

<br />

##### **Comunicacion durante incidentes**
Cuando algo esta roto, la gente quiere saber. Tus usuarios, tu equipo de soporte, tu liderazgo.
Buena comunicacion durante incidentes reduce el panico, construye confianza, y te deja enfocarte en
arreglar el problema en vez de responder mensajes de "ya esta arreglado?" de doce personas diferentes.

<br />

**Status pages**

<br />

Una status page publica (o interna) es la unica fuente de verdad durante un incidente. Herramientas
como Statuspage (de Atlassian), Cachet (open source), o incluso una pagina estatica simple les dan
a tus usuarios un lugar donde revisar en vez de inundar tus canales de soporte.

<br />

Una buena actualizacion de estado incluye:

<br />

> * **Que esta afectado**: "La API de checkout esta experimentando tiempos de respuesta lentos"
> * **Estado actual**: "Investigando / Identificado / Monitoreando / Resuelto"
> * **Impacto**: "Algunos usuarios pueden experimentar demoras al completar compras"
> * **Proxima actualizacion**: "Vamos a dar una actualizacion en 30 minutos o cuando tengamos mas informacion"

<br />

Mantene las actualizaciones facticas y concisas. No especules sobre las causas raiz en las
actualizaciones publicas. Deci "identificamos el problema y estamos implementando una solucion"
en vez de "creemos que el indice de la base de datos se corrompio."

<br />

**Comunicacion interna**

<br />

Para tu equipo y stakeholders, necesitas mas detalle. La mayoria de los equipos usan un canal
dedicado de Slack por incidente (por ejemplo, `#inc-2026-06-14-api-latency`). Esto mantiene la
conversacion enfocada y crea un registro escrito que podes referenciar en el postmortem.

<br />

En el canal del incidente, publica actualizaciones regulares incluso si no hay novedades. "Todavia
investigando, sin hallazgos nuevos" es mejor que el silencio. El silencio pone nerviosa a la gente.

<br />

**War rooms**

<br />

Para incidentes SEV1, los equipos suelen abrir una videollamada (a veces llamada war room o bridge
call) donde todos los que estan trabajando en el incidente pueden comunicarse en tiempo real. Las
reglas clave para war rooms:

<br />

> * **Mantenerlo enfocado**: Solo las personas que estan trabajando activamente en el incidente deberian estar en la llamada. Los observadores pueden seguir el canal de Slack.
> * **Designar un responsable de comunicacion**: Una persona maneja todas las actualizaciones externas para que los ingenieros puedan enfocarse en arreglar las cosas.
> * **Documentar decisiones**: Alguien deberia estar anotando que esta pasando, que se intento, y cual es el plan actual. Esto se convierte en la linea de tiempo de tu postmortem.

<br />

##### **Postmortems sin culpa**
Un postmortem (tambien llamado retrospectiva o revision de incidente) es un analisis estructurado de
lo que paso durante un incidente. La palabra "sin culpa" es la parte mas importante. Un postmortem
sin culpa se enfoca en sistemas y procesos, no en individuos.

<br />

**Por que importa que sea sin culpa**

<br />

Si la gente tiene miedo de que la castiguen por causar un incidente, van a esconder informacion,
evitar tomar riesgos, y no reportar situaciones que casi fueron incidentes. La culpa crea una cultura
de miedo y silencio. La ausencia de culpa crea una cultura de transparencia y aprendizaje. La persona
que hizo el cambio que causo la caida es muchas veces la que mejor entiende el sistema y puede ayudar
a prevenir que vuelva a pasar. Queres que hablen abiertamente, no que se defiendan.

<br />

Esto no significa ignorar la responsabilidad. Significa reconocer que la mayoria de los incidentes son
causados por fallas del sistema (herramientas malas, falta de guardrails, procesos poco claros), no
porque la gente fue descuidada.

<br />

**Template de postmortem**

<br />

```markdown
# Postmortem del incidente: [Titulo]

## Resumen
- **Fecha**: [Cuando ocurrio el incidente]
- **Duracion**: [Cuanto duro]
- **Severidad**: [Nivel SEV]
- **Impacto**: [Quien fue afectado y como]
- **Autores**: [Quien escribio este postmortem]

## Linea de tiempo (todos los horarios en UTC)
- 14:32 - Se dispara alerta de monitoreo: APIHighLatency
- 14:35 - El ingeniero de on-call reconoce la alerta
- 14:38 - El ingeniero revisa el dashboard, confirma latencia p99 en 4.2s
- 14:42 - Identifica que el pico de latencia empezo a las 14:25, correlacionando con el deploy abc123
- 14:45 - Inicia rollback del despliegue
- 14:48 - Rollback completo, la latencia empieza a recuperarse
- 14:55 - Latencia volvio a la normalidad (p99 en 280ms)
- 14:58 - Incidente marcado como resuelto

## Causa raiz
Una migracion de base de datos en el commit abc123 agrego una nueva columna a la tabla de orders
sin un indice. El endpoint /orders hace una query de filtro sobre esta columna, lo que causo un
full table scan en cada request. Bajo trafico normal, esto aumento la latencia p99 de 250ms a mas
de 4 segundos.

## Que salio bien
- La alerta se disparo dentro de los 7 minutos del deploy
- El ingeniero de on-call respondio en 3 minutos
- El rollback fue rapido y efectivo (menos de 5 minutos desde la decision hasta la recuperacion)
- La status page se actualizo en 10 minutos

## Que salio mal
- La migracion no incluyo un indice para la nueva columna
- No se hizo load testing contra la base de datos de staging con volumenes de datos realistas
- La base de staging tiene 1.000 filas; produccion tiene 2 millones, asi que la diferencia de
  performance no era visible en staging

## Items de accion
- [ ] Agregar indice a la nueva columna (responsable: equipo de backend, fecha: 2026-06-16)
- [ ] Agregar un chequeo de CI que marque migraciones sin indices en columnas consultadas (responsable: equipo de plataforma, fecha: 2026-06-30)
- [ ] Popular la base de staging con volumenes de datos realistas (responsable: equipo de plataforma, fecha: 2026-07-15)
- [ ] Agregar un chequeo de latencia a los smoke tests post-deploy (responsable: equipo de plataforma, fecha: 2026-06-30)
```

<br />

Fijate en la estructura. La linea de tiempo es factica y precisa. La causa raiz es tecnica, no
personal. "Que salio bien" es tan importante como "que salio mal" porque refuerza las cosas que tu
equipo deberia seguir haciendo. Y los items de accion son especificos, asignados, y tienen fechas
limite.

<br />

**Llevando adelante la reunion de postmortem**

<br />

Agenda el postmortem dentro de las 48 horas del incidente mientras los recuerdos estan frescos.
Que dure 30-60 minutos. El facilitador (generalmente alguien que no estuvo directamente involucrado
en el incidente) recorre la linea de tiempo y hace preguntas:

<br />

> * "Que informacion tenias en ese momento?"
> * "Que intentaste y por que?"
> * "Que te hubiera ayudado a resolver esto mas rapido?"
> * "Hubo senales que nos perdimos que podrian haber detectado esto antes?"

<br />

El objetivo es entender el sistema, no juzgar decisiones tomadas bajo presion. La gente toma
decisiones razonables basandose en la informacion que tiene en el momento. Si el sistema hizo facil
desplegar una migracion sin indice, el arreglo es un mejor sistema, no un sermon.

<br />

##### **Construyendo una cultura de on-call saludable**
El on-call no tiene que ser una tortura. Vi equipos donde el on-call es temido y equipos donde es
manejable e incluso gratificante. La diferencia se reduce a cultura e inversion.

<br />

**Expectativas razonables**

<br />

> * **Frecuencia**: Nadie deberia estar de on-call mas de una semana de cada cuatro. Si tu equipo es demasiado chico para esa rotacion, necesitas contratar, compartir la rotacion con otro equipo, o reducir el alcance de tu on-call.
> * **Carga de trabajo**: El ingeniero de on-call deberia poder hacer su trabajo regular durante turnos tranquilos de on-call. Si el on-call es tan ocupado que no pueden escribir codigo durante el dia, tus alertas necesitan ajuste.
> * **Sueno**: Que te paginen una vez por noche es aceptable ocasionalmente. Que te paginen tres o cuatro veces cada noche es un problema sistemico. Registra las paginaciones fuera de horario como una metrica y establece un objetivo para reducirlas.

<br />

**Practicar incidentes**

<br />

El peor momento para aprender respuesta a incidentes es durante un incidente real. Practica con game
days o ejercicios de mesa. Un game day es un ejercicio planificado donde intencionalmente rompes algo
(de manera controlada) y practicas la respuesta. Un ejercicio de mesa es donde recorres un escenario
de incidente verbalmente sin romper nada.

<br />

```plaintext
Ejemplo de escenario de mesa:

"Son las 2am de un martes. Te paginan por APIHighLatency.
 Revisas el dashboard y ves la latencia p99 en 8 segundos.
 La tasa de error esta en 12%. El ultimo deploy fue hace 6 horas.

 Que haces primero?
 Que revisas?
 A quien contactas?
 Como te comunicas con los stakeholders?"
```

<br />

Estos ejercicios construyen memoria muscular. Cuando un incidente real pasa, el ingeniero de on-call
no esta pensando "que hago?" Sino "ya hice esto antes, voy a seguir el proceso."

<br />

**Calidad del traspaso**

<br />

Un buen traspaso entre turnos de on-call incluye:

<br />

> * **Incidentes activos**: Cualquier cosa que siga en curso o se haya resuelto recientemente
> * **Alertas recientes**: Alertas que se dispararon y fueron manejadas, con contexto
> * **Problemas conocidos**: Cosas que podrian paginarte pero que ya se estan trabajando
> * **Cambios en el entorno**: Despliegues recientes, cambios de infraestructura, o ventanas de mantenimiento

<br />

Una llamada rapida de 15 minutos o un mensaje estructurado en Slack a la hora del traspaso previene
mucha confusion.

<br />

**Invertir en herramientas**

<br />

Cada vez que alguien es paginado por algo que podria haberse automatizado, eso es una falla de
herramientas. Registra tus incidentes y busca patrones. Si el mismo problema sigue pasando y el
runbook siempre dice "reiniciar el pod", automatiza el reinicio. Si una alerta particular siempre
resulta ser un falso positivo, arregla la alerta. El on-call deberia ser para problemas que
genuinamente necesitan un cerebro humano, no para tareas que un script podria manejar.

<br />

##### **Temas avanzados**
Cubrimos los fundamentos de la respuesta a incidentes en este articulo, pero hay mucho mas para
explorar a medida que tu equipo y sistemas crecen:

<br />

> * **Rol de incident commander**: Para incidentes SEV1, un incident commander dedicado coordina la respuesta, maneja la comunicacion, y toma decisiones sobre escalacion. Este rol es separado de los ingenieros haciendo el trabajo tecnico.
> * **Practicas de SRE**: Error budgets, alertas basadas en SLOs, y reduccion de toil son conceptos avanzados que se construyen sobre todo lo que cubrimos aca.
> * **Postmortems como codigo**: Templates de postmortem versionados, generacion automatizada de lineas de tiempo, y seguimiento de items de accion integrado en tu herramienta de gestion de proyectos.
> * **Ingenieria del caos**: Inyectar fallas intencionalmente para probar tu proceso de respuesta a incidentes antes de que pasen incidentes reales.

<br />

Para una inmersion profunda en todos estos temas, mira el articulo de
[SRE Incident Management](/blog/sre-incident-management-on-call-and-postmortems-as-code). Cubre
workflows de incident commander, automatizacion de on-call con operadores de Kubernetes, templates
de postmortem como codigo gestionados a traves de GitOps, y estrategias avanzadas de alertas.

<br />

##### **Notas finales**
La respuesta a incidentes no se trata solo de herramientas y procesos. Se trata de personas. Se trata
de asegurarse de que la persona que es paginada a las 3am tenga lo que necesita para resolver el
problema: alertas claras, buenos runbooks, el acceso correcto, y la confianza que viene de la practica.

<br />

En este articulo cubrimos que son los incidentes y como clasificarlos con niveles de severidad, las
cinco fases del ciclo de vida del incidente, como funcionan las rotaciones de on-call y como hacerlas
justas, configurar alertas desde Prometheus hasta PagerDuty o OpsGenie, por que la fatiga de alertas
es peligrosa y como combatirla, como escribir runbooks que realmente ayuden, buenas practicas de
comunicacion durante incidentes, postmortems sin culpa que impulsen mejoras, y construir una cultura
donde el on-call sea sostenible.

<br />

Lo mas importante para llevarse es esto: inverti en tu proceso de respuesta a incidentes antes de
necesitarlo. Escribi los runbooks, ajusta las alertas, practica los escenarios, y hace los
postmortems. Cuando el incidente real pase, vas a estar listo.

<br />

En el proximo y ultimo articulo de la serie, vamos a juntar todo y ver que viene despues de dominar
los fundamentos.

<br />

Espero que te haya resultado util y que lo hayas disfrutado, hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, mandame un mensaje para que se corrija.

Tambien, podes revisar el codigo fuente y los cambios en las [fuentes aca](https://github.com/kainlite/tr)

<br />
