%{
  title: "DevOps from Zero to Hero: EKS, Running Kubernetes on AWS",
  author: "Gabriel Garrido",
  description: "We will provision an EKS cluster with Terraform, configure managed node groups and Karpenter, set up IRSA, install the AWS Load Balancer Controller, and deploy our TypeScript API...",
  tags: ~w(devops kubernetes aws eks terraform beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article thirteen of the DevOps from Zero to Hero series. In the previous article we
packaged our TypeScript API as a Helm chart. Now it is time to give that chart a real home on AWS
by provisioning an EKS cluster.

<br />

Amazon Elastic Kubernetes Service (EKS) is AWS's managed Kubernetes offering. You get a
production-grade control plane that AWS patches, scales, and keeps highly available. You only
worry about your workloads and the worker nodes that run them. If you have been following the
series, you already know how ECS works from article eight. EKS takes a different approach: instead
of a proprietary API, you get standard Kubernetes, which means everything you learned in articles
eleven and twelve (Kubernetes fundamentals and Helm) applies directly.

<br />

If you want to see how Kubernetes on AWS was done before EKS became the default, check out
[From zero to hero with kops and AWS](/blog/from_zero_to_hero_with_kops_and_aws). That article
covers kops, a tool that provisions self-managed clusters. EKS has since become the go-to choice
for most teams because it removes the burden of managing the control plane yourself.

<br />

In this article we will cover what EKS is, compare it with ECS, provision a full cluster with
Terraform, explore node group options, set up IAM Roles for Service Accounts, configure Karpenter
for autoscaling, install the AWS Load Balancer Controller, deploy our TypeScript API, and discuss
storage and cost considerations. Let's get into it.

<br />

##### **What is EKS?**
EKS gives you a managed Kubernetes control plane. That means AWS runs the API server, etcd, the
scheduler, and the controller manager for you. These components run across multiple availability
zones for high availability, and AWS handles upgrades, patches, and backups.

<br />

Your responsibilities are:

<br />

> * **Worker nodes**: You provision the EC2 instances (or Fargate profiles) where your pods run. AWS offers managed node groups that automate the lifecycle of these instances, but you still decide instance types, sizes, and scaling.
> * **Networking**: EKS integrates with your VPC. Pods get IP addresses from your VPC subnets using the VPC CNI plugin, which means they are first-class citizens on the network.
> * **Add-ons**: Things like the CoreDNS, kube-proxy, and the VPC CNI are installed by default, but you manage their versions and configuration.
> * **Workloads**: Everything you deploy, from Deployments to StatefulSets to CronJobs, is your responsibility.

<br />

The EKS control plane costs $0.10 per hour (about $73 per month). On top of that you pay for
whatever compute you use for worker nodes. This is important to keep in mind when we discuss cost
later.

<br />

##### **EKS vs ECS: when to use each**
Both EKS and ECS run containers on AWS, but they solve the problem differently. Here is how to
think about the choice:

<br />

> * **EKS** is standard Kubernetes. If your team already knows Kubernetes, if you need portability across clouds, or if you are running complex microservice architectures with custom operators, service meshes, or advanced scheduling, EKS is the right pick. The ecosystem is massive, and nearly every tool in the CNCF landscape works out of the box.
> * **ECS** is AWS-native. If your workloads are straightforward, if your team is small and does not want to learn Kubernetes, or if you want tight integration with AWS services without extra controllers, ECS is simpler and cheaper (no control plane fee). The Fargate launch type means you do not manage any infrastructure at all.

<br />

A practical rule of thumb: if you have fewer than five services and no requirement for multi-cloud,
start with ECS. If you have a growing platform team, need the Kubernetes ecosystem, or plan to run
on multiple providers, go with EKS.

<br />

For this series we are covering both because real teams encounter both. You already deployed to ECS
in article eight. Now you will see how EKS compares hands-on.

<br />

##### **Prerequisites**
Before we start, make sure you have the following installed:

<br />

```bash
# AWS CLI v2
aws --version

# Terraform
terraform --version

# kubectl
kubectl version --client

# Helm
helm version

# eksctl (optional but useful for debugging)
eksctl version
```

<br />

You also need an AWS account with permissions to create VPCs, EKS clusters, IAM roles, and EC2
instances. If you followed article six (AWS from scratch), you already have this set up.

<br />

##### **Provisioning the VPC with Terraform**
EKS clusters live inside a VPC. The VPC needs public subnets (for load balancers) and private
subnets (for worker nodes). Let's start with the network foundation.

<br />

Create a new Terraform project:

<br />

```bash
mkdir -p eks-cluster/terraform
cd eks-cluster/terraform
```

<br />

First, the provider and backend configuration:

<br />

```hcl
# providers.tf
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "alx-v/kubectl"
      version = "~> 2.1"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}
```

<br />

Now the variables:

<br />

```hcl
# variables.tf
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "devops-zero-to-hero"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
```

<br />

And the VPC using the official AWS module:

<br />

```hcl
# vpc.tf
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 52)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"         = var.cluster_name
  }

  tags = {
    Project     = "devops-zero-to-hero"
    Environment = "dev"
  }
}
```

<br />

A few things to note about the subnet tags:

<br />

> * **`kubernetes.io/role/elb`** on public subnets tells the AWS Load Balancer Controller where to place internet-facing ALBs.
> * **`kubernetes.io/role/internal-elb`** on private subnets is for internal load balancers.
> * **`karpenter.sh/discovery`** on private subnets lets Karpenter find subnets to launch nodes in.

<br />

We use a single NAT gateway to keep costs down for a dev environment. In production you would
want one per availability zone for redundancy.

<br />

##### **Provisioning the EKS cluster**
Now for the main event. We will use the official EKS Terraform module, which wraps a lot of
complexity into a clean interface:

<br />

```hcl
# eks.tf
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Cluster access
  cluster_endpoint_public_access = true

  # Cluster add-ons
  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Give the Terraform identity admin access to the cluster
  enable_cluster_creator_admin_permissions = true

  # Managed node groups
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]

      min_size     = 2
      max_size     = 5
      desired_size = 2

      labels = {
        role = "general"
      }

      tags = {
        "karpenter.sh/discovery" = var.cluster_name
      }
    }
  }

  tags = {
    Project     = "devops-zero-to-hero"
    Environment = "dev"
  }
}
```

<br />

This creates an EKS cluster with a managed node group of two `t3.medium` instances. Let's
break down what is happening:

<br />

> * **`cluster_endpoint_public_access`**: Makes the Kubernetes API reachable from the internet. For production you might restrict this to specific CIDR blocks or use a VPN.
> * **`cluster_addons`**: These are the essential EKS add-ons. CoreDNS handles service discovery, kube-proxy manages network rules, and vpc-cni gives pods VPC-native IP addresses.
> * **`enable_cluster_creator_admin_permissions`**: Grants the IAM identity that creates the cluster full admin access. Without this, you can lock yourself out.
> * **`eks_managed_node_groups`**: We define one node group with auto-scaling between 2 and 5 nodes.

<br />

##### **Node groups: understanding your options**
EKS gives you three ways to run your workloads. Each has trade-offs:

<br />

> * **Managed node groups**: AWS handles the EC2 instance lifecycle. You pick instance types and sizes, and AWS takes care of provisioning, draining, and updating nodes. This is the default choice for most teams. The example above uses managed node groups.
> * **Self-managed node groups**: You create and manage the EC2 instances yourself using Auto Scaling Groups. This gives you full control but more operational overhead. Use this only if you need custom AMIs, GPUs with specific drivers, or unusual instance configurations.
> * **Fargate profiles**: AWS runs your pods on serverless compute. No EC2 instances to manage at all. Each pod gets its own isolated micro-VM. This is great for batch jobs or workloads with unpredictable scaling, but it has limitations: no DaemonSets, no persistent volumes backed by EBS, and higher per-pod cost compared to well-utilized EC2 instances.

<br />

For most workloads, start with managed node groups. If you need more sophisticated scaling
(which we will set up shortly), add Karpenter on top.

<br />

##### **IAM Roles for Service Accounts (IRSA)**
This is one of the most important EKS concepts to understand. Your pods often need to talk to
AWS services: reading from S3, writing to DynamoDB, sending messages to SQS. The old approach
was to attach IAM policies to the node's instance profile, but that means every pod on that
node gets the same permissions. That is a security nightmare.

<br />

IRSA solves this by letting you map a Kubernetes ServiceAccount to a specific IAM role. Only
pods using that ServiceAccount get those permissions. Here is how it works under the hood:

<br />

```plaintext
Pod (with ServiceAccount annotation)
  --> Kubernetes mounts a projected token
    --> AWS STS validates the token via OIDC
      --> Pod assumes the IAM role
        --> Pod gets temporary AWS credentials
```

<br />

EKS creates an OpenID Connect (OIDC) provider for your cluster. When a pod starts, Kubernetes
injects a signed JWT token. AWS STS validates this token against the OIDC provider and issues
temporary credentials for the mapped IAM role. No long-lived credentials, no shared permissions.

<br />

Here is how to set up IRSA for a pod that needs S3 access:

<br />

```hcl
# irsa.tf

# The OIDC provider is created by the EKS module automatically
# We just need to create the IAM role and policy

module "s3_reader_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-s3-reader"

  role_policy_arns = {
    policy = aws_iam_policy.s3_read.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:s3-reader"]
    }
  }
}

resource "aws_iam_policy" "s3_read" {
  name        = "${var.cluster_name}-s3-read"
  description = "Allow reading from the application S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::my-app-bucket",
          "arn:aws:s3:::my-app-bucket/*"
        ]
      }
    ]
  })
}
```

<br />

Then in your Kubernetes manifest (or Helm values), you annotate the ServiceAccount:

<br />

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-reader
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/devops-zero-to-hero-s3-reader
```

<br />

Any pod using this ServiceAccount will automatically receive temporary AWS credentials scoped
to that IAM role. This is the right way to handle AWS permissions in EKS.

<br />

##### **Cluster autoscaler vs Karpenter**
When your workloads grow, you need more nodes. There are two main options for autoscaling nodes
in EKS:

<br />

> * **Cluster Autoscaler**: The traditional Kubernetes approach. It watches for pods that cannot be scheduled due to insufficient resources, then adds nodes from your existing node groups. It works, but it is limited by your pre-defined node group configurations. If you need a GPU instance but your node group only has `t3.medium`, you are stuck.
> * **Karpenter**: AWS's open-source node provisioner. Instead of scaling pre-defined node groups, Karpenter looks at pending pod requirements and provisions the right instance type on the fly. It can mix instance types, use Spot instances, and right-size nodes based on actual workload needs. It is faster, smarter, and more cost-effective.

<br />

For new clusters, Karpenter is the better choice. Let's set it up.

<br />

##### **Setting up Karpenter with Terraform**
Karpenter needs IAM permissions to launch EC2 instances and manage their lifecycle. The official
Karpenter module for Terraform makes this straightforward:

<br />

```hcl
# karpenter.tf
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = module.eks.cluster_name

  # Create the IAM role for the Karpenter controller
  enable_v1_permissions = true

  # Create the node IAM role that Karpenter-provisioned nodes will use
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Project     = "devops-zero-to-hero"
    Environment = "dev"
  }
}

