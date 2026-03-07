%{
  title: "SRE: Cost Optimization in the Cloud",
  author: "Gabriel Garrido",
  description: "We will explore FinOps principles and cost optimization strategies for Kubernetes and cloud infrastructure, from right-sizing workloads and spot instances to Kubecost visibility and cost-aware SLOs...",
  tags: ~w(sre kubernetes cloud cost-optimization finops),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Throughout this SRE series we have covered [SLIs and SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[incident management](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observability](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[capacity planning](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd), and
[secrets management](/blog/sre-secrets-management-in-kubernetes). We have built a solid foundation for running
reliable systems, but reliability is only half the picture. If your infrastructure bill keeps growing unchecked,
it does not matter how reliable things are because eventually someone is going to ask hard questions about cost.

<br />

Cloud spending has a tendency to creep up. You spin up a test cluster and forget about it, someone requests a
large instance "just in case," dev environments run 24/7, and before you know it your monthly bill has doubled.
The FinOps movement emerged to bring financial accountability to cloud spending, and SRE teams are in a unique
position to drive cost optimization because they already understand the infrastructure deeply.

<br />

In this article we will cover FinOps principles, right-sizing workloads, spot instances, resource quotas, cost
visibility with Kubecost and OpenCost, idle resource detection, storage tiering, reserved capacity planning,
cost alerts tied to SLOs, and tagging strategies for cost allocation. These are all practical techniques you
can start applying today.

<br />

Let's get into it.

<br />

##### **FinOps principles**
FinOps (Financial Operations) is a cultural practice that brings together engineering, finance, and business
teams to manage cloud costs collaboratively. It is not about cutting costs at all costs. It is about making
informed decisions and getting the most value from every dollar spent.

<br />

The FinOps lifecycle has three phases:

<br />

> 1. **Inform**: Understand what you are spending, where, and why. You cannot optimize what you cannot see.
> 2. **Optimize**: Take action to reduce waste. Right-size instances, use spot nodes, clean up idle resources.
> 3. **Operate**: Continuously monitor costs, set budgets, and build cost awareness into your engineering culture.

<br />

For SRE teams, the key insight is that cost should be treated as a first-class metric, just like latency,
availability, and error rate. You already have dashboards for SLIs. Add a cost panel to those dashboards.
When you review your SLO performance weekly, review your cost metrics too.

<br />

Some practical principles to adopt:

<br />

> * **Everyone is accountable for cost**, not just finance. Engineers who provision resources should understand the cost impact.
> * **Cost decisions are data-driven**. Use actual utilization data, not guesses or "we might need it someday."
> * **Cost optimization is continuous**, not a one-time project. Treat it like reliability, always improving.
> * **Optimize for value, not just savings**. Sometimes spending more is the right call if it improves reliability or developer productivity.

<br />

##### **Right-sizing workloads**
Right-sizing is the single most impactful cost optimization you can make in Kubernetes. Most teams over-provision
their workloads significantly because developers request resources based on worst-case estimates rather than
actual usage.

<br />

The Vertical Pod Autoscaler (VPA) is your best friend here. Even if you do not enable it in auto mode, running
it in recommendation mode gives you data on what your pods actually use versus what they request.

<br />

Install the VPA:

<br />

```bash
# Install VPA components
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler
./hack/vpa-up.sh
```

<br />

Create a VPA in recommendation mode for your workloads:

<br />

```yaml
# vpa/tr-web-vpa.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: tr-web-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tr-web
  updatePolicy:
    updateMode: "Off"  # Recommendation only, no auto-updates
  resourcePolicy:
    containerPolicies:
      - containerName: tr-web
        minAllowed:
          cpu: 50m
          memory: 64Mi
        maxAllowed:
          cpu: 2000m
          memory: 2Gi
        controlledResources:
          - cpu
          - memory
```

<br />

After a few days of running, check the recommendations:

<br />

```bash
kubectl describe vpa tr-web-vpa

# Output will look something like:
# Recommendation:
#   Container Recommendations:
#     Container Name: tr-web
#     Lower Bound:
#       Cpu:     25m
#       Memory:  80Mi
#     Target:
#       Cpu:     100m
#       Memory:  180Mi
#     Uncapped Target:
#       Cpu:     100m
#       Memory:  180Mi
#     Upper Bound:
#       Cpu:     350m
#       Memory:  400Mi
```

<br />

Now compare that to what you actually requested:

<br />

```hcl
# Check current resource requests across all pods
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{"\t"}Req: {.resources.requests.cpu}/{.resources.requests.memory}{"\t"}Lim: {.resources.limits.cpu}/{.resources.limits.memory}{"\n"}{end}{end}' | column -t
```

<br />

If your pods are requesting 500m CPU but only using 100m on average, you are paying for 5x more compute than
you need. That gap is pure waste.

<br />

A good rule of thumb for setting requests and limits:

<br />

> * **Requests**: Set to the P95 of actual usage (from VPA recommendations or Prometheus metrics). This ensures the scheduler places pods on nodes with enough capacity.
> * **Limits**: Set to 2-3x the request for CPU (to allow bursting), and 1.5-2x for memory (to avoid OOM kills while still preventing runaway consumption).
> * **Review quarterly**: Usage patterns change as your application evolves. What was right-sized six months ago might be wrong today.

<br />

Here is a Prometheus query to find the most over-provisioned workloads:

<br />

```bash
# CPU over-provisioning ratio by deployment
# Values > 2 mean the workload is requesting 2x+ more CPU than it uses
sum by (namespace, owner_name) (
  kube_pod_container_resource_requests{resource="cpu"}
) /
sum by (namespace, owner_name) (
  rate(container_cpu_usage_seconds_total[24h])
)
```

<br />

##### **Spot and preemptible instances**
Spot instances (AWS), preemptible VMs (GCP), or spot VMs (Azure) offer 60-90% discounts compared to on-demand
pricing. The tradeoff is that the cloud provider can reclaim them with short notice (usually 2 minutes). For
stateless, fault-tolerant workloads in Kubernetes, this is a great deal.

<br />

The trick is to run your workloads on a mix of on-demand and spot nodes. Critical workloads like your database
go on on-demand nodes. Stateless web servers and batch jobs go on spot nodes.

<br />

Set up a spot node group (EKS example):

<br />

```yaml
# eks-nodegroup-spot.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: production-cluster
  region: us-east-1
spec:
  managedNodeGroups:
    - name: on-demand-critical
      instanceType: t3.large
      desiredCapacity: 2
      minSize: 2
      maxSize: 4
      labels:
        node-type: on-demand
        workload-type: critical
      taints:
        - key: workload-type
          value: critical
          effect: NoSchedule

    - name: spot-general
      instanceTypes:
        - t3.large
        - t3.xlarge
        - t3a.large
        - t3a.xlarge
        - m5.large
        - m5a.large
      spot: true
      desiredCapacity: 3
      minSize: 1
      maxSize: 10
      labels:
        node-type: spot
        workload-type: general
```

<br />

Notice the spot node group uses multiple instance types. This is important because spot availability varies by
instance type. Using a diverse set increases your chances of getting capacity.

<br />

Now schedule your workloads appropriately using node affinity and tolerations:

<br />

```yaml
# deployments/tr-web.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tr-web
  namespace: default
spec:
  replicas: 3
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 80
              preference:
                matchExpressions:
                  - key: node-type
                    operator: In
                    values:
                      - spot
          # Spread across nodes for resilience
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
              - weight: 100
                podAffinityTerm:
                  labelSelector:
                    matchExpressions:
                      - key: app
                        operator: In
                        values:
                          - tr-web
                  topologyKey: kubernetes.io/hostname
      tolerations:
        - key: "node-type"
          operator: "Equal"
          value: "spot"
          effect: "NoSchedule"
      containers:
        - name: tr-web
          image: kainlite/tr:latest
          resources:
            requests:
              cpu: 100m
              memory: 180Mi
            limits:
              cpu: 300m
              memory: 360Mi
```

<br />

The `preferredDuringSchedulingIgnoredDuringExecution` with weight 80 means the scheduler will try to place pods
on spot nodes but will fall back to on-demand if no spot capacity is available. This is important for resilience.

<br />

You also need a PodDisruptionBudget to handle spot node reclamation gracefully:

<br />

```yaml
# pdb/tr-web-pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: tr-web-pdb
  namespace: default
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: tr-web
```

<br />

This ensures that at least 2 pods are always running, even during spot node reclamation. Combined with multiple
replicas spread across different nodes, your service stays available while saving 60-90% on compute.

<br />

##### **Resource quotas and limit ranges**
Without guardrails, any team member can deploy a workload that requests 64 CPUs and 256GB of memory. Resource
quotas and limit ranges prevent this kind of runaway cost.

<br />

A ResourceQuota sets hard limits per namespace:

<br />

```yaml
# quotas/dev-namespace-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: dev
spec:
  hard:
    requests.cpu: "4"           # Total CPU requests across all pods
    requests.memory: 8Gi        # Total memory requests
    limits.cpu: "8"             # Total CPU limits
    limits.memory: 16Gi         # Total memory limits
    pods: "20"                  # Maximum number of pods
    services.loadbalancers: "2" # Limit expensive LB services
    persistentvolumeclaims: "10"
    requests.storage: 100Gi     # Total PVC storage
```

<br />

A LimitRange sets defaults and per-pod constraints. This is especially useful for catching pods deployed
without resource requests:

<br />

```yaml
# quotas/dev-namespace-limitrange.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: dev
spec:
  limits:
    - type: Container
      default:          # Default limits if not specified
        cpu: 200m
        memory: 256Mi
      defaultRequest:   # Default requests if not specified
        cpu: 50m
        memory: 64Mi
      min:              # Minimum allowed
        cpu: 10m
        memory: 16Mi
      max:              # Maximum allowed per container
        cpu: "2"
        memory: 4Gi
    - type: Pod
      max:              # Maximum per pod (all containers combined)
        cpu: "4"
        memory: 8Gi
    - type: PersistentVolumeClaim
      min:
        storage: 1Gi
      max:
        storage: 50Gi
```

<br />

Now if someone deploys a pod without resource requests, it automatically gets 50m CPU and 64Mi memory as
defaults. And if someone tries to request 32 CPUs, the API server rejects the request.

<br />

For production namespaces, you want different quotas:

<br />

```yaml
# quotas/production-namespace-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: production
spec:
  hard:
    requests.cpu: "16"
    requests.memory: 32Gi
    limits.cpu: "32"
    limits.memory: 64Gi
    pods: "50"
    services.loadbalancers: "5"
    persistentvolumeclaims: "20"
    requests.storage: 500Gi
  scopeSelector:
    matchExpressions:
      - scopeName: PriorityClass
        operator: In
        values:
          - high
          - medium
```

<br />

##### **Kubecost and OpenCost**
You cannot optimize what you cannot measure. Kubecost (and its open source core, OpenCost) gives you cost
visibility into your Kubernetes cluster, broken down by namespace, deployment, label, and team.

<br />

Install OpenCost with Helm:

<br />

```sql
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update

helm install opencost opencost/opencost \
  --namespace opencost \
  --create-namespace \
  --set opencost.exporter.defaultClusterId="production" \
  --set opencost.ui.enabled=true \
  --set opencost.prometheus.internal.enabled=false \
  --set opencost.prometheus.external.url="http://prometheus-server.monitoring.svc:9090"
```

<br />

For Kubecost (which includes more features like recommendations and savings insights):

<br />

```sql
helm repo add kubecost https://kubecost.github.io/cost-analyzer
helm repo update

helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set kubecostToken="your-token-here" \
  --set prometheus.server.global.external_labels.cluster_id="production" \
  --set prometheus.nodeExporter.enabled=false \
  --set prometheus.serviceAccounts.nodeExporter.create=false
```

<br />

Once installed, you can query cost data via the API:

<br />

```yaml
# Get cost allocation by namespace for the last 7 days
curl -s "http://kubecost.kubecost.svc:9090/model/allocation?window=7d&aggregate=namespace" \
  | jq '.data[0] | to_entries[] | {
    namespace: .key,
    totalCost: .value.totalCost,
    cpuCost: .value.cpuCost,
    memCost: .value.ramCost,
    pvCost: .value.pvCost,
    cpuEfficiency: .value.cpuEfficiency,
    ramEfficiency: .value.ramEfficiency
  }'

# Example output:
# {
#   "namespace": "default",
#   "totalCost": 42.15,
#   "cpuCost": 18.30,
#   "memCost": 15.85,
#   "pvCost": 8.00,
#   "cpuEfficiency": 0.35,
#   "ramEfficiency": 0.42
# }
```

<br />

That CPU efficiency of 0.35 means you are only using 35% of the CPU you are paying for. That is a big
optimization opportunity.

<br />

Create a Grafana dashboard for cost visibility:

<br />

```bash
# grafana/cost-dashboard.json (simplified)
# Useful Prometheus queries for cost panels:

# Monthly cost estimate by namespace
sum by (namespace) (
  container_cpu_allocation * on(node) group_left()
  node_cpu_hourly_cost * 730
) +
sum by (namespace) (
  container_memory_allocation_bytes / 1024 / 1024 / 1024 * on(node) group_left()
  node_ram_hourly_cost * 730
)

# Idle cost (resources requested but not used)
sum by (namespace) (
  (kube_pod_container_resource_requests{resource="cpu"} -
   rate(container_cpu_usage_seconds_total[1h]))
  * on(node) group_left() node_cpu_hourly_cost * 730
)

# Cost per request (useful for cost-per-SLI tracking)
sum(rate(container_cpu_usage_seconds_total{namespace="default"}[1h])
  * on(node) group_left() node_cpu_hourly_cost)
/
sum(rate(http_requests_total{namespace="default"}[1h]))
```

<br />

##### **Idle resource detection**
Idle resources are the low-hanging fruit of cost optimization. These are things you are paying for but nobody
is using. In a typical Kubernetes cluster, 20-30% of spend goes to idle resources.

<br />

Here is a script to find common idle resources:

<br />

```bash
#!/bin/bash
# idle-resource-audit.sh
# Find idle and wasted resources in your cluster

echo "=== Unused PersistentVolumeClaims ==="
# PVCs not mounted by any pod
kubectl get pvc -A -o json | jq -r '
  .items[] |
  select(.status.phase == "Bound") |
  .metadata.namespace + "/" + .metadata.name
' | while read pvc; do
  ns=$(echo $pvc | cut -d/ -f1)
  name=$(echo $pvc | cut -d/ -f2)
  # Check if any pod references this PVC
  used=$(kubectl get pods -n $ns -o json | jq -r \
    --arg pvc "$name" \
    '.items[].spec.volumes[]? | select(.persistentVolumeClaim.claimName == $pvc) | .name' \
    2>/dev/null)
  if [ -z "$used" ]; then
    size=$(kubectl get pvc $name -n $ns -o jsonpath='{.spec.resources.requests.storage}')
    echo "  UNUSED: $pvc ($size)"
  fi
done

echo ""
echo "=== LoadBalancer Services ==="
# Each LB costs money even if no traffic flows through it
kubectl get svc -A --field-selector spec.type=LoadBalancer \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,IP:.status.loadBalancer.ingress[0].ip,AGE:.metadata.creationTimestamp'

echo ""
echo "=== Deployments with 0 replicas ==="
# Scaled to 0 but still have PVCs, configmaps, secrets attached
kubectl get deploy -A -o json | jq -r '
  .items[] |
  select(.spec.replicas == 0) |
  .metadata.namespace + "/" + .metadata.name
'

echo ""
echo "=== Pods in CrashLoopBackOff ==="
# Burning CPU on restart loops
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount'

echo ""
echo "=== Unattached Persistent Volumes ==="
kubectl get pv -o json | jq -r '
  .items[] |
  select(.status.phase == "Available" or .status.phase == "Released") |
  .metadata.name + " (" + .spec.capacity.storage + ") - " + .status.phase
'
```

<br />

For a more automated approach, set up a CronJob that runs this audit weekly and sends results to Slack:

<br />

```yaml
# cronjob/idle-resource-audit.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: idle-resource-audit
  namespace: monitoring
spec:
  schedule: "0 9 * * 1"  # Every Monday at 9am
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: resource-auditor
          containers:
            - name: auditor
              image: bitnami/kubectl:latest
              command:
                - /bin/bash
                - -c
                - |
                  # Run audit and post to Slack
                  UNUSED_PVCS=$(kubectl get pvc -A -o json | jq '[.items[] | select(.status.phase == "Bound")] | length')
                  TOTAL_PVCS=$(kubectl get pvc -A -o json | jq '.items | length')
                  LB_COUNT=$(kubectl get svc -A --field-selector spec.type=LoadBalancer -o json | jq '.items | length')
                  ZERO_REPLICAS=$(kubectl get deploy -A -o json | jq '[.items[] | select(.spec.replicas == 0)] | length')

                  curl -X POST "$SLACK_WEBHOOK_URL" \
                    -H 'Content-type: application/json' \
                    -d "{
                      \"text\": \"Weekly Idle Resource Report\",
                      \"blocks\": [{
                        \"type\": \"section\",
                        \"text\": {
                          \"type\": \"mrkdwn\",
                          \"text\": \"*Weekly Idle Resource Audit*\n- PVCs: $TOTAL_PVCS total\n- LoadBalancers: $LB_COUNT active\n- Zero-replica deployments: $ZERO_REPLICAS\"
                        }
                      }]
                    }"
              env:
                - name: SLACK_WEBHOOK_URL
                  valueFrom:
                    secretKeyRef:
                      name: slack-webhook
                      key: url
          restartPolicy: OnFailure
```

<br />

##### **Storage tiering**
Storage costs can sneak up on you, especially if everything defaults to high-performance SSD. Not all data
needs fast storage. Logs, backups, and archived data can live on cheaper storage tiers.

<br />

Define multiple StorageClasses for different tiers:

<br />

```yaml
# storage/storageclass-fast.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
  labels:
    cost-tier: high
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "5000"
  throughput: "250"
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
# storage/storageclass-standard.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
  labels:
    cost-tier: medium
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
# storage/storageclass-cold.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cold-storage
  labels:
    cost-tier: low
provisioner: ebs.csi.aws.com
parameters:
  type: sc1
  encrypted: "true"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

<br />

Use the right tier for each workload:

<br />

```hcl
# Database: fast SSD for low latency
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-data
  namespace: default
spec:
  storageClassName: fast-ssd
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
# Application logs: standard storage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-logs
  namespace: default
spec:
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
---
# Backups and archives: cold storage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-archive
  namespace: default
spec:
  storageClassName: cold-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi
```

<br />

For object storage (S3, GCS), set up lifecycle policies to move data to cheaper tiers automatically:

<br />

```hcl
# terraform/s3-lifecycle.tf
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"  # ~45% cheaper
    }

    transition {
      days          = 90
      storage_class = "GLACIER"       # ~80% cheaper
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"  # ~95% cheaper
    }

    expiration {
      days = 730  # Delete after 2 years
    }
  }
}
```

<br />

The cost difference between tiers is significant. For AWS EBS, gp3 costs about $0.08/GB/month while sc1 costs
$0.015/GB/month. For S3, Standard is $0.023/GB/month while Deep Archive is $0.00099/GB/month. Moving 1TB of
archive data from Standard to Deep Archive saves about $264/year.

<br />

##### **Reserved vs on-demand**
If you know you will need a certain amount of compute for the next 1-3 years, reserved instances or savings
plans offer 30-60% discounts compared to on-demand. The tradeoff is commitment, you pay whether you use it
or not.

<br />

The key is to only commit to your baseline, the minimum compute you always need. Let on-demand and spot handle
the peaks.

<br />

Here is how to analyze your reservation coverage:

<br />

```bash
# Prometheus query: average CPU utilization over 30 days
# This shows your baseline compute needs
avg_over_time(
  sum(
    rate(container_cpu_usage_seconds_total[5m])
  )[30d:1h]
)

