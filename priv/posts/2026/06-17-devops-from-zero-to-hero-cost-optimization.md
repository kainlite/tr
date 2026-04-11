%{
  title: "DevOps from Zero to Hero: Cost Optimization and What Comes Next",
  author: "Gabriel Garrido",
  description: "We will explore cloud cost optimization strategies including AWS Cost Explorer, right-sizing, Spot instances, Kubernetes resource tuning, tagging strategies, and wrap up the entire DevOps from Zero to Hero series with a full recap and what comes next...",
  tags: ~w(devops aws cost-optimization finops beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article twenty, the final article of the DevOps from Zero to Hero series. Over the past
nineteen articles we built an entire DevOps practice from scratch. We wrote a TypeScript API, learned
version control, set up CI/CD pipelines, deployed to AWS, mastered Kubernetes, automated everything
with GitOps, and added observability so we could actually see what was happening in production.

<br />

But there is one topic we have not covered yet, and it might be the one that gets you the most
attention from leadership: cost. Cloud bills have a way of growing quietly in the background until
someone notices a five-figure monthly invoice and starts asking hard questions. Cost optimization is
not about being cheap. It is about spending intentionally and getting maximum value from every dollar.

<br />

In this article we will cover how to understand your AWS bill, identify common cost traps, right-size
your resources, use Spot instances and Savings Plans, optimize Kubernetes costs, build a tagging
strategy, set up cost monitoring, and manage dev/staging environments efficiently. Then we will wrap
up the entire series with a full recap of everything we learned and talk about where to go from here.

<br />

Let's get into it.

<br />

##### **Why cost matters: the rise of FinOps**
When you are learning cloud in a personal account, costs feel manageable. A small EKS cluster, a few
EC2 instances, and an RDS database might cost $100-300 per month. But in a real organization, those
numbers multiply fast. Teams spin up resources and forget about them. Someone creates a NAT Gateway
for testing and leaves it running for six months. A developer provisions an m5.4xlarge instance for a
service that barely uses 10% of its CPU.

<br />

The cloud makes it incredibly easy to spend money. That is by design. There is no procurement process,
no hardware to order, no six-week wait. You click a button and resources appear. This is powerful for
speed, but dangerous for budgets.

<br />

This is where FinOps comes in. FinOps (Financial Operations) is a practice that brings financial
accountability to cloud spending. It is not about cutting costs blindly. It is about making informed
decisions about what to spend and why.

<br />

The core principles of FinOps are:

<br />

> * **Teams need to own their cloud costs**: Just like DevOps made teams responsible for running their software, FinOps makes teams responsible for the cost of running it. If you deploy it, you should know what it costs.
> * **Decisions are driven by business value**: Not every cost reduction is a good idea. Cutting your monitoring stack to save $500/month might cost you $50,000 when you miss an outage. Cost optimization is about value, not just spending less.
> * **Cloud is a variable cost model**: Unlike on-premise where you buy servers and depreciate them over years, cloud costs change monthly. This means you need to review and optimize continuously, not just once a year.

<br />

Think of FinOps as the financial pillar of DevOps. You would not deploy code without testing it. You
should not deploy infrastructure without understanding what it costs.

<br />

##### **AWS Cost Explorer: understanding your bill**
The first step in cost optimization is understanding where your money is going. AWS Cost Explorer is
the primary tool for this. It is free and built into every AWS account.

<br />

To access it, go to the AWS Billing Console and click on Cost Explorer. The first time you enable it,
it takes about 24 hours to populate historical data. After that, you get up to 12 months of spending
history.

<br />

Here are the views you should use regularly:

<br />

**Monthly cost by service**

<br />

This is your starting point. Group by "Service" and set the time range to the last 3 months. You will
immediately see which services are costing the most. In a typical Kubernetes-based setup, your top
costs will usually be:

<br />

> * **EC2** (including EKS worker nodes): Compute is almost always the biggest line item
> * **RDS**: Database instances, especially if you run Multi-AZ
> * **NAT Gateway**: Data transfer through NAT Gateways is surprisingly expensive
> * **EBS**: Persistent volumes, snapshots, and unattached volumes
> * **S3**: Storage and request costs
> * **Data Transfer**: Cross-AZ and internet egress charges

<br />

**Cost by tag**

<br />

If you have a proper tagging strategy (we will cover this later), you can group costs by tag. This
lets you answer questions like "How much does the staging environment cost?" or "What is team-alpha
spending per month?" To use this view, you first need to activate your cost allocation tags in the
Billing Console under Cost Allocation Tags.

<br />

**Daily cost trends**

<br />

Switch to daily granularity and look for spikes. A sudden jump in EC2 costs might mean someone
launched a bunch of instances for a load test and forgot to terminate them. A spike in data transfer
costs might indicate a misconfigured service that is pulling data across regions.

<br />

You can also use the AWS CLI to query cost data programmatically:

<br />

```bash
# Get last month's cost grouped by service
aws ce get-cost-and-usage \
  --time-period Start=2026-05-01,End=2026-06-01 \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE
```

<br />

```bash
# Get daily costs for the current month
aws ce get-cost-and-usage \
  --time-period Start=2026-06-01,End=2026-06-17 \
  --granularity DAILY \
  --metrics "BlendedCost"
```

<br />

##### **Common cost traps**
Every cloud environment has hidden costs waiting to surprise you. Here are the most common ones and
how to find them.

<br />

**Forgotten resources**

<br />

These are resources that were created for a purpose but are no longer needed. They quietly accumulate
charges every month.

<br />

> * **Unattached EBS volumes**: When you terminate an EC2 instance, its EBS volumes might not be deleted automatically (depends on the DeleteOnTermination flag). These orphaned volumes cost money even when nothing is using them.
> * **Old EBS snapshots**: Snapshots pile up over time. A daily snapshot policy on a 500GB volume creates 365 snapshots per year. At $0.05/GB-month, that adds up.
> * **Idle load balancers**: A load balancer with no healthy targets still costs about $16-22/month. If you have abandoned ALBs from old projects, find them and delete them.
> * **NAT Gateways**: Each NAT Gateway costs about $32/month just to exist, plus $0.045 per GB of data processed. If you have NAT Gateways in multiple AZs across multiple VPCs, that is hundreds of dollars per month doing nothing if those VPCs are inactive.
> * **Elastic IPs**: An Elastic IP attached to a running instance is free. An Elastic IP not attached to anything costs $3.65/month. Small, but they add up.
> * **Unused ECR images**: Container images in ECR cost $0.10/GB-month. If your CI pipeline pushes a new image on every commit and you never clean up old ones, storage costs grow linearly.

<br />

Find forgotten resources with these commands:

<br />

```bash
# Find unattached EBS volumes
aws ec2 describe-volumes \
  --filters Name=status,Values=available \
  --query 'Volumes[*].{ID:VolumeId,Size:Size,Created:CreateTime}' \
  --output table

# Find Elastic IPs not associated with anything
aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==`null`].{IP:PublicIp,AllocID:AllocationId}' \
  --output table

# Find load balancers with no targets
aws elbv2 describe-target-groups \
  --query 'TargetGroups[*].{ARN:TargetGroupArn,Name:TargetGroupName}' \
  --output table
```

<br />

**Oversized instances**

<br />

This is the most common cost trap. Teams pick an instance type when they first deploy a service and
never revisit it. That m5.xlarge you chose "just in case" might be running at 5% CPU utilization. You
could be on a t3.medium and save 75%.

<br />

**Idle dev/staging environments**

<br />

Your staging environment runs 24/7 but your team works 8 hours a day, 5 days a week. That means
staging is idle 76% of the time. If staging costs $2,000/month, you are wasting about $1,500/month
on compute that nobody is using.

<br />

**Cross-AZ data transfer**

<br />

Data transfer between Availability Zones costs $0.01/GB in each direction ($0.02/GB round trip).
This sounds tiny, but a chatty microservice architecture with services spread across AZs can generate
terabytes of cross-AZ traffic. This is often the most surprising line item on an AWS bill.

<br />

##### **Right-sizing: matching resources to actual usage**
Right-sizing means adjusting your compute resources to match what your workload actually needs. It is
the highest-impact cost optimization you can do because compute is usually your biggest expense.

<br />

**Step 1: Gather metrics**

<br />

Before you can right-size anything, you need data. Use CloudWatch to understand your actual resource
utilization:

<br />

```bash
# Get average CPU utilization for an instance over the last 7 days
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-0abc123def456789 \
  --start-time 2026-06-10T00:00:00Z \
  --end-time 2026-06-17T00:00:00Z \
  --period 3600 \
  --statistics Average Maximum \
  --output table
```

<br />

Look at both the average and the maximum. If your average CPU is 10% and your max is 25%, you have
significant room to downsize. If your average is 10% but your max spikes to 95%, you might need that
capacity for peak loads (or you might need to investigate what causes those spikes).

<br />

**Step 2: Use AWS Compute Optimizer**

<br />

AWS Compute Optimizer analyzes your CloudWatch metrics and recommends instance types that would better
fit your workload. Enable it in the AWS Console under Compute Optimizer. It is free for basic
recommendations.

<br />

It will tell you things like: "This m5.xlarge instance averages 8% CPU utilization. A t3.medium would
save 75% while still providing sufficient capacity." These recommendations are a great starting point,
but always validate them against your application's actual requirements. Memory-intensive applications
might need more RAM than CPU, for example.

<br />

**Step 3: Right-size gradually**

<br />

Do not downsize everything at once. Pick your most over-provisioned instances, downsize them one at a
time, and monitor for a week. If performance is fine, move to the next one. If you see issues, scale
back up. Right-sizing is iterative, not a one-time event.

<br />

```bash
# Change instance type (requires stop/start)
aws ec2 stop-instances --instance-ids i-0abc123def456789
aws ec2 modify-instance-attribute \
  --instance-id i-0abc123def456789 \
  --instance-type '{"Value":"t3.medium"}'
aws ec2 start-instances --instance-ids i-0abc123def456789
```

<br />

For EKS worker nodes managed by a node group, you would update the launch template or node group
configuration instead:

<br />

```bash
# Update managed node group instance type
aws eks update-nodegroup-config \
  --cluster-name my-cluster \
  --nodegroup-name my-nodegroup \
  --scaling-config minSize=2,maxSize=6,desiredSize=3
```

<br />

##### **Spot instances and Karpenter**
Spot instances let you use unused EC2 capacity at up to 90% discount compared to on-demand prices.
The trade-off is that AWS can reclaim them with a 2-minute warning when it needs the capacity back.
This sounds scary, but with the right architecture, Spot is one of the most effective cost optimization
strategies available.

<br />

**How Spot works**

<br />

When AWS has unused capacity in a particular instance type and AZ, it makes that capacity available
as Spot instances at a reduced price. The price fluctuates based on supply and demand but is typically
60-90% cheaper than on-demand. When AWS needs that capacity back (a "Spot interruption"), your instance
gets a 2-minute warning and then is terminated.

<br />

**When to use Spot**

<br />

> * **Stateless workloads**: Web servers, API servers, and workers that do not store data locally are perfect for Spot. If an instance gets interrupted, the load balancer routes traffic to other instances.
> * **Batch processing**: Jobs that can be checkpointed and restarted work well on Spot.
> * **CI/CD runners**: Build agents are short-lived by nature and can tolerate interruptions.
> * **Development and staging environments**: These do not need the same reliability guarantees as production.

<br />

**When NOT to use Spot**

<br />

> * **Databases**: Losing a database instance mid-transaction is a bad day.
> * **Stateful workloads without replication**: If losing an instance means losing data, do not put it on Spot.
> * **Single-instance workloads**: If you only have one instance and it gets interrupted, your service is down.

<br />

**Mixing on-demand and Spot**

<br />

The best practice is to run a baseline of on-demand instances that can handle your minimum expected
load, and use Spot for everything above that. For example, if your API needs at least 3 instances to
handle normal traffic but scales to 10 during peak hours, run 3 on-demand and let the remaining 7
be Spot.

<br />

**Karpenter for Kubernetes**

<br />

If you are running EKS, Karpenter is the best way to use Spot instances with Kubernetes. Karpenter is
an open-source node provisioning tool that automatically selects the right instance types and purchase
options (on-demand vs Spot) based on your pod requirements.

<br />

Here is a basic Karpenter NodePool configuration that mixes on-demand and Spot:

<br />

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - m5.large
            - m5.xlarge
            - m5a.large
            - m5a.xlarge
            - m6i.large
            - m6i.xlarge
        - key: topology.kubernetes.io/zone
          operator: In
          values:
            - us-east-1a
            - us-east-1b
            - us-east-1c
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  limits:
    cpu: "100"
    memory: 400Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
```

<br />

Karpenter will automatically diversify across multiple instance types and AZs to reduce the chance
of simultaneous Spot interruptions. The `disruption` block tells Karpenter to consolidate
underutilized nodes, which saves money by packing pods more efficiently.

<br />

**Handling Spot interruptions**

<br />

For graceful handling of Spot interruptions in Kubernetes, make sure your pods handle SIGTERM properly
and have appropriate `terminationGracePeriodSeconds`. Karpenter integrates with the AWS Node
Termination Handler to cordon and drain nodes before they are reclaimed.

<br />

##### **Reserved Instances and Savings Plans**
If you know you will need a certain amount of compute for the next 1-3 years, Reserved Instances (RIs)
and Savings Plans offer significant discounts (up to 72%) in exchange for a commitment.

<br />

**Savings Plans vs Reserved Instances**

<br />

> * **Compute Savings Plans**: You commit to a specific dollar amount of compute per hour (e.g., $10/hour) for 1 or 3 years. The discount applies across EC2, Fargate, and Lambda. This is the most flexible option.
> * **EC2 Instance Savings Plans**: You commit to a specific instance family in a specific region (e.g., m5 in us-east-1). Higher discount than Compute Savings Plans but less flexible.
> * **Reserved Instances**: You commit to a specific instance type, AZ, and tenancy. The highest discount but the least flexible. These are the legacy option and Savings Plans are generally recommended instead.

<br />

**When commitments make sense**

<br />

> * **Stable, predictable workloads**: If your production database has been running on an r5.2xlarge for a year and will continue to do so, a Savings Plan is a no-brainer.
> * **Baseline compute**: Commit to your minimum required compute. Use on-demand and Spot for anything above the baseline.
> * **After right-sizing**: Always right-size first, then commit. There is nothing worse than committing to an oversized instance for 3 years.

<br />

**When to avoid commitments**

<br />

> * **New workloads**: Wait until you understand the actual resource requirements (at least 2-3 months of data).
> * **Rapidly changing architectures**: If you are migrating from EC2 to containers or from x86 to ARM, locking into commitments can backfire.
> * **Small amounts**: The administrative overhead of managing RIs for a $50/month saving is not worth it.

<br />

A practical approach is to cover 60-70% of your steady-state compute with Savings Plans, handle the
next 20% with on-demand, and use Spot for the remaining 10-20% that handles peak loads.

<br />

##### **Kubernetes cost optimization**
Kubernetes adds its own layer of cost complexity. Pods request resources, nodes provide them, and the
gap between requested and actually used resources is wasted money.

<br />

**Resource requests and limits**

<br />

Every pod should have resource requests and limits defined. Requests tell the scheduler how much CPU
and memory a pod needs. Limits cap how much it can use. The gap between what you request and what you
actually use is waste.

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: api
          image: my-api:latest
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
```

<br />

The most common mistake is setting requests too high "just to be safe." If your API container uses
50m CPU on average but you request 500m, each pod wastes 450m of CPU. With 10 replicas, you are
wasting 4.5 vCPUs, which could be an entire node worth of compute.

<br />

To find the right values, check actual usage with `kubectl top`:

<br />

```bash
# Check actual resource usage per pod
kubectl top pods -n my-namespace

# Check node-level resource utilization
kubectl top nodes

# Detailed resource allocation per node
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

<br />

Set requests based on the P95 usage (what the pod actually uses 95% of the time) and limits at
roughly 2x the request to handle bursts. Review and adjust these values every month.

<br />

**Namespace resource quotas**

<br />

Resource quotas prevent any single team or namespace from consuming more than its fair share of
cluster resources. Without quotas, one team's runaway deployment can starve everyone else and force
unnecessary cluster scaling.

<br />

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "8"
    requests.memory: "16Gi"
    limits.cpu: "16"
    limits.memory: "32Gi"
    pods: "50"
    persistentvolumeclaims: "10"
```

<br />

**Cluster Autoscaler and Karpenter**

<br />

Both Cluster Autoscaler and Karpenter scale your node count based on pending pods, but they approach
it differently:

<br />

> * **Cluster Autoscaler**: Works with AWS Auto Scaling Groups. You predefine node group configurations (instance types, sizes). The autoscaler adds or removes nodes from these predefined groups. Simpler to set up but less flexible.
> * **Karpenter**: Evaluates pending pods and provisions the optimal instance type on the fly. It can choose from a wide range of instance types and automatically bin-pack pods efficiently. More flexible and generally more cost-effective, but requires more initial configuration.

<br />

Whichever you use, make sure scale-down is enabled and tuned. By default, Cluster Autoscaler waits
10 minutes before removing an underutilized node. In a bursty environment, this delay means you are
paying for idle nodes for 10 minutes after every traffic spike.

<br />

**Horizontal Pod Autoscaler (HPA)**

<br />

HPA scales your pod count based on metrics like CPU or custom metrics. This lets you run fewer pods
during low-traffic periods and scale up during peaks, instead of running peak capacity 24/7.

<br />

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
```

<br />

##### **Tagging strategy: tag everything**
Tags are the foundation of cost visibility. Without tags, your AWS bill is one big number. With tags,
you can answer "How much does each environment cost?", "Which team is spending the most?", and "What
is the cost per customer?"

<br />

**Minimum required tags**

<br />

Every resource in your AWS account should have at least these tags:

<br />

> * **Environment**: `production`, `staging`, `development`
> * **Team**: The team that owns the resource
> * **Service**: The application or service name
> * **CostCenter**: For chargeback or showback to business units
> * **ManagedBy**: `terraform`, `manual`, `karpenter`, etc.

<br />

**Enforce tags with policies**

<br />

Tags only work if they are applied consistently. Use AWS Organizations tag policies or Terraform
validation to enforce tagging:

<br />

```hcl
# Terraform: enforce tags on all resources
variable "required_tags" {
  type = map(string)
  default = {
    Environment = ""
    Team        = ""
    Service     = ""
    ManagedBy   = "terraform"
  }
}

resource "aws_instance" "api" {
  ami           = "ami-0abc123def456789"
  instance_type = "t3.medium"

  tags = merge(var.required_tags, {
    Name        = "api-server"
    Environment = "production"
    Team        = "backend"
    Service     = "user-api"
  })
}
```

<br />

For a more robust approach, use an AWS Organizations tag policy:

<br />

```json
{
  "tags": {
    "Environment": {
      "tag_key": {
        "@@assign": "Environment"
      },
      "tag_value": {
        "@@assign": [
          "production",
          "staging",
          "development"
        ]
      },
      "enforced_for": {
        "@@assign": [
          "ec2:instance",
          "rds:db",
          "s3:bucket",
          "elasticloadbalancing:loadbalancer"
        ]
      }
    }
  }
}
```

<br />

**Activate cost allocation tags**

<br />

Creating tags is not enough. You also need to activate them as cost allocation tags in the Billing
Console. Only activated tags appear in Cost Explorer for grouping and filtering. Go to Billing, then
Cost Allocation Tags, find your tags, and click Activate. It takes up to 24 hours for activated tags
to appear in Cost Explorer.

<br />

##### **Cost monitoring: budgets and alerts**
Setting up cost monitoring is like setting up application monitoring. You do not wait for users to
report outages. You set up alerts. You should not wait for finance to report cost overruns either.

<br />

**AWS Budgets**

<br />

Create budgets for your total account spend and for each major service or environment:

<br />

```bash
# Create a monthly budget with email alerts
aws budgets create-budget \
  --account-id 123456789012 \
  --budget '{
    "BudgetName": "monthly-total",
    "BudgetLimit": {
      "Amount": "5000",
      "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "team@example.com"
        }
      ]
    },
    {
      "Notification": {
        "NotificationType": "FORECASTED",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "team@example.com"
        }
      ]
    }
  ]'