# Install Karpenter using Helm
resource "helm_release" "karpenter" {
  namespace        = "kube-system"
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.1.1"
  wait             = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}
```

<br />

After Karpenter is installed, you need to define a `NodePool` and an `EC2NodeClass` that tell
Karpenter what kind of nodes to provision:

<br />

```yaml
# karpenter-nodepool.yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r", "t"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["4"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
  limits:
    cpu: "100"
    memory: 200Gi
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  role: "KarpenterNodeRole-devops-zero-to-hero"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: devops-zero-to-hero
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: devops-zero-to-hero
  tags:
    Project: devops-zero-to-hero
    ManagedBy: karpenter
```

<br />

Apply the Karpenter resources after the cluster is ready:

<br />

```bash
kubectl apply -f karpenter-nodepool.yaml
```

<br />

Here is what is happening in this configuration:

<br />

> * **NodePool**: Defines constraints for nodes. We allow both on-demand and spot instances, restrict to modern instance families (c, m, r, t with generation > 4), and set resource limits so Karpenter does not spin up unlimited compute.
> * **`expireAfter`**: Nodes are recycled after 30 days. This ensures they pick up the latest AMIs and security patches.
> * **`consolidationPolicy`**: Karpenter actively consolidates workloads. If nodes are empty or underutilized, it moves pods around and terminates the excess nodes to save cost.
> * **EC2NodeClass**: Defines AWS-specific settings like the AMI, IAM role, and subnet/security group selectors.

<br />

With Karpenter running, you can scale down your managed node group to just one or two nodes
for system workloads, and let Karpenter handle everything else dynamically.

<br />

##### **AWS Load Balancer Controller**
By default, Kubernetes services of type `LoadBalancer` create Classic Load Balancers on AWS.
These are outdated. The AWS Load Balancer Controller replaces that behavior with modern ALBs
(for HTTP/HTTPS) and NLBs (for TCP/UDP).

<br />

The controller watches for Ingress resources and Service annotations, then creates and
configures the corresponding AWS load balancers automatically. Let's install it:

<br />

```hcl
# alb-controller.tf
module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_lb_controller" {
  namespace  = "kube-system"
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.9.2"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lb_controller_irsa.iam_role_arn
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
}
```

<br />

Notice how we use IRSA here. The Load Balancer Controller needs permissions to create ALBs,
manage target groups, and read subnet tags. Instead of giving those permissions to the node,
we create a dedicated IAM role and bind it to the controller's ServiceAccount.

<br />

Once installed, you can create Ingress resources that automatically provision ALBs:

<br />

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: task-api
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123456789012:certificate/abc-123
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: task-api
                port:
                  number: 3000
```