# Compare against your reserved capacity
# If reserved < baseline, you are under-committed (paying too much on-demand)
# If reserved > baseline, you are over-committed (paying for unused reservations)
```

<br />

A practical approach to reservation planning:

<br />

> 1. **Measure your baseline** for at least 3 months. Look at the minimum sustained usage, not the average.
> 2. **Reserve 70-80% of baseline**. This gives you a safety margin for workload changes.
> 3. **Use savings plans over reserved instances** when possible. Savings plans are more flexible because they apply to any instance family.
> 4. **Review quarterly**. If your baseline has shifted, adjust your commitments at renewal time.
> 5. **Consider 1-year terms first**. The savings gap between 1-year and 3-year is often not worth the risk of being locked in.

<br />

For Kubernetes specifically, you can use Karpenter (AWS) or the cluster autoscaler with mixed instance policies
to automatically choose the cheapest available instance types:

<br />

```yaml
# karpenter/provisioner.yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values:
        - on-demand
        - spot
    - key: node.kubernetes.io/instance-type
      operator: In
      values:
        - t3.medium
        - t3.large
        - t3a.medium
        - t3a.large
        - m5.large
        - m5a.large
        - m6i.large
        - m6a.large
    - key: kubernetes.io/arch
      operator: In
      values:
        - amd64
        - arm64   # ARM instances are ~20% cheaper
  limits:
    resources:
      cpu: "64"
      memory: 128Gi
  providerRef:
    name: default
  # Consolidation: Karpenter will replace underutilized nodes
  # with smaller ones to save money
  consolidation:
    enabled: true
  ttlSecondsAfterEmpty: 30