```

<br />

This creates a $5,000/month budget with two alerts: one when actual spend hits 80% of the budget, and
another when the forecasted spend is projected to exceed the budget. The forecast alert is especially
useful because it gives you time to act before you actually overspend.

<br />

**Weekly cost reviews**

<br />

Set up a weekly ritual where someone on the team reviews costs. It does not need to be a long meeting.
A 15-minute check of Cost Explorer once a week is enough. Look for:

<br />

> * **Unexpected spikes**: Anything that jumped significantly from the previous week
> * **New services**: Any service that appeared in your bill that was not there before
> * **Trend lines**: Is overall spending trending up? If so, is it proportional to growth?
> * **Idle resources**: Any resources with zero or near-zero utilization

<br />

The person doing the review should rotate across the team. This builds cost awareness across the
entire team, not just one designated cost watcher.

<br />

##### **Dev/staging environment strategies**
Development and staging environments are often the easiest place to cut costs because they do not need
to be available 24/7 and they do not need production-grade resources.

<br />

**Scale down at night and on weekends**

<br />

If your team works 9am to 6pm on weekdays, your dev and staging environments are idle 73% of the
time. Use scheduled scaling to shut them down outside working hours:

<br />

```bash
# Scale down EKS node group at night (run via cron or Lambda)
aws eks update-nodegroup-config \
  --cluster-name dev-cluster \
  --nodegroup-name dev-nodes \
  --scaling-config minSize=0,maxSize=3,desiredSize=0