<br />

The controller reads the annotations, creates an ALB in your public subnets, attaches the ACM
certificate for TLS, and routes traffic to your pods. You do not need to manage load balancers
manually anymore.

<br />

##### **Configuring kubeconfig**
After the cluster is provisioned, you need to configure kubectl to talk to it. The AWS CLI
makes this simple:

<br />

```bash
# Update your kubeconfig
aws eks update-kubeconfig --region us-east-1 --name devops-zero-to-hero

# Verify the connection
kubectl get nodes
```

<br />

You should see your managed node group instances:

<br />

```bash
NAME                             STATUS   ROLES    AGE   VERSION
ip-10-0-1-42.ec2.internal       Ready    <none>   5m    v1.31.2-eks-7f9249a
ip-10-0-2-87.ec2.internal       Ready    <none>   5m    v1.31.2-eks-7f9249a
```

<br />

If you work with multiple clusters, you can switch between them using contexts:

<br />

```bash
# List all contexts
kubectl config get-contexts

# Switch to a specific context
kubectl config use-context arn:aws:eks:us-east-1:123456789012:cluster/devops-zero-to-hero

# Rename a context for convenience
kubectl config rename-context \
  arn:aws:eks:us-east-1:123456789012:cluster/devops-zero-to-hero \
  eks-dev
```

<br />

##### **Deploying the TypeScript API to EKS**
Remember the Helm chart we built in article twelve? Now we put it to use. If you have your
chart in an OCI registry, the deployment is a single command:

<br />

```bash
# Create a namespace for the application
kubectl create namespace task-api

# Install the chart
helm install task-api oci://ghcr.io/your-org/charts/task-api \
  --version 0.1.0 \
  --namespace task-api \
  -f values-eks.yaml
```

<br />

Here is what the EKS-specific values file looks like:

<br />

```yaml
# values-eks.yaml
replicaCount: 2

image:
  repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api
  tag: "1.0.0"

service:
  type: ClusterIP
  port: 3000

ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123456789012:certificate/abc-123
    alb.ingress.kubernetes.io/healthcheck-path: /health
  hosts:
    - host: api.example.com
      paths:
        - path: /
          pathType: Prefix

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/task-api-role
```

<br />

After the deployment completes, you can check everything is running:

<br />

```bash
# Check the pods
kubectl get pods -n task-api
NAME                        READY   STATUS    RESTARTS   AGE
task-api-6d8f9c7b4a-k2m5n   1/1     Running   0          2m
task-api-6d8f9c7b4a-x9p3r   1/1     Running   0          2m

# Check the ingress (the ALB takes a minute or two to provision)
kubectl get ingress -n task-api
NAME       CLASS   HOSTS              ADDRESS                                      PORTS   AGE
task-api   alb     api.example.com    k8s-taskapi-xxxxx.us-east-1.elb.amazonaws.com   80      3m

# Test the endpoint
curl https://api.example.com/health
{"status": "ok"}
```

<br />

The AWS Load Balancer Controller sees the Ingress resource, creates an ALB, configures target
groups pointing to your pod IPs, and attaches the TLS certificate. Traffic flows from the
internet through the ALB directly to your pods.

<br />

##### **Storage: EBS CSI driver**
If your workloads need persistent storage (databases, caches, file uploads), you need the EBS
CSI driver. This driver allows Kubernetes PersistentVolumes to be backed by EBS volumes.

<br />

Add it as an EKS add-on in your Terraform:

<br />

```hcl
# Add to the cluster_addons in eks.tf
cluster_addons = {
  coredns                = {}
  eks-pod-identity-agent = {}
  kube-proxy             = {}
  vpc-cni                = {}
  aws-ebs-csi-driver = {
    service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
  }
}
```

<br />

```hcl
# ebs-csi.tf
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}
```

<br />

Then create a StorageClass and use it in your workloads:

<br />

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-volume
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 10Gi
```

<br />

The `WaitForFirstConsumer` binding mode is important. It delays volume creation until a pod
actually needs it, ensuring the volume is created in the same availability zone as the pod.
Without this, you can end up with a volume in one AZ and a pod that needs to run in another.

<br />

##### **Cost considerations**
EKS is not cheap, especially compared to ECS with Fargate for small workloads. Here is what you
are paying for:

<br />

> * **Control plane**: $0.10/hour ($73/month). This is fixed regardless of how many nodes you run.
> * **Worker nodes**: Standard EC2 pricing. A `t3.medium` (2 vCPU, 4 GB) runs about $30/month on-demand.
> * **Spot instances**: Up to 90% cheaper than on-demand, but can be interrupted. Karpenter makes using Spot easy by diversifying across instance types. Great for stateless workloads, not recommended for databases.
> * **NAT gateway**: $32/month plus data transfer. This is often the sneaky cost that surprises people. Use a single NAT gateway for dev, one per AZ for production.
> * **Load balancers**: ALBs cost about $16/month plus data transfer. Each Ingress resource can share a single ALB using IngressGroups to avoid provisioning one per service.
> * **Data transfer**: Inter-AZ traffic costs $0.01/GB each way. Cross-AZ pod-to-pod communication adds up in chatty microservice architectures.

<br />

Cost saving tips:

<br />

> * **Use Karpenter with Spot instances** for stateless workloads. Diversify across many instance types to reduce interruption rates.
> * **Right-size your nodes**. Karpenter helps here by picking the optimal instance type for your workload mix.
> * **Consolidate ALBs** using IngressGroup annotations so multiple services share one ALB.
> * **Use a single NAT gateway** for non-production environments.
> * **Set resource requests and limits** on every pod so Karpenter can bin-pack efficiently.
> * **Consider Savings Plans or Reserved Instances** for baseline capacity you know you will always need.

<br />

A minimal EKS dev environment (control plane + 2 `t3.medium` nodes + NAT gateway + ALB) costs
roughly $180/month. A production setup with more nodes, multi-AZ NAT, and monitoring will be
significantly more. Compare this to ECS with Fargate where you only pay for the compute your
containers actually use.

<br />

##### **Putting it all together**
Let's run through the full provisioning flow:

<br />

```bash
# Initialize Terraform
cd eks-cluster/terraform
terraform init

# Review the plan
terraform plan -out=tfplan

# Apply (this takes 15-20 minutes, mostly the EKS cluster creation)
terraform apply tfplan

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name devops-zero-to-hero

# Verify the cluster
kubectl get nodes
kubectl get pods -n kube-system

# Apply Karpenter resources
kubectl apply -f karpenter-nodepool.yaml

# Deploy the application
kubectl create namespace task-api
helm install task-api oci://ghcr.io/your-org/charts/task-api \
  --version 0.1.0 \
  --namespace task-api \
  -f values-eks.yaml

# Check everything is running
kubectl get all -n task-api
```

<br />

After about 20 minutes, you will have a fully functional EKS cluster with managed node groups,
Karpenter for dynamic scaling, the AWS Load Balancer Controller for automated ALB provisioning,
IRSA for secure pod-level AWS permissions, and the EBS CSI driver for persistent storage.

<br />

##### **Cleaning up**
If you are following along and do not want to keep the cluster running, tear it down:

<br />

```bash
# Remove application resources first
helm uninstall task-api -n task-api
kubectl delete -f karpenter-nodepool.yaml

# Destroy everything with Terraform
terraform destroy
```

<br />

Always remove Kubernetes resources before destroying the infrastructure. If you destroy the
VPC while ALBs still exist, Terraform will hang waiting for the load balancers to be deleted,
and you will have to clean them up manually in the AWS console.

<br />

##### **Closing notes**
EKS gives you the full power of Kubernetes without the operational burden of managing the control
plane. In this article we provisioned a complete cluster with Terraform, configured managed node
groups for baseline compute, set up Karpenter for intelligent autoscaling, used IRSA for secure
pod-level AWS permissions, installed the AWS Load Balancer Controller for automated ALB
management, and deployed our TypeScript API from the Helm chart we built in the previous article.

<br />

The trade-off compared to ECS is complexity and cost. EKS requires more infrastructure knowledge,
more moving parts, and a baseline cost even when nothing is running. But in return you get the
entire Kubernetes ecosystem, portability across clouds, and the ability to handle complex
workloads that would be difficult to model in ECS.

<br />

In the next article we will dive into monitoring and observability, because having a running
cluster is only the beginning. You need to know what is happening inside it.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: EKS, Corriendo Kubernetes en AWS",
  author: "Gabriel Garrido",
  description: "Vamos a provisionar un cluster EKS con Terraform, configurar managed node groups y Karpenter, configurar IRSA, instalar el AWS Load Balancer Controller, y deployear nuestra API TypeScript...",
  tags: ~w(devops kubernetes aws eks terraform beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo trece de la serie DevOps desde Cero. En el articulo anterior empaquetamos
nuestra API TypeScript como un Helm chart. Ahora es momento de darle a ese chart un hogar real
en AWS provisionando un cluster EKS.

<br />

Amazon Elastic Kubernetes Service (EKS) es la oferta de Kubernetes gestionado de AWS. Obtenes un
control plane de nivel produccion que AWS parchea, escala y mantiene altamente disponible. Vos
solo te preocupas por tus workloads y los worker nodes que los corren. Si veniste siguiendo la
serie, ya sabes como funciona ECS del articulo ocho. EKS toma un enfoque diferente: en vez de una
API propietaria, obtenes Kubernetes estandar, lo que significa que todo lo que aprendiste en los
articulos once y doce (fundamentos de Kubernetes y Helm) se aplica directamente.

<br />

Si queres ver como se hacia Kubernetes en AWS antes de que EKS se convirtiera en el default, mira
[From zero to hero with kops and AWS](/blog/from_zero_to_hero_with_kops_and_aws). Ese articulo
cubre kops, una herramienta que provisiona clusters autogestionados. EKS se convirtio desde
entonces en la opcion principal para la mayoria de los equipos porque te saca de encima la carga
de gestionar el control plane vos mismo.

<br />

En este articulo vamos a cubrir que es EKS, compararlo con ECS, provisionar un cluster completo
con Terraform, explorar las opciones de node groups, configurar IAM Roles for Service Accounts,
configurar Karpenter para autoscaling, instalar el AWS Load Balancer Controller, deployear nuestra
API TypeScript, y discutir storage y consideraciones de costo. Vamos a meterle.

<br />

##### **Que es EKS?**
EKS te da un control plane de Kubernetes gestionado. Eso significa que AWS corre el API server,
etcd, el scheduler, y el controller manager por vos. Estos componentes corren en multiples
availability zones para alta disponibilidad, y AWS se encarga de upgrades, parches y backups.

<br />

Tus responsabilidades son:

<br />

> * **Worker nodes**: Vos provisionas las instancias EC2 (o Fargate profiles) donde corren tus pods. AWS ofrece managed node groups que automatizan el ciclo de vida de estas instancias, pero vos seguis decidiendo tipos de instancia, tamanos y escalado.
> * **Networking**: EKS se integra con tu VPC. Los pods obtienen direcciones IP de las subnets de tu VPC usando el plugin VPC CNI, lo que significa que son ciudadanos de primera clase en la red.
> * **Add-ons**: Cosas como CoreDNS, kube-proxy, y el VPC CNI se instalan por defecto, pero vos gestionas sus versiones y configuracion.
> * **Workloads**: Todo lo que deployeas, desde Deployments hasta StatefulSets y CronJobs, es tu responsabilidad.

<br />

El control plane de EKS cuesta $0.10 por hora (aproximadamente $73 por mes). Ademas de eso pagas
por el compute que uses para worker nodes. Esto es importante tenerlo en cuenta cuando discutamos
costos mas adelante.

<br />

##### **EKS vs ECS: cuando usar cada uno**
Tanto EKS como ECS corren containers en AWS, pero resuelven el problema de manera diferente. Asi
es como pensar la eleccion:

<br />

> * **EKS** es Kubernetes estandar. Si tu equipo ya conoce Kubernetes, si necesitas portabilidad entre nubes, o si estas corriendo arquitecturas complejas de microservicios con operadores custom, service meshes, o scheduling avanzado, EKS es la eleccion correcta. El ecosistema es enorme, y casi todas las herramientas del landscape de CNCF funcionan out of the box.
> * **ECS** es nativo de AWS. Si tus workloads son sencillos, si tu equipo es chico y no quiere aprender Kubernetes, o si queres integracion estrecha con servicios de AWS sin controllers extra, ECS es mas simple y mas barato (sin costo de control plane). El tipo de lanzamiento Fargate significa que no gestionas infraestructura en absoluto.

<br />

Una regla practica: si tenes menos de cinco servicios y no tenes requerimiento de multi-cloud,
empeza con ECS. Si tenes un equipo de plataforma en crecimiento, necesitas el ecosistema
Kubernetes, o planeas correr en multiples proveedores, anda con EKS.

<br />

Para esta serie estamos cubriendo ambos porque los equipos reales se encuentran con los dos. Ya
deployeaste a ECS en el articulo ocho. Ahora vas a ver como se compara EKS de manera practica.

<br />

##### **Prerrequisitos**
Antes de empezar, asegurate de tener lo siguiente instalado:

<br />

```bash
# AWS CLI v2
aws --version