```

<br />

Notice the `arm64` architecture option. ARM instances (like AWS Graviton) are typically 20% cheaper and offer
comparable or better performance for most workloads. If your container images support multi-arch builds (which
they should), this is an easy win.

<br />

##### **Cost alerts tied to SLOs**
Here is where SRE and FinOps intersect beautifully: using your error budget as a cost control mechanism.
The idea is that if you are spending more than necessary to maintain your SLOs, you have room to optimize.

<br />

Think about it this way. If your availability SLO is 99.9% and you are running at 99.99%, you are probably
over-provisioned. That extra "9" is costing you money and it is not required by the SLO. You could reduce
capacity until availability drops to around 99.95% and still have plenty of error budget left.

<br />

Set up cost-per-request as a metric:

<br />

```yaml
# prometheus/cost-per-request-rule.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-metrics
  namespace: monitoring
spec:
  groups:
    - name: cost.rules
      interval: 5m
      rules:
        # Cost per request (estimated)
        - record: cost:per_request:ratio
          expr: |
            (
              sum(container_cpu_allocation{namespace="default"} *
                on(node) group_left() node_cpu_hourly_cost)
              +
              sum(container_memory_allocation_bytes{namespace="default"} / 1024 / 1024 / 1024 *
                on(node) group_left() node_ram_hourly_cost)
            )
            /
            sum(rate(http_requests_total{namespace="default"}[1h]))

        # Monthly cost estimate
        - record: cost:monthly:estimate
          expr: |
            sum(
              container_cpu_allocation * on(node) group_left()
              node_cpu_hourly_cost * 730
            ) +
            sum(
              container_memory_allocation_bytes / 1024 / 1024 / 1024 *
              on(node) group_left() node_ram_hourly_cost * 730
            )

        # Cost efficiency: value delivered per dollar
        - record: cost:efficiency:ratio
          expr: |
            sum(rate(http_requests_total{status=~"2.."}[1h]))
            /
            (
              sum(container_cpu_allocation{namespace="default"} *
                on(node) group_left() node_cpu_hourly_cost)
              +
              sum(container_memory_allocation_bytes{namespace="default"} / 1024 / 1024 / 1024 *
                on(node) group_left() node_ram_hourly_cost)
            )
```

<br />

Now create alerts that fire when costs exceed thresholds:

<br />

```yaml
# prometheus/cost-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-alerts
  namespace: monitoring