# Scale up in the morning
aws eks update-nodegroup-config \
  --cluster-name dev-cluster \
  --nodegroup-name dev-nodes \
  --scaling-config minSize=1,maxSize=3,desiredSize=2
```

<br />

You can automate this with a Lambda function triggered by EventBridge on a schedule:

<br />

```json
{
  "schedule_expression": "cron(0 22 ? * MON-FRI *)",
  "description": "Scale down dev cluster at 10 PM",
  "action": "scale-down"
}
```

<br />

**Use smaller instances for non-production**

<br />

If production runs on m5.xlarge, staging can probably run on t3.medium. Dev can run on t3.small. The
goal is not identical environments. It is environments that are similar enough to catch bugs but small
enough to be affordable.

<br />

**Ephemeral environments**

<br />

Instead of running a persistent staging environment, consider spinning up short-lived environments
for each pull request. The environment gets created when the PR is opened, runs integration tests,
and gets destroyed when the PR is merged or closed. You only pay for the time someone is actively
testing. Tools like Argo CD ApplicationSets or Terraform workspaces can automate this pattern.

<br />

**Single-node dev clusters**

<br />

For development, consider running a single-node Kubernetes cluster or using a local tool like kind
or minikube. This avoids the EKS control plane cost ($73/month) and multi-node compute costs
entirely for local development.

<br />

##### **Putting it all together: a cost optimization checklist**
Here is a practical checklist you can work through to optimize your cloud costs:

<br />

> * **Week 1**: Enable Cost Explorer, activate cost allocation tags, create a basic budget with alerts
> * **Week 2**: Audit for forgotten resources (unattached volumes, idle load balancers, unused Elastic IPs). Delete anything not needed
> * **Week 3**: Analyze compute utilization with CloudWatch and Compute Optimizer. Identify right-sizing candidates
> * **Week 4**: Right-size your most over-provisioned instances. Start with non-production
> * **Month 2**: Implement tagging policies, set up scheduled scaling for dev/staging, evaluate Spot for stateless workloads
> * **Month 3**: Review Kubernetes resource requests/limits, implement HPA, consider Karpenter. Evaluate Savings Plans for stable production workloads
> * **Ongoing**: Weekly cost reviews, monthly optimization passes, quarterly Savings Plan evaluation

<br />

##### **The complete series recap**
We have covered a lot of ground in this series. Let's take a moment to look back at every article and
what we learned in each one. If you missed any or want to revisit a topic, the links below will take
you there.

<br />

> * **Article 1: [What It Actually Means](/blog/devops-from-zero-to-hero-what-it-actually-means)** - We started from the very beginning. What DevOps is, where it came from, the DORA metrics that measure it, and how DevOps relates to SRE and Platform Engineering.
> * **Article 2: [Your First TypeScript API](/blog/devops-from-zero-to-hero-your-first-typescript-api)** - We built a real application with Express and Docker. This gave us something concrete to deploy throughout the rest of the series.
> * **Article 3: [Version Control for Teams](/blog/devops-from-zero-to-hero-version-control-for-teams)** - We learned Git workflows, branching strategies, pull requests, and code review. The collaboration foundation for everything that followed.
> * **Article 4: [Automated Testing](/blog/devops-from-zero-to-hero-automated-testing)** - We wrote unit tests, integration tests, and learned the testing pyramid. No CI pipeline works without good tests.
> * **Article 5: [Your First CI Pipeline](/blog/devops-from-zero-to-hero-your-first-ci-pipeline)** - We set up GitHub Actions to automatically lint, test, and build our code on every push. Our first taste of automation.
> * **Article 6: [AWS from Scratch](/blog/devops-from-zero-to-hero-aws-from-scratch)** - We created an AWS account, set up IAM users and roles, understood regions and AZs, and got comfortable with the AWS CLI.
> * **Article 7: [Infrastructure as Code with Terraform](/blog/devops-from-zero-to-hero-infrastructure-as-code)** - We stopped clicking around in the console and started defining infrastructure as code. VPCs, subnets, security groups, all in Terraform.
> * **Article 8: [Deploying to ECS with Fargate](/blog/devops-from-zero-to-hero-deploying-to-ecs)** - We deployed our API to AWS for the first time using ECS and Fargate. Real cloud infrastructure running our real application.
> * **Article 9: [Secrets and Config Management](/blog/devops-from-zero-to-hero-secrets-and-config)** - We learned how to manage secrets safely with AWS Secrets Manager and SSM Parameter Store. No more hardcoded passwords.
> * **Article 10: [DNS, TLS, and Networking](/blog/devops-from-zero-to-hero-dns-tls-and-networking)** - We made our app reachable with a real domain, set up TLS certificates with ACM, and understood how networking ties everything together.
> * **Article 11: [Kubernetes Fundamentals](/blog/devops-from-zero-to-hero-kubernetes-fundamentals)** - We learned pods, deployments, services, and namespaces. The building blocks of container orchestration.
> * **Article 12: [Helm Charts](/blog/devops-from-zero-to-hero-helm-charts)** - We packaged our Kubernetes application with Helm, making it reusable and configurable across environments.
> * **Article 13: [EKS, Running Kubernetes on AWS](/blog/devops-from-zero-to-hero-eks)** - We set up a production-grade EKS cluster with Terraform, including managed node groups, IAM integration, and networking.
> * **Article 14: [GitOps with ArgoCD](/blog/devops-from-zero-to-hero-gitops-with-argocd)** - We implemented GitOps so that git became the single source of truth for our deployments. Push to git and ArgoCD handles the rest.
> * **Article 15: [Observability in Kubernetes](/blog/devops-from-zero-to-hero-observability)** - We set up Prometheus, Grafana, and structured logging. We learned about the three pillars: logs, metrics, and traces.
> * **Article 16: [CI/CD, The Complete Pipeline](/blog/devops-from-zero-to-hero-the-complete-pipeline)** - We stitched everything together into a complete pipeline from pull request to production, with staging gates and manual approvals.
> * **Article 17: Security and Compliance** - We covered container image scanning, RBAC policies, network policies, and how to bake security into every stage of the pipeline.
> * **Article 18: Disaster Recovery and High Availability** - We learned multi-AZ deployments, backup strategies, RTO/RPO targets, and how to plan for the worst so your systems stay up.
> * **Article 19: Advanced Deployment Strategies** - We explored canary deployments, blue/green deployments, feature flags, and progressive delivery patterns for zero-downtime releases.
> * **Article 20: Cost Optimization and What Comes Next (this article)** - We learned how to understand, monitor, and optimize cloud costs, then wrapped up the entire series.

<br />

That is twenty articles, and if you followed along, you went from knowing nothing about DevOps to
having a complete, production-grade pipeline with automated testing, infrastructure as code,
Kubernetes, GitOps, observability, security, and cost optimization. That is a serious achievement.

<br />

##### **What comes next**
Finishing this series does not mean you are done learning. In many ways, you are just getting started.
You now have a solid foundation, and there are several paths forward depending on your interests and
career goals.

<br />

**Site Reliability Engineering (SRE)**

<br />

If you enjoyed the observability, monitoring, and reliability aspects of this series, SRE is a natural
next step. SRE takes the DevOps principles we covered and adds rigorous engineering practices around
reliability: SLIs, SLOs, error budgets, incident management, chaos engineering, and capacity planning.

<br />

We have an entire SRE series on this blog that picks up where this one leaves off. Start with
[SRE: SLIs, SLOs, and Automations That Actually Help](/blog/sre-slis-slos-and-automations-that-actually-help)
and work through all fourteen articles.

<br />

**Platform Engineering**

<br />

If you found yourself thinking "I wish developers did not have to know all of this just to deploy
their apps," Platform Engineering is for you. Platform teams build internal developer platforms
that abstract away infrastructure complexity. You would build golden paths, self-service portals,
and developer tooling that makes it easy for any developer to deploy, observe, and manage their
applications without needing to understand every underlying component.

<br />

**Developer Experience (DX)**

<br />

Related to Platform Engineering, Developer Experience focuses on making developers productive and
happy. Fast CI pipelines, great local development setups, clear documentation, easy onboarding. If
you care about how people experience the tools and processes you build, DX is worth exploring.

<br />

**Certifications**

<br />

If you want to formalize your knowledge and signal your skills to employers, consider these
certifications:

<br />

> * **AWS Solutions Architect Associate (SAA-C03)**: Covers the core AWS services we used throughout this series. If you followed along and built everything, you already know about 70% of what is on this exam.
> * **Certified Kubernetes Administrator (CKA)**: Validates your Kubernetes skills. The articles on Kubernetes fundamentals, Helm, and EKS gave you a strong head start.
> * **HashiCorp Terraform Associate**: Covers the Terraform concepts we used for infrastructure as code. Probably the easiest of the three if you have been writing Terraform along with the series.

<br />

None of these certifications are required. Hands-on experience matters more than certificates. But
they can be helpful for landing interviews, especially early in your career.

<br />

**Communities and resources**

<br />

Learning does not happen in isolation. Here are some communities and resources worth checking out:

<br />

> * **CNCF (Cloud Native Computing Foundation)**: The organization behind Kubernetes, Prometheus, ArgoCD, and many other tools we used. Their landscape page gives you a map of the entire cloud native ecosystem.
> * **DevOps subreddits and forums**: r/devops, r/kubernetes, and r/aws are active communities where people share experiences and help each other.
> * **KubeCon talks**: The recorded talks from KubeCon are freely available on YouTube and cover everything from beginner to advanced topics.
> * **The SRE Book**: Google's "Site Reliability Engineering" book is available free online at sre.google. It is the foundational text for SRE practices.
> * **"Accelerate" by Forsgren, Humble, and Kim**: The book behind the DORA metrics. If you want to understand the research that proves DevOps practices work, this is the one.

<br />

##### **Closing notes**
This is the end of the DevOps from Zero to Hero series, and if you made it all the way here, I want
to say something sincerely: well done. Twenty articles is a lot. Building all of this from scratch
takes real commitment, and the fact that you stuck with it says a lot about you.

<br />

When we started this series, we talked about what DevOps actually means. Not the buzzword, not the
job title, but the real idea: that the people who build software and the people who run it should
work together, share responsibility, and use automation to move faster without sacrificing stability.
Every article since then has been a practical expression of that idea. Automated tests, CI pipelines,
infrastructure as code, Kubernetes, GitOps, observability, security, and now cost optimization. Each
piece reinforces the others. Together, they form a complete practice.

<br />

But the most important thing you built is not a pipeline or a cluster. It is a way of thinking. You
now approach problems differently. When you see a manual process, you think about automating it. When
you see a deployment that requires SSH and prayer, you think about CI/CD. When someone says "it works
on my machine," you think about containers. That mindset is more valuable than any specific tool, and
it will serve you well no matter where your career takes you.

<br />

The cloud ecosystem will keep evolving. New tools will appear, some of what we covered will become
outdated, and best practices will shift. That is fine. The fundamentals we covered (version control,
testing, automation, infrastructure as code, observability, security, cost awareness) are timeless.
The specific tools change, but the principles do not.

<br />

So go build something. Take what you learned here and apply it at work, on a side project, or in
an open source contribution. The best way to solidify knowledge is to use it. And when you get stuck,
remember that every expert you admire was once exactly where you are now.

<br />

Thank you for reading this series. I genuinely hope it helped you, and I hope you had as much fun
following along as I had writing it. Until the next series!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: Optimizacion de Costos y Lo Que Viene Despues",
  author: "Gabriel Garrido",
  description: "Vamos a explorar estrategias de optimizacion de costos en la nube incluyendo AWS Cost Explorer, right-sizing, instancias Spot, ajuste de recursos en Kubernetes, estrategias de tagging, y cerrar toda la serie DevOps desde Cero con un repaso completo y que viene despues...",
  tags: ~w(devops aws cost-optimization finops beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo veinte, el articulo final de la serie DevOps desde Cero. A lo largo de los
diecinueve articulos anteriores construimos una practica DevOps completa desde cero. Escribimos una
API en TypeScript, aprendimos control de versiones, configuramos pipelines de CI/CD, deployeamos en
AWS, dominamos Kubernetes, automatizamos todo con GitOps, y agregamos observabilidad para poder ver
lo que realmente estaba pasando en produccion.

<br />

Pero hay un tema que todavia no cubrimos, y puede ser el que mas atencion te consiga de parte de
la gerencia: los costos. Las facturas de la nube tienen una forma de crecer silenciosamente en el
fondo hasta que alguien nota una factura mensual de cinco cifras y empieza a hacer preguntas
dificiles. La optimizacion de costos no se trata de ser tacano. Se trata de gastar intencionalmente
y obtener el maximo valor de cada dolar.

<br />

En este articulo vamos a cubrir como entender tu factura de AWS, identificar trampas de costos comunes,
ajustar tus recursos al tamano correcto, usar instancias Spot y Savings Plans, optimizar costos de
Kubernetes, construir una estrategia de tagging, configurar monitoreo de costos, y gestionar ambientes
de dev/staging de forma eficiente. Despues vamos a cerrar la serie completa con un repaso de todo lo
que aprendimos y hablar sobre hacia donde ir desde aca.

<br />

Vamos a meternos de lleno.

<br />

##### **Por que importan los costos: el surgimiento de FinOps**
Cuando estas aprendiendo cloud en una cuenta personal, los costos se sienten manejables. Un cluster
EKS chico, unas instancias EC2 y una base de datos RDS pueden costar entre $100 y $300 por mes. Pero
en una organizacion real, esos numeros se multiplican rapido. Los equipos levantan recursos y se
olvidan de ellos. Alguien crea un NAT Gateway para pruebas y lo deja corriendo seis meses. Un
desarrollador provisiona una instancia m5.4xlarge para un servicio que apenas usa el 10% de su CPU.

<br />

La nube hace increiblemente facil gastar plata. Eso es por diseno. No hay proceso de compras, no hay
hardware que pedir, no hay espera de seis semanas. Haces click en un boton y los recursos aparecen.
Esto es poderoso para la velocidad, pero peligroso para los presupuestos.

<br />

Aca es donde entra FinOps. FinOps (Financial Operations) es una practica que trae responsabilidad
financiera al gasto en la nube. No se trata de recortar costos a ciegas. Se trata de tomar decisiones
informadas sobre que gastar y por que.

<br />

Los principios centrales de FinOps son:

<br />

> * **Los equipos necesitan ser duenos de sus costos cloud**: Asi como DevOps hizo que los equipos fueran responsables de correr su software, FinOps hace que los equipos sean responsables del costo de correrlo. Si lo deployas, deberias saber cuanto cuesta.
> * **Las decisiones se basan en valor de negocio**: No toda reduccion de costos es buena idea. Recortar tu stack de monitoreo para ahorrar $500/mes puede costarte $50,000 cuando te perdas una caida. La optimizacion de costos se trata de valor, no solo de gastar menos.
> * **La nube es un modelo de costo variable**: A diferencia de on-premise donde compras servidores y los deprecias durante anos, los costos cloud cambian mensualmente. Esto significa que necesitas revisar y optimizar continuamente, no solo una vez al ano.

<br />

Pensa en FinOps como el pilar financiero de DevOps. No deployearias codigo sin testearlo. No deberias
deployear infraestructura sin entender cuanto cuesta.

<br />

##### **AWS Cost Explorer: entendiendo tu factura**
El primer paso en la optimizacion de costos es entender a donde va tu plata. AWS Cost Explorer es la
herramienta principal para esto. Es gratis y viene incluida en toda cuenta de AWS.

<br />

Para acceder, anda a la consola de Billing de AWS y hace click en Cost Explorer. La primera vez que
lo habilitas, tarda unas 24 horas en poblar datos historicos. Despues de eso, tenes hasta 12 meses
de historial de gastos.

<br />

Estas son las vistas que deberias usar regularmente:

<br />

**Costo mensual por servicio**

<br />

Este es tu punto de partida. Agrupa por "Service" y configura el rango de tiempo a los ultimos 3
meses. Inmediatamente vas a ver que servicios estan costando mas. En un setup tipico basado en
Kubernetes, tus costos principales van a ser usualmente:

<br />

> * **EC2** (incluyendo nodos worker de EKS): El computo es casi siempre la linea mas grande
> * **RDS**: Instancias de base de datos, especialmente si corres Multi-AZ
> * **NAT Gateway**: La transferencia de datos a traves de NAT Gateways es sorprendentemente cara
> * **EBS**: Volumenes persistentes, snapshots y volumenes sin adjuntar
> * **S3**: Costos de almacenamiento y solicitudes
> * **Data Transfer**: Cargos de cross-AZ y egress a internet

<br />

**Costo por tag**

<br />

Si tenes una estrategia de tagging adecuada (lo vamos a cubrir mas adelante), podes agrupar costos
por tag. Esto te permite responder preguntas como "Cuanto cuesta el ambiente de staging?" o "Cuanto
esta gastando el equipo-alpha por mes?" Para usar esta vista, primero necesitas activar tus cost
allocation tags en la consola de Billing bajo Cost Allocation Tags.

<br />

**Tendencias diarias de costos**

<br />

Cambia a granularidad diaria y busca picos. Un salto repentino en costos de EC2 puede significar que
alguien levanto un monton de instancias para un test de carga y se olvido de terminarlas. Un pico en
costos de transferencia de datos puede indicar un servicio mal configurado que esta trayendo datos
entre regiones.

<br />

Tambien podes usar la CLI de AWS para consultar datos de costos programaticamente:

<br />

```bash
# Obtener el costo del mes pasado agrupado por servicio
aws ce get-cost-and-usage \
  --time-period Start=2026-05-01,End=2026-06-01 \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE
```

<br />

```bash
# Obtener costos diarios del mes actual
aws ce get-cost-and-usage \
  --time-period Start=2026-06-01,End=2026-06-17 \
  --granularity DAILY \
  --metrics "BlendedCost"
```

<br />

##### **Trampas de costos comunes**
Todo ambiente cloud tiene costos ocultos esperando para sorprenderte. Aca estan los mas comunes y
como encontrarlos.

<br />

**Recursos olvidados**

<br />

Estos son recursos que se crearon con un proposito pero ya no se necesitan. Acumulan cargos
silenciosamente todos los meses.

<br />

> * **Volumenes EBS sin adjuntar**: Cuando terminas una instancia EC2, sus volumenes EBS pueden no borrarse automaticamente (depende del flag DeleteOnTermination). Estos volumenes huerfanos cuestan plata aunque nada los este usando.
> * **Snapshots EBS viejos**: Los snapshots se acumulan con el tiempo. Una politica de snapshots diarios en un volumen de 500GB crea 365 snapshots por ano. A $0.05/GB-mes, eso suma.
> * **Load balancers inactivos**: Un load balancer sin targets saludables igual cuesta unos $16-22/mes. Si tenes ALBs abandonados de proyectos viejos, encontralos y borralos.
> * **NAT Gateways**: Cada NAT Gateway cuesta unos $32/mes solo por existir, mas $0.045 por GB de datos procesados. Si tenes NAT Gateways en multiples AZs a traves de multiples VPCs, son cientos de dolares por mes sin hacer nada si esas VPCs estan inactivas.
> * **Elastic IPs**: Una Elastic IP adjunta a una instancia corriendo es gratis. Una Elastic IP sin adjuntar a nada cuesta $3.65/mes. Poco, pero se acumula.
> * **Imagenes ECR sin usar**: Las imagenes de containers en ECR cuestan $0.10/GB-mes. Si tu pipeline de CI pushea una imagen nueva en cada commit y nunca limpias las viejas, los costos de almacenamiento crecen linealmente.

<br />

Encontra recursos olvidados con estos comandos:

<br />

```bash
# Encontrar volumenes EBS sin adjuntar
aws ec2 describe-volumes \
  --filters Name=status,Values=available \
  --query 'Volumes[*].{ID:VolumeId,Size:Size,Created:CreateTime}' \
  --output table