# Terraform
terraform --version

# kubectl
kubectl version --client

# Helm
helm version

# eksctl (opcional pero util para debugging)
eksctl version
```

<br />

Tambien necesitas una cuenta de AWS con permisos para crear VPCs, clusters EKS, roles IAM, e
instancias EC2. Si seguiste el articulo seis (AWS desde cero), ya tenes esto configurado.

<br />

##### **Provisionando la VPC con Terraform**
Los clusters EKS viven dentro de una VPC. La VPC necesita subnets publicas (para load balancers)
y subnets privadas (para worker nodes). Empecemos con la base de red.

<br />

Crea un nuevo proyecto de Terraform:

<br />

```bash
mkdir -p eks-cluster/terraform
cd eks-cluster/terraform
```

<br />

Primero, la configuracion del provider y backend:

<br />

```hcl
# providers.tf
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "alx-v/kubectl"
      version = "~> 2.1"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}
```

<br />

Ahora las variables:

<br />

```hcl
# variables.tf
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "devops-zero-to-hero"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
```

<br />

Y la VPC usando el modulo oficial de AWS:

<br />

```hcl
# vpc.tf
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 52)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"         = var.cluster_name
  }

  tags = {
    Project     = "devops-zero-to-hero"
    Environment = "dev"
  }
}
```

<br />

Algunas cosas a notar sobre los tags de las subnets:

<br />

> * **`kubernetes.io/role/elb`** en subnets publicas le dice al AWS Load Balancer Controller donde colocar ALBs con acceso a internet.
> * **`kubernetes.io/role/internal-elb`** en subnets privadas es para load balancers internos.
> * **`karpenter.sh/discovery`** en subnets privadas permite que Karpenter encuentre subnets para lanzar nodos.

<br />

Usamos un solo NAT gateway para mantener los costos bajos en un entorno de dev. En produccion
querrias uno por availability zone para redundancia.

<br />

##### **Provisionando el cluster EKS**
Ahora el evento principal. Vamos a usar el modulo oficial de EKS para Terraform, que envuelve
mucha complejidad en una interfaz limpia:

<br />

```hcl
# eks.tf
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Acceso al cluster
  cluster_endpoint_public_access = true

  # Add-ons del cluster
  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Dar acceso admin al identity de Terraform
  enable_cluster_creator_admin_permissions = true

  # Managed node groups
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]

      min_size     = 2
      max_size     = 5
      desired_size = 2

      labels = {
        role = "general"
      }

      tags = {
        "karpenter.sh/discovery" = var.cluster_name
      }
    }
  }

  tags = {
    Project     = "devops-zero-to-hero"
    Environment = "dev"
  }
}
```

<br />

Esto crea un cluster EKS con un managed node group de dos instancias `t3.medium`. Desglosemos
lo que esta pasando:

<br />

> * **`cluster_endpoint_public_access`**: Hace que la API de Kubernetes sea accesible desde internet. Para produccion podrias restringir esto a bloques CIDR especificos o usar una VPN.
> * **`cluster_addons`**: Estos son los add-ons esenciales de EKS. CoreDNS maneja service discovery, kube-proxy gestiona reglas de red, y vpc-cni les da a los pods direcciones IP nativas de la VPC.
> * **`enable_cluster_creator_admin_permissions`**: Otorga acceso admin completo al identity de IAM que crea el cluster. Sin esto, podes quedar bloqueado.
> * **`eks_managed_node_groups`**: Definimos un node group con auto-scaling entre 2 y 5 nodos.

<br />

##### **Node groups: entendiendo tus opciones**
EKS te da tres formas de correr tus workloads. Cada una tiene sus trade-offs:

<br />

> * **Managed node groups**: AWS maneja el ciclo de vida de las instancias EC2. Vos elegis tipos de instancia y tamanos, y AWS se encarga de provisionar, drenar, y actualizar nodos. Esta es la opcion default para la mayoria de los equipos. El ejemplo de arriba usa managed node groups.
> * **Self-managed node groups**: Vos creas y gestionas las instancias EC2 usando Auto Scaling Groups. Esto te da control total pero mas overhead operacional. Usa esto solo si necesitas AMIs custom, GPUs con drivers especificos, o configuraciones de instancia inusuales.
> * **Fargate profiles**: AWS corre tus pods en compute serverless. Nada de instancias EC2 que gestionar. Cada pod tiene su propia micro-VM aislada. Esto esta genial para batch jobs o workloads con escalado impredecible, pero tiene limitaciones: nada de DaemonSets, nada de persistent volumes respaldados por EBS, y mayor costo por pod comparado con instancias EC2 bien utilizadas.

<br />

Para la mayoria de los workloads, empeza con managed node groups. Si necesitas escalado mas
sofisticado (que vamos a configurar en un rato), agrega Karpenter encima.

<br />

##### **IAM Roles for Service Accounts (IRSA)**
Este es uno de los conceptos mas importantes de EKS para entender. Tus pods muchas veces necesitan
hablar con servicios de AWS: leer de S3, escribir en DynamoDB, enviar mensajes a SQS. El enfoque
viejo era adjuntar politicas IAM al instance profile del nodo, pero eso significa que cada pod en
ese nodo obtiene los mismos permisos. Eso es una pesadilla de seguridad.

<br />

IRSA resuelve esto permitiendote mapear un ServiceAccount de Kubernetes a un rol IAM especifico.
Solo los pods que usan ese ServiceAccount obtienen esos permisos. Asi funciona internamente:

<br />

```plaintext
Pod (con anotacion de ServiceAccount)
  --> Kubernetes monta un token proyectado
    --> AWS STS valida el token via OIDC
      --> El pod asume el rol IAM
        --> El pod obtiene credenciales temporales de AWS