spec:
  groups:
    - name: cost.alerts
      rules:
        # Alert when monthly cost estimate exceeds budget
        - alert: MonthlyCostExceedsBudget
          expr: cost:monthly:estimate > 500
          for: 6h
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Monthly cost estimate exceeds $500 budget"
            description: "Current estimated monthly cost is ${{ $value | printf \"%.2f\" }}. Budget is $500."
            runbook_url: "https://wiki.internal/runbooks/cost-overrun"

        # Alert when cost per request spikes
        - alert: CostPerRequestSpike
          expr: cost:per_request:ratio > 0.001
          for: 1h
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Cost per request exceeds $0.001"
            description: "Current cost per request is ${{ $value | printf \"%.6f\" }}. This may indicate over-provisioning or a traffic drop."

        # Alert when CPU efficiency drops (over-provisioning)
        - alert: LowCPUEfficiency
          expr: |
            sum by (namespace) (rate(container_cpu_usage_seconds_total[24h]))
            /
            sum by (namespace) (kube_pod_container_resource_requests{resource="cpu"})
            < 0.2
          for: 24h
          labels:
            severity: info
            team: platform
          annotations:
            summary: "Namespace {{ $labels.namespace }} CPU utilization below 20%"
            description: "The namespace {{ $labels.namespace }} is only using {{ $value | printf \"%.1f\" }}% of requested CPU. Consider right-sizing."

        # Alert when error budget is healthy but costs are high
        # This is the key FinOps+SRE integration
        - alert: OverProvisionedForSLO
          expr: |
            (1 - slo:error_budget:remaining_ratio) < 0.1
            and
            cost:monthly:estimate > 400
          for: 24h
          labels:
            severity: info
            team: platform
          annotations:
            summary: "Over-provisioned: SLO healthy but costs high"
            description: "Error budget consumed is only {{ $value | printf \"%.1f\" }}% but monthly cost is high. Consider reducing capacity to save costs while maintaining SLO."
```

<br />

The `OverProvisionedForSLO` alert is the most interesting one. It fires when your error budget is barely
touched (meaning you are way above your SLO target) AND your costs are high. This is a signal that you can
safely reduce capacity.

<br />

##### **Tagging strategies**
Without proper tagging, your cost data is just a big number with no context. You need to know which team,
project, and environment is responsible for each cost.

<br />

In Kubernetes, labels serve as tags for cost allocation. Define a consistent labeling standard:

<br />

```hcl
# labels/standard-labels.yaml
# Every resource should have these labels
metadata:
  labels:
    # Who owns this?
    app.kubernetes.io/name: tr-web
    app.kubernetes.io/component: frontend
    app.kubernetes.io/part-of: tr-blog
    app.kubernetes.io/managed-by: argocd

    # Cost allocation
    cost-center: engineering
    team: platform
    environment: production
    project: tr-blog

    # Lifecycle
    lifecycle: permanent   # or: temporary, ephemeral, review
    expiry: "none"         # or: "2026-04-01" for temporary resources
```

<br />

Enforce these labels with a policy engine like Kyverno:

<br />

```yaml
# kyverno/require-cost-labels.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-cost-labels
  annotations:
    policies.kyverno.io/title: Require Cost Allocation Labels
    policies.kyverno.io/description: >-
      All deployments must have cost allocation labels for
      tracking and chargeback purposes.
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: check-cost-labels
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
                - DaemonSet
                - Job
                - CronJob
      validate:
        message: >-
          All workloads must have cost allocation labels:
          cost-center, team, environment, and project.
        pattern:
          metadata:
            labels:
              cost-center: "?*"
              team: "?*"
              environment: "?*"
              project: "?*"

    - name: check-pvc-labels
      match:
        any:
          - resources:
              kinds:
                - PersistentVolumeClaim
      validate:
        message: "PVCs must have cost-center and team labels."
        pattern:
          metadata:
            labels:
              cost-center: "?*"
              team: "?*"

    - name: check-service-labels
      match:
        any:
          - resources:
              kinds:
                - Service
      validate:
        message: "Services must have cost-center and team labels."
        pattern:
          metadata:
            labels:
              cost-center: "?*"
              team: "?*"
```

<br />

With this policy in place, any deployment without cost allocation labels is rejected at admission time. This
ensures 100% label coverage, which means your cost reports are accurate.

<br />

For cloud resources outside Kubernetes (S3 buckets, RDS instances, etc.), use Terraform to enforce tags:

<br />

```hcl
# terraform/provider.tf
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "production"
      Team        = "platform"
      Project     = "tr-blog"
      ManagedBy   = "terraform"
      CostCenter  = "engineering"
    }
  }
}

# terraform/tag-policy.tf
resource "aws_organizations_policy" "require_tags" {
  name        = "require-cost-tags"
  description = "Require cost allocation tags on all resources"
  type        = "TAG"

  content = jsonencode({
    tags = {
      CostCenter = {
        tag_key = {
          "@@assign" = "CostCenter"
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "ec2:volume",
            "s3:bucket",
            "rds:db",
            "elasticloadbalancing:loadbalancer"
          ]
        }
      }
      Team = {
        tag_key = {
          "@@assign" = "Team"
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "ec2:volume",
            "s3:bucket",
            "rds:db"
          ]
        }
      }
    }
  })
}
```

<br />

Once tagging is consistent, you can generate cost reports per team:

<br />

```yaml
# Query Kubecost for cost by team label
curl -s "http://kubecost.kubecost.svc:9090/model/allocation?window=30d&aggregate=label:team" \
  | jq '.data[0] | to_entries[] | {
    team: .key,
    monthlyCost: (.value.totalCost | . * 100 | round / 100),
    cpuEfficiency: (.value.cpuEfficiency | . * 100 | round),
    ramEfficiency: (.value.ramEfficiency | . * 100 | round)
  }'