# Encontrar Elastic IPs no asociadas con nada
aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==`null`].{IP:PublicIp,AllocID:AllocationId}' \
  --output table

# Encontrar load balancers sin targets
aws elbv2 describe-target-groups \
  --query 'TargetGroups[*].{ARN:TargetGroupArn,Name:TargetGroupName}' \
  --output table
```

<br />

**Instancias sobredimensionadas**

<br />

Esta es la trampa de costos mas comun. Los equipos eligen un tipo de instancia cuando deployean un
servicio por primera vez y nunca lo revisan. Ese m5.xlarge que elegiste "por las dudas" puede estar
corriendo con 5% de utilizacion de CPU. Podrias estar en un t3.medium y ahorrar 75%.

<br />

**Ambientes dev/staging inactivos**

<br />

Tu ambiente de staging corre 24/7 pero tu equipo trabaja 8 horas al dia, 5 dias a la semana. Eso
significa que staging esta inactivo el 76% del tiempo. Si staging cuesta $2,000/mes, estas
desperdiciando unos $1,500/mes en computo que nadie esta usando.

<br />

**Transferencia de datos cross-AZ**

<br />

La transferencia de datos entre Availability Zones cuesta $0.01/GB en cada direccion ($0.02/GB ida
y vuelta). Suena minusculo, pero una arquitectura de microservicios con mucha comunicacion y servicios
distribuidos entre AZs puede generar terabytes de trafico cross-AZ. Esto es frecuentemente la linea
mas sorprendente en una factura de AWS.

<br />

##### **Right-sizing: ajustando recursos al uso real**
Right-sizing significa ajustar tus recursos de computo para que coincidan con lo que tu carga de
trabajo realmente necesita. Es la optimizacion de costos de mayor impacto que podes hacer porque
el computo es usualmente tu gasto mas grande.

<br />

**Paso 1: Recolectar metricas**

<br />

Antes de poder hacer right-sizing, necesitas datos. Usa CloudWatch para entender tu utilizacion
real de recursos:

<br />

```bash
# Obtener la utilizacion promedio de CPU para una instancia en los ultimos 7 dias
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-0abc123def456789 \
  --start-time 2026-06-10T00:00:00Z \
  --end-time 2026-06-17T00:00:00Z \
  --period 3600 \
  --statistics Average Maximum \
  --output table
```

<br />

Mira tanto el promedio como el maximo. Si tu CPU promedio es 10% y tu maximo es 25%, tenes espacio
significativo para reducir. Si tu promedio es 10% pero tu maximo llega a 95%, puede que necesites
esa capacidad para picos de carga (o puede que necesites investigar que causa esos picos).

<br />

**Paso 2: Usar AWS Compute Optimizer**

<br />

AWS Compute Optimizer analiza tus metricas de CloudWatch y recomienda tipos de instancia que se
ajustarian mejor a tu carga de trabajo. Habilitalo en la consola de AWS bajo Compute Optimizer.
Es gratis para recomendaciones basicas.

<br />

Te va a decir cosas como: "Esta instancia m5.xlarge promedia 8% de utilizacion de CPU. Un t3.medium
ahorraria 75% y aun asi proveeria capacidad suficiente." Estas recomendaciones son un buen punto de
partida, pero siempre validalas contra los requerimientos reales de tu aplicacion. Aplicaciones
intensivas en memoria pueden necesitar mas RAM que CPU, por ejemplo.

<br />

**Paso 3: Hacer right-sizing gradualmente**

<br />

No reduzcas todo de una vez. Elegi tus instancias mas sobredimensionadas, reducilas una a la vez, y
monitorealas por una semana. Si el rendimiento esta bien, pasa a la siguiente. Si ves problemas,
volvela a subir. El right-sizing es iterativo, no un evento unico.

<br />

```bash
# Cambiar tipo de instancia (requiere stop/start)
aws ec2 stop-instances --instance-ids i-0abc123def456789
aws ec2 modify-instance-attribute \
  --instance-id i-0abc123def456789 \
  --instance-type '{"Value":"t3.medium"}'
aws ec2 start-instances --instance-ids i-0abc123def456789
```

<br />

Para nodos worker de EKS gestionados por un node group, actualizarias la launch template o la
configuracion del node group:

<br />

```bash
# Actualizar el node group gestionado de EKS
aws eks update-nodegroup-config \
  --cluster-name my-cluster \
  --nodegroup-name my-nodegroup \
  --scaling-config minSize=2,maxSize=6,desiredSize=3