```

<br />

EKS crea un proveedor OpenID Connect (OIDC) para tu cluster. Cuando un pod arranca, Kubernetes
inyecta un token JWT firmado. AWS STS valida este token contra el proveedor OIDC y emite
credenciales temporales para el rol IAM mapeado. Sin credenciales de larga duracion, sin
permisos compartidos.

<br />

Asi es como configuras IRSA para un pod que necesita acceso a S3:

<br />

```hcl
# irsa.tf

# El proveedor OIDC lo crea el modulo EKS automaticamente
# Solo necesitamos crear el rol IAM y la politica

module "s3_reader_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-s3-reader"

  role_policy_arns = {
    policy = aws_iam_policy.s3_read.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:s3-reader"]
    }
  }
}

resource "aws_iam_policy" "s3_read" {
  name        = "${var.cluster_name}-s3-read"
  description = "Allow reading from the application S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::my-app-bucket",
          "arn:aws:s3:::my-app-bucket/*"
        ]
      }
    ]
  })
}
```

<br />

Despues en tu manifiesto de Kubernetes (o en los values de Helm), anotas el ServiceAccount:

<br />

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-reader
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/devops-zero-to-hero-s3-reader
```

<br />

Cualquier pod que use este ServiceAccount va a recibir automaticamente credenciales temporales
de AWS con el scope de ese rol IAM. Esta es la forma correcta de manejar permisos de AWS en EKS.

<br />

##### **Cluster autoscaler vs Karpenter**
Cuando tus workloads crecen, necesitas mas nodos. Hay dos opciones principales para autoscaling
de nodos en EKS:

<br />

> * **Cluster Autoscaler**: El enfoque tradicional de Kubernetes. Observa pods que no se pueden schedulear por recursos insuficientes, y despues agrega nodos de tus node groups existentes. Funciona, pero esta limitado por las configuraciones pre-definidas de tus node groups. Si necesitas una instancia con GPU pero tu node group solo tiene `t3.medium`, quedaste.
> * **Karpenter**: El provisionador de nodos open-source de AWS. En vez de escalar node groups pre-definidos, Karpenter mira los requerimientos de los pods pendientes y provisiona el tipo de instancia correcto sobre la marcha. Puede mezclar tipos de instancia, usar instancias Spot, y dimensionar los nodos basado en las necesidades reales del workload. Es mas rapido, mas inteligente, y mas costo-efectivo.

<br />

Para clusters nuevos, Karpenter es la mejor opcion. Vamos a configurarlo.

<br />

##### **Configurando Karpenter con Terraform**
Karpenter necesita permisos IAM para lanzar instancias EC2 y gestionar su ciclo de vida. El
modulo oficial de Karpenter para Terraform lo hace bastante directo:

<br />

```hcl
# karpenter.tf
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = module.eks.cluster_name

  # Crear el rol IAM para el controller de Karpenter
  enable_v1_permissions = true

  # Crear el rol IAM del nodo que los nodos provisionados por Karpenter van a usar
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Project     = "devops-zero-to-hero"
    Environment = "dev"
  }
}

# Instalar Karpenter usando Helm
resource "helm_release" "karpenter" {
  namespace        = "kube-system"
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.1.1"
  wait             = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}
```

<br />

Despues de instalar Karpenter, necesitas definir un `NodePool` y un `EC2NodeClass` que le digan
a Karpenter que tipo de nodos provisionar:

<br />

```yaml
# karpenter-nodepool.yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r", "t"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["4"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
  limits:
    cpu: "100"
    memory: 200Gi
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  role: "KarpenterNodeRole-devops-zero-to-hero"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: devops-zero-to-hero
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: devops-zero-to-hero
  tags:
    Project: devops-zero-to-hero
    ManagedBy: karpenter
```

<br />