# Example output:
# { "team": "platform", "monthlyCost": 285.42, "cpuEfficiency": 45, "ramEfficiency": 52 }
# { "team": "backend", "monthlyCost": 156.78, "cpuEfficiency": 62, "ramEfficiency": 58 }
# { "team": "data", "monthlyCost": 412.33, "cpuEfficiency": 78, "ramEfficiency": 71 }
```

<br />

This data makes cost conversations productive. Instead of "we need to cut costs," you can say "the platform
team has 45% CPU efficiency, let's right-size those workloads to save an estimated $128/month."

<br />

##### **Closing notes**
Cost optimization in the cloud is not a one-time project. It is an ongoing practice that requires visibility,
accountability, and continuous improvement. The good news is that as an SRE team, you already have most of the
skills and tooling you need. You know how to measure things (SLIs), set targets (SLOs), and automate responses
(alerts and runbooks). Apply those same patterns to cost.

<br />

Start with the quick wins: run VPA in recommendation mode and right-size your top 10 over-provisioned workloads.
Install OpenCost to get visibility into where your money goes. Set up a weekly cost review alongside your SLO
review. Then gradually adopt spot instances, storage tiering, and cost-aware alerting.

<br />

The key takeaway is that reliability and cost efficiency are not in conflict. With the right approach, you can
reduce spending while maintaining or even improving your SLOs. Every dollar saved on over-provisioning is a
dollar you can invest in better tooling, more reliability features, or your team.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Optimización de Costos en la Nube",
  author: "Gabriel Garrido",
  description: "Vamos a explorar los principios de FinOps y estrategias de optimización de costos para Kubernetes e infraestructura cloud, desde right-sizing de workloads e instancias spot hasta visibilidad con Kubecost y SLOs conscientes del costo...",
  tags: ~w(sre kubernetes cloud cost-optimization finops),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
A lo largo de esta serie de SRE cubrimos [SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[gestion de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observabilidad](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[capacity planning](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd), y
[gestion de secretos](/blog/sre-secrets-management-in-kubernetes). Construimos una base solida para correr
sistemas confiables, pero la confiabilidad es solo la mitad de la historia. Si tu factura de infraestructura
sigue creciendo sin control, no importa lo confiable que sea todo porque eventualmente alguien va a hacer
preguntas dificiles sobre el costo.

<br />

El gasto en la nube tiene la tendencia de crecer de a poco. Levantas un cluster de prueba y te olvidas,
alguien pide una instancia grande "por las dudas," los entornos de desarrollo corren 24/7, y antes de que te
des cuenta tu factura mensual se duplico. El movimiento FinOps surgio para traer responsabilidad financiera
al gasto en la nube, y los equipos de SRE estan en una posicion unica para impulsar la optimizacion de costos
porque ya entienden la infraestructura en profundidad.

<br />

En este articulo vamos a cubrir principios de FinOps, right-sizing de workloads, instancias spot, resource
quotas, visibilidad de costos con Kubecost y OpenCost, deteccion de recursos ociosos, storage tiering,
planificacion de capacidad reservada, alertas de costos vinculadas a SLOs, y estrategias de etiquetado para
asignacion de costos. Son todas tecnicas practicas que podes empezar a aplicar hoy.

<br />

Vamos al tema.

<br />

##### **Principios de FinOps**
FinOps (Financial Operations) es una practica cultural que reune a equipos de ingenieria, finanzas y negocio
para gestionar los costos en la nube de forma colaborativa. No se trata de cortar costos a cualquier precio.
Se trata de tomar decisiones informadas y obtener el maximo valor de cada peso o dolar gastado.

<br />

El ciclo de vida de FinOps tiene tres fases:

<br />

> 1. **Informar**: Entender que estas gastando, donde y por que. No podes optimizar lo que no podes ver.
> 2. **Optimizar**: Tomar accion para reducir el desperdicio. Right-size de instancias, usar nodos spot, limpiar recursos ociosos.
> 3. **Operar**: Monitorear costos continuamente, establecer presupuestos y construir conciencia de costos en tu cultura de ingenieria.

<br />

Para los equipos de SRE, el insight clave es que el costo deberia tratarse como una metrica de primera clase,
igual que la latencia, la disponibilidad y la tasa de errores. Ya tenes dashboards para SLIs. Agrega un panel
de costos a esos dashboards. Cuando revises el rendimiento de tus SLOs semanalmente, revisa tambien tus metricas
de costos.

<br />

Algunos principios practicos para adoptar:

<br />

> * **Todos son responsables del costo**, no solo finanzas. Los ingenieros que aprovisionan recursos deberian entender el impacto en costos.
> * **Las decisiones de costos se basan en datos**. Usa datos reales de utilizacion, no suposiciones ni "capaz lo necesitemos algun dia."
> * **La optimizacion de costos es continua**, no un proyecto de una sola vez. Tratala como la confiabilidad, siempre mejorando.
> * **Optimiza por valor, no solo por ahorro**. A veces gastar mas es la decision correcta si mejora la confiabilidad o la productividad del equipo.

<br />

##### **Right-sizing de workloads**
El right-sizing es la optimizacion de costos con mayor impacto que podes hacer en Kubernetes. La mayoria de los
equipos sobre-aprovisionan sus workloads significativamente porque los desarrolladores piden recursos basandose
en estimaciones del peor caso en vez de uso real.

<br />

El Vertical Pod Autoscaler (VPA) es tu mejor amigo aca. Incluso si no lo habilitas en modo automatico, correrlo
en modo recomendacion te da datos de lo que tus pods realmente usan versus lo que piden.

<br />

Instala el VPA:

<br />

```bash
# Instalar componentes del VPA
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler
./hack/vpa-up.sh
```

<br />

Crea un VPA en modo recomendacion para tus workloads:

<br />

```yaml
# vpa/tr-web-vpa.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: tr-web-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tr-web
  updatePolicy:
    updateMode: "Off"  # Solo recomendaciones, sin auto-updates
  resourcePolicy:
    containerPolicies:
      - containerName: tr-web
        minAllowed:
          cpu: 50m
          memory: 64Mi
        maxAllowed:
          cpu: 2000m
          memory: 2Gi
        controlledResources:
          - cpu
          - memory
```

<br />

Despues de unos dias corriendo, revisa las recomendaciones:

<br />

```bash
kubectl describe vpa tr-web-vpa

# La salida va a verse algo asi:
# Recommendation:
#   Container Recommendations:
#     Container Name: tr-web
#     Lower Bound:
#       Cpu:     25m
#       Memory:  80Mi
#     Target:
#       Cpu:     100m
#       Memory:  180Mi
#     Uncapped Target:
#       Cpu:     100m
#       Memory:  180Mi
#     Upper Bound:
#       Cpu:     350m
#       Memory:  400Mi
```

<br />

Ahora compara eso con lo que realmente pediste:

<br />

```hcl
# Revisar resource requests actuales en todos los pods
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{"\t"}Req: {.resources.requests.cpu}/{.resources.requests.memory}{"\t"}Lim: {.resources.limits.cpu}/{.resources.limits.memory}{"\n"}{end}{end}' | column -t
```

<br />

Si tus pods piden 500m de CPU pero solo usan 100m en promedio, estas pagando 5 veces mas computo del que
necesitas. Esa diferencia es desperdicio puro.

<br />

Una buena regla general para configurar requests y limits:

<br />

> * **Requests**: Configuralos al P95 del uso real (de las recomendaciones del VPA o metricas de Prometheus). Esto asegura que el scheduler coloque pods en nodos con capacidad suficiente.
> * **Limits**: Configuralos a 2-3x del request para CPU (para permitir bursting), y 1.5-2x para memoria (para evitar OOM kills mientras prevenis consumo descontrolado).
> * **Revisa trimestralmente**: Los patrones de uso cambian a medida que tu aplicacion evoluciona. Lo que estaba bien dimensionado hace seis meses puede estar mal hoy.

<br />

Aca hay un query de Prometheus para encontrar los workloads mas sobre-aprovisionados:

<br />

```bash
# Ratio de sobre-aprovisionamiento de CPU por deployment
# Valores > 2 significan que el workload pide 2x+ mas CPU de la que usa
sum by (namespace, owner_name) (
  kube_pod_container_resource_requests{resource="cpu"}
) /
sum by (namespace, owner_name) (
  rate(container_cpu_usage_seconds_total[24h])
)
```

<br />

##### **Instancias spot y preemptible**
Las instancias spot (AWS), VMs preemptible (GCP), o VMs spot (Azure) ofrecen descuentos del 60-90% comparado
con precios on-demand. La contrapartida es que el proveedor cloud puede reclamarlas con poco aviso (usualmente
2 minutos). Para workloads stateless y tolerantes a fallas en Kubernetes, es un gran negocio.

<br />

El truco es correr tus workloads en una mezcla de nodos on-demand y spot. Workloads criticos como tu base de
datos van en nodos on-demand. Servidores web stateless y jobs batch van en nodos spot.

<br />

Configura un node group spot (ejemplo EKS):

<br />

```yaml
# eks-nodegroup-spot.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: production-cluster
  region: us-east-1
spec:
  managedNodeGroups:
    - name: on-demand-critical
      instanceType: t3.large
      desiredCapacity: 2
      minSize: 2
      maxSize: 4
      labels:
        node-type: on-demand
        workload-type: critical
      taints:
        - key: workload-type
          value: critical
          effect: NoSchedule

    - name: spot-general
      instanceTypes:
        - t3.large
        - t3.xlarge
        - t3a.large
        - t3a.xlarge
        - m5.large
        - m5a.large
      spot: true
      desiredCapacity: 3
      minSize: 1
      maxSize: 10
      labels:
        node-type: spot
        workload-type: general
```

<br />

Fijate que el node group spot usa multiples tipos de instancia. Esto es importante porque la disponibilidad de
spot varia por tipo de instancia. Usar un conjunto diverso aumenta tus chances de conseguir capacidad.

<br />

Ahora programa tus workloads apropiadamente usando node affinity y tolerations:

<br />

```yaml
# deployments/tr-web.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tr-web
  namespace: default
spec:
  replicas: 3
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 80
              preference:
                matchExpressions:
                  - key: node-type
                    operator: In
                    values:
                      - spot
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
              - weight: 100
                podAffinityTerm:
                  labelSelector:
                    matchExpressions:
                      - key: app
                        operator: In
                        values:
                          - tr-web
                  topologyKey: kubernetes.io/hostname
      tolerations:
        - key: "node-type"
          operator: "Equal"
          value: "spot"
          effect: "NoSchedule"
      containers:
        - name: tr-web
          image: kainlite/tr:latest
          resources:
            requests:
              cpu: 100m
              memory: 180Mi
            limits:
              cpu: 300m
              memory: 360Mi