```

<br />

##### **Instancias Spot y Karpenter**
Las instancias Spot te permiten usar capacidad EC2 no utilizada con hasta 90% de descuento comparado
con precios on-demand. La contrapartida es que AWS puede reclamarlas con un aviso de 2 minutos cuando
necesita la capacidad de vuelta. Esto suena aterrador, pero con la arquitectura correcta, Spot es
una de las estrategias de optimizacion de costos mas efectivas disponibles.

<br />

**Como funciona Spot**

<br />

Cuando AWS tiene capacidad no utilizada en un tipo de instancia y AZ particular, hace esa capacidad
disponible como instancias Spot a un precio reducido. El precio fluctua segun oferta y demanda pero
tipicamente es 60-90% mas barato que on-demand. Cuando AWS necesita esa capacidad de vuelta (una
"interrupcion Spot"), tu instancia recibe un aviso de 2 minutos y despues es terminada.

<br />

**Cuando usar Spot**

<br />

> * **Cargas de trabajo stateless**: Servidores web, servidores de API y workers que no guardan datos localmente son perfectos para Spot. Si una instancia se interrumpe, el load balancer enruta trafico a otras instancias.
> * **Procesamiento por lotes**: Trabajos que pueden hacer checkpoint y reiniciarse funcionan bien con Spot.
> * **Runners de CI/CD**: Los agentes de build son de corta vida por naturaleza y pueden tolerar interrupciones.
> * **Ambientes de desarrollo y staging**: Estos no necesitan las mismas garantias de confiabilidad que produccion.

<br />

**Cuando NO usar Spot**

<br />

> * **Bases de datos**: Perder una instancia de base de datos a mitad de una transaccion es un mal dia.
> * **Cargas de trabajo stateful sin replicacion**: Si perder una instancia significa perder datos, no la pongas en Spot.
> * **Cargas de trabajo de una sola instancia**: Si solo tenes una instancia y se interrumpe, tu servicio esta caido.

<br />

**Mezclando on-demand y Spot**

<br />

La mejor practica es correr una base de instancias on-demand que pueda manejar tu carga minima
esperada, y usar Spot para todo lo que este por encima. Por ejemplo, si tu API necesita al menos
3 instancias para manejar trafico normal pero escala a 10 durante horas pico, corres 3 on-demand
y dejas que las 7 restantes sean Spot.

<br />

**Karpenter para Kubernetes**

<br />

Si estas corriendo EKS, Karpenter es la mejor forma de usar instancias Spot con Kubernetes. Karpenter
es una herramienta open-source de provisionamiento de nodos que automaticamente selecciona los tipos
de instancia y opciones de compra correctos (on-demand vs Spot) basandose en los requerimientos de
tus pods.

<br />

Aca tenes una configuracion basica de NodePool de Karpenter que mezcla on-demand y Spot:

<br />

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - m5.large
            - m5.xlarge
            - m5a.large
            - m5a.xlarge
            - m6i.large
            - m6i.xlarge
        - key: topology.kubernetes.io/zone
          operator: In
          values:
            - us-east-1a
            - us-east-1b
            - us-east-1c
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  limits:
    cpu: "100"
    memory: 400Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
```

<br />

Karpenter automaticamente se diversifica entre multiples tipos de instancia y AZs para reducir la
chance de interrupciones Spot simultaneas. El bloque `disruption` le dice a Karpenter que consolide
nodos subutilizados, lo que ahorra plata empaquetando pods de forma mas eficiente.

<br />

**Manejando interrupciones Spot**

<br />

Para manejar interrupciones Spot de forma graciosa en Kubernetes, asegurate de que tus pods manejen
SIGTERM correctamente y tengan `terminationGracePeriodSeconds` apropiados. Karpenter se integra con
el AWS Node Termination Handler para hacer cordon y drain de nodos antes de que sean reclamados.

<br />

##### **Reserved Instances y Savings Plans**
Si sabes que vas a necesitar cierta cantidad de computo por los proximos 1-3 anos, los Reserved
Instances (RIs) y Savings Plans ofrecen descuentos significativos (hasta 72%) a cambio de un
compromiso.

<br />

**Savings Plans vs Reserved Instances**

<br />

> * **Compute Savings Plans**: Te comprometes a un monto especifico en dolares de computo por hora (ej: $10/hora) por 1 o 3 anos. El descuento aplica en EC2, Fargate y Lambda. Esta es la opcion mas flexible.
> * **EC2 Instance Savings Plans**: Te comprometes a una familia de instancias especifica en una region especifica (ej: m5 en us-east-1). Mayor descuento que los Compute Savings Plans pero menos flexible.
> * **Reserved Instances**: Te comprometes a un tipo de instancia, AZ y tenencia especificos. El mayor descuento pero el menos flexible. Estos son la opcion legacy y generalmente se recomiendan los Savings Plans en su lugar.

<br />

**Cuando los compromisos tienen sentido**

<br />

> * **Cargas de trabajo estables y predecibles**: Si tu base de datos de produccion viene corriendo en un r5.2xlarge hace un ano y va a seguir asi, un Savings Plan es obvio.
> * **Computo base**: Comprometete a tu computo minimo requerido. Usa on-demand y Spot para todo lo que este por encima de la base.
> * **Despues del right-sizing**: Siempre hace right-sizing primero, despues comprometete. No hay nada peor que comprometerse a una instancia sobredimensionada por 3 anos.

<br />

**Cuando evitar compromisos**

<br />

> * **Cargas de trabajo nuevas**: Espera hasta que entiendas los requerimientos reales de recursos (al menos 2-3 meses de datos).
> * **Arquitecturas que cambian rapidamente**: Si estas migrando de EC2 a containers o de x86 a ARM, bloquearte en compromisos puede salir mal.
> * **Montos chicos**: La sobrecarga administrativa de gestionar RIs para ahorrar $50/mes no vale la pena.

<br />

Un enfoque practico es cubrir el 60-70% de tu computo estable con Savings Plans, manejar el siguiente
20% con on-demand, y usar Spot para el 10-20% restante que maneja picos de carga.

<br />

##### **Optimizacion de costos en Kubernetes**
Kubernetes agrega su propia capa de complejidad de costos. Los pods solicitan recursos, los nodos los
proveen, y la brecha entre lo solicitado y lo realmente usado es plata desperdiciada.

<br />

**Requests y limits de recursos**

<br />

Todo pod deberia tener requests y limits de recursos definidos. Los requests le dicen al scheduler
cuanto CPU y memoria necesita un pod. Los limits ponen un tope a cuanto puede usar. La brecha entre
lo que solicitas y lo que realmente usas es desperdicio.

<br />

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: api
          image: my-api:latest
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
```

<br />

El error mas comun es poner requests muy altos "por las dudas." Si tu container de API usa 50m de
CPU en promedio pero solicitas 500m, cada pod desperdicia 450m de CPU. Con 10 replicas, estas
desperdiciando 4.5 vCPUs, que podria ser un nodo entero de computo.

<br />

Para encontrar los valores correctos, revisa el uso real con `kubectl top`:

<br />

```bash
# Revisar uso real de recursos por pod
kubectl top pods -n my-namespace

# Revisar utilizacion de recursos a nivel de nodo
kubectl top nodes

# Asignacion detallada de recursos por nodo
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

<br />

Configura los requests basandote en el uso P95 (lo que el pod realmente usa el 95% del tiempo) y
los limits a aproximadamente 2x el request para manejar rafagas. Revisa y ajusta estos valores
cada mes.

<br />

**Resource quotas por namespace**

<br />

Los resource quotas previenen que un solo equipo o namespace consuma mas de su parte justa de recursos
del cluster. Sin quotas, un deployment descontrolado de un equipo puede dejar sin recursos a todos
los demas y forzar escalado innecesario del cluster.

<br />

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "8"
    requests.memory: "16Gi"
    limits.cpu: "16"
    limits.memory: "32Gi"
    pods: "50"
    persistentvolumeclaims: "10"
```

<br />

**Cluster Autoscaler y Karpenter**

<br />

Tanto el Cluster Autoscaler como Karpenter escalan la cantidad de nodos basandose en pods pendientes,
pero lo abordan de forma diferente:

<br />

> * **Cluster Autoscaler**: Trabaja con AWS Auto Scaling Groups. Vos predefiniras configuraciones de node groups (tipos de instancia, tamanos). El autoscaler agrega o remueve nodos de estos grupos predefinidos. Mas simple de configurar pero menos flexible.
> * **Karpenter**: Evalua los pods pendientes y provisiona el tipo de instancia optimo en el momento. Puede elegir de un amplio rango de tipos de instancia y automaticamente empaquetar pods eficientemente. Mas flexible y generalmente mas cost-effective, pero requiere mas configuracion inicial.

<br />

Cualquiera que uses, asegurate de que el scale-down este habilitado y ajustado. Por defecto, el
Cluster Autoscaler espera 10 minutos antes de remover un nodo subutilizado. En un ambiente con
trafico variable, este delay significa que estas pagando por nodos inactivos 10 minutos despues
de cada pico de trafico.

<br />

**Horizontal Pod Autoscaler (HPA)**

<br />

El HPA escala la cantidad de pods basandose en metricas como CPU o metricas personalizadas. Esto te
permite correr menos pods durante periodos de poco trafico y escalar durante picos, en lugar de
correr capacidad pico 24/7.

<br />

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
```

<br />

##### **Estrategia de tagging: etiqueta todo**
Los tags son la base de la visibilidad de costos. Sin tags, tu factura de AWS es un solo numero
grande. Con tags, podes responder "Cuanto cuesta cada ambiente?", "Que equipo esta gastando mas?",
y "Cual es el costo por cliente?"

<br />

**Tags minimos requeridos**

<br />

Cada recurso en tu cuenta de AWS deberia tener al menos estos tags:

<br />

> * **Environment**: `production`, `staging`, `development`
> * **Team**: El equipo que es dueno del recurso
> * **Service**: El nombre de la aplicacion o servicio
> * **CostCenter**: Para chargeback o showback a unidades de negocio
> * **ManagedBy**: `terraform`, `manual`, `karpenter`, etc.

<br />

**Forzar tags con politicas**

<br />