Aplica los recursos de Karpenter despues de que el cluster este listo:

<br />

```bash
kubectl apply -f karpenter-nodepool.yaml
```

<br />

Esto es lo que pasa en esta configuracion:

<br />

> * **NodePool**: Define restricciones para los nodos. Permitimos instancias tanto on-demand como spot, restringimos a familias de instancias modernas (c, m, r, t con generacion > 4), y ponemos limites de recursos para que Karpenter no levante compute ilimitado.
> * **`expireAfter`**: Los nodos se reciclan despues de 30 dias. Esto asegura que agarren las ultimas AMIs y parches de seguridad.
> * **`consolidationPolicy`**: Karpenter consolida workloads activamente. Si los nodos estan vacios o subutilizados, mueve pods y termina los nodos sobrantes para ahorrar costo.
> * **EC2NodeClass**: Define configuraciones especificas de AWS como la AMI, el rol IAM, y los selectores de subnets/security groups.

<br />

Con Karpenter corriendo, podes bajar tu managed node group a solo uno o dos nodos para workloads
de sistema, y dejar que Karpenter maneje todo lo demas dinamicamente.

<br />

##### **AWS Load Balancer Controller**
Por defecto, los servicios de Kubernetes de tipo `LoadBalancer` crean Classic Load Balancers en
AWS. Estos estan desactualizados. El AWS Load Balancer Controller reemplaza ese comportamiento
con ALBs modernos (para HTTP/HTTPS) y NLBs (para TCP/UDP).

<br />

El controller observa recursos Ingress y anotaciones de Service, y despues crea y configura los
load balancers de AWS correspondientes automaticamente. Vamos a instalarlo:

<br />

```hcl
# alb-controller.tf
module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_lb_controller" {
  namespace  = "kube-system"
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.9.2"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lb_controller_irsa.iam_role_arn
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
}
```

<br />

Fijate como usamos IRSA aca. El Load Balancer Controller necesita permisos para crear ALBs,
gestionar target groups, y leer tags de subnets. En vez de darle esos permisos al nodo,
creamos un rol IAM dedicado y lo vinculamos al ServiceAccount del controller.

<br />

Una vez instalado, podes crear recursos Ingress que provisionen ALBs automaticamente:

<br />

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: task-api
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123456789012:certificate/abc-123
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: task-api
                port:
                  number: 3000
```

<br />

El controller lee las anotaciones, crea un ALB en tus subnets publicas, adjunta el certificado
ACM para TLS, y rutea trafico a tus pods. Ya no necesitas gestionar load balancers manualmente.

<br />

##### **Configurando kubeconfig**
Despues de provisionar el cluster, necesitas configurar kubectl para comunicarse con el. La AWS
CLI lo hace simple:

<br />

```bash
# Actualizar tu kubeconfig
aws eks update-kubeconfig --region us-east-1 --name devops-zero-to-hero

# Verificar la conexion
kubectl get nodes
```

<br />

Deberias ver las instancias de tu managed node group:

<br />

```bash
NAME                             STATUS   ROLES    AGE   VERSION
ip-10-0-1-42.ec2.internal       Ready    <none>   5m    v1.31.2-eks-7f9249a
ip-10-0-2-87.ec2.internal       Ready    <none>   5m    v1.31.2-eks-7f9249a
```

<br />

Si trabajas con multiples clusters, podes cambiar entre ellos usando contextos:

<br />

```bash
# Listar todos los contextos
kubectl config get-contexts

# Cambiar a un contexto especifico
kubectl config use-context arn:aws:eks:us-east-1:123456789012:cluster/devops-zero-to-hero

# Renombrar un contexto por conveniencia
kubectl config rename-context \
  arn:aws:eks:us-east-1:123456789012:cluster/devops-zero-to-hero \
  eks-dev
```

<br />

##### **Deployeando la API TypeScript a EKS**
Te acordas del Helm chart que construimos en el articulo doce? Ahora lo ponemos a trabajar. Si
tenes tu chart en un registry OCI, el deploy es un solo comando:

<br />

```bash
# Crear un namespace para la aplicacion
kubectl create namespace task-api

# Instalar el chart
helm install task-api oci://ghcr.io/your-org/charts/task-api \
  --version 0.1.0 \
  --namespace task-api \
  -f values-eks.yaml
```

<br />

Asi se ve el archivo de values especifico para EKS:

<br />

```yaml
# values-eks.yaml
replicaCount: 2

image:
  repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api
  tag: "1.0.0"

service:
  type: ClusterIP
  port: 3000

ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123456789012:certificate/abc-123
    alb.ingress.kubernetes.io/healthcheck-path: /health
  hosts:
    - host: api.example.com
      paths:
        - path: /
          pathType: Prefix

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/task-api-role
```

<br />

Despues de que el deploy termine, podes verificar que todo esta corriendo:

<br />

```bash
# Chequear los pods
kubectl get pods -n task-api
NAME                        READY   STATUS    RESTARTS   AGE
task-api-6d8f9c7b4a-k2m5n   1/1     Running   0          2m
task-api-6d8f9c7b4a-x9p3r   1/1     Running   0          2m

# Chequear el ingress (el ALB tarda un minuto o dos en provisionar)
kubectl get ingress -n task-api
NAME       CLASS   HOSTS              ADDRESS                                      PORTS   AGE
task-api   alb     api.example.com    k8s-taskapi-xxxxx.us-east-1.elb.amazonaws.com   80      3m

# Testear el endpoint
curl https://api.example.com/health
{"status": "ok"}
```

<br />

El AWS Load Balancer Controller ve el recurso Ingress, crea un ALB, configura target groups
apuntando a las IPs de tus pods, y adjunta el certificado TLS. El trafico fluye desde internet
a traves del ALB directamente a tus pods.

<br />

##### **Storage: EBS CSI driver**
Si tus workloads necesitan storage persistente (bases de datos, caches, subida de archivos),
necesitas el EBS CSI driver. Este driver permite que los PersistentVolumes de Kubernetes esten
respaldados por volumenes EBS.

<br />

Agregalo como add-on de EKS en tu Terraform:

<br />

```hcl
# Agregar a los cluster_addons en eks.tf
cluster_addons = {
  coredns                = {}
  eks-pod-identity-agent = {}
  kube-proxy             = {}
  vpc-cni                = {}
  aws-ebs-csi-driver = {
    service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
  }
}
```

<br />

```hcl
# ebs-csi.tf
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}
```

<br />

Despues crea un StorageClass y usalo en tus workloads:

<br />

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-volume
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 10Gi
```