```

<br />

El `preferredDuringSchedulingIgnoredDuringExecution` con weight 80 significa que el scheduler va a intentar
colocar pods en nodos spot pero va a caer a on-demand si no hay capacidad spot disponible. Esto es importante
para la resiliencia.

<br />

Tambien necesitas un PodDisruptionBudget para manejar la reclamacion de nodos spot de forma elegante:

<br />

```yaml
# pdb/tr-web-pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: tr-web-pdb
  namespace: default
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: tr-web
```

<br />

Esto asegura que al menos 2 pods esten siempre corriendo, incluso durante la reclamacion de nodos spot.
Combinado con multiples replicas distribuidas en diferentes nodos, tu servicio se mantiene disponible mientras
ahorras 60-90% en computo.

<br />

##### **Resource quotas y limit ranges**
Sin guardarrailes, cualquier miembro del equipo puede deployar un workload que pida 64 CPUs y 256GB de memoria.
Las resource quotas y limit ranges previenen este tipo de costo descontrolado.

<br />

Un ResourceQuota establece limites duros por namespace:

<br />

```yaml
# quotas/dev-namespace-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: dev
spec:
  hard:
    requests.cpu: "4"           # Total de requests de CPU en todos los pods
    requests.memory: 8Gi        # Total de requests de memoria
    limits.cpu: "8"             # Total de limits de CPU
    limits.memory: 16Gi         # Total de limits de memoria
    pods: "20"                  # Maximo numero de pods
    services.loadbalancers: "2" # Limitar servicios LB costosos
    persistentvolumeclaims: "10"
    requests.storage: 100Gi     # Total de storage en PVCs
```

<br />

Un LimitRange establece defaults y restricciones por pod. Es especialmente util para atrapar pods desplegados
sin resource requests:

<br />

```yaml
# quotas/dev-namespace-limitrange.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: dev
spec:
  limits:
    - type: Container
      default:          # Limits por defecto si no se especifican
        cpu: 200m
        memory: 256Mi
      defaultRequest:   # Requests por defecto si no se especifican
        cpu: 50m
        memory: 64Mi
      min:              # Minimo permitido
        cpu: 10m
        memory: 16Mi
      max:              # Maximo permitido por container
        cpu: "2"
        memory: 4Gi
    - type: Pod
      max:              # Maximo por pod (todos los containers combinados)
        cpu: "4"
        memory: 8Gi
    - type: PersistentVolumeClaim
      min:
        storage: 1Gi
      max:
        storage: 50Gi
```

<br />

Ahora si alguien deploya un pod sin resource requests, automaticamente recibe 50m de CPU y 64Mi de memoria
como defaults. Y si alguien intenta pedir 32 CPUs, el API server rechaza el request.

<br />

Para namespaces de produccion, vas a querer quotas diferentes:

<br />

```yaml
# quotas/production-namespace-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: production
spec:
  hard:
    requests.cpu: "16"
    requests.memory: 32Gi
    limits.cpu: "32"
    limits.memory: 64Gi
    pods: "50"
    services.loadbalancers: "5"
    persistentvolumeclaims: "20"
    requests.storage: 500Gi
  scopeSelector:
    matchExpressions:
      - scopeName: PriorityClass
        operator: In
        values:
          - high
          - medium
```

<br />

##### **Kubecost y OpenCost**
No podes optimizar lo que no podes medir. Kubecost (y su nucleo open source, OpenCost) te da visibilidad de
costos en tu cluster de Kubernetes, desglosado por namespace, deployment, label y equipo.

<br />

Instala OpenCost con Helm:

<br />

```sql
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update

helm install opencost opencost/opencost \
  --namespace opencost \
  --create-namespace \
  --set opencost.exporter.defaultClusterId="production" \
  --set opencost.ui.enabled=true \
  --set opencost.prometheus.internal.enabled=false \
  --set opencost.prometheus.external.url="http://prometheus-server.monitoring.svc:9090"
```

<br />

Para Kubecost (que incluye mas funcionalidades como recomendaciones e insights de ahorro):

<br />

```sql
helm repo add kubecost https://kubecost.github.io/cost-analyzer
helm repo update

helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set kubecostToken="your-token-here" \
  --set prometheus.server.global.external_labels.cluster_id="production" \
  --set prometheus.nodeExporter.enabled=false \
  --set prometheus.serviceAccounts.nodeExporter.create=false
```

<br />

Una vez instalado, podes consultar los datos de costos via la API:

<br />

```yaml
# Obtener asignacion de costos por namespace de los ultimos 7 dias
curl -s "http://kubecost.kubecost.svc:9090/model/allocation?window=7d&aggregate=namespace" \
  | jq '.data[0] | to_entries[] | {
    namespace: .key,
    totalCost: .value.totalCost,
    cpuCost: .value.cpuCost,
    memCost: .value.ramCost,
    pvCost: .value.pvCost,
    cpuEfficiency: .value.cpuEfficiency,
    ramEfficiency: .value.ramEfficiency
  }'

# Ejemplo de salida:
# {
#   "namespace": "default",
#   "totalCost": 42.15,
#   "cpuCost": 18.30,
#   "memCost": 15.85,
#   "pvCost": 8.00,
#   "cpuEfficiency": 0.35,
#   "ramEfficiency": 0.42
# }
```

<br />

Esa eficiencia de CPU de 0.35 significa que solo estas usando el 35% de la CPU por la que estas pagando. Eso
es una gran oportunidad de optimizacion.

<br />

Crea un dashboard de Grafana para visibilidad de costos:

<br />

```bash
# grafana/cost-dashboard.json (simplificado)
# Queries utiles de Prometheus para paneles de costos:

# Estimacion de costo mensual por namespace
sum by (namespace) (
  container_cpu_allocation * on(node) group_left()
  node_cpu_hourly_cost * 730
) +
sum by (namespace) (
  container_memory_allocation_bytes / 1024 / 1024 / 1024 * on(node) group_left()
  node_ram_hourly_cost * 730
)

# Costo ocioso (recursos pedidos pero no usados)
sum by (namespace) (
  (kube_pod_container_resource_requests{resource="cpu"} -
   rate(container_cpu_usage_seconds_total[1h]))
  * on(node) group_left() node_cpu_hourly_cost * 730
)

# Costo por request (util para tracking de costo-por-SLI)
sum(rate(container_cpu_usage_seconds_total{namespace="default"}[1h])
  * on(node) group_left() node_cpu_hourly_cost)
/
sum(rate(http_requests_total{namespace="default"}[1h]))
```

<br />

##### **Deteccion de recursos ociosos**
Los recursos ociosos son la fruta al alcance de la mano de la optimizacion de costos. Son cosas por las que
estas pagando pero nadie esta usando. En un cluster de Kubernetes tipico, el 20-30% del gasto va a recursos
ociosos.

<br />

Aca hay un script para encontrar recursos ociosos comunes:

<br />

```bash
#!/bin/bash
# idle-resource-audit.sh
# Encontrar recursos ociosos y desperdiciados en tu cluster

echo "=== PersistentVolumeClaims sin usar ==="
# PVCs no montados por ningun pod
kubectl get pvc -A -o json | jq -r '
  .items[] |
  select(.status.phase == "Bound") |
  .metadata.namespace + "/" + .metadata.name
' | while read pvc; do
  ns=$(echo $pvc | cut -d/ -f1)
  name=$(echo $pvc | cut -d/ -f2)
  used=$(kubectl get pods -n $ns -o json | jq -r \
    --arg pvc "$name" \
    '.items[].spec.volumes[]? | select(.persistentVolumeClaim.claimName == $pvc) | .name' \
    2>/dev/null)
  if [ -z "$used" ]; then
    size=$(kubectl get pvc $name -n $ns -o jsonpath='{.spec.resources.requests.storage}')
    echo "  SIN USAR: $pvc ($size)"
  fi
done

echo ""
echo "=== Servicios LoadBalancer ==="
kubectl get svc -A --field-selector spec.type=LoadBalancer \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,IP:.status.loadBalancer.ingress[0].ip,AGE:.metadata.creationTimestamp'

echo ""
echo "=== Deployments con 0 replicas ==="
kubectl get deploy -A -o json | jq -r '
  .items[] |
  select(.spec.replicas == 0) |
  .metadata.namespace + "/" + .metadata.name
'

echo ""
echo "=== Pods en CrashLoopBackOff ==="
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount'

echo ""
echo "=== Persistent Volumes sin adjuntar ==="
kubectl get pv -o json | jq -r '
  .items[] |
  select(.status.phase == "Available" or .status.phase == "Released") |
  .metadata.name + " (" + .spec.capacity.storage + ") - " + .status.phase