Los tags solo funcionan si se aplican consistentemente. Usa politicas de tags de AWS Organizations
o validacion de Terraform para forzar el tagging:

<br />

```hcl
# Terraform: forzar tags en todos los recursos
variable "required_tags" {
  type = map(string)
  default = {
    Environment = ""
    Team        = ""
    Service     = ""
    ManagedBy   = "terraform"
  }
}

resource "aws_instance" "api" {
  ami           = "ami-0abc123def456789"
  instance_type = "t3.medium"

  tags = merge(var.required_tags, {
    Name        = "api-server"
    Environment = "production"
    Team        = "backend"
    Service     = "user-api"
  })
}
```

<br />

Para un enfoque mas robusto, usa una politica de tags de AWS Organizations:

<br />

```json
{
  "tags": {
    "Environment": {
      "tag_key": {
        "@@assign": "Environment"
      },
      "tag_value": {
        "@@assign": [
          "production",
          "staging",
          "development"
        ]
      },
      "enforced_for": {
        "@@assign": [
          "ec2:instance",
          "rds:db",
          "s3:bucket",
          "elasticloadbalancing:loadbalancer"
        ]
      }
    }
  }
}
```

<br />

**Activar cost allocation tags**

<br />

Crear tags no alcanza. Tambien necesitas activarlos como cost allocation tags en la consola de
Billing. Solo los tags activados aparecen en Cost Explorer para agrupar y filtrar. Anda a Billing,
despues a Cost Allocation Tags, encontra tus tags, y hace click en Activate. Tarda hasta 24 horas
para que los tags activados aparezcan en Cost Explorer.

<br />

##### **Monitoreo de costos: presupuestos y alertas**
Configurar monitoreo de costos es como configurar monitoreo de aplicaciones. No esperas a que los
usuarios reporten caidas. Configuras alertas. Tampoco deberias esperar a que finanzas reporte
excesos de costos.

<br />

**AWS Budgets**

<br />

Crea presupuestos para tu gasto total de cuenta y para cada servicio o ambiente principal:

<br />

```bash
# Crear un presupuesto mensual con alertas por email
aws budgets create-budget \
  --account-id 123456789012 \
  --budget '{
    "BudgetName": "monthly-total",
    "BudgetLimit": {
      "Amount": "5000",
      "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "team@example.com"
        }
      ]
    },
    {
      "Notification": {
        "NotificationType": "FORECASTED",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "team@example.com"
        }
      ]
    }
  ]'
```

<br />

Esto crea un presupuesto de $5,000/mes con dos alertas: una cuando el gasto real llega al 80% del
presupuesto, y otra cuando el gasto proyectado se proyecta que va a exceder el presupuesto. La
alerta de proyeccion es especialmente util porque te da tiempo para actuar antes de que realmente
te pases.

<br />

**Revisiones semanales de costos**

<br />

Arma un ritual semanal donde alguien del equipo revise los costos. No necesita ser una reunion
larga. Un chequeo de 15 minutos de Cost Explorer una vez por semana alcanza. Busca:

<br />

> * **Picos inesperados**: Cualquier cosa que haya saltado significativamente respecto a la semana anterior
> * **Servicios nuevos**: Cualquier servicio que aparecio en tu factura que no estaba antes
> * **Lineas de tendencia**: El gasto general esta subiendo? Si es asi, es proporcional al crecimiento?
> * **Recursos inactivos**: Cualquier recurso con cero o casi cero utilizacion

<br />

La persona que hace la revision deberia rotar en el equipo. Esto construye conciencia de costos en
todo el equipo, no solo en un vigilante de costos designado.

<br />

##### **Estrategias para ambientes dev/staging**
Los ambientes de desarrollo y staging son frecuentemente el lugar mas facil para recortar costos
porque no necesitan estar disponibles 24/7 y no necesitan recursos de grado produccion.

<br />

**Apagar de noche y los fines de semana**

<br />

Si tu equipo trabaja de 9am a 6pm los dias habiles, tus ambientes de dev y staging estan inactivos
el 73% del tiempo. Usa escalado programado para apagarlos fuera del horario laboral:

<br />

```bash
# Reducir el node group de EKS de noche (ejecutar via cron o Lambda)
aws eks update-nodegroup-config \
  --cluster-name dev-cluster \
  --nodegroup-name dev-nodes \
  --scaling-config minSize=0,maxSize=3,desiredSize=0

# Levantar a la manana
aws eks update-nodegroup-config \
  --cluster-name dev-cluster \
  --nodegroup-name dev-nodes \
  --scaling-config minSize=1,maxSize=3,desiredSize=2
```

<br />

Podes automatizar esto con una funcion Lambda disparada por EventBridge en un horario:

<br />

```json
{
  "schedule_expression": "cron(0 22 ? * MON-FRI *)",
  "description": "Reducir cluster dev a las 10 PM",
  "action": "scale-down"
}
```

<br />

**Usar instancias mas chicas para no-produccion**

<br />

Si produccion corre en m5.xlarge, staging probablemente puede correr en t3.medium. Dev puede correr
en t3.small. El objetivo no es ambientes identicos. Es ambientes que sean lo suficientemente
similares para detectar bugs pero lo suficientemente chicos para ser accesibles.

<br />

**Ambientes efimeros**

<br />

En lugar de correr un ambiente de staging persistente, considera levantar ambientes de corta vida
para cada pull request. El ambiente se crea cuando se abre el PR, corre tests de integracion, y se
destruye cuando el PR se mergea o se cierra. Solo pagas por el tiempo en que alguien esta activamente
testeando. Herramientas como Argo CD ApplicationSets o Terraform workspaces pueden automatizar este
patron.

<br />

**Clusters dev de un solo nodo**

<br />

Para desarrollo, considera correr un cluster Kubernetes de un solo nodo o usar una herramienta local
como kind o minikube. Esto evita el costo del control plane de EKS ($73/mes) y los costos de computo
multi-nodo completamente para desarrollo local.

<br />

##### **Juntando todo: checklist de optimizacion de costos**
Aca tenes un checklist practico que podes seguir para optimizar tus costos cloud:

<br />

> * **Semana 1**: Habilitar Cost Explorer, activar cost allocation tags, crear un presupuesto basico con alertas
> * **Semana 2**: Auditar recursos olvidados (volumenes sin adjuntar, load balancers inactivos, Elastic IPs sin usar). Borrar todo lo que no se necesite
> * **Semana 3**: Analizar utilizacion de computo con CloudWatch y Compute Optimizer. Identificar candidatos para right-sizing
> * **Semana 4**: Hacer right-sizing de tus instancias mas sobredimensionadas. Empezar con no-produccion
> * **Mes 2**: Implementar politicas de tagging, configurar escalado programado para dev/staging, evaluar Spot para cargas de trabajo stateless
> * **Mes 3**: Revisar requests/limits de recursos de Kubernetes, implementar HPA, considerar Karpenter. Evaluar Savings Plans para cargas de trabajo de produccion estables
> * **Continuo**: Revisiones semanales de costos, pasadas de optimizacion mensuales, evaluacion trimestral de Savings Plans

<br />

##### **Repaso completo de la serie**
Cubrimos un monton de terreno en esta serie. Tomemos un momento para mirar atras cada articulo y lo
que aprendimos en cada uno. Si te perdiste alguno o queres revisitar un tema, los links de abajo te
van a llevar.

<br />