<br />

El modo de binding `WaitForFirstConsumer` es importante. Retrasa la creacion del volumen hasta
que un pod realmente lo necesite, asegurando que el volumen se cree en la misma availability
zone que el pod. Sin esto, podes terminar con un volumen en una AZ y un pod que necesita correr
en otra.

<br />

##### **Consideraciones de costo**
EKS no es barato, especialmente comparado con ECS con Fargate para workloads chicos. Esto es
lo que estas pagando:

<br />

> * **Control plane**: $0.10/hora ($73/mes). Esto es fijo sin importar cuantos nodos corras.
> * **Worker nodes**: Precios estandar de EC2. Un `t3.medium` (2 vCPU, 4 GB) cuesta aproximadamente $30/mes on-demand.
> * **Instancias Spot**: Hasta 90% mas baratas que on-demand, pero pueden ser interrumpidas. Karpenter hace facil usar Spot diversificando entre tipos de instancia. Genial para workloads stateless, no recomendado para bases de datos.
> * **NAT gateway**: $32/mes mas transferencia de datos. Este es generalmente el costo solapado que sorprende a la gente. Usa un solo NAT gateway para dev, uno por AZ para produccion.
> * **Load balancers**: Los ALBs cuestan aproximadamente $16/mes mas transferencia de datos. Cada recurso Ingress puede compartir un solo ALB usando IngressGroups para evitar provisionar uno por servicio.
> * **Transferencia de datos**: El trafico inter-AZ cuesta $0.01/GB en cada direccion. La comunicacion pod-a-pod entre AZs se acumula en arquitecturas de microservicios con mucha comunicacion.

<br />

Tips para ahorrar costos:

<br />

> * **Usa Karpenter con instancias Spot** para workloads stateless. Diversifica entre muchos tipos de instancia para reducir tasas de interrupcion.
> * **Dimensiona bien tus nodos**. Karpenter ayuda aca eligiendo el tipo de instancia optimo para tu mix de workloads.
> * **Consolida ALBs** usando anotaciones de IngressGroup para que multiples servicios compartan un ALB.
> * **Usa un solo NAT gateway** para entornos de no-produccion.
> * **Pone resource requests y limits** en cada pod para que Karpenter pueda empaquetar eficientemente.
> * **Considera Savings Plans o Reserved Instances** para capacidad base que sabes que siempre vas a necesitar.

<br />

Un entorno dev EKS minimo (control plane + 2 nodos `t3.medium` + NAT gateway + ALB) cuesta
aproximadamente $180/mes. Un setup de produccion con mas nodos, NAT multi-AZ, y monitoreo va a
ser significativamente mas. Compara esto con ECS con Fargate donde solo pagas por el compute
que tus containers realmente usan.

<br />

##### **Poniendo todo junto**
Recorramos el flujo completo de provisionamiento:

<br />

```bash
# Inicializar Terraform
cd eks-cluster/terraform
terraform init

# Revisar el plan
terraform plan -out=tfplan

# Aplicar (esto tarda 15-20 minutos, mayormente la creacion del cluster EKS)
terraform apply tfplan

# Configurar kubectl
aws eks update-kubeconfig --region us-east-1 --name devops-zero-to-hero

# Verificar el cluster
kubectl get nodes
kubectl get pods -n kube-system

# Aplicar recursos de Karpenter
kubectl apply -f karpenter-nodepool.yaml

# Deployear la aplicacion
kubectl create namespace task-api
helm install task-api oci://ghcr.io/your-org/charts/task-api \
  --version 0.1.0 \
  --namespace task-api \
  -f values-eks.yaml

# Verificar que todo esta corriendo
kubectl get all -n task-api
```

<br />

Despues de unos 20 minutos, vas a tener un cluster EKS completamente funcional con managed node
groups, Karpenter para escalado dinamico, el AWS Load Balancer Controller para provisionamiento
automatico de ALBs, IRSA para permisos de AWS seguros a nivel pod, y el EBS CSI driver para
storage persistente.

<br />

##### **Limpieza**
Si estas siguiendo y no queres mantener el cluster corriendo, tiralo abajo:

<br />

```bash
# Eliminar recursos de la aplicacion primero
helm uninstall task-api -n task-api
kubectl delete -f karpenter-nodepool.yaml

# Destruir todo con Terraform
terraform destroy
```

<br />

Siempre elimina los recursos de Kubernetes antes de destruir la infraestructura. Si destruis la
VPC mientras los ALBs todavia existen, Terraform se va a colgar esperando que los load balancers
se eliminen, y vas a tener que limpiarlos manualmente en la consola de AWS.

<br />

##### **Notas finales**
EKS te da todo el poder de Kubernetes sin la carga operacional de gestionar el control plane.
En este articulo provisionamos un cluster completo con Terraform, configuramos managed node
groups para compute base, configuramos Karpenter para autoscaling inteligente, usamos IRSA para
permisos de AWS seguros a nivel pod, instalamos el AWS Load Balancer Controller para gestion
automatica de ALBs, y deployeamos nuestra API TypeScript del Helm chart que construimos en el
articulo anterior.

<br />

El trade-off comparado con ECS es complejidad y costo. EKS requiere mas conocimiento de
infraestructura, mas partes moviles, y un costo base incluso cuando nada esta corriendo. Pero a
cambio obtenes todo el ecosistema de Kubernetes, portabilidad entre nubes, y la capacidad de
manejar workloads complejos que serian dificiles de modelar en ECS.

<br />

En el proximo articulo vamos a meternos con monitoreo y observabilidad, porque tener un cluster
corriendo es solo el comienzo. Necesitas saber que esta pasando adentro.

<br />

Espero que te haya resultado util y lo hayas disfrutado! Hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en las [fuentes aca](https://github.com/kainlite/tr)

<br />