'
```

<br />

Para un enfoque mas automatizado, configura un CronJob que corra esta auditoria semanalmente y envie los
resultados a Slack:

<br />

```yaml
# cronjob/idle-resource-audit.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: idle-resource-audit
  namespace: monitoring
spec:
  schedule: "0 9 * * 1"  # Cada lunes a las 9am
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: resource-auditor
          containers:
            - name: auditor
              image: bitnami/kubectl:latest
              command:
                - /bin/bash
                - -c
                - |
                  UNUSED_PVCS=$(kubectl get pvc -A -o json | jq '[.items[] | select(.status.phase == "Bound")] | length')
                  TOTAL_PVCS=$(kubectl get pvc -A -o json | jq '.items | length')
                  LB_COUNT=$(kubectl get svc -A --field-selector spec.type=LoadBalancer -o json | jq '.items | length')
                  ZERO_REPLICAS=$(kubectl get deploy -A -o json | jq '[.items[] | select(.spec.replicas == 0)] | length')

                  curl -X POST "$SLACK_WEBHOOK_URL" \
                    -H 'Content-type: application/json' \
                    -d "{
                      \"text\": \"Reporte Semanal de Recursos Ociosos\",
                      \"blocks\": [{
                        \"type\": \"section\",
                        \"text\": {
                          \"type\": \"mrkdwn\",
                          \"text\": \"*Auditoria Semanal de Recursos Ociosos*\n- PVCs: $TOTAL_PVCS total\n- LoadBalancers: $LB_COUNT activos\n- Deployments con cero replicas: $ZERO_REPLICAS\"
                        }
                      }]
                    }"
              env:
                - name: SLACK_WEBHOOK_URL
                  valueFrom:
                    secretKeyRef:
                      name: slack-webhook
                      key: url
          restartPolicy: OnFailure
```

<br />

##### **Storage tiering**
Los costos de almacenamiento pueden acumularse sin que te des cuenta, especialmente si todo usa SSD de alto
rendimiento por defecto. No todos los datos necesitan almacenamiento rapido. Logs, backups y datos archivados
pueden vivir en tiers de almacenamiento mas baratos.

<br />

Define multiples StorageClasses para diferentes tiers:

<br />

```yaml
# storage/storageclass-fast.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
  labels:
    cost-tier: high
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "5000"
  throughput: "250"
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
# storage/storageclass-standard.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
  labels:
    cost-tier: medium
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
# storage/storageclass-cold.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cold-storage
  labels:
    cost-tier: low
provisioner: ebs.csi.aws.com
parameters:
  type: sc1
  encrypted: "true"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

<br />

Usa el tier correcto para cada workload:

<br />

```hcl
# Base de datos: SSD rapido para baja latencia
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-data
  namespace: default
spec:
  storageClassName: fast-ssd
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
# Logs de aplicacion: almacenamiento estandar
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-logs
  namespace: default
spec:
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
---
# Backups y archivos: almacenamiento frio
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-archive
  namespace: default
spec:
  storageClassName: cold-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi
```

<br />

Para object storage (S3, GCS), configura lifecycle policies para mover datos a tiers mas baratos automaticamente:

<br />

```hcl
# terraform/s3-lifecycle.tf
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"  # ~45% mas barato
    }

    transition {
      days          = 90
      storage_class = "GLACIER"       # ~80% mas barato
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"  # ~95% mas barato
    }

    expiration {
      days = 730  # Borrar despues de 2 anios
    }
  }
}
```

<br />

La diferencia de costos entre tiers es significativa. Para AWS EBS, gp3 cuesta aproximadamente $0.08/GB/mes
mientras que sc1 cuesta $0.015/GB/mes. Para S3, Standard es $0.023/GB/mes mientras que Deep Archive es
$0.00099/GB/mes. Mover 1TB de datos de archivo de Standard a Deep Archive ahorra unos $264/anio.

<br />

##### **Reservado vs on-demand**
Si sabes que vas a necesitar una cierta cantidad de computo por los proximos 1-3 anios, las instancias reservadas
o savings plans ofrecen descuentos del 30-60% comparados con on-demand. La contrapartida es el compromiso,
pagas lo uses o no.

<br />

La clave es solo comprometerte con tu baseline, el computo minimo que siempre necesitas. Deja que on-demand y
spot manejen los picos.

<br />

Aca como analizar tu cobertura de reservaciones:

<br />

```bash
# Query de Prometheus: utilizacion promedio de CPU en 30 dias
# Esto muestra tus necesidades base de computo
avg_over_time(
  sum(
    rate(container_cpu_usage_seconds_total[5m])
  )[30d:1h]
)

# Compara con tu capacidad reservada
# Si reservado < baseline, estas sub-comprometido (pagando demasiado on-demand)
# Si reservado > baseline, estas sobre-comprometido (pagando por reservaciones sin usar)
```

<br />

Un enfoque practico para la planificacion de reservaciones:

<br />

> 1. **Medi tu baseline** por al menos 3 meses. Fijate en el uso minimo sostenido, no el promedio.
> 2. **Reserva el 70-80% del baseline**. Esto te da un margen de seguridad para cambios en los workloads.
> 3. **Usa savings plans en vez de instancias reservadas** cuando sea posible. Los savings plans son mas flexibles porque aplican a cualquier familia de instancias.
> 4. **Revisa trimestralmente**. Si tu baseline cambio, ajusta tus compromisos en el momento de la renovacion.
> 5. **Considera terminos de 1 anio primero**. La diferencia de ahorro entre 1 anio y 3 anios muchas veces no justifica el riesgo de quedar atrapado.

<br />

Para Kubernetes especificamente, podes usar Karpenter (AWS) o el cluster autoscaler con politicas de instancias
mixtas para elegir automaticamente los tipos de instancia mas baratos disponibles:

<br />

```yaml
# karpenter/provisioner.yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values:
        - on-demand
        - spot
    - key: node.kubernetes.io/instance-type
      operator: In
      values:
        - t3.medium
        - t3.large
        - t3a.medium
        - t3a.large
        - m5.large
        - m5a.large
        - m6i.large
        - m6a.large
    - key: kubernetes.io/arch
      operator: In
      values:
        - amd64
        - arm64   # Las instancias ARM son ~20% mas baratas
  limits:
    resources:
      cpu: "64"
      memory: 128Gi
  providerRef:
    name: default
  # Consolidacion: Karpenter va a reemplazar nodos subutilizados
  # con nodos mas chicos para ahorrar plata
  consolidation:
    enabled: true
  ttlSecondsAfterEmpty: 30
```

<br />

Fijate en la opcion de arquitectura `arm64`. Las instancias ARM (como AWS Graviton) son tipicamente 20% mas
baratas y ofrecen rendimiento comparable o mejor para la mayoria de los workloads. Si tus imagenes de container
soportan builds multi-arch (lo cual deberian), es una ganancia facil.

<br />

##### **Alertas de costos vinculadas a SLOs**
Aca es donde SRE y FinOps se cruzan de manera hermosa: usar tu error budget como mecanismo de control de costos.
La idea es que si estas gastando mas de lo necesario para mantener tus SLOs, tenes margen para optimizar.

<br />

Pensalo asi. Si tu SLO de disponibilidad es 99.9% y estas corriendo a 99.99%, probablemente estes
sobre-aprovisionado. Ese "9" extra te esta costando plata y no es requerido por el SLO. Podrias reducir
capacidad hasta que la disponibilidad baje a alrededor de 99.95% y todavia tendrias bastante error budget
sobrante.

<br />

Configura costo-por-request como metrica:

<br />

```yaml
# prometheus/cost-per-request-rule.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-metrics
  namespace: monitoring
spec:
  groups:
    - name: cost.rules
      interval: 5m
      rules:
        # Costo por request (estimado)
        - record: cost:per_request:ratio
          expr: |
            (
              sum(container_cpu_allocation{namespace="default"} *
                on(node) group_left() node_cpu_hourly_cost)
              +
              sum(container_memory_allocation_bytes{namespace="default"} / 1024 / 1024 / 1024 *
                on(node) group_left() node_ram_hourly_cost)
            )
            /
            sum(rate(http_requests_total{namespace="default"}[1h]))

        # Estimacion de costo mensual
        - record: cost:monthly:estimate
          expr: |
            sum(
              container_cpu_allocation * on(node) group_left()
              node_cpu_hourly_cost * 730
            ) +
            sum(
              container_memory_allocation_bytes / 1024 / 1024 / 1024 *
              on(node) group_left() node_ram_hourly_cost * 730
            )

        # Eficiencia de costos: valor entregado por dolar
        - record: cost:efficiency:ratio
          expr: |
            sum(rate(http_requests_total{status=~"2.."}[1h]))
            /
            (
              sum(container_cpu_allocation{namespace="default"} *
                on(node) group_left() node_cpu_hourly_cost)
              +
              sum(container_memory_allocation_bytes{namespace="default"} / 1024 / 1024 / 1024 *
                on(node) group_left() node_ram_hourly_cost)
            )
```

