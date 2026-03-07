%{
  title: "SRE: Disaster Recovery and Business Continuity",
  author: "Gabriel Garrido",
  description: "We will explore disaster recovery planning for Kubernetes, from RPO and RTO targets to Velero backups, etcd recovery, multi-region strategies, DR drills, and runbooks for full cluster recovery...",
  tags: ~w(sre kubernetes disaster-recovery backup reliability),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Throughout this SRE series we have built a comprehensive toolkit for running reliable systems. We covered
[SLIs and SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[incident management](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observability](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[capacity planning](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[secrets management](/blog/sre-secrets-management-in-kubernetes),
[cost optimization](/blog/sre-cost-optimization-in-the-cloud),
[dependency management](/blog/sre-dependency-management-and-graceful-degradation),
[database reliability](/blog/sre-database-reliability),
[release engineering](/blog/sre-release-engineering-and-progressive-delivery), and
[security as code](/blog/sre-security-as-code). We have metrics, alerts, incident response, and chaos
experiments in place. But there is one question we have not fully addressed yet: what happens when
everything goes down at once?

<br />

"Hope is not a strategy" is a saying you hear often in SRE circles, and nowhere does it apply more than
in disaster recovery. A single availability zone going dark, a botched cluster upgrade, a ransomware
attack, or even an accidental `kubectl delete namespace production` can wipe out your entire workload. The
question is not if a disaster will happen, but when, and whether you will be ready for it.

<br />

In this article we will cover everything you need to build a solid disaster recovery (DR) and business
continuity plan for Kubernetes environments. We will go from defining RPO and RTO targets all the way to
Velero backups, etcd recovery, multi-region strategies, DR drills, communication plans, and step-by-step
runbooks for full cluster recovery.

<br />

Let's get into it.

<br />

##### **RPO and RTO: defining your recovery targets**
Before you can plan for disaster recovery, you need to answer two fundamental questions:

<br />

> * **RPO (Recovery Point Objective)**: How much data can you afford to lose? If your RPO is 1 hour, you need backups at least every hour. If your RPO is zero, you need synchronous replication.
> * **RTO (Recovery Time Objective)**: How long can your service be down? If your RTO is 15 minutes, you need automated failover. If your RTO is 4 hours, manual recovery might be acceptable.

<br />

These targets are not technical decisions, they are business decisions. You need to sit down with
stakeholders and understand the actual cost of downtime and data loss for each service. A payment
processing system has very different requirements than an internal wiki.

<br />

Here is a simple business impact analysis template to guide those conversations:

<br />

```hcl
# dr-plan/business-impact-analysis.yaml
services:
  - name: payment-api
    tier: critical
    rpo: "0 minutes"         # Zero data loss
    rto: "5 minutes"         # Automated failover required
    data_classification: pci
    revenue_impact_per_hour: "$50,000"
    dependencies:
      - postgresql-primary
      - redis-sessions
      - stripe-api
    backup_strategy: synchronous-replication
    failover_strategy: active-active

  - name: user-api
    tier: high
    rpo: "15 minutes"
    rto: "30 minutes"
    data_classification: pii
    revenue_impact_per_hour: "$10,000"
    dependencies:
      - postgresql-primary
      - redis-cache
    backup_strategy: streaming-replication
    failover_strategy: active-passive

  - name: blog
    tier: medium
    rpo: "24 hours"
    rto: "4 hours"
    data_classification: public
    revenue_impact_per_hour: "$0"
    dependencies:
      - postgresql-primary
    backup_strategy: daily-snapshots
    failover_strategy: rebuild-from-backup

  - name: internal-tools
    tier: low
    rpo: "24 hours"
    rto: "24 hours"
    data_classification: internal
    revenue_impact_per_hour: "$500"
    dependencies:
      - postgresql-primary
    backup_strategy: daily-snapshots
    failover_strategy: rebuild-from-backup
```

<br />

The key insight here is that not every service needs the same level of protection. Over-engineering DR for
a low-tier service wastes money, while under-engineering it for a critical service creates real risk.
Tier your services and plan accordingly.

<br />

##### **DR plan template**
Every organization needs a documented, tested, and regularly updated DR plan. Here is a structured template
that covers the essentials:

<br />

```hcl
# dr-plan/disaster-recovery-plan.yaml
metadata:
  version: "2.1"
  last_updated: "2026-03-15"
  next_review: "2026-06-15"
  owner: "platform-team"
  approver: "vp-engineering"

scope:
  environments:
    - production
    - staging
  regions:
    - primary: us-east-1
    - secondary: eu-west-1
  clusters:
    - prod-primary (us-east-1)
    - prod-secondary (eu-west-1)

roles_and_responsibilities:
  incident_commander:
    name: "Rotating on-call lead"
    responsibilities:
      - Declare disaster
      - Coordinate recovery
      - Authorize failover decisions
      - Communicate with leadership

  dr_lead:
    name: "Senior SRE on-call"
    responsibilities:
      - Execute recovery runbooks
      - Verify backup integrity
      - Coordinate infrastructure recovery
      - Run post-recovery validation

  communications_lead:
    name: "Engineering manager on-call"
    responsibilities:
      - Update status page
      - Notify customers
      - Coordinate with support team
      - Send internal updates

  database_lead:
    name: "DBA on-call"
    responsibilities:
      - Verify database backups
      - Execute database recovery
      - Validate data integrity
      - Monitor replication lag

activation_criteria:
  - "Complete loss of primary region availability"
  - "Primary Kubernetes cluster unrecoverable"
  - "Data corruption affecting critical services"
  - "Security breach requiring infrastructure rebuild"
  - "Cloud provider outage exceeding 30 minutes"

communication_channels:
  primary: "Slack #incident-war-room"
  secondary: "PagerDuty conference bridge"
  tertiary: "Personal phone numbers (see emergency contacts doc)"
  status_page: "https://status.example.com"

recovery_priority:
  - tier: 1
    services: [payment-api, auth-service]
    target_rto: "5 minutes"
    action: "Automated DNS failover to secondary region"
  - tier: 2
    services: [user-api, notification-service]
    target_rto: "30 minutes"
    action: "Restore from replica in secondary region"
  - tier: 3
    services: [blog, docs, internal-tools]
    target_rto: "4 hours"
    action: "Rebuild from backups and GitOps repo"
```

<br />

Notice that the plan has a version, an owner, and a scheduled review date. A DR plan that was written two
years ago and never updated is worse than no plan at all because it gives you false confidence. Review your
DR plan quarterly and update it every time your infrastructure changes.

<br />

##### **Velero for Kubernetes backup**
Velero is the standard tool for backing up Kubernetes resources and persistent volumes. It can back up your
entire cluster state (or specific namespaces) and restore it to the same or a different cluster.

<br />

Install Velero with the AWS plugin (works with S3-compatible storage including MinIO):

<br />

```hcl
# Install Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-arm64.tar.gz
tar -xvf velero-v1.13.0-linux-arm64.tar.gz
sudo mv velero-v1.13.0-linux-arm64/velero /usr/local/bin/

# Install Velero in the cluster
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=us-east-1,s3ForcePathStyle=true,s3Url=https://s3.us-east-1.amazonaws.com \
  --snapshot-location-config region=us-east-1 \
  --use-node-agent \
  --default-volumes-to-fs-backup
```

<br />

Now set up scheduled backups. The key is to have different backup schedules for different tiers of
services:

<br />

```yaml
# velero/backup-schedule-critical.yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: critical-services-hourly
  namespace: velero
spec:
  schedule: "0 * * * *"  # Every hour
  template:
    includedNamespaces:
      - payment-system
      - auth-system
    includedResources:
      - deployments
      - services
      - configmaps
      - secrets
      - persistentvolumeclaims
      - persistentvolumes
      - ingresses
      - horizontalpodautoscalers
    defaultVolumesToFsBackup: true
    storageLocation: default
    ttl: 168h  # Keep for 7 days
    metadata:
      labels:
        tier: critical
        backup-type: scheduled
```

<br />

```yaml
# velero/backup-schedule-standard.yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: standard-services-daily
  namespace: velero
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  template:
    includedNamespaces:
      - default
      - blog
      - monitoring
      - ingress-nginx
    excludedResources:
      - events
      - pods
    defaultVolumesToFsBackup: true
    storageLocation: default
    ttl: 720h  # Keep for 30 days
    metadata:
      labels:
        tier: standard
        backup-type: scheduled
```

<br />

```yaml
# velero/backup-schedule-full.yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: full-cluster-weekly
  namespace: velero
spec:
  schedule: "0 3 * * 0"  # Every Sunday at 3 AM
  template:
    includedNamespaces:
      - "*"
    excludedNamespaces:
      - velero
      - kube-system
    excludedResources:
      - events
      - pods
    defaultVolumesToFsBackup: true
    storageLocation: default
    ttl: 2160h  # Keep for 90 days
    metadata:
      labels:
        backup-type: full-cluster
```

<br />

To restore from a Velero backup, first check what backups are available:

<br />

```bash
# List available backups
velero backup get

# Describe a specific backup to see what it contains
velero backup describe critical-services-hourly-20260328120000

# Restore to a new namespace (for testing)
velero restore create test-restore \
  --from-backup critical-services-hourly-20260328120000 \
  --namespace-mappings payment-system:payment-system-restored

# Restore to the original namespace (for actual DR)
velero restore create dr-restore \
  --from-backup critical-services-hourly-20260328120000

# Check restore status
velero restore describe dr-restore
velero restore logs dr-restore
```

<br />

One critical thing people miss: you need to regularly test your backups by actually restoring them. A
backup that has never been tested is not a backup, it is a hope. Set up a weekly job that restores your
latest backup to a test namespace and validates the resources:

<br />

```yaml
# velero/backup-validation-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: validate-velero-backups
  namespace: velero
spec:
  schedule: "0 6 * * 1"  # Every Monday at 6 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: velero-validator
          containers:
            - name: validator
              image: bitnami/kubectl:1.29
              command:
                - /bin/bash
                - -c
                - |
                  set -euo pipefail

                  echo "=== Velero Backup Validation ==="
                  LATEST_BACKUP=$(velero backup get -o json | \
                    jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name')

                  echo "Latest backup: ${LATEST_BACKUP}"

                  # Create a test restore
                  velero restore create validation-${LATEST_BACKUP} \
                    --from-backup ${LATEST_BACKUP} \
                    --namespace-mappings default:validation-test

                  # Wait for restore to complete
                  sleep 120

                  # Check restore status
                  RESTORE_STATUS=$(velero restore get validation-${LATEST_BACKUP} -o json | \
                    jq -r '.status.phase')

                  if [ "$RESTORE_STATUS" = "Completed" ]; then
                    echo "PASS: Restore completed successfully"
                  else
                    echo "FAIL: Restore status is ${RESTORE_STATUS}"
                    # Send alert to PagerDuty or Slack
                    curl -X POST "$SLACK_WEBHOOK" \
                      -H 'Content-Type: application/json' \
                      -d "{\"text\": \"Velero backup validation FAILED for ${LATEST_BACKUP}\"}"
                  fi

                  # Clean up the test namespace
                  kubectl delete namespace validation-test --ignore-not-found=true
              env:
                - name: SLACK_WEBHOOK
                  valueFrom:
                    secretKeyRef:
                      name: slack-webhook
                      key: url
          restartPolicy: OnFailure
```

<br />

##### **etcd backup and restore**
etcd is the brain of your Kubernetes cluster. It stores all cluster state, including deployments, services,
secrets, configmaps, and RBAC policies. If you lose etcd and you do not have a backup, you lose your
entire cluster. Everything else can be rebuilt from GitOps, but etcd is the one piece that holds the live
state.

<br />

Here is a script for automated etcd snapshots:

<br />

```sql
#!/bin/bash
# etcd-backup.sh - Automated etcd snapshot backup
# Run this as a CronJob on one of the control plane nodes

set -euo pipefail

BACKUP_DIR="/var/backups/etcd"
S3_BUCKET="s3://etcd-backups-prod"
RETENTION_DAYS=30
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_FILE="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

echo "[$(date)] Starting etcd backup..."

# Take the snapshot
ETCDCTL_API=3 etcdctl snapshot save "${SNAPSHOT_FILE}" \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify the snapshot
ETCDCTL_API=3 etcdctl snapshot status "${SNAPSHOT_FILE}" \
  --write-out=table

# Get the snapshot size for logging
SNAPSHOT_SIZE=$(du -h "${SNAPSHOT_FILE}" | cut -f1)
echo "[$(date)] Snapshot created: ${SNAPSHOT_FILE} (${SNAPSHOT_SIZE})"

# Upload to S3
aws s3 cp "${SNAPSHOT_FILE}" \
  "${S3_BUCKET}/etcd-snapshot-${TIMESTAMP}.db" \
  --storage-class STANDARD_IA

echo "[$(date)] Snapshot uploaded to ${S3_BUCKET}"

# Calculate checksum and upload it alongside the snapshot
sha256sum "${SNAPSHOT_FILE}" > "${SNAPSHOT_FILE}.sha256"
aws s3 cp "${SNAPSHOT_FILE}.sha256" \
  "${S3_BUCKET}/etcd-snapshot-${TIMESTAMP}.db.sha256"

# Clean up old local backups
find "${BACKUP_DIR}" -name "etcd-snapshot-*.db" -mtime +${RETENTION_DAYS} -delete
find "${BACKUP_DIR}" -name "etcd-snapshot-*.sha256" -mtime +${RETENTION_DAYS} -delete

# Clean up old S3 backups using lifecycle policies
echo "[$(date)] etcd backup completed successfully"
```

<br />

Schedule this as a CronJob on your control plane:

<br />

```yaml
# etcd/backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-backup
  namespace: kube-system
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          nodeName: control-plane-1  # Pin to a control plane node
          hostNetwork: true
          containers:
            - name: etcd-backup
              image: registry.k8s.io/etcd:3.5.12-0
              command:
                - /bin/sh
                - /scripts/etcd-backup.sh
              volumeMounts:
                - name: etcd-certs
                  mountPath: /etc/kubernetes/pki/etcd
                  readOnly: true
                - name: backup-scripts
                  mountPath: /scripts
                - name: backup-storage
                  mountPath: /var/backups/etcd
          volumes:
            - name: etcd-certs
              hostPath:
                path: /etc/kubernetes/pki/etcd
            - name: backup-scripts
              configMap:
                name: etcd-backup-scripts
                defaultMode: 0755
            - name: backup-storage
              hostPath:
                path: /var/backups/etcd
          restartPolicy: OnFailure
          tolerations:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
              effect: NoSchedule
```

<br />

Now the critical part, restoring etcd. This is the procedure you follow when your cluster is completely
gone:

<br />

```hcl
#!/bin/bash
# etcd-restore.sh - Restore etcd from a snapshot
# WARNING: This replaces ALL cluster state. Only use during disaster recovery.

set -euo pipefail

SNAPSHOT_FILE="$1"
DATA_DIR="/var/lib/etcd-restored"

if [ -z "${SNAPSHOT_FILE}" ]; then
  echo "Usage: $0 <snapshot-file>"
  exit 1
fi

echo "WARNING: This will replace ALL etcd data!"
echo "Snapshot: ${SNAPSHOT_FILE}"
echo "Press Ctrl+C to abort, or wait 10 seconds to continue..."
sleep 10

# Stop the kubelet (which manages etcd as a static pod)
systemctl stop kubelet

# Stop etcd if running
crictl ps | grep etcd && crictl stop $(crictl ps -q --name etcd)

# Verify the snapshot integrity
echo "Verifying snapshot integrity..."
ETCDCTL_API=3 etcdctl snapshot status "${SNAPSHOT_FILE}" \
  --write-out=table

# Restore the snapshot to a new data directory
ETCDCTL_API=3 etcdctl snapshot restore "${SNAPSHOT_FILE}" \
  --data-dir="${DATA_DIR}" \
  --name=control-plane-1 \
  --initial-cluster=control-plane-1=https://10.0.1.10:2380 \
  --initial-cluster-token=etcd-cluster-1 \
  --initial-advertise-peer-urls=https://10.0.1.10:2380

# Back up the old data directory
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if [ -d /var/lib/etcd ]; then
  mv /var/lib/etcd "/var/lib/etcd-old-${TIMESTAMP}"
fi

# Move the restored data into place
mv "${DATA_DIR}" /var/lib/etcd

# Fix ownership
chown -R etcd:etcd /var/lib/etcd 2>/dev/null || true

# Start kubelet (which will start etcd as a static pod)
systemctl start kubelet

echo "Waiting for etcd to become healthy..."
for i in $(seq 1 60); do
  if ETCDCTL_API=3 etcdctl endpoint health \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key 2>/dev/null; then
    echo "etcd is healthy!"
    break
  fi
  echo "Waiting... ($i/60)"
  sleep 5
done

echo "etcd restore completed. Verify cluster state with: kubectl get nodes"
```

<br />

One important note about etcd restores: when you restore from a snapshot, you get the cluster state at the
time the snapshot was taken. Any resources created after the snapshot will be gone. This is why your RPO for
cluster state is determined by your etcd snapshot frequency. If you snapshot every 6 hours, your worst-case
data loss for cluster state is 6 hours of changes. However, if you are using GitOps (and you should be),
you can re-apply all your manifests from the Git repository to bring the cluster back to current state.

<br />

##### **Multi-region and multi-cluster strategies**
For services that need very low RTO, you need your workloads running in multiple regions or clusters
simultaneously. There are two main approaches:

<br />

**Active-Active**: Both regions serve traffic simultaneously. If one goes down, the other absorbs
all traffic. This gives you the lowest possible RTO (just the time for DNS or load balancer health checks
to detect the failure) but it is also the most complex to set up and operate.

<br />

**Active-Passive**: One region serves all traffic, the other is on standby. When the active region fails,
you failover to the passive region. This is simpler but has a longer RTO because you need to detect the
failure, make the failover decision, and potentially warm up the passive region.

<br />

Here is a DNS-based failover configuration using external-dns and health checks:

<br />

```yaml
# multi-region/dns-failover.yaml
# Primary region health check
apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: app-primary
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/aws-region: us-east-1
spec:
  endpoints:
    - dnsName: app.example.com
      recordTTL: 60
      recordType: A
      targets:
        - 10.0.1.100  # Primary region LB
      setIdentifier: primary
      providerSpecific:
        - name: aws/failover
          value: PRIMARY
        - name: aws/health-check-id
          value: "hc-primary-12345"

---
# Secondary region (failover target)
apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: app-secondary
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/aws-region: eu-west-1
spec:
  endpoints:
    - dnsName: app.example.com
      recordTTL: 60
      recordType: A
      targets:
        - 10.1.1.100  # Secondary region LB
      setIdentifier: secondary
      providerSpecific:
        - name: aws/failover
          value: SECONDARY
        - name: aws/health-check-id
          value: "hc-secondary-67890"
```

<br />

For multi-cluster management, here is a configuration sync setup using ArgoCD ApplicationSets:

<br />

```yaml
# multi-region/argocd-multi-cluster.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: critical-services
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: production
        values:
          region: "{{metadata.labels.region}}"
  template:
    metadata:
      name: "critical-services-{{name}}"
    spec:
      project: production
      source:
        repoURL: https://github.com/example/k8s-manifests
        targetRevision: main
        path: "clusters/{{values.region}}/critical-services"
      destination:
        server: "{{server}}"
        namespace: production
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

<br />

With this setup, ArgoCD automatically deploys your critical services to every production cluster. When you
add a new cluster, the services get deployed automatically. This is where GitOps really shines for DR: your
entire desired state is in Git, and ArgoCD ensures every cluster matches it.

<br />

##### **Database DR: cross-region PostgreSQL replication**
Databases are usually the hardest part of disaster recovery because they hold state. For PostgreSQL, here
is a setup using streaming replication with pgBackRest for cross-region backups:

<br />

```yaml
# database/postgresql-dr.yaml
# Primary PostgreSQL configuration for DR
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgresql-dr-config
  namespace: database
data:
  postgresql.conf: |
    # Replication settings for DR
    wal_level = replica
    max_wal_senders = 10
    wal_keep_size = 1024      # Keep 1GB of WAL for replication lag tolerance
    synchronous_commit = on
    synchronous_standby_names = 'standby_eu_west'

    # Archive settings for point-in-time recovery
    archive_mode = on
    archive_command = 'pgbackrest --stanza=main archive-push %p'
    archive_timeout = 60      # Archive at least every 60 seconds

  pg_hba.conf: |
    # Replication access from secondary region
    hostssl replication replicator 10.1.0.0/16 scram-sha-256
    hostssl replication replicator 10.0.0.0/16 scram-sha-256
    hostssl all all 10.0.0.0/8 scram-sha-256

  pgbackrest.conf: |
    [global]
    repo1-type=s3
    repo1-s3-bucket=pg-backups-primary
    repo1-s3-region=us-east-1
    repo1-s3-endpoint=s3.us-east-1.amazonaws.com
    repo1-retention-full=4
    repo1-retention-diff=14

    # Cross-region backup for DR
    repo2-type=s3
    repo2-s3-bucket=pg-backups-dr
    repo2-s3-region=eu-west-1
    repo2-s3-endpoint=s3.eu-west-1.amazonaws.com
    repo2-retention-full=4
    repo2-retention-diff=14

    [main]
    pg1-path=/var/lib/postgresql/data
```

<br />

And the backup schedule:

<br />

```yaml
# database/pgbackrest-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pgbackrest-full-backup
  namespace: database
spec:
  schedule: "0 1 * * 0"  # Full backup every Sunday at 1 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: pgbackrest/pgbackrest:2.50
              command:
                - /bin/bash
                - -c
                - |
                  echo "Starting full backup to both repos..."

                  # Backup to primary region
                  pgbackrest --stanza=main --type=full --repo=1 backup
                  echo "Primary region backup complete"

                  # Backup to DR region
                  pgbackrest --stanza=main --type=full --repo=2 backup
                  echo "DR region backup complete"

                  # Verify both backups
                  pgbackrest --stanza=main --repo=1 info
                  pgbackrest --stanza=main --repo=2 info
          restartPolicy: OnFailure

---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pgbackrest-diff-backup
  namespace: database
spec:
  schedule: "0 */4 * * *"  # Differential backup every 4 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: pgbackrest/pgbackrest:2.50
              command:
                - /bin/bash
                - -c
                - |
                  pgbackrest --stanza=main --type=diff --repo=1 backup
                  pgbackrest --stanza=main --type=diff --repo=2 backup
                  echo "Differential backups completed"
          restartPolicy: OnFailure
```

<br />

The restore procedure for PostgreSQL when your primary is gone:

<br />

```hcl
#!/bin/bash
# database/pg-dr-restore.sh
# Restore PostgreSQL from pgBackRest backup in DR region

set -euo pipefail

DR_REPO=2  # Use the DR region repository
TARGET_TIME="${1:-}"  # Optional: point-in-time recovery target

echo "=== PostgreSQL DR Restore ==="
echo "Using repository: repo${DR_REPO} (DR region)"

# List available backups
echo "Available backups:"
pgbackrest --stanza=main --repo=${DR_REPO} info

# Stop PostgreSQL if running
pg_ctl stop -D /var/lib/postgresql/data -m fast 2>/dev/null || true

# Clear the data directory
rm -rf /var/lib/postgresql/data/*

if [ -n "${TARGET_TIME}" ]; then
  echo "Restoring to point-in-time: ${TARGET_TIME}"
  pgbackrest --stanza=main --repo=${DR_REPO} \
    --type=time \
    --target="${TARGET_TIME}" \
    --target-action=promote \
    restore
else
  echo "Restoring latest backup..."
  pgbackrest --stanza=main --repo=${DR_REPO} \
    --type=default \
    restore
fi

# Start PostgreSQL
pg_ctl start -D /var/lib/postgresql/data

# Wait for recovery to complete
echo "Waiting for recovery..."
until pg_isready; do
  sleep 2
done

echo "PostgreSQL restored and ready"

# Verify data integrity
psql -c "SELECT count(*) as total_tables FROM information_schema.tables WHERE table_schema = 'public';"
psql -c "SELECT pg_size_pretty(pg_database_size(current_database())) as db_size;"
```

<br />

##### **DR testing and drills**
The best DR plan in the world is worthless if you have never tested it. DR drills are how you turn a
theoretical plan into a proven capability. There are three levels of DR testing:

<br />

> 1. **Tabletop exercises**: The team walks through the DR plan on paper. No actual systems are affected. This is good for finding gaps in documentation and communication plans.
> 2. **Component drills**: You test individual components of the plan, like restoring a Velero backup or failing over DNS. This validates that the tools and procedures work.
> 3. **Full DR simulation**: You simulate a complete disaster and execute the full recovery plan. This is the gold standard, and it is scary, which is exactly why you need to do it.

<br />

Here is a tabletop exercise template:

<br />

```hcl
# dr-drills/tabletop-exercise.yaml
exercise:
  name: "Q1 2026 DR Tabletop Exercise"
  date: "2026-03-20"
  duration: "2 hours"
  facilitator: "Senior SRE"
  participants:
    - platform-team
    - database-team
    - application-team
    - engineering-management

scenario:
  description: |
    At 2:30 AM on a Tuesday, the primary cloud region (us-east-1)
    experiences a complete outage. All services in the region are
    unreachable. The cloud provider estimates 4-6 hours for recovery.
    Your payment-api is processing $5,000 per hour in transactions.

  timeline:
    - time: "T+0"
      event: "PagerDuty fires alerts for all services in us-east-1"
      question: "Who gets paged? What is the escalation path?"

    - time: "T+5min"
      event: "On-call engineer confirms the region is down"
      question: "What is the first action? Who makes the failover decision?"

    - time: "T+10min"
      event: "Incident commander declares disaster, initiates DR plan"
      question: "What communication goes out? To whom? Through which channels?"

    - time: "T+15min"
      event: "DR lead begins failover procedure"
      question: "What are the exact steps? Walk through the runbook."

    - time: "T+30min"
      event: "DNS failover complete for tier-1 services"
      question: "How do you verify services are healthy in the DR region?"

    - time: "T+1hr"
      event: "Tier-2 services restored from replicas"
      question: "What data was lost? How do you reconcile?"

    - time: "T+4hr"
      event: "Primary region comes back online"
      question: "Do you fail back immediately? What is the failback procedure?"

  discussion_questions:
    - "Where are the gaps in our current DR plan?"
    - "Do we have all the access and credentials needed for DR?"
    - "What would happen if the person who knows how to do X is unavailable?"
    - "Are our backups actually restorable? When did we last test?"
    - "What is our communication plan for customers?"
```

<br />

For live DR drills, here is a structured approach:

<br />

```hcl
# dr-drills/live-drill-plan.yaml
drill:
  name: "Q1 2026 Live DR Drill"
  date: "2026-03-25"
  time: "10:00 AM - 2:00 PM"
  type: "component"  # Options: tabletop, component, full
  environment: "staging"  # Always start with staging

  pre_drill_checklist:
    - "All participants confirmed and available"
    - "Stakeholders notified about potential staging impact"
    - "Monitoring dashboards open for staging environment"
    - "Rollback procedures reviewed and ready"
    - "DR region/cluster verified accessible"
    - "Latest backups verified available"
    - "Communication channels tested"

  scenarios:
    - name: "Velero backup restore"
      objective: "Verify we can restore a namespace from Velero backup"
      steps:
        - "Delete the test-app namespace in staging"
        - "Restore from latest Velero backup"
        - "Verify all resources are recreated"
        - "Verify the application is functional"
      success_criteria:
        - "All deployments running with correct replica count"
        - "All services and ingresses recreated"
        - "Application responds to health checks"
        - "Persistent data is present and correct"
      max_duration: "30 minutes"

    - name: "etcd snapshot restore"
      objective: "Verify we can restore etcd from a snapshot"
      steps:
        - "Take a fresh etcd snapshot"
        - "Create some test resources (deployment, service, configmap)"
        - "Restore from the snapshot (before the test resources)"
        - "Verify test resources are gone (proving the restore worked)"
        - "Verify pre-existing resources are intact"
      success_criteria:
        - "etcd restore completes without errors"
        - "Cluster is functional after restore"
        - "Test resources are absent (proving point-in-time restore)"
      max_duration: "45 minutes"

    - name: "Database failover"
      objective: "Verify PostgreSQL failover to read replica"
      steps:
        - "Verify replication lag is zero"
        - "Simulate primary failure (stop primary pod)"
        - "Promote read replica to primary"
        - "Update application connection strings"
        - "Verify application writes succeed on new primary"
      success_criteria:
        - "Failover completes within RTO target"
        - "No data loss (RPO target met)"
        - "Application functions normally on new primary"
      max_duration: "30 minutes"

  post_drill:
    - "Restore staging to normal state"
    - "Document all findings"
    - "Create issues for any failures or gaps found"
    - "Update DR plan based on findings"
    - "Share results with the broader team"
    - "Schedule next drill"
```

<br />

You should also tie DR drills into your chaos engineering practice. A chaos experiment that simulates a zone
failure is essentially a lightweight DR drill. If you are already running chaos experiments regularly (as we
discussed in the [chaos engineering article](/blog/sre-chaos-engineering-breaking-things-on-purpose)), you
are building the muscle memory your team needs for real disasters.

<br />

##### **Runbook for full cluster recovery**
This is the big one: your cluster is gone and you need to rebuild from scratch. Here is a step-by-step
runbook that covers the full recovery process:

<br />

```hcl
# runbooks/full-cluster-recovery.yaml
runbook:
  name: "Full Kubernetes Cluster Recovery"
  version: "1.3"
  last_tested: "2026-03-15"
  estimated_time: "2-4 hours"
  prerequisites:
    - "Access to cloud provider console/CLI"
    - "Access to etcd backup storage (S3)"
    - "Access to Velero backup storage (S3)"
    - "Access to GitOps repository"
    - "Access to container registry"
    - "DNS management access"
    - "TLS certificates or cert-manager configuration"

  phases:
    - phase: 1
      name: "Infrastructure provisioning"
      estimated_time: "30-60 minutes"
      steps:
        - step: 1.1
          action: "Provision new compute nodes"
          command: |
            # Using Terraform (assuming state is in remote backend)
            cd infrastructure/terraform/kubernetes
            terraform plan -var="cluster_name=prod-recovery"
            terraform apply -auto-approve
          verification: |
            # Verify nodes are provisioned
            kubectl get nodes
            # Expected: all nodes in Ready state

        - step: 1.2
          action: "Verify networking"
          command: |
            # Check CNI is functional
            kubectl run nettest --image=busybox --rm -it -- nslookup kubernetes.default
            # Check external connectivity
            kubectl run nettest --image=busybox --rm -it -- wget -qO- https://hub.docker.com
          verification: "DNS resolution and external connectivity working"

        - step: 1.3
          action: "Verify storage provisioner"
          command: |
            kubectl get storageclass
            # Create a test PVC
            kubectl apply -f - <<EOF
            apiVersion: v1
            kind: PersistentVolumeClaim
            metadata:
              name: test-pvc
            spec:
              accessModes: [ReadWriteOnce]
              resources:
                requests:
                  storage: 1Gi
            EOF
            kubectl get pvc test-pvc
          verification: "PVC transitions to Bound state"

    - phase: 2
      name: "Core infrastructure recovery"
      estimated_time: "20-30 minutes"
      steps:
        - step: 2.1
          action: "Restore etcd from backup (if applicable)"
          command: |
            # Download latest snapshot from S3
            aws s3 cp s3://etcd-backups-prod/latest/etcd-snapshot.db /tmp/
            # Verify snapshot
            ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-snapshot.db
            # Restore (see etcd-restore.sh)
            bash /scripts/etcd-restore.sh /tmp/etcd-snapshot.db
          verification: "kubectl get nodes returns expected node list"

        - step: 2.2
          action: "Install ArgoCD"
          command: |
            kubectl create namespace argocd
            kubectl apply -n argocd -f \
              https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
            # Wait for ArgoCD to be ready
            kubectl wait --for=condition=available deployment/argocd-server \
              -n argocd --timeout=300s
            # Configure the GitOps repository
            argocd repo add https://github.com/example/k8s-manifests \
              --username git --password "${GIT_TOKEN}"
          verification: "ArgoCD UI accessible, repository connected"

        - step: 2.3
          action: "Deploy cert-manager"
          command: |
            helm repo add jetstack https://charts.jetstack.io
            helm install cert-manager jetstack/cert-manager \
              --namespace cert-manager --create-namespace \
              --set installCRDs=true
            # Apply ClusterIssuer
            kubectl apply -f manifests/cert-manager/cluster-issuer.yaml
          verification: "cert-manager pods running, ClusterIssuer ready"

        - step: 2.4
          action: "Deploy ingress controller"
          command: |
            helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
            helm install ingress-nginx ingress-nginx/ingress-nginx \
              --namespace ingress-nginx --create-namespace \
              --values manifests/ingress-nginx/values.yaml
          verification: "Ingress controller has external IP assigned"

    - phase: 3
      name: "Data recovery"
      estimated_time: "30-60 minutes"
      steps:
        - step: 3.1
          action: "Restore databases from backup"
          command: |
            # Deploy PostgreSQL operator
            kubectl apply -f manifests/database/operator.yaml
            # Wait for operator
            kubectl wait --for=condition=available deployment/postgres-operator \
              --timeout=300s
            # Restore from pgBackRest backup
            bash /scripts/pg-dr-restore.sh
          verification: |
            psql -c "SELECT count(*) FROM users;"
            # Compare with expected count from backup manifest

        - step: 3.2
          action: "Restore Velero and recover persistent volumes"
          command: |
            # Install Velero
            velero install --provider aws ...
            # Restore critical namespaces
            velero restore create dr-critical \
              --from-backup critical-services-hourly-latest
            # Verify restore
            velero restore describe dr-critical
          verification: "All PVCs bound, data verified"

    - phase: 4
      name: "Application recovery"
      estimated_time: "30-45 minutes"
      steps:
        - step: 4.1
          action: "Sync all ArgoCD applications"
          command: |
            # Apply the app-of-apps pattern
            kubectl apply -f manifests/argocd/app-of-apps.yaml
            # Force sync all applications
            argocd app sync --all --prune
            # Wait for all apps to be healthy
            argocd app wait --all --health --timeout 600
          verification: "All ArgoCD applications in Synced and Healthy state"

        - step: 4.2
          action: "Verify tier-1 services"
          command: |
            # Check payment-api
            curl -f https://payment-api.example.com/health
            # Check auth-service
            curl -f https://auth.example.com/health
            # Run integration tests against recovered services
            ./scripts/integration-tests.sh --target=production
          verification: "All health checks passing, integration tests green"

        - step: 4.3
          action: "Verify tier-2 and tier-3 services"
          command: |
            # Check all remaining services
            for svc in user-api notifications blog docs; do
              curl -f "https://${svc}.example.com/health" || echo "WARN: ${svc} not ready"
            done
          verification: "All services responding"

    - phase: 5
      name: "DNS and traffic cutover"
      estimated_time: "10-15 minutes"
      steps:
        - step: 5.1
          action: "Update DNS to point to recovered cluster"
          command: |
            # Update Route53 records
            aws route53 change-resource-record-sets \
              --hosted-zone-id Z1234567890 \
              --change-batch file://dns-changes.json

            # Verify DNS propagation
            for domain in app auth payment-api; do
              dig +short ${domain}.example.com
            done
          verification: "DNS resolving to new cluster IPs"

        - step: 5.2
          action: "Gradually increase traffic"
          command: |
            # If using weighted routing, gradually shift traffic
            # Start with 10%, then 50%, then 100%
            aws route53 change-resource-record-sets \
              --hosted-zone-id Z1234567890 \
              --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"app.example.com","Type":"A","SetIdentifier":"recovered","Weight":10,"TTL":60,"ResourceRecords":[{"Value":"NEW_IP"}]}}]}'
          verification: "Traffic flowing to recovered cluster, no errors"

    - phase: 6
      name: "Post-recovery validation"
      estimated_time: "30 minutes"
      steps:
        - step: 6.1
          action: "Run full smoke test suite"
          command: |
            ./scripts/smoke-tests.sh --environment=production
          verification: "All smoke tests passing"

        - step: 6.2
          action: "Verify monitoring and alerting"
          command: |
            # Check Prometheus is scraping
            curl -s http://prometheus:9090/api/v1/targets | jq '.data.activeTargets | length'
            # Verify Grafana dashboards
            curl -f http://grafana:3000/api/health
            # Check alert rules are loaded
            curl -s http://prometheus:9090/api/v1/rules | jq '.data.groups | length'
          verification: "Monitoring stack fully operational"

        - step: 6.3
          action: "Document recovery results"
          command: |
            # Create a post-recovery report
            echo "Recovery completed at: $(date)"
            echo "Total recovery time: X hours Y minutes"
            echo "Data loss window: etcd snapshot age + WAL gap"
            echo "Services recovered: all / partial"
            echo "Issues encountered: ..."
          verification: "Report shared with stakeholders"
```

<br />

The runbook is long, and it should be. Every step has a verification step because during a disaster, you
cannot afford to skip ahead and hope things work. Every step must be confirmed before moving to the next.

<br />

##### **Communication during disasters**
Communication is often the weakest link during a disaster. People are stressed, multiple teams are
involved, and customers are impacted. Having pre-written communication templates saves valuable time and
ensures nothing important gets missed.

<br />

Here is a set of communication templates:

<br />

```yaml
# communication/disaster-templates.yaml
templates:
  internal_declaration:
    channel: "#incident-war-room"
    template: |
      @here DISASTER DECLARED - DR Plan Activated

      What happened: [Brief description of the failure]
      Impact: [Which services are affected]
      Severity: [SEV-1]
      Incident Commander: [Name]
      DR Lead: [Name]
      Communications Lead: [Name]

      Current status: Executing DR plan phase 1 (infrastructure provisioning)
      Expected recovery time: [X hours based on RTO targets]

      War room: [Link to video call]
      Status page: https://status.example.com
      DR runbook: [Link to runbook]

      Updates will be posted every 15 minutes in this channel.

  customer_initial:
    channel: "status page"
    template: |
      Title: Service Disruption - [Affected Services]
      Status: Investigating

      We are currently experiencing a disruption affecting
      [list affected services]. Our team has been engaged and is
      actively working on recovery.

      We will provide an update within 30 minutes.

      Affected services:
      - [Service 1]: [Status]
      - [Service 2]: [Status]

  customer_update:
    channel: "status page"
    template: |
      Title: Service Disruption - Update
      Status: Identified / Recovering

      Update: We have identified the issue as [brief, non-technical
      description]. Our team is executing our disaster recovery plan.

      Current progress:
      - Infrastructure: [Restored / In progress]
      - Critical services: [Restored / In progress]
      - All services: [Restored / In progress]

      Estimated time to full recovery: [X hours]
      Next update: [Time]

  customer_resolved:
    channel: "status page"
    template: |
      Title: Service Disruption - Resolved
      Status: Resolved

      The service disruption that began at [start time] has been
      fully resolved as of [resolution time].

      Root cause: [Brief, non-technical description]
      Duration: [X hours Y minutes]
      Data impact: [None / Transactions between X and Y may need review]

      We will be publishing a detailed post-incident report within
      5 business days. We apologize for the disruption and are taking
      steps to prevent similar issues in the future.

  internal_update_cadence:
    description: "How often to post updates during DR"
    schedule:
      - phase: "First hour"
        frequency: "Every 15 minutes"
      - phase: "Hours 2-4"
        frequency: "Every 30 minutes"
      - phase: "After hour 4"
        frequency: "Every hour"
      - phase: "Post-recovery"
        frequency: "Final summary within 1 hour of resolution"
```

<br />

A few key points about disaster communication:

<br />

> * **Do not wait until you have all the answers to communicate**. "We are aware of the issue and investigating" is infinitely better than silence.
> * **Use pre-written templates**. During a disaster, your brain is not at its best. Templates prevent you from forgetting important details or saying the wrong thing.
> * **Separate internal and external communication**. Internal messages can be technical and detailed. External messages should be clear, non-technical, and empathetic.
> * **Set a cadence and stick to it**. Saying "next update in 30 minutes" and then going silent for 2 hours destroys trust. If you have nothing new to say, post "No significant change, still working on recovery."
> * **Assign a dedicated communications person**. The people doing the recovery should not also be writing status page updates. Split those responsibilities.

<br />

##### **Putting it all together: a DR maturity model**
Just like we discussed chaos engineering maturity levels in the [chaos engineering article](/blog/sre-chaos-engineering-breaking-things-on-purpose),
here is a maturity model for disaster recovery:

<br />

> 1. **Level 0 - Hope**: No DR plan, no backups, no idea what would happen. (Surprisingly common)
> 2. **Level 1 - Documented**: DR plan exists on paper but has never been tested. Backups exist but have never been restored.
> 3. **Level 2 - Tested components**: Individual DR components (backup restore, DNS failover) have been tested. Tabletop exercises completed.
> 4. **Level 3 - Drilled**: Full DR simulations have been run. The team has practiced the entire recovery process. RTO and RPO targets have been validated.
> 5. **Level 4 - Automated**: DR failover is automated and can be triggered with a single command. Regular automated DR tests validate the plan continuously.

<br />

Most teams are at Level 1 or Level 2. Getting to Level 3 is where the real confidence comes from. You do
not need full automation (Level 4) to be prepared, but you absolutely need to have practiced the process at
least once.

<br />

##### **Closing notes**
Disaster recovery is not glamorous work. Nobody gets excited about writing backup scripts and
communication templates. But when disaster strikes, and it will eventually, the difference between a team
that has practiced recovery and a team that has not is the difference between a few hours of downtime and
a catastrophic, company-threatening event.

<br />

The key takeaways from this article are:

<br />

> * **Define RPO and RTO targets** based on business impact, not technical convenience.
> * **Back up everything** and store backups in a different region than your primary infrastructure.
> * **Test your backups regularly**. A backup that has never been restored is not a backup.
> * **Write detailed runbooks** with verification steps for every action.
> * **Practice, practice, practice**. Run DR drills at least quarterly.
> * **Prepare communication templates** before you need them.

<br />

Start small. If you have no DR plan today, start by setting up Velero backups and etcd snapshots. Then
write a basic runbook. Then test it. Then iterate. Each step makes you more prepared than you were before,
and being slightly prepared is infinitely better than not being prepared at all.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "SRE: Recuperación ante Desastres y Continuidad del Negocio",
  author: "Gabriel Garrido",
  description: "Vamos a explorar la planificación de recuperación ante desastres para Kubernetes, desde objetivos de RPO y RTO hasta backups con Velero, recuperación de etcd, estrategias multi-región, simulacros de DR, y runbooks para recuperación completa del cluster...",
  tags: ~w(sre kubernetes disaster-recovery backup reliability),
  published: false,
  image: "sre.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
A lo largo de esta serie de SRE fuimos construyendo un conjunto completo de herramientas para correr
sistemas confiables. Cubrimos
[SLIs y SLOs](/blog/sre-slis-slos-and-automations-that-actually-help),
[gestión de incidentes](/blog/sre-incident-management-on-call-and-postmortems-as-code),
[observabilidad](/blog/sre-observability-deep-dive-traces-logs-and-metrics),
[chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose),
[planificación de capacidad](/blog/sre-capacity-planning-autoscaling-and-load-testing),
[GitOps](/blog/sre-gitops-with-argocd),
[gestión de secretos](/blog/sre-secrets-management-in-kubernetes),
[optimización de costos](/blog/sre-cost-optimization-in-the-cloud),
[gestión de dependencias](/blog/sre-dependency-management-and-graceful-degradation),
[confiabilidad de bases de datos](/blog/sre-database-reliability),
[ingeniería de releases](/blog/sre-release-engineering-and-progressive-delivery), y
[seguridad como código](/blog/sre-security-as-code). Tenemos métricas, alertas, respuesta a incidentes y
experimentos de caos funcionando. Pero hay una pregunta que todavía no abordamos del todo: ¿qué pasa cuando
todo se cae al mismo tiempo?

<br />

"La esperanza no es una estrategia" es una frase que se escucha seguido en círculos de SRE, y en ningún
lado aplica más que en recuperación ante desastres. Una sola zona de disponibilidad que se apaga, un
upgrade de cluster que sale mal, un ataque de ransomware, o incluso un
`kubectl delete namespace production` accidental puede borrar toda tu carga de trabajo. La pregunta no es
si un desastre va a pasar, sino cuándo, y si vas a estar preparado.

<br />

En este artículo vamos a cubrir todo lo que necesitás para armar un plan sólido de recuperación ante
desastres (DR) y continuidad del negocio para ambientes Kubernetes. Vamos desde definir objetivos de RPO y
RTO hasta backups con Velero, recuperación de etcd, estrategias multi-región, simulacros de DR, planes de
comunicación, y runbooks paso a paso para recuperación completa del cluster.

<br />

Vamos al tema.

<br />

##### **RPO y RTO: definiendo tus objetivos de recuperación**
Antes de poder planificar la recuperación ante desastres, necesitás responder dos preguntas fundamentales:

<br />

> * **RPO (Recovery Point Objective)**: ¿Cuántos datos podés permitirte perder? Si tu RPO es 1 hora, necesitás backups al menos cada hora. Si tu RPO es cero, necesitás replicación sincrónica.
> * **RTO (Recovery Time Objective)**: ¿Cuánto tiempo puede estar caído tu servicio? Si tu RTO es 15 minutos, necesitás failover automatizado. Si tu RTO es 4 horas, la recuperación manual puede ser aceptable.

<br />

Estos objetivos no son decisiones técnicas, son decisiones de negocio. Necesitás sentarte con los
stakeholders y entender el costo real del downtime y la pérdida de datos para cada servicio. Un sistema de
procesamiento de pagos tiene requerimientos muy distintos a una wiki interna.

<br />

Acá hay un template simple de análisis de impacto al negocio para guiar esas conversaciones:

<br />

```yaml
# dr-plan/business-impact-analysis.yaml
services:
  - name: payment-api
    tier: critical
    rpo: "0 minutos"          # Cero pérdida de datos
    rto: "5 minutos"          # Failover automatizado requerido
    data_classification: pci
    revenue_impact_per_hour: "$50,000"
    dependencies:
      - postgresql-primary
      - redis-sessions
      - stripe-api
    backup_strategy: synchronous-replication
    failover_strategy: active-active

  - name: user-api
    tier: high
    rpo: "15 minutos"
    rto: "30 minutos"
    data_classification: pii
    revenue_impact_per_hour: "$10,000"
    dependencies:
      - postgresql-primary
      - redis-cache
    backup_strategy: streaming-replication
    failover_strategy: active-passive

  - name: blog
    tier: medium
    rpo: "24 horas"
    rto: "4 horas"
    data_classification: public
    revenue_impact_per_hour: "$0"
    dependencies:
      - postgresql-primary
    backup_strategy: daily-snapshots
    failover_strategy: rebuild-from-backup

  - name: internal-tools
    tier: low
    rpo: "24 horas"
    rto: "24 horas"
    data_classification: internal
    revenue_impact_per_hour: "$500"
    dependencies:
      - postgresql-primary
    backup_strategy: daily-snapshots
    failover_strategy: rebuild-from-backup
```

<br />

Lo clave acá es que no todos los servicios necesitan el mismo nivel de protección. Sobre-ingeniar el DR
para un servicio de bajo nivel desperdicia plata, mientras que sub-ingeniarlo para un servicio crítico crea
riesgo real. Clasificá tus servicios en niveles y planificá en consecuencia.

<br />

##### **Template del plan de DR**
Toda organización necesita un plan de DR documentado, probado y actualizado regularmente. Acá hay un
template estructurado que cubre lo esencial:

<br />

```yaml
# dr-plan/disaster-recovery-plan.yaml
metadata:
  version: "2.1"
  last_updated: "2026-03-15"
  next_review: "2026-06-15"
  owner: "platform-team"
  approver: "vp-engineering"

scope:
  environments:
    - production
    - staging
  regions:
    - primary: us-east-1
    - secondary: eu-west-1
  clusters:
    - prod-primary (us-east-1)
    - prod-secondary (eu-west-1)

roles_and_responsibilities:
  incident_commander:
    name: "Líder de guardia rotativo"
    responsibilities:
      - Declarar desastre
      - Coordinar recuperación
      - Autorizar decisiones de failover
      - Comunicar con liderazgo

  dr_lead:
    name: "SRE senior de guardia"
    responsibilities:
      - Ejecutar runbooks de recuperación
      - Verificar integridad de backups
      - Coordinar recuperación de infraestructura
      - Correr validación post-recuperación

  communications_lead:
    name: "Engineering manager de guardia"
    responsibilities:
      - Actualizar la página de estado
      - Notificar a los clientes
      - Coordinar con el equipo de soporte
      - Enviar actualizaciones internas

  database_lead:
    name: "DBA de guardia"
    responsibilities:
      - Verificar backups de base de datos
      - Ejecutar recuperación de base de datos
      - Validar integridad de datos
      - Monitorear lag de replicación

activation_criteria:
  - "Pérdida completa de disponibilidad de la región primaria"
  - "Cluster de Kubernetes primario irrecuperable"
  - "Corrupción de datos que afecta servicios críticos"
  - "Brecha de seguridad que requiere reconstruir infraestructura"
  - "Caída del proveedor cloud por más de 30 minutos"

communication_channels:
  primary: "Slack #incident-war-room"
  secondary: "PagerDuty conference bridge"
  tertiary: "Números de teléfono personales (ver doc de contactos de emergencia)"
  status_page: "https://status.example.com"

recovery_priority:
  - tier: 1
    services: [payment-api, auth-service]
    target_rto: "5 minutos"
    action: "Failover DNS automatizado a región secundaria"
  - tier: 2
    services: [user-api, notification-service]
    target_rto: "30 minutos"
    action: "Restaurar desde réplica en región secundaria"
  - tier: 3
    services: [blog, docs, internal-tools]
    target_rto: "4 horas"
    action: "Reconstruir desde backups y repo de GitOps"
```

<br />

Notá que el plan tiene versión, dueño, y una fecha de revisión programada. Un plan de DR que se escribió
hace dos años y nunca se actualizó es peor que no tener plan porque te da falsa confianza. Revisá tu plan
de DR trimestralmente y actualizalo cada vez que tu infraestructura cambie.

<br />

##### **Velero para backup de Kubernetes**
Velero es la herramienta estándar para hacer backup de recursos de Kubernetes y volúmenes persistentes.
Puede hacer backup de todo el estado de tu cluster (o namespaces específicos) y restaurarlo en el mismo
cluster o en uno diferente.

<br />

Instalá Velero con el plugin de AWS (funciona con storage compatible con S3, incluyendo MinIO):

<br />

```hcl
# Instalar el CLI de Velero
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-arm64.tar.gz
tar -xvf velero-v1.13.0-linux-arm64.tar.gz
sudo mv velero-v1.13.0-linux-arm64/velero /usr/local/bin/

# Instalar Velero en el cluster
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=us-east-1,s3ForcePathStyle=true,s3Url=https://s3.us-east-1.amazonaws.com \
  --snapshot-location-config region=us-east-1 \
  --use-node-agent \
  --default-volumes-to-fs-backup
```

<br />

Ahora configurá backups programados. Lo clave es tener diferentes programaciones de backup para
diferentes niveles de servicios:

<br />

```yaml
# velero/backup-schedule-critical.yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: critical-services-hourly
  namespace: velero
spec:
  schedule: "0 * * * *"  # Cada hora
  template:
    includedNamespaces:
      - payment-system
      - auth-system
    includedResources:
      - deployments
      - services
      - configmaps
      - secrets
      - persistentvolumeclaims
      - persistentvolumes
      - ingresses
      - horizontalpodautoscalers
    defaultVolumesToFsBackup: true
    storageLocation: default
    ttl: 168h  # Mantener por 7 días
    metadata:
      labels:
        tier: critical
        backup-type: scheduled
```

<br />

```yaml
# velero/backup-schedule-standard.yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: standard-services-daily
  namespace: velero
spec:
  schedule: "0 2 * * *"  # Diario a las 2 AM
  template:
    includedNamespaces:
      - default
      - blog
      - monitoring
      - ingress-nginx
    excludedResources:
      - events
      - pods
    defaultVolumesToFsBackup: true
    storageLocation: default
    ttl: 720h  # Mantener por 30 días
    metadata:
      labels:
        tier: standard
        backup-type: scheduled
```

<br />

```yaml
# velero/backup-schedule-full.yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: full-cluster-weekly
  namespace: velero
spec:
  schedule: "0 3 * * 0"  # Cada domingo a las 3 AM
  template:
    includedNamespaces:
      - "*"
    excludedNamespaces:
      - velero
      - kube-system
    excludedResources:
      - events
      - pods
    defaultVolumesToFsBackup: true
    storageLocation: default
    ttl: 2160h  # Mantener por 90 días
    metadata:
      labels:
        backup-type: full-cluster
```

<br />

Para restaurar desde un backup de Velero, primero chequeá qué backups están disponibles:

<br />

```bash
# Listar backups disponibles
velero backup get

# Describir un backup específico para ver qué contiene
velero backup describe critical-services-hourly-20260328120000

# Restaurar a un namespace nuevo (para testing)
velero restore create test-restore \
  --from-backup critical-services-hourly-20260328120000 \
  --namespace-mappings payment-system:payment-system-restored

# Restaurar al namespace original (para DR real)
velero restore create dr-restore \
  --from-backup critical-services-hourly-20260328120000

# Verificar estado de la restauración
velero restore describe dr-restore
velero restore logs dr-restore
```

<br />

Algo crítico que mucha gente se pierde: necesitás probar regularmente tus backups restaurándolos. Un
backup que nunca se probó no es un backup, es una esperanza. Configurá un job semanal que restaure tu
último backup a un namespace de prueba y valide los recursos:

<br />

```yaml
# velero/backup-validation-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: validate-velero-backups
  namespace: velero
spec:
  schedule: "0 6 * * 1"  # Cada lunes a las 6 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: velero-validator
          containers:
            - name: validator
              image: bitnami/kubectl:1.29
              command:
                - /bin/bash
                - -c
                - |
                  set -euo pipefail

                  echo "=== Validación de Backup de Velero ==="
                  LATEST_BACKUP=$(velero backup get -o json | \
                    jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name')

                  echo "Último backup: ${LATEST_BACKUP}"

                  # Crear una restauración de prueba
                  velero restore create validation-${LATEST_BACKUP} \
                    --from-backup ${LATEST_BACKUP} \
                    --namespace-mappings default:validation-test

                  # Esperar a que complete la restauración
                  sleep 120

                  # Verificar estado de restauración
                  RESTORE_STATUS=$(velero restore get validation-${LATEST_BACKUP} -o json | \
                    jq -r '.status.phase')

                  if [ "$RESTORE_STATUS" = "Completed" ]; then
                    echo "PASS: Restauración completada exitosamente"
                  else
                    echo "FAIL: Estado de restauración es ${RESTORE_STATUS}"
                    # Enviar alerta a PagerDuty o Slack
                    curl -X POST "$SLACK_WEBHOOK" \
                      -H 'Content-Type: application/json' \
                      -d "{\"text\": \"Validación de backup de Velero FALLÓ para ${LATEST_BACKUP}\"}"
                  fi

                  # Limpiar el namespace de prueba
                  kubectl delete namespace validation-test --ignore-not-found=true
              env:
                - name: SLACK_WEBHOOK
                  valueFrom:
                    secretKeyRef:
                      name: slack-webhook
                      key: url
          restartPolicy: OnFailure
```

<br />

##### **Backup y restauración de etcd**
etcd es el cerebro de tu cluster de Kubernetes. Almacena todo el estado del cluster, incluyendo
deployments, services, secrets, configmaps y políticas RBAC. Si perdés etcd y no tenés un backup, perdés
todo tu cluster. Todo lo demás se puede reconstruir desde GitOps, pero etcd es la pieza que contiene el
estado en vivo.

<br />

Acá hay un script para snapshots automatizados de etcd:

<br />

```sql
#!/bin/bash
# etcd-backup.sh - Backup automatizado de snapshots de etcd
# Correr como CronJob en uno de los nodos del control plane

set -euo pipefail

BACKUP_DIR="/var/backups/etcd"
S3_BUCKET="s3://etcd-backups-prod"
RETENTION_DAYS=30
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_FILE="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"

# Crear directorio de backup
mkdir -p "${BACKUP_DIR}"

echo "[$(date)] Iniciando backup de etcd..."

# Tomar el snapshot
ETCDCTL_API=3 etcdctl snapshot save "${SNAPSHOT_FILE}" \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verificar el snapshot
ETCDCTL_API=3 etcdctl snapshot status "${SNAPSHOT_FILE}" \
  --write-out=table

# Obtener tamaño del snapshot para logging
SNAPSHOT_SIZE=$(du -h "${SNAPSHOT_FILE}" | cut -f1)
echo "[$(date)] Snapshot creado: ${SNAPSHOT_FILE} (${SNAPSHOT_SIZE})"

# Subir a S3
aws s3 cp "${SNAPSHOT_FILE}" \
  "${S3_BUCKET}/etcd-snapshot-${TIMESTAMP}.db" \
  --storage-class STANDARD_IA

echo "[$(date)] Snapshot subido a ${S3_BUCKET}"

# Calcular checksum y subirlo junto al snapshot
sha256sum "${SNAPSHOT_FILE}" > "${SNAPSHOT_FILE}.sha256"
aws s3 cp "${SNAPSHOT_FILE}.sha256" \
  "${S3_BUCKET}/etcd-snapshot-${TIMESTAMP}.db.sha256"

# Limpiar backups locales viejos
find "${BACKUP_DIR}" -name "etcd-snapshot-*.db" -mtime +${RETENTION_DAYS} -delete
find "${BACKUP_DIR}" -name "etcd-snapshot-*.sha256" -mtime +${RETENTION_DAYS} -delete

echo "[$(date)] Backup de etcd completado exitosamente"
```

<br />

Programá esto como un CronJob en tu control plane:

<br />

```yaml
# etcd/backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-backup
  namespace: kube-system
spec:
  schedule: "0 */6 * * *"  # Cada 6 horas
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          nodeName: control-plane-1  # Fijar a un nodo del control plane
          hostNetwork: true
          containers:
            - name: etcd-backup
              image: registry.k8s.io/etcd:3.5.12-0
              command:
                - /bin/sh
                - /scripts/etcd-backup.sh
              volumeMounts:
                - name: etcd-certs
                  mountPath: /etc/kubernetes/pki/etcd
                  readOnly: true
                - name: backup-scripts
                  mountPath: /scripts
                - name: backup-storage
                  mountPath: /var/backups/etcd
          volumes:
            - name: etcd-certs
              hostPath:
                path: /etc/kubernetes/pki/etcd
            - name: backup-scripts
              configMap:
                name: etcd-backup-scripts
                defaultMode: 0755
            - name: backup-storage
              hostPath:
                path: /var/backups/etcd
          restartPolicy: OnFailure
          tolerations:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
              effect: NoSchedule
```

<br />

Ahora la parte crítica, restaurar etcd. Este es el procedimiento que seguís cuando tu cluster se fue
por completo:

<br />

```bash
#!/bin/bash
# etcd-restore.sh - Restaurar etcd desde un snapshot
# ADVERTENCIA: Esto reemplaza TODO el estado del cluster. Solo usar durante DR.

set -euo pipefail

SNAPSHOT_FILE="$1"
DATA_DIR="/var/lib/etcd-restored"

if [ -z "${SNAPSHOT_FILE}" ]; then
  echo "Uso: $0 <archivo-snapshot>"
  exit 1
fi

echo "ADVERTENCIA: Esto va a reemplazar TODOS los datos de etcd!"
echo "Snapshot: ${SNAPSHOT_FILE}"
echo "Presioná Ctrl+C para abortar, o esperá 10 segundos para continuar..."
sleep 10

# Parar el kubelet (que maneja etcd como pod estático)
systemctl stop kubelet

# Parar etcd si está corriendo
crictl ps | grep etcd && crictl stop $(crictl ps -q --name etcd)

# Verificar la integridad del snapshot
echo "Verificando integridad del snapshot..."
ETCDCTL_API=3 etcdctl snapshot status "${SNAPSHOT_FILE}" \
  --write-out=table

# Restaurar el snapshot a un nuevo directorio de datos
ETCDCTL_API=3 etcdctl snapshot restore "${SNAPSHOT_FILE}" \
  --data-dir="${DATA_DIR}" \
  --name=control-plane-1 \
  --initial-cluster=control-plane-1=https://10.0.1.10:2380 \
  --initial-cluster-token=etcd-cluster-1 \
  --initial-advertise-peer-urls=https://10.0.1.10:2380

# Hacer backup del directorio de datos viejo
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if [ -d /var/lib/etcd ]; then
  mv /var/lib/etcd "/var/lib/etcd-old-${TIMESTAMP}"
fi

# Mover los datos restaurados a su lugar
mv "${DATA_DIR}" /var/lib/etcd

# Arreglar ownership
chown -R etcd:etcd /var/lib/etcd 2>/dev/null || true

# Iniciar kubelet (que va a iniciar etcd como pod estático)
systemctl start kubelet

echo "Esperando a que etcd esté saludable..."
for i in $(seq 1 60); do
  if ETCDCTL_API=3 etcdctl endpoint health \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key 2>/dev/null; then
    echo "etcd está saludable!"
    break
  fi
  echo "Esperando... ($i/60)"
  sleep 5
done

echo "Restauración de etcd completada. Verificá el estado del cluster con: kubectl get nodes"
```

<br />

Una nota importante sobre restauraciones de etcd: cuando restaurás desde un snapshot, obtenés el estado del
cluster en el momento en que se tomó el snapshot. Cualquier recurso creado después del snapshot se habrá
perdido. Por eso tu RPO para el estado del cluster está determinado por la frecuencia de snapshots de etcd.
Si hacés snapshots cada 6 horas, tu peor caso de pérdida de datos para estado del cluster es 6 horas de
cambios. Sin embargo, si estás usando GitOps (y deberías), podés re-aplicar todos tus manifiestos desde el
repositorio de Git para traer el cluster al estado actual.

<br />

##### **Estrategias multi-región y multi-cluster**
Para servicios que necesitan un RTO muy bajo, necesitás tus workloads corriendo en múltiples regiones o
clusters simultáneamente. Hay dos enfoques principales:

<br />

**Active-Active**: Ambas regiones sirven tráfico simultáneamente. Si una se cae, la otra absorbe todo el
tráfico. Esto te da el RTO más bajo posible (solo el tiempo para que los health checks de DNS o del load
balancer detecten la falla) pero también es lo más complejo de configurar y operar.

<br />

**Active-Passive**: Una región sirve todo el tráfico, la otra está en espera. Cuando la región activa
falla, hacés failover a la región pasiva. Esto es más simple pero tiene un RTO más largo porque necesitás
detectar la falla, tomar la decisión de failover, y potencialmente calentar la región pasiva.

<br />

Acá hay una configuración de failover basada en DNS usando external-dns y health checks:

<br />

```yaml
# multi-region/dns-failover.yaml
# Health check de la región primaria
apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: app-primary
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/aws-region: us-east-1
spec:
  endpoints:
    - dnsName: app.example.com
      recordTTL: 60
      recordType: A
      targets:
        - 10.0.1.100  # LB de la región primaria
      setIdentifier: primary
      providerSpecific:
        - name: aws/failover
          value: PRIMARY
        - name: aws/health-check-id
          value: "hc-primary-12345"

---
# Región secundaria (destino de failover)
apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: app-secondary
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/aws-region: eu-west-1
spec:
  endpoints:
    - dnsName: app.example.com
      recordTTL: 60
      recordType: A
      targets:
        - 10.1.1.100  # LB de la región secundaria
      setIdentifier: secondary
      providerSpecific:
        - name: aws/failover
          value: SECONDARY
        - name: aws/health-check-id
          value: "hc-secondary-67890"
```

<br />

Para gestión multi-cluster, acá hay una configuración de sync usando ApplicationSets de ArgoCD:

<br />

```yaml
# multi-region/argocd-multi-cluster.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: critical-services
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: production
        values:
          region: "{{metadata.labels.region}}"
  template:
    metadata:
      name: "critical-services-{{name}}"
    spec:
      project: production
      source:
        repoURL: https://github.com/example/k8s-manifests
        targetRevision: main
        path: "clusters/{{values.region}}/critical-services"
      destination:
        server: "{{server}}"
        namespace: production
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

<br />

Con este setup, ArgoCD automáticamente despliega tus servicios críticos en cada cluster de producción.
Cuando agregás un nuevo cluster, los servicios se despliegan automáticamente. Acá es donde GitOps realmente
brilla para DR: todo tu estado deseado está en Git, y ArgoCD se asegura de que cada cluster lo cumpla.

<br />

##### **DR de base de datos: replicación cross-region de PostgreSQL**
Las bases de datos son generalmente la parte más difícil de la recuperación ante desastres porque contienen
estado. Para PostgreSQL, acá hay un setup usando streaming replication con pgBackRest para backups
cross-region:

<br />

```yaml
# database/postgresql-dr.yaml
# Configuración del PostgreSQL primario para DR
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgresql-dr-config
  namespace: database
data:
  postgresql.conf: |
    # Configuración de replicación para DR
    wal_level = replica
    max_wal_senders = 10
    wal_keep_size = 1024      # Mantener 1GB de WAL para tolerancia de lag
    synchronous_commit = on
    synchronous_standby_names = 'standby_eu_west'

    # Configuración de archivado para point-in-time recovery
    archive_mode = on
    archive_command = 'pgbackrest --stanza=main archive-push %p'
    archive_timeout = 60      # Archivar al menos cada 60 segundos

  pg_hba.conf: |
    # Acceso de replicación desde la región secundaria
    hostssl replication replicator 10.1.0.0/16 scram-sha-256
    hostssl replication replicator 10.0.0.0/16 scram-sha-256
    hostssl all all 10.0.0.0/8 scram-sha-256

  pgbackrest.conf: |
    [global]
    repo1-type=s3
    repo1-s3-bucket=pg-backups-primary
    repo1-s3-region=us-east-1
    repo1-s3-endpoint=s3.us-east-1.amazonaws.com
    repo1-retention-full=4
    repo1-retention-diff=14

    # Backup cross-region para DR
    repo2-type=s3
    repo2-s3-bucket=pg-backups-dr
    repo2-s3-region=eu-west-1
    repo2-s3-endpoint=s3.eu-west-1.amazonaws.com
    repo2-retention-full=4
    repo2-retention-diff=14

    [main]
    pg1-path=/var/lib/postgresql/data
```

<br />

Y la programación de backups:

<br />

```yaml
# database/pgbackrest-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pgbackrest-full-backup
  namespace: database
spec:
  schedule: "0 1 * * 0"  # Backup completo cada domingo a la 1 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: pgbackrest/pgbackrest:2.50
              command:
                - /bin/bash
                - -c
                - |
                  echo "Iniciando backup completo a ambos repos..."

                  # Backup a la región primaria
                  pgbackrest --stanza=main --type=full --repo=1 backup
                  echo "Backup de región primaria completo"

                  # Backup a la región de DR
                  pgbackrest --stanza=main --type=full --repo=2 backup
                  echo "Backup de región DR completo"

                  # Verificar ambos backups
                  pgbackrest --stanza=main --repo=1 info
                  pgbackrest --stanza=main --repo=2 info
          restartPolicy: OnFailure

---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pgbackrest-diff-backup
  namespace: database
spec:
  schedule: "0 */4 * * *"  # Backup diferencial cada 4 horas
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: pgbackrest/pgbackrest:2.50
              command:
                - /bin/bash
                - -c
                - |
                  pgbackrest --stanza=main --type=diff --repo=1 backup
                  pgbackrest --stanza=main --type=diff --repo=2 backup
                  echo "Backups diferenciales completados"
          restartPolicy: OnFailure
```

<br />

El procedimiento de restauración para PostgreSQL cuando tu primario se fue:

<br />

```sql
#!/bin/bash
# database/pg-dr-restore.sh
# Restaurar PostgreSQL desde backup de pgBackRest en la región de DR

set -euo pipefail

DR_REPO=2  # Usar el repositorio de la región de DR
TARGET_TIME="${1:-}"  # Opcional: objetivo de point-in-time recovery

echo "=== Restauración DR de PostgreSQL ==="
echo "Usando repositorio: repo${DR_REPO} (región de DR)"

# Listar backups disponibles
echo "Backups disponibles:"
pgbackrest --stanza=main --repo=${DR_REPO} info

# Parar PostgreSQL si está corriendo
pg_ctl stop -D /var/lib/postgresql/data -m fast 2>/dev/null || true

# Limpiar el directorio de datos
rm -rf /var/lib/postgresql/data/*

if [ -n "${TARGET_TIME}" ]; then
  echo "Restaurando a point-in-time: ${TARGET_TIME}"
  pgbackrest --stanza=main --repo=${DR_REPO} \
    --type=time \
    --target="${TARGET_TIME}" \
    --target-action=promote \
    restore
else
  echo "Restaurando último backup..."
  pgbackrest --stanza=main --repo=${DR_REPO} \
    --type=default \
    restore
fi

# Iniciar PostgreSQL
pg_ctl start -D /var/lib/postgresql/data

# Esperar a que se complete la recuperación
echo "Esperando recuperación..."
until pg_isready; do
  sleep 2
done

echo "PostgreSQL restaurado y listo"

# Verificar integridad de datos
psql -c "SELECT count(*) as total_tables FROM information_schema.tables WHERE table_schema = 'public';"
psql -c "SELECT pg_size_pretty(pg_database_size(current_database())) as db_size;"
```

<br />

##### **Simulacros y pruebas de DR**
El mejor plan de DR del mundo no sirve de nada si nunca lo probaste. Los simulacros de DR son la forma en
que convertís un plan teórico en una capacidad comprobada. Hay tres niveles de pruebas de DR:

<br />

> 1. **Ejercicios de mesa (tabletop)**: El equipo recorre el plan de DR en papel. No se afectan sistemas reales. Esto es bueno para encontrar brechas en documentación y planes de comunicación.
> 2. **Pruebas de componentes**: Probás componentes individuales del plan, como restaurar un backup de Velero o hacer failover de DNS. Esto valida que las herramientas y procedimientos funcionan.
> 3. **Simulación completa de DR**: Simulás un desastre completo y ejecutás el plan de recuperación completo. Este es el estándar de oro, y da miedo, que es exactamente por lo que necesitás hacerlo.

<br />

Acá hay un template de ejercicio de mesa:

<br />

```yaml
# dr-drills/tabletop-exercise.yaml
exercise:
  name: "Ejercicio de Mesa DR Q1 2026"
  date: "2026-03-20"
  duration: "2 horas"
  facilitator: "SRE Senior"
  participants:
    - equipo-plataforma
    - equipo-base-de-datos
    - equipo-aplicaciones
    - gerencia-ingeniería

scenario:
  description: |
    A las 2:30 AM de un martes, la región primaria del cloud (us-east-1)
    experimenta una caída completa. Todos los servicios en la región están
    inaccesibles. El proveedor cloud estima 4-6 horas para la recuperación.
    Tu payment-api está procesando $5,000 por hora en transacciones.

  timeline:
    - time: "T+0"
      event: "PagerDuty dispara alertas para todos los servicios en us-east-1"
      question: "¿A quién se le envía la alerta? ¿Cuál es el path de escalación?"

    - time: "T+5min"
      event: "El ingeniero de guardia confirma que la región está caída"
      question: "¿Cuál es la primera acción? ¿Quién toma la decisión de failover?"

    - time: "T+10min"
      event: "El incident commander declara desastre, inicia el plan de DR"
      question: "¿Qué comunicación se envía? ¿A quién? ¿Por qué canales?"

    - time: "T+15min"
      event: "El líder de DR comienza el procedimiento de failover"
      question: "¿Cuáles son los pasos exactos? Recorré el runbook."

    - time: "T+30min"
      event: "Failover de DNS completo para servicios de tier-1"
      question: "¿Cómo verificás que los servicios están saludables en la región de DR?"

    - time: "T+1hr"
      event: "Servicios de tier-2 restaurados desde réplicas"
      question: "¿Qué datos se perdieron? ¿Cómo reconciliás?"

    - time: "T+4hr"
      event: "La región primaria vuelve en línea"
      question: "¿Hacés failback inmediatamente? ¿Cuál es el procedimiento de failback?"

  discussion_questions:
    - "¿Dónde están las brechas en nuestro plan de DR actual?"
    - "¿Tenemos todos los accesos y credenciales necesarios para DR?"
    - "¿Qué pasaría si la persona que sabe hacer X no está disponible?"
    - "¿Nuestros backups son realmente restaurables? ¿Cuándo fue la última vez que probamos?"
    - "¿Cuál es nuestro plan de comunicación para los clientes?"
```

<br />

Para simulacros de DR en vivo, acá hay un enfoque estructurado:

<br />

```yaml
# dr-drills/live-drill-plan.yaml
drill:
  name: "Simulacro DR en Vivo Q1 2026"
  date: "2026-03-25"
  time: "10:00 AM - 2:00 PM"
  type: "component"  # Opciones: tabletop, component, full
  environment: "staging"  # Siempre empezar con staging

  pre_drill_checklist:
    - "Todos los participantes confirmados y disponibles"
    - "Stakeholders notificados sobre potencial impacto en staging"
    - "Dashboards de monitoreo abiertos para ambiente de staging"
    - "Procedimientos de rollback revisados y listos"
    - "Región/cluster de DR verificado accesible"
    - "Últimos backups verificados disponibles"
    - "Canales de comunicación probados"

  scenarios:
    - name: "Restauración de backup de Velero"
      objective: "Verificar que podemos restaurar un namespace desde un backup de Velero"
      steps:
        - "Borrar el namespace test-app en staging"
        - "Restaurar desde el último backup de Velero"
        - "Verificar que todos los recursos se recrearon"
        - "Verificar que la aplicación es funcional"
      success_criteria:
        - "Todos los deployments corriendo con la cantidad correcta de réplicas"
        - "Todos los services e ingresses recreados"
        - "La aplicación responde a health checks"
        - "Los datos persistentes están presentes y correctos"
      max_duration: "30 minutos"

    - name: "Restauración de snapshot de etcd"
      objective: "Verificar que podemos restaurar etcd desde un snapshot"
      steps:
        - "Tomar un snapshot fresco de etcd"
        - "Crear algunos recursos de prueba (deployment, service, configmap)"
        - "Restaurar desde el snapshot (antes de los recursos de prueba)"
        - "Verificar que los recursos de prueba no están (probando que la restauración funcionó)"
        - "Verificar que los recursos pre-existentes están intactos"
      success_criteria:
        - "Restauración de etcd completa sin errores"
        - "Cluster funcional después de la restauración"
        - "Recursos de prueba ausentes (probando restauración point-in-time)"
      max_duration: "45 minutos"

    - name: "Failover de base de datos"
      objective: "Verificar failover de PostgreSQL a read replica"
      steps:
        - "Verificar que el lag de replicación es cero"
        - "Simular falla del primario (parar pod primario)"
        - "Promover read replica a primario"
        - "Actualizar connection strings de la aplicación"
        - "Verificar que las escrituras de la aplicación funcionan en el nuevo primario"
      success_criteria:
        - "Failover completo dentro del objetivo de RTO"
        - "Sin pérdida de datos (objetivo de RPO cumplido)"
        - "La aplicación funciona normalmente en el nuevo primario"
      max_duration: "30 minutos"

  post_drill:
    - "Restaurar staging al estado normal"
    - "Documentar todos los hallazgos"
    - "Crear issues para cualquier falla o brecha encontrada"
    - "Actualizar el plan de DR basado en los hallazgos"
    - "Compartir resultados con el equipo más amplio"
    - "Programar el próximo simulacro"
```

<br />

También deberías vincular los simulacros de DR con tu práctica de chaos engineering. Un experimento de caos
que simula una falla de zona es esencialmente un simulacro de DR liviano. Si ya estás corriendo experimentos
de caos regularmente (como discutimos en el
[artículo de chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose)), estás
construyendo la memoria muscular que tu equipo necesita para desastres reales.

<br />

##### **Runbook para recuperación completa del cluster**
Este es el grande: tu cluster se fue y necesitás reconstruir desde cero. Acá hay un runbook paso a paso que
cubre el proceso completo de recuperación:

<br />

```hcl
# runbooks/full-cluster-recovery.yaml
runbook:
  name: "Recuperación Completa del Cluster de Kubernetes"
  version: "1.3"
  last_tested: "2026-03-15"
  estimated_time: "2-4 horas"
  prerequisites:
    - "Acceso a la consola/CLI del proveedor cloud"
    - "Acceso al storage de backups de etcd (S3)"
    - "Acceso al storage de backups de Velero (S3)"
    - "Acceso al repositorio de GitOps"
    - "Acceso al registry de containers"
    - "Acceso a gestión de DNS"
    - "Certificados TLS o configuración de cert-manager"

  phases:
    - phase: 1
      name: "Provisión de infraestructura"
      estimated_time: "30-60 minutos"
      steps:
        - step: 1.1
          action: "Provisionar nuevos nodos de cómputo"
          command: |
            # Usando Terraform (asumiendo estado en backend remoto)
            cd infrastructure/terraform/kubernetes
            terraform plan -var="cluster_name=prod-recovery"
            terraform apply -auto-approve
          verification: |
            # Verificar que los nodos están provisionados
            kubectl get nodes
            # Esperado: todos los nodos en estado Ready

        - step: 1.2
          action: "Verificar networking"
          command: |
            # Verificar que el CNI es funcional
            kubectl run nettest --image=busybox --rm -it -- nslookup kubernetes.default
            # Verificar conectividad externa
            kubectl run nettest --image=busybox --rm -it -- wget -qO- https://hub.docker.com
          verification: "Resolución DNS y conectividad externa funcionando"

        - step: 1.3
          action: "Verificar provisioner de storage"
          command: |
            kubectl get storageclass
            # Crear un PVC de prueba
            kubectl apply -f - <<EOF
            apiVersion: v1
            kind: PersistentVolumeClaim
            metadata:
              name: test-pvc
            spec:
              accessModes: [ReadWriteOnce]
              resources:
                requests:
                  storage: 1Gi
            EOF
            kubectl get pvc test-pvc
          verification: "PVC transiciona a estado Bound"

    - phase: 2
      name: "Recuperación de infraestructura core"
      estimated_time: "20-30 minutos"
      steps:
        - step: 2.1
          action: "Restaurar etcd desde backup (si aplica)"
          command: |
            # Descargar último snapshot desde S3
            aws s3 cp s3://etcd-backups-prod/latest/etcd-snapshot.db /tmp/
            # Verificar snapshot
            ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-snapshot.db
            # Restaurar (ver etcd-restore.sh)
            bash /scripts/etcd-restore.sh /tmp/etcd-snapshot.db
          verification: "kubectl get nodes devuelve la lista esperada de nodos"

        - step: 2.2
          action: "Instalar ArgoCD"
          command: |
            kubectl create namespace argocd
            kubectl apply -n argocd -f \
              https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
            # Esperar a que ArgoCD esté listo
            kubectl wait --for=condition=available deployment/argocd-server \
              -n argocd --timeout=300s
            # Configurar el repositorio de GitOps
            argocd repo add https://github.com/example/k8s-manifests \
              --username git --password "${GIT_TOKEN}"
          verification: "UI de ArgoCD accesible, repositorio conectado"

        - step: 2.3
          action: "Desplegar cert-manager"
          command: |
            helm repo add jetstack https://charts.jetstack.io
            helm install cert-manager jetstack/cert-manager \
              --namespace cert-manager --create-namespace \
              --set installCRDs=true
            # Aplicar ClusterIssuer
            kubectl apply -f manifests/cert-manager/cluster-issuer.yaml
          verification: "Pods de cert-manager corriendo, ClusterIssuer listo"

        - step: 2.4
          action: "Desplegar ingress controller"
          command: |
            helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
            helm install ingress-nginx ingress-nginx/ingress-nginx \
              --namespace ingress-nginx --create-namespace \
              --values manifests/ingress-nginx/values.yaml
          verification: "Ingress controller tiene IP externa asignada"

    - phase: 3
      name: "Recuperación de datos"
      estimated_time: "30-60 minutos"
      steps:
        - step: 3.1
          action: "Restaurar bases de datos desde backup"
          command: |
            # Desplegar operador de PostgreSQL
            kubectl apply -f manifests/database/operator.yaml
            # Esperar al operador
            kubectl wait --for=condition=available deployment/postgres-operator \
              --timeout=300s
            # Restaurar desde backup de pgBackRest
            bash /scripts/pg-dr-restore.sh
          verification: |
            psql -c "SELECT count(*) FROM users;"
            # Comparar con el conteo esperado del manifiesto de backup

        - step: 3.2
          action: "Restaurar Velero y recuperar volúmenes persistentes"
          command: |
            # Instalar Velero
            velero install --provider aws ...
            # Restaurar namespaces críticos
            velero restore create dr-critical \
              --from-backup critical-services-hourly-latest
            # Verificar restauración
            velero restore describe dr-critical
          verification: "Todos los PVCs vinculados, datos verificados"

    - phase: 4
      name: "Recuperación de aplicaciones"
      estimated_time: "30-45 minutos"
      steps:
        - step: 4.1
          action: "Sincronizar todas las aplicaciones de ArgoCD"
          command: |
            # Aplicar el patrón app-of-apps
            kubectl apply -f manifests/argocd/app-of-apps.yaml
            # Forzar sync de todas las aplicaciones
            argocd app sync --all --prune
            # Esperar a que todas las apps estén saludables
            argocd app wait --all --health --timeout 600
          verification: "Todas las aplicaciones de ArgoCD en estado Synced y Healthy"

        - step: 4.2
          action: "Verificar servicios de tier-1"
          command: |
            # Verificar payment-api
            curl -f https://payment-api.example.com/health
            # Verificar auth-service
            curl -f https://auth.example.com/health
            # Correr tests de integración contra servicios recuperados
            ./scripts/integration-tests.sh --target=production
          verification: "Todos los health checks pasando, tests de integración verdes"

        - step: 4.3
          action: "Verificar servicios de tier-2 y tier-3"
          command: |
            # Verificar todos los servicios restantes
            for svc in user-api notifications blog docs; do
              curl -f "https://${svc}.example.com/health" || echo "WARN: ${svc} no está listo"
            done
          verification: "Todos los servicios respondiendo"

    - phase: 5
      name: "DNS y cutover de tráfico"
      estimated_time: "10-15 minutos"
      steps:
        - step: 5.1
          action: "Actualizar DNS para apuntar al cluster recuperado"
          command: |
            # Actualizar registros de Route53
            aws route53 change-resource-record-sets \
              --hosted-zone-id Z1234567890 \
              --change-batch file://dns-changes.json

            # Verificar propagación DNS
            for domain in app auth payment-api; do
              dig +short ${domain}.example.com
            done
          verification: "DNS resolviendo a las nuevas IPs del cluster"

        - step: 5.2
          action: "Aumentar tráfico gradualmente"
          command: |
            # Si usás weighted routing, mover tráfico gradualmente
            # Empezar con 10%, luego 50%, luego 100%
            aws route53 change-resource-record-sets \
              --hosted-zone-id Z1234567890 \
              --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"app.example.com","Type":"A","SetIdentifier":"recovered","Weight":10,"TTL":60,"ResourceRecords":[{"Value":"NEW_IP"}]}}]}'
          verification: "Tráfico fluyendo al cluster recuperado, sin errores"

    - phase: 6
      name: "Validación post-recuperación"
      estimated_time: "30 minutos"
      steps:
        - step: 6.1
          action: "Correr suite completa de smoke tests"
          command: |
            ./scripts/smoke-tests.sh --environment=production
          verification: "Todos los smoke tests pasando"

        - step: 6.2
          action: "Verificar monitoreo y alertas"
          command: |
            # Verificar que Prometheus está scrapeando
            curl -s http://prometheus:9090/api/v1/targets | jq '.data.activeTargets | length'
            # Verificar dashboards de Grafana
            curl -f http://grafana:3000/api/health
            # Verificar que las reglas de alertas están cargadas
            curl -s http://prometheus:9090/api/v1/rules | jq '.data.groups | length'
          verification: "Stack de monitoreo completamente operativo"

        - step: 6.3
          action: "Documentar resultados de la recuperación"
          command: |
            # Crear reporte post-recuperación
            echo "Recuperación completada a las: $(date)"
            echo "Tiempo total de recuperación: X horas Y minutos"
            echo "Ventana de pérdida de datos: edad del snapshot de etcd + gap de WAL"
            echo "Servicios recuperados: todos / parcial"
            echo "Problemas encontrados: ..."
          verification: "Reporte compartido con stakeholders"
```

<br />

El runbook es largo, y debería serlo. Cada paso tiene un paso de verificación porque durante un desastre,
no podés permitirte saltear pasos y esperar que las cosas funcionen. Cada paso debe confirmarse antes de
pasar al siguiente.

<br />

##### **Comunicación durante desastres**
La comunicación es frecuentemente el eslabón más débil durante un desastre. La gente está estresada,
múltiples equipos están involucrados, y los clientes están impactados. Tener templates de comunicación
pre-escritos ahorra tiempo valioso y asegura que no se pierda nada importante.

<br />

Acá hay un conjunto de templates de comunicación:

<br />

```yaml
# communication/disaster-templates.yaml
templates:
  internal_declaration:
    channel: "#incident-war-room"
    template: |
      @here DESASTRE DECLARADO - Plan de DR Activado

      Qué pasó: [Descripción breve de la falla]
      Impacto: [Qué servicios están afectados]
      Severidad: [SEV-1]
      Incident Commander: [Nombre]
      Líder de DR: [Nombre]
      Líder de Comunicaciones: [Nombre]

      Estado actual: Ejecutando plan de DR fase 1 (provisión de infraestructura)
      Tiempo estimado de recuperación: [X horas basado en objetivos de RTO]

      War room: [Link a videollamada]
      Página de estado: https://status.example.com
      Runbook de DR: [Link al runbook]

      Se publicarán actualizaciones cada 15 minutos en este canal.

  customer_initial:
    channel: "página de estado"
    template: |
      Título: Interrupción del Servicio - [Servicios Afectados]
      Estado: Investigando

      Actualmente estamos experimentando una interrupción que afecta a
      [listar servicios afectados]. Nuestro equipo fue convocado y está
      trabajando activamente en la recuperación.

      Proporcionaremos una actualización dentro de 30 minutos.

      Servicios afectados:
      - [Servicio 1]: [Estado]
      - [Servicio 2]: [Estado]

  customer_update:
    channel: "página de estado"
    template: |
      Título: Interrupción del Servicio - Actualización
      Estado: Identificado / Recuperando

      Actualización: Identificamos el problema como [descripción breve,
      no técnica]. Nuestro equipo está ejecutando nuestro plan de
      recuperación ante desastres.

      Progreso actual:
      - Infraestructura: [Restaurada / En progreso]
      - Servicios críticos: [Restaurados / En progreso]
      - Todos los servicios: [Restaurados / En progreso]

      Tiempo estimado para recuperación completa: [X horas]
      Próxima actualización: [Hora]

  customer_resolved:
    channel: "página de estado"
    template: |
      Título: Interrupción del Servicio - Resuelta
      Estado: Resuelto

      La interrupción del servicio que comenzó a las [hora de inicio]
      fue completamente resuelta a las [hora de resolución].

      Causa raíz: [Descripción breve, no técnica]
      Duración: [X horas Y minutos]
      Impacto en datos: [Ninguno / Las transacciones entre X e Y pueden
      necesitar revisión]

      Publicaremos un reporte post-incidente detallado dentro de
      5 días hábiles. Pedimos disculpas por la interrupción y estamos
      tomando medidas para prevenir problemas similares en el futuro.

  internal_update_cadence:
    description: "Cada cuánto publicar actualizaciones durante DR"
    schedule:
      - phase: "Primera hora"
        frequency: "Cada 15 minutos"
      - phase: "Horas 2-4"
        frequency: "Cada 30 minutos"
      - phase: "Después de la hora 4"
        frequency: "Cada hora"
      - phase: "Post-recuperación"
        frequency: "Resumen final dentro de 1 hora de la resolución"
```

<br />

Algunos puntos clave sobre la comunicación en desastres:

<br />

> * **No esperes a tener todas las respuestas para comunicar**. "Estamos al tanto del problema e investigando" es infinitamente mejor que el silencio.
> * **Usá templates pre-escritos**. Durante un desastre, tu cerebro no está en su mejor momento. Los templates previenen que te olvides de detalles importantes o digas algo incorrecto.
> * **Separá la comunicación interna de la externa**. Los mensajes internos pueden ser técnicos y detallados. Los mensajes externos deben ser claros, no técnicos y empáticos.
> * **Establecé una cadencia y respetala**. Decir "próxima actualización en 30 minutos" y después quedar en silencio por 2 horas destruye la confianza. Si no tenés nada nuevo que decir, publicá "Sin cambios significativos, seguimos trabajando en la recuperación."
> * **Asigná una persona dedicada a comunicaciones**. Las personas haciendo la recuperación no deberían también estar escribiendo actualizaciones de la página de estado. Separá esas responsabilidades.

<br />

##### **Juntando todo: un modelo de madurez de DR**
Al igual que discutimos niveles de madurez de chaos engineering en el
[artículo de chaos engineering](/blog/sre-chaos-engineering-breaking-things-on-purpose), acá hay un modelo
de madurez para recuperación ante desastres:

<br />

> 1. **Nivel 0 - Esperanza**: Sin plan de DR, sin backups, sin idea de qué pasaría. (Sorprendentemente común)
> 2. **Nivel 1 - Documentado**: El plan de DR existe en papel pero nunca se probó. Los backups existen pero nunca se restauraron.
> 3. **Nivel 2 - Componentes probados**: Componentes individuales de DR (restauración de backup, failover de DNS) fueron probados. Ejercicios de mesa completados.
> 4. **Nivel 3 - Simulado**: Se corrieron simulaciones completas de DR. El equipo practicó todo el proceso de recuperación. Los objetivos de RTO y RPO fueron validados.
> 5. **Nivel 4 - Automatizado**: El failover de DR está automatizado y se puede disparar con un solo comando. Tests automatizados regulares de DR validan el plan continuamente.

<br />

La mayoría de los equipos están en Nivel 1 o Nivel 2. Llegar al Nivel 3 es donde viene la confianza real.
No necesitás automatización completa (Nivel 4) para estar preparado, pero absolutamente necesitás haber
practicado el proceso al menos una vez.

<br />

##### **Notas finales**
La recuperación ante desastres no es un trabajo glamoroso. A nadie le emociona escribir scripts de backup
y templates de comunicación. Pero cuando el desastre llega, y eventualmente va a llegar, la diferencia
entre un equipo que practicó la recuperación y uno que no es la diferencia entre unas pocas horas de
downtime y un evento catastrófico que amenaza a la empresa.

<br />

Los puntos clave de este artículo son:

<br />

> * **Definí objetivos de RPO y RTO** basados en el impacto al negocio, no en la conveniencia técnica.
> * **Hacé backup de todo** y almacená los backups en una región diferente a tu infraestructura primaria.
> * **Probá tus backups regularmente**. Un backup que nunca se restauró no es un backup.
> * **Escribí runbooks detallados** con pasos de verificación para cada acción.
> * **Practicá, practicá, practicá**. Corré simulacros de DR al menos trimestralmente.
> * **Prepará templates de comunicación** antes de necesitarlos.

<br />

Empezá de a poco. Si hoy no tenés un plan de DR, empezá configurando backups de Velero y snapshots de etcd.
Después escribí un runbook básico. Después probalo. Después iterá. Cada paso te hace más preparado de lo
que estabas antes, y estar ligeramente preparado es infinitamente mejor que no estar preparado en absoluto.

<br />

¡Espero que te haya resultado útil y lo hayas disfrutado! ¡Hasta la próxima!

<br />

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje para que se corrija.

También podés revisar el código fuente y los cambios en las [fuentes acá](https://github.com/kainlite/tr)

<br />