> * **Articulo 1: [Que Significa Realmente](/blog/devops-from-zero-to-hero-what-it-actually-means)** - Empezamos desde el principio. Que es DevOps, de donde viene, las metricas DORA que lo miden, y como se relaciona DevOps con SRE y Platform Engineering.
> * **Articulo 2: [Tu Primera API en TypeScript](/blog/devops-from-zero-to-hero-your-first-typescript-api)** - Construimos una aplicacion real con Express y Docker. Esto nos dio algo concreto para deployear a lo largo del resto de la serie.
> * **Articulo 3: [Control de Versiones para Equipos](/blog/devops-from-zero-to-hero-version-control-for-teams)** - Aprendimos workflows de Git, estrategias de branching, pull requests y code review. La base de colaboracion para todo lo que siguio.
> * **Articulo 4: [Testing Automatizado](/blog/devops-from-zero-to-hero-automated-testing)** - Escribimos tests unitarios, tests de integracion y aprendimos la piramide de testing. Ningun pipeline de CI funciona sin buenos tests.
> * **Articulo 5: [Tu Primer Pipeline de CI](/blog/devops-from-zero-to-hero-your-first-ci-pipeline)** - Configuramos GitHub Actions para automaticamente hacer lint, testear y buildear nuestro codigo en cada push. Nuestra primera probada de automatizacion.
> * **Articulo 6: [AWS desde Cero](/blog/devops-from-zero-to-hero-aws-from-scratch)** - Creamos una cuenta de AWS, configuramos usuarios y roles de IAM, entendimos regiones y AZs, y nos sentimos comodos con la CLI de AWS.
> * **Articulo 7: [Infraestructura como Codigo con Terraform](/blog/devops-from-zero-to-hero-infrastructure-as-code)** - Dejamos de clickear en la consola y empezamos a definir infraestructura como codigo. VPCs, subnets, security groups, todo en Terraform.
> * **Articulo 8: [Deployeando a ECS con Fargate](/blog/devops-from-zero-to-hero-deploying-to-ecs)** - Deployeamos nuestra API en AWS por primera vez usando ECS y Fargate. Infraestructura cloud real corriendo nuestra aplicacion real.
> * **Articulo 9: [Gestion de Secrets y Configuracion](/blog/devops-from-zero-to-hero-secrets-and-config)** - Aprendimos como gestionar secretos de forma segura con AWS Secrets Manager y SSM Parameter Store. No mas passwords hardcodeados.
> * **Articulo 10: [DNS, TLS y Networking](/blog/devops-from-zero-to-hero-dns-tls-and-networking)** - Hicimos nuestra app accesible con un dominio real, configuramos certificados TLS con ACM, y entendimos como el networking conecta todo.
> * **Articulo 11: [Fundamentos de Kubernetes](/blog/devops-from-zero-to-hero-kubernetes-fundamentals)** - Aprendimos pods, deployments, services y namespaces. Los bloques fundamentales de la orquestacion de containers.
> * **Articulo 12: [Helm Charts](/blog/devops-from-zero-to-hero-helm-charts)** - Empaquetamos nuestra aplicacion Kubernetes con Helm, haciendola reutilizable y configurable entre ambientes.
> * **Articulo 13: [EKS, Corriendo Kubernetes en AWS](/blog/devops-from-zero-to-hero-eks)** - Configuramos un cluster EKS de grado produccion con Terraform, incluyendo managed node groups, integracion IAM y networking.
> * **Articulo 14: [GitOps con ArgoCD](/blog/devops-from-zero-to-hero-gitops-with-argocd)** - Implementamos GitOps para que git se convirtiera en la unica fuente de verdad para nuestros deploys. Push a git y ArgoCD se encarga del resto.
> * **Articulo 15: [Observabilidad en Kubernetes](/blog/devops-from-zero-to-hero-observability)** - Configuramos Prometheus, Grafana y logging estructurado. Aprendimos sobre los tres pilares: logs, metricas y trazas.
> * **Articulo 16: [CI/CD, El Pipeline Completo](/blog/devops-from-zero-to-hero-the-complete-pipeline)** - Unimos todo en un pipeline completo desde pull request hasta produccion, con gates de staging y aprobaciones manuales.
> * **Articulo 17: Seguridad y Compliance** - Cubrimos escaneo de imagenes de containers, politicas RBAC, network policies, y como integrar seguridad en cada etapa del pipeline.
> * **Articulo 18: Disaster Recovery y Alta Disponibilidad** - Aprendimos deploys multi-AZ, estrategias de backup, objetivos de RTO/RPO, y como planificar para lo peor para que tus sistemas sigan funcionando.
> * **Articulo 19: Estrategias de Deploy Avanzadas** - Exploramos deploys canary, deploys blue/green, feature flags, y patrones de entrega progresiva para releases sin downtime.
> * **Articulo 20: Optimizacion de Costos y Lo Que Viene Despues (este articulo)** - Aprendimos como entender, monitorear y optimizar costos cloud, y cerramos la serie completa.

<br />

Son veinte articulos, y si seguiste el recorrido, pasaste de no saber nada de DevOps a tener un
pipeline completo de grado produccion con testing automatizado, infraestructura como codigo,
Kubernetes, GitOps, observabilidad, seguridad y optimizacion de costos. Eso es un logro serio.

<br />

##### **Que viene despues**
Terminar esta serie no significa que dejaste de aprender. En muchos sentidos, recien estas empezando.
Ahora tenes una base solida, y hay varios caminos hacia adelante dependiendo de tus intereses y
objetivos de carrera.

<br />

**Site Reliability Engineering (SRE)**

<br />

Si disfrutaste los aspectos de observabilidad, monitoreo y confiabilidad de esta serie, SRE es un
paso natural. SRE toma los principios DevOps que cubrimos y agrega practicas de ingenieria rigurosas
alrededor de la confiabilidad: SLIs, SLOs, error budgets, gestion de incidentes, chaos engineering
y capacity planning.

<br />

Tenemos una serie completa de SRE en este blog que continua donde esta termina. Empeza con
[SRE: SLIs, SLOs, and Automations That Actually Help](/blog/sre-slis-slos-and-automations-that-actually-help)
y trabaja los catorce articulos.

<br />

**Platform Engineering**

<br />

Si te encontraste pensando "ojala los desarrolladores no tuvieran que saber todo esto solo para
deployear sus apps," Platform Engineering es para vos. Los equipos de plataforma construyen
plataformas internas para desarrolladores que abstraen la complejidad de la infraestructura.
Construirias golden paths, portales de autoservicio y herramientas para desarrolladores que hacen
facil para cualquier developer deployear, observar y gestionar sus aplicaciones sin necesidad de
entender cada componente subyacente.

<br />

**Developer Experience (DX)**

<br />

Relacionado con Platform Engineering, Developer Experience se enfoca en hacer que los desarrolladores
sean productivos y esten contentos. Pipelines de CI rapidos, setups locales de desarrollo excelentes,
documentacion clara, onboarding facil. Si te importa como la gente experimenta las herramientas y
procesos que construis, DX vale la pena explorar.

<br />

**Certificaciones**

<br />

Si queres formalizar tu conocimiento y senalar tus habilidades a empleadores, considera estas
certificaciones:

<br />

> * **AWS Solutions Architect Associate (SAA-C03)**: Cubre los servicios core de AWS que usamos a lo largo de la serie. Si seguiste el recorrido y construiste todo, ya sabes como el 70% de lo que esta en este examen.
> * **Certified Kubernetes Administrator (CKA)**: Valida tus habilidades de Kubernetes. Los articulos sobre fundamentos de Kubernetes, Helm y EKS te dieron una ventaja fuerte.
> * **HashiCorp Terraform Associate**: Cubre los conceptos de Terraform que usamos para infraestructura como codigo. Probablemente la mas facil de las tres si veniste escribiendo Terraform a lo largo de la serie.

<br />

Ninguna de estas certificaciones es obligatoria. La experiencia practica importa mas que los
certificados. Pero pueden ser utiles para conseguir entrevistas, especialmente al principio de tu
carrera.

<br />

**Comunidades y recursos**

<br />

Aprender no pasa en aislamiento. Aca hay algunas comunidades y recursos que vale la pena revisar:

<br />

> * **CNCF (Cloud Native Computing Foundation)**: La organizacion detras de Kubernetes, Prometheus, ArgoCD y muchas otras herramientas que usamos. Su pagina de landscape te da un mapa de todo el ecosistema cloud native.
> * **Subreddits y foros de DevOps**: r/devops, r/kubernetes y r/aws son comunidades activas donde la gente comparte experiencias y se ayuda mutuamente.
> * **Charlas de KubeCon**: Las charlas grabadas de KubeCon estan disponibles gratis en YouTube y cubren desde temas para principiantes hasta avanzados.
> * **El libro de SRE**: El libro "Site Reliability Engineering" de Google esta disponible gratis online en sre.google. Es el texto fundacional para practicas SRE.
> * **"Accelerate" de Forsgren, Humble y Kim**: El libro detras de las metricas DORA. Si queres entender la investigacion que prueba que las practicas DevOps funcionan, este es el indicado.

<br />

##### **Notas finales**
Este es el final de la serie DevOps desde Cero, y si llegaste hasta aca, quiero decirte algo con
sinceridad: muy bien hecho. Veinte articulos es mucho. Construir todo esto desde cero requiere
compromiso real, y el hecho de que te hayas mantenido dice mucho de vos.

<br />

Cuando empezamos esta serie, hablamos de lo que DevOps realmente significa. No el buzzword, no el
titulo de puesto, sino la idea real: que las personas que construyen software y las personas que lo
corren deberian trabajar juntos, compartir responsabilidad, y usar automatizacion para moverse mas
rapido sin sacrificar estabilidad. Cada articulo desde entonces fue una expresion practica de esa
idea. Tests automatizados, pipelines de CI, infraestructura como codigo, Kubernetes, GitOps,
observabilidad, seguridad, y ahora optimizacion de costos. Cada pieza refuerza a las otras. Juntas,
forman una practica completa.

<br />

Pero lo mas importante que construiste no es un pipeline o un cluster. Es una forma de pensar.
Ahora encaras los problemas de forma diferente. Cuando ves un proceso manual, pensas en automatizarlo.
Cuando ves un deploy que requiere SSH y oraciones, pensas en CI/CD. Cuando alguien dice "funciona en
mi maquina," pensas en containers. Esa mentalidad es mas valiosa que cualquier herramienta especifica,
y te va a servir bien sin importar a donde te lleve tu carrera.

<br />

El ecosistema cloud va a seguir evolucionando. Nuevas herramientas van a aparecer, algo de lo que
cubrimos se va a volver obsoleto, y las mejores practicas van a cambiar. Esta bien. Los fundamentos
que cubrimos (control de versiones, testing, automatizacion, infraestructura como codigo,
observabilidad, seguridad, conciencia de costos) son atemporales. Las herramientas especificas
cambian, pero los principios no.

<br />

Asi que anda y construi algo. Toma lo que aprendiste aca y aplicalo en el trabajo, en un proyecto
personal, o en una contribucion open source. La mejor forma de solidificar el conocimiento es usarlo.
Y cuando te trabes, recorda que todo experto que admiras estuvo alguna vez exactamente donde vos
estas ahora.

<br />

Gracias por leer esta serie. Genuinamente espero que te haya ayudado, y espero que la hayas
disfrutado tanto siguiendola como yo escribiendola. Hasta la proxima serie!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en las [fuentes aca](https://github.com/kainlite/tr)

<br />