<br />

Ahora crea alertas que se disparen cuando los costos excedan umbrales:

<br />

```yaml
# prometheus/cost-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-alerts
  namespace: monitoring
spec:
  groups:
    - name: cost.alerts
      rules:
        # Alerta cuando el costo mensual estimado excede el presupuesto
        - alert: MonthlyCostExceedsBudget
          expr: cost:monthly:estimate > 500
          for: 6h
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "El costo mensual estimado excede el presupuesto de $500"
            description: "El costo mensual estimado actual es ${{ $value | printf \"%.2f\" }}. El presupuesto es $500."

        # Alerta cuando el costo por request sube
        - alert: CostPerRequestSpike
          expr: cost:per_request:ratio > 0.001
          for: 1h
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "El costo por request excede $0.001"
            description: "El costo actual por request es ${{ $value | printf \"%.6f\" }}. Esto puede indicar sobre-aprovisionamiento o una caida de trafico."

        # Alerta cuando la eficiencia de CPU cae (sobre-aprovisionamiento)
        - alert: LowCPUEfficiency
          expr: |
            sum by (namespace) (rate(container_cpu_usage_seconds_total[24h]))
            /
            sum by (namespace) (kube_pod_container_resource_requests{resource="cpu"})
            < 0.2
          for: 24h
          labels:
            severity: info
            team: platform
          annotations:
            summary: "Namespace {{ $labels.namespace }} utilizacion de CPU por debajo del 20%"
            description: "El namespace {{ $labels.namespace }} solo esta usando {{ $value | printf \"%.1f\" }}% de la CPU pedida. Considera right-sizing."

        # Alerta cuando el error budget esta sano pero los costos son altos
        - alert: OverProvisionedForSLO
          expr: |
            (1 - slo:error_budget:remaining_ratio) < 0.1
            and
            cost:monthly:estimate > 400
          for: 24h
          labels:
            severity: info
            team: platform
          annotations:
            summary: "Sobre-aprovisionado: SLO sano pero costos altos"
            description: "El error budget consumido es solo {{ $value | printf \"%.1f\" }}% pero el costo mensual es alto. Considera reducir capacidad para ahorrar costos manteniendo el SLO."
```

<br />

La alerta `OverProvisionedForSLO` es la mas interesante. Se dispara cuando tu error budget casi no se toca
(lo que significa que estas muy por encima de tu objetivo de SLO) Y tus costos son altos. Es una señal de que
podes reducir capacidad de forma segura.

<br />

##### **Estrategias de etiquetado**
Sin etiquetado adecuado, tus datos de costos son solo un numero grande sin contexto. Necesitas saber que equipo,
proyecto y entorno es responsable de cada costo.

<br />

En Kubernetes, los labels sirven como etiquetas para asignacion de costos. Define un estandar de etiquetado
consistente:

<br />

```yaml
# labels/standard-labels.yaml
# Todo recurso deberia tener estos labels
metadata:
  labels:
    # Quien es el dueño?
    app.kubernetes.io/name: tr-web
    app.kubernetes.io/component: frontend
    app.kubernetes.io/part-of: tr-blog
    app.kubernetes.io/managed-by: argocd

    # Asignacion de costos
    cost-center: engineering
    team: platform
    environment: production
    project: tr-blog

    # Ciclo de vida
    lifecycle: permanent   # o: temporary, ephemeral, review
    expiry: "none"         # o: "2026-04-01" para recursos temporales
```

<br />

Aplica estos labels con un motor de politicas como Kyverno:

<br />

```yaml
# kyverno/require-cost-labels.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-cost-labels
  annotations:
    policies.kyverno.io/title: Require Cost Allocation Labels
    policies.kyverno.io/description: >-
      Todos los deployments deben tener labels de asignacion de costos
      para tracking y chargeback.
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: check-cost-labels
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
                - DaemonSet
                - Job
                - CronJob
      validate:
        message: >-
          Todos los workloads deben tener labels de asignacion de costos:
          cost-center, team, environment y project.
        pattern:
          metadata:
            labels:
              cost-center: "?*"
              team: "?*"
              environment: "?*"
              project: "?*"

    - name: check-pvc-labels
      match:
        any:
          - resources:
              kinds:
                - PersistentVolumeClaim
      validate:
        message: "Los PVCs deben tener labels de cost-center y team."
        pattern:
          metadata:
            labels:
              cost-center: "?*"
              team: "?*"

    - name: check-service-labels
      match:
        any:
          - resources:
              kinds:
                - Service
      validate:
        message: "Los Services deben tener labels de cost-center y team."
        pattern:
          metadata:
            labels:
              cost-center: "?*"
              team: "?*"
```

<br />

Con esta politica en su lugar, cualquier deployment sin labels de asignacion de costos es rechazado en el
momento de admision. Esto asegura 100% de cobertura de labels, lo que significa que tus reportes de costos
son precisos.

<br />

Para recursos cloud fuera de Kubernetes (buckets S3, instancias RDS, etc.), usa Terraform para aplicar tags:

<br />

```hcl
# terraform/provider.tf
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "production"
      Team        = "platform"
      Project     = "tr-blog"
      ManagedBy   = "terraform"
      CostCenter  = "engineering"
    }
  }
}
```

<br />

Una vez que el etiquetado es consistente, podes generar reportes de costos por equipo:

<br />

```yaml
# Consultar Kubecost por costo por label de equipo
curl -s "http://kubecost.kubecost.svc:9090/model/allocation?window=30d&aggregate=label:team" \
  | jq '.data[0] | to_entries[] | {
    team: .key,
    monthlyCost: (.value.totalCost | . * 100 | round / 100),
    cpuEfficiency: (.value.cpuEfficiency | . * 100 | round),
    ramEfficiency: (.value.ramEfficiency | . * 100 | round)
  }'

# Ejemplo de salida:
# { "team": "platform", "monthlyCost": 285.42, "cpuEfficiency": 45, "ramEfficiency": 52 }
# { "team": "backend", "monthlyCost": 156.78, "cpuEfficiency": 62, "ramEfficiency": 58 }
# { "team": "data", "monthlyCost": 412.33, "cpuEfficiency": 78, "ramEfficiency": 71 }
```

<br />

Estos datos hacen que las conversaciones de costos sean productivas. En vez de "necesitamos cortar costos,"
podes decir "el equipo de platform tiene 45% de eficiencia de CPU, hagamos right-size de esos workloads para
ahorrar un estimado de $128/mes."

<br />

##### **Notas finales**
La optimizacion de costos en la nube no es un proyecto de una sola vez. Es una practica continua que requiere
visibilidad, responsabilidad y mejora continua. La buena noticia es que como equipo de SRE, ya tenes la mayoria
de las habilidades y herramientas que necesitas. Sabes como medir cosas (SLIs), establecer objetivos (SLOs),
y automatizar respuestas (alertas y runbooks). Aplica esos mismos patrones al costo.

<br />

Empeza con las ganancias rapidas: corré el VPA en modo recomendacion y hace right-size de tus 10 workloads mas
sobre-aprovisionados. Instala OpenCost para tener visibilidad de a donde va tu plata. Configura una revision
semanal de costos junto con tu revision de SLOs. Despues gradualmente adopta instancias spot, storage tiering,
y alertas conscientes del costo.

<br />

El punto clave es que la confiabilidad y la eficiencia de costos no estan en conflicto. Con el enfoque correcto,
podes reducir el gasto mientras mantenes o incluso mejoras tus SLOs. Cada dolar ahorrado en sobre-aprovisionamiento
es un dolar que podes invertir en mejores herramientas, mas funcionalidades de confiabilidad, o tu equipo.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
