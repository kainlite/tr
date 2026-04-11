%{
  title: "DevOps from Zero to Hero: Deploying Your API to AWS ECS with Fargate",
  author: "Gabriel Garrido",
  description: "We will deploy a TypeScript API to AWS ECS with Fargate, set up an Application Load Balancer, configure auto-scaling, and manage everything with Terraform...",
  tags: ~w(devops aws ecs fargate terraform beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article eight of the DevOps from Zero to Hero series. In the previous article we learned
how to provision AWS infrastructure with Terraform. Now it is time to put that knowledge to work and
deploy our TypeScript task API (the one we built in article two) to a real cloud environment using
AWS ECS with Fargate.

<br />

ECS (Elastic Container Service) is AWS's own container orchestration platform. It lets you run Docker
containers without having to manage the underlying infrastructure yourself. When you pair it with
Fargate, you do not even need to think about EC2 instances. You just define what your container needs,
and AWS takes care of the rest. This is a great starting point before we get into Kubernetes later in
the series.

<br />

In this article we will cover the core ECS concepts, push our Docker image to a registry, write
Terraform code to provision everything (cluster, service, load balancer, auto-scaling), deploy the
API, and verify it is running. By the end you will have a production-ready deployment that scales
automatically based on demand.

<br />

Let's get into it.

<br />

##### **What is ECS?**
Amazon Elastic Container Service (ECS) is a fully managed container orchestration service. Instead
of installing and managing your own orchestrator (like Kubernetes), you hand your container definitions
to ECS and it handles scheduling, scaling, and networking for you.

<br />

There are four key concepts you need to understand:

<br />

> * **Cluster**: A logical grouping of resources where your containers run. Think of it as the boundary that holds everything together. A cluster can contain multiple services.
> * **Task Definition**: A blueprint for your container. It specifies which Docker image to use, how much CPU and memory to allocate, what ports to expose, which environment variables to set, and where to send logs. It is versioned, so you can roll back to a previous definition if needed.
> * **Task**: A running instance of a task definition. If the task definition is the recipe, the task is the actual dish being served. Each task runs one or more containers.
> * **Service**: A long-running construct that ensures a specified number of tasks are always running. If a task crashes, the service automatically starts a new one. Services also handle rolling deployments when you update your task definition.

<br />

Here is how these pieces fit together:

<br />

```plaintext
ECS Cluster
  └── Service (maintains desired count of tasks)
        ├── Task 1 (running container based on task definition v3)
        ├── Task 2 (running container based on task definition v3)
        └── Task 3 (running container based on task definition v3)
```

<br />

##### **ECS launch types: Fargate vs EC2**
When you create an ECS service, you choose a launch type that determines where your containers
actually run:

<br />

> * **EC2 launch type**: You manage a fleet of EC2 instances. ECS schedules containers onto those instances. You are responsible for patching, scaling, and maintaining the instances. More control, more work.
> * **Fargate launch type**: AWS manages the compute. You just specify CPU and memory for each task, and Fargate provisions the right amount of compute behind the scenes. No servers to manage, no capacity planning, no OS patches.

<br />

For this article we are using Fargate because it removes an entire layer of complexity. You pay a
small premium compared to EC2, but you save a lot of operational effort. For most teams starting
out, Fargate is the right choice.

<br />

##### **ECS vs EKS: a brief comparison**
You might wonder why we are not going straight to Kubernetes. AWS offers EKS (Elastic Kubernetes
Service) for that. Here is the quick comparison:

<br />

> * **ECS** is simpler to set up, tightly integrated with AWS services, and has no control plane cost with Fargate. If your workloads are AWS-only, ECS gets you running faster.
> * **EKS** gives you the full Kubernetes API, portability across clouds, and access to the massive Kubernetes ecosystem. It is more complex but more flexible.

<br />

We will cover EKS in depth later in this series. For now, ECS with Fargate is the perfect stepping
stone because it teaches you container orchestration concepts without the Kubernetes learning curve.

<br />

##### **Pushing your Docker image to ECR**
Before ECS can run your container, the image needs to be stored in a container registry that ECS can
access. AWS provides ECR (Elastic Container Registry) for this purpose. You could also use GitHub
Container Registry (GHCR) or Docker Hub, but ECR integrates seamlessly with ECS, so it is the
simplest option.

<br />

First, create an ECR repository using the AWS CLI:

<br />

```bash
aws ecr create-repository \
  --repository-name task-api \
  --region us-east-1 \
  --image-scanning-configuration scanOnPush=true
```

<br />

The `scanOnPush=true` flag enables automatic vulnerability scanning on every push. This is a free
feature and there is no reason not to use it.

<br />

Now authenticate Docker with ECR, build the image, tag it, and push:

<br />

```bash
# Get the login token and pipe it to docker login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com

# Build the image (using the Dockerfile from article 2)
docker build -t task-api .

# Tag it for ECR
docker tag task-api:latest \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest

# Push to ECR
docker push \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest
```

<br />

Replace `123456789012` with your actual AWS account ID. You can find it by running
`aws sts get-caller-identity --query Account --output text`.

<br />

##### **The Terraform project structure**
We are going to provision everything with Terraform, building on the foundations from article seven.
Here is the project structure we will end up with:

<br />

```plaintext
infra/
  ├── main.tf            # Provider and backend configuration
  ├── variables.tf       # Input variables
  ├── outputs.tf         # Output values
  ├── vpc.tf             # VPC, subnets, internet gateway
  ├── ecr.tf             # ECR repository
  ├── ecs.tf             # ECS cluster, task definition, service
  ├── alb.tf             # Application Load Balancer
  ├── autoscaling.tf     # Auto-scaling policies
  ├── iam.tf             # IAM roles and policies
  └── security_groups.tf # Security groups
```

<br />

Let's start with the provider configuration and variables.

<br />

##### **Provider and variables**
The `main.tf` file configures the AWS provider and the Terraform backend:

<br />

```hcl
# main.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "my-terraform-state-bucket"
    key    = "ecs/task-api/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}
```

<br />

Now define the variables we will use throughout the configuration:

<br />

```hcl
# variables.tf
variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "task-api"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 3000
}

variable "container_cpu" {
  description = "CPU units for the container (1024 = 1 vCPU)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Memory in MiB for the container"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run"
  type        = number
  default     = 2
}

variable "container_image" {
  description = "Docker image URI for the container"
  type        = string
}
```

<br />

##### **Networking: VPC and subnets**
Our ECS service needs a VPC with public and private subnets. The ALB will sit in the public subnets,
and the Fargate tasks will run in the private subnets:

<br />

```hcl
# vpc.tf
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

<br />

A few things to note here. The public subnets have a route to the internet gateway, which is where
our ALB will live. The private subnets route through a NAT gateway, which lets our Fargate tasks
pull images from ECR and send logs to CloudWatch without being directly exposed to the internet.
This is a standard pattern for production workloads.

<br />

##### **Security groups**
We need two security groups: one for the ALB (allows inbound HTTP traffic from the internet) and one
for the ECS tasks (allows traffic only from the ALB):

<br />

```hcl
# security_groups.tf
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ecs-tasks-sg"
  }
}
```

<br />

This is the principle of least privilege applied to networking. The ECS tasks only accept traffic
from the ALB, not from the public internet directly. The ALB is the single entry point.

<br />

##### **IAM roles for ECS**
ECS tasks need two IAM roles: an execution role (used by ECS itself to pull images and write logs)
and a task role (used by your application code to access AWS services):

<br />

```hcl
# iam.tf
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}
```

<br />

The execution role gets the managed `AmazonECSTaskExecutionRolePolicy`, which grants permissions
to pull images from ECR and write logs to CloudWatch. The task role starts empty. As your application
grows and needs access to other AWS services (S3, DynamoDB, SQS, etc.), you would attach policies
to this role. Keep them separate so you maintain clear boundaries between what ECS needs and what
your app needs.

<br />

##### **The ECR repository in Terraform**
Instead of creating the ECR repository manually with the CLI, let's manage it with Terraform so
everything is in code:

<br />

```hcl
# ecr.tf
resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = var.project_name
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```

<br />

The lifecycle policy is important. Without it, your ECR repository will accumulate old images
indefinitely, and you will pay for the storage. This policy keeps only the last 10 images and
expires the rest automatically.

<br />

##### **ECS cluster, task definition, and service**
Now the main event. We are going to create the ECS cluster, define our task, and create a service
that keeps it running:

<br />

```hcl
# ecs.tf
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name = var.project_name
  }
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = var.project_name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "PORT"
          value = tostring(var.container_port)
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.project_name
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]
}
```

<br />

There is a lot happening here, so let's break it down piece by piece.

<br />

The **CloudWatch log group** is where all container logs will be sent. Setting `retention_in_days`
to 30 prevents logs from accumulating forever and running up your bill.

<br />

The **cluster** is straightforward. We enable Container Insights for better monitoring metrics.

<br />

The **task definition** is the most detailed part:

<br />

> * `network_mode = "awsvpc"` gives each task its own elastic network interface. This is required for Fargate.
> * `cpu` and `memory` define the Fargate sizing. 256 CPU units (0.25 vCPU) and 512 MiB is the smallest configuration and works well for a lightweight API.
> * The `container_definitions` block defines the container: image, port mappings, environment variables, log configuration, and health check.
> * The health check runs `curl` against the `/health` endpoint every 30 seconds. If three consecutive checks fail, ECS marks the task as unhealthy and replaces it.

<br />

The **service** ties everything together:

<br />

> * `desired_count = 2` means ECS will always try to keep two tasks running.
> * `deployment_minimum_healthy_percent = 50` means during a deployment, at least one task (50% of 2) must stay healthy. This allows rolling updates without downtime.
> * `deployment_maximum_percent = 200` means ECS can temporarily run up to four tasks during a deployment (the old ones plus the new ones).
> * The `deployment_circuit_breaker` automatically rolls back a deployment if the new tasks fail to stabilize. This prevents a bad image from taking down your service.

<br />

##### **Application Load Balancer**
The ALB sits in front of your ECS service, distributes traffic across tasks, and provides a stable
endpoint for clients. It also handles health checks to ensure traffic only goes to healthy tasks:

<br />

```hcl
# alb.tf
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
```

<br />

A few important details:

<br />

> * `target_type = "ip"` is required for Fargate. With the EC2 launch type you would use `instance`, but Fargate tasks get their own IP addresses.
> * The health check hits `/health` and expects a `200` response. If a task fails three consecutive checks, the ALB stops sending it traffic and ECS replaces it.
> * `deregistration_delay = 30` gives in-flight requests 30 seconds to complete before a task is removed from the target group during deployments. The default is 300 seconds, which is too long for most APIs.

<br />

In production you would add HTTPS support with an ACM certificate and a listener on port 443. We
are keeping it simple with HTTP for now, but do not expose production APIs over plain HTTP.

<br />

##### **Auto-scaling**
Running a fixed number of tasks works, but it wastes money during low-traffic periods and risks
overload during spikes. ECS integrates with Application Auto Scaling to adjust the task count
based on metrics:

<br />

```hcl
# autoscaling.tf
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "memory" {
  name               = "${var.project_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
```

<br />

Here is what this does:

<br />

> * **Minimum 2, maximum 10 tasks**. You always have at least two tasks running for availability, and you cap at ten to control costs.
> * **CPU target: 70%**. If average CPU across all tasks exceeds 70%, ECS adds more tasks. If it drops well below 70%, ECS removes tasks (down to the minimum of 2).
> * **Memory target: 80%**. Same idea, but for memory utilization.
> * **Scale-out cooldown: 60 seconds**. After adding tasks, wait at least 60 seconds before considering adding more. This prevents thrashing.
> * **Scale-in cooldown: 300 seconds**. After removing tasks, wait 5 minutes before considering removing more. This is deliberately slower to avoid premature scale-down.

<br />

Target tracking is the simplest auto-scaling strategy and it works well for most workloads. You
tell AWS "keep CPU around 70%" and it figures out how many tasks to run. If your scaling needs
are more complex, you can use step scaling policies or scheduled scaling, but target tracking
is a solid default.

<br />

##### **Outputs**
Finally, define outputs so you can easily find the ALB URL and other useful information after
deploying:

<br />

```hcl
# outputs.tf
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for the ECS tasks"
  value       = aws_cloudwatch_log_group.app.name
}
```

<br />

##### **Deploying with Terraform**
With all the configuration in place, deploying is a matter of running the standard Terraform workflow:

<br />

```bash
cd infra

# Initialize Terraform (download providers, configure backend)
terraform init

# Review the execution plan
terraform plan -var="container_image=123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest"

# Apply the changes
terraform apply -var="container_image=123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest"
```

<br />

Terraform will show you everything it plans to create before it does anything. Review the plan
carefully, then type `yes` to proceed. The first deployment takes a few minutes because it needs
to create the VPC, subnets, NAT gateway, ALB, and ECS resources.

<br />

When it finishes, Terraform will print the outputs. Grab the `alb_dns_name` value, that is your
API endpoint.

<br />

##### **Testing the deployment**
Let's verify everything is working. Use the ALB DNS name from the Terraform output:

<br />

```bash
# Check the health endpoint
curl http://task-api-alb-123456789.us-east-1.elb.amazonaws.com/health

# Expected response:
# {"status":"healthy","uptime":42.123,"timestamp":"2026-05-12T10:30:00.000Z"}
```

<br />

Try creating a task:

<br />

```bash
# Create a new task
curl -X POST \
  http://task-api-alb-123456789.us-east-1.elb.amazonaws.com/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Deploy to ECS", "description": "First task from production!"}'

# List all tasks
curl http://task-api-alb-123456789.us-east-1.elb.amazonaws.com/tasks
```

<br />

If everything is working, you should see healthy responses. If something is wrong, check the
CloudWatch logs:

<br />

```bash
# View recent logs from the ECS tasks
aws logs tail /ecs/task-api --follow --since 10m
```

<br />

You can also check the ECS service events to see if tasks are starting and stopping properly:

<br />

```bash
aws ecs describe-services \
  --cluster task-api-cluster \
  --services task-api-service \
  --query 'services[0].events[:10]' \
  --output table
```

<br />

##### **Deploying updates: the rolling deployment flow**
When you push a new version of your Docker image, you need to tell ECS to pick it up. The
simplest way is to force a new deployment:

<br />

```bash
# Build, tag, and push the new image
docker build -t task-api .
docker tag task-api:latest \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest
docker push \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest

# Force ECS to pull the new image
aws ecs update-service \
  --cluster task-api-cluster \
  --service task-api-service \
  --force-new-deployment
```

<br />

Here is what happens during a rolling deployment:

<br />

> * ECS starts new tasks with the updated image alongside the existing ones (up to `deployment_maximum_percent`)
> * The ALB health checks verify the new tasks are healthy
> * Once the new tasks pass health checks, the ALB starts routing traffic to them
> * ECS drains connections from the old tasks (respecting `deregistration_delay`)
> * The old tasks are stopped
> * If the new tasks fail to become healthy, the deployment circuit breaker automatically rolls back to the previous version

<br />

This entire process happens with zero downtime. Your users never see an error during the deployment
because the old tasks keep serving traffic until the new ones are ready.

<br />

In a real CI/CD pipeline (which we covered earlier in the series), you would automate this entire
flow. Push to main, CI builds the image, pushes to ECR, and triggers the ECS deployment. No manual
steps required.

<br />

##### **Cost considerations**
Before we wrap up, let's talk about what this costs. Fargate pricing is based on the CPU and memory
you allocate to each task, billed per second with a one-minute minimum:

<br />

> * **0.25 vCPU, 512 MiB** (our configuration): roughly $0.01/hour per task
> * **With 2 tasks running 24/7**: approximately $15/month for compute
> * **NAT gateway**: about $32/month (this is often the largest cost for small deployments)
> * **ALB**: approximately $16/month plus data transfer
> * **ECR**: $0.10/GB/month for storage, first 500 MB free
> * **CloudWatch Logs**: $0.50/GB ingested

<br />

For a small API, you are looking at roughly $65-80/month total. The NAT gateway is the single
most expensive component. If cost is a concern, you could run your tasks in public subnets with
`assign_public_ip = true` and skip the NAT gateway, but this is not recommended for production
workloads because it exposes your tasks directly to the internet.

<br />

##### **Closing notes**
You now have a production-grade deployment of your TypeScript API on AWS ECS with Fargate. The
setup includes a proper VPC with public and private subnets, an Application Load Balancer for
traffic distribution and health checking, auto-scaling to handle variable load, a deployment
circuit breaker for safety, and centralized logging in CloudWatch. All managed as code with
Terraform.

<br />

ECS with Fargate is a great choice when you want container orchestration without the complexity of
Kubernetes. It integrates tightly with the AWS ecosystem, requires minimal operational overhead,
and scales well for most workloads.

<br />

In the next article, we will look at more advanced AWS services and prepare for the jump to
Kubernetes with EKS. If you have followed along this far, you already understand the fundamentals
of container orchestration, which will make Kubernetes much easier to learn.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: Deployeando Tu API a AWS ECS con Fargate",
  author: "Gabriel Garrido",
  description: "Vamos a deployear una API TypeScript a AWS ECS con Fargate, configurar un Application Load Balancer, auto-scaling, y manejar todo con Terraform...",
  tags: ~w(devops aws ecs fargate terraform beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo ocho de la serie DevOps desde Cero. En el articulo anterior aprendimos
como provisionar infraestructura AWS con Terraform. Ahora es momento de poner ese conocimiento
en practica y deployear nuestra API TypeScript de tareas (la que construimos en el articulo dos)
a un entorno cloud real usando AWS ECS con Fargate.

<br />

ECS (Elastic Container Service) es la plataforma de orquestacion de containers propia de AWS. Te
permite correr containers Docker sin tener que gestionar la infraestructura subyacente vos mismo.
Cuando lo combinas con Fargate, ni siquiera tenes que pensar en instancias EC2. Simplemente
definis lo que necesita tu container y AWS se encarga del resto. Es un excelente punto de partida
antes de meternos con Kubernetes mas adelante en la serie.

<br />

En este articulo vamos a cubrir los conceptos centrales de ECS, pushear nuestra imagen Docker a
un registry, escribir codigo Terraform para provisionar todo (cluster, servicio, load balancer,
auto-scaling), deployear la API y verificar que esta corriendo. Al final vas a tener un deployment
listo para produccion que escala automaticamente segun la demanda.

<br />

Vamos a meternos de lleno.

<br />

##### **Que es ECS?**
Amazon Elastic Container Service (ECS) es un servicio de orquestacion de containers completamente
gestionado. En lugar de instalar y gestionar tu propio orquestador (como Kubernetes), le das tus
definiciones de container a ECS y el se encarga del scheduling, scaling y networking por vos.

<br />

Hay cuatro conceptos clave que necesitas entender:

<br />

> * **Cluster**: Un agrupamiento logico de recursos donde corren tus containers. Pensalo como el limite que mantiene todo junto. Un cluster puede contener multiples servicios.
> * **Task Definition**: Un plano de tu container. Especifica que imagen Docker usar, cuanta CPU y memoria asignar, que puertos exponer, que variables de entorno setear, y a donde enviar los logs. Esta versionado, asi que podes volver a una definicion anterior si es necesario.
> * **Task**: Una instancia en ejecucion de un task definition. Si el task definition es la receta, el task es el plato que se esta sirviendo. Cada task corre uno o mas containers.
> * **Service**: Un constructo de larga duracion que asegura que una cantidad especificada de tasks esten siempre corriendo. Si un task se cae, el servicio automaticamente inicia uno nuevo. Los servicios tambien manejan rolling deployments cuando actualizas tu task definition.

<br />

Asi es como encajan estas piezas:

<br />

```plaintext
ECS Cluster
  └── Service (mantiene la cantidad deseada de tasks)
        ├── Task 1 (container corriendo basado en task definition v3)
        ├── Task 2 (container corriendo basado en task definition v3)
        └── Task 3 (container corriendo basado en task definition v3)
```

<br />

##### **Tipos de lanzamiento en ECS: Fargate vs EC2**
Cuando creas un servicio ECS, elegis un tipo de lanzamiento que determina donde corren realmente
tus containers:

<br />

> * **Tipo de lanzamiento EC2**: Vos gestionas una flota de instancias EC2. ECS programa los containers en esas instancias. Vos sos responsable de los parches, el scaling y el mantenimiento de las instancias. Mas control, mas trabajo.
> * **Tipo de lanzamiento Fargate**: AWS gestiona el computo. Solo especificas CPU y memoria para cada task, y Fargate provisiona la cantidad correcta de computo detras de escena. Sin servidores que gestionar, sin planificacion de capacidad, sin parches de SO.

<br />

Para este articulo usamos Fargate porque elimina una capa entera de complejidad. Pagas un poco
mas comparado con EC2, pero te ahorras un monton de esfuerzo operativo. Para la mayoria de los
equipos que estan empezando, Fargate es la eleccion correcta.

<br />

##### **ECS vs EKS: una comparacion breve**
Te podrias preguntar por que no vamos directo a Kubernetes. AWS ofrece EKS (Elastic Kubernetes
Service) para eso. Aca va la comparacion rapida:

<br />

> * **ECS** es mas simple de configurar, esta integrado estrechamente con servicios AWS, y no tiene costo de control plane con Fargate. Si tus workloads son solo AWS, ECS te pone en marcha mas rapido.
> * **EKS** te da la API completa de Kubernetes, portabilidad entre nubes, y acceso al ecosistema masivo de Kubernetes. Es mas complejo pero mas flexible.

<br />

Vamos a cubrir EKS en profundidad mas adelante en la serie. Por ahora, ECS con Fargate es el
escalon perfecto porque te ensenia conceptos de orquestacion de containers sin la curva de
aprendizaje de Kubernetes.

<br />

##### **Pusheando tu imagen Docker a ECR**
Antes de que ECS pueda correr tu container, la imagen necesita estar almacenada en un container
registry al que ECS pueda acceder. AWS provee ECR (Elastic Container Registry) para esto. Tambien
podrias usar GitHub Container Registry (GHCR) o Docker Hub, pero ECR se integra transparentemente
con ECS, asi que es la opcion mas simple.

<br />

Primero, crea un repositorio ECR usando el AWS CLI:

<br />

```bash
aws ecr create-repository \
  --repository-name task-api \
  --region us-east-1 \
  --image-scanning-configuration scanOnPush=true
```

<br />

El flag `scanOnPush=true` habilita escaneo automatico de vulnerabilidades en cada push. Es una
funcionalidad gratuita y no hay razon para no usarla.

<br />

Ahora autenticate Docker con ECR, construi la imagen, etiquetala y pusheala:

<br />

```bash
# Obtener el token de login y pasarselo a docker login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com

# Construir la imagen (usando el Dockerfile del articulo 2)
docker build -t task-api .

# Etiquetar para ECR
docker tag task-api:latest \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest

# Pushear a ECR
docker push \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest
```

<br />

Reemplaza `123456789012` con tu ID de cuenta AWS real. Lo podes encontrar ejecutando
`aws sts get-caller-identity --query Account --output text`.

<br />

##### **Estructura del proyecto Terraform**
Vamos a provisionar todo con Terraform, construyendo sobre las bases del articulo siete.
Esta es la estructura del proyecto con la que vamos a terminar:

<br />

```plaintext
infra/
  ├── main.tf            # Configuracion del provider y backend
  ├── variables.tf       # Variables de entrada
  ├── outputs.tf         # Valores de salida
  ├── vpc.tf             # VPC, subnets, internet gateway
  ├── ecr.tf             # Repositorio ECR
  ├── ecs.tf             # Cluster ECS, task definition, servicio
  ├── alb.tf             # Application Load Balancer
  ├── autoscaling.tf     # Politicas de auto-scaling
  ├── iam.tf             # Roles y politicas IAM
  └── security_groups.tf # Security groups
```

<br />

Empecemos con la configuracion del provider y las variables.

<br />

##### **Provider y variables**
El archivo `main.tf` configura el provider de AWS y el backend de Terraform:

<br />

```hcl
# main.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "my-terraform-state-bucket"
    key    = "ecs/task-api/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}
```

<br />

Ahora defini las variables que vamos a usar a lo largo de la configuracion:

<br />

```hcl
# variables.tf
variable "aws_region" {
  description = "Region de AWS para deployear"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto, usado para nombrar recursos"
  type        = string
  default     = "task-api"
}

variable "environment" {
  description = "Entorno de deployment"
  type        = string
  default     = "production"
}

variable "container_port" {
  description = "Puerto en el que escucha el container"
  type        = number
  default     = 3000
}

variable "container_cpu" {
  description = "Unidades de CPU para el container (1024 = 1 vCPU)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Memoria en MiB para el container"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Numero de tasks a correr"
  type        = number
  default     = 2
}

variable "container_image" {
  description = "URI de la imagen Docker para el container"
  type        = string
}
```

<br />

##### **Networking: VPC y subnets**
Nuestro servicio ECS necesita una VPC con subnets publicas y privadas. El ALB va a estar en las
subnets publicas, y los tasks de Fargate van a correr en las subnets privadas:

<br />

```hcl
# vpc.tf
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

<br />

Algunas cosas para notar aca. Las subnets publicas tienen una ruta al internet gateway, que es donde
va a estar nuestro ALB. Las subnets privadas enrutan a traves de un NAT gateway, que le permite a
nuestros tasks de Fargate pullear imagenes de ECR y enviar logs a CloudWatch sin estar directamente
expuestos a internet. Este es un patron estandar para workloads de produccion.

<br />

##### **Security groups**
Necesitamos dos security groups: uno para el ALB (permite trafico HTTP entrante desde internet)
y uno para los tasks de ECS (permite trafico solo desde el ALB):

<br />

```hcl
# security_groups.tf
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group para el Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP desde cualquier lugar"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group para los tasks de ECS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Permitir trafico desde el ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ecs-tasks-sg"
  }
}
```

<br />

Esto es el principio de minimo privilegio aplicado al networking. Los tasks de ECS solo aceptan
trafico del ALB, no del internet publico directamente. El ALB es el unico punto de entrada.

<br />

##### **Roles IAM para ECS**
Los tasks de ECS necesitan dos roles IAM: un rol de ejecucion (usado por ECS mismo para pullear
imagenes y escribir logs) y un rol de tarea (usado por el codigo de tu aplicacion para acceder
a servicios AWS):

<br />

```hcl
# iam.tf
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}
```

<br />

El rol de ejecucion recibe la politica gestionada `AmazonECSTaskExecutionRolePolicy`, que otorga
permisos para pullear imagenes de ECR y escribir logs en CloudWatch. El rol de tarea empieza vacio.
A medida que tu aplicacion crezca y necesite acceso a otros servicios AWS (S3, DynamoDB, SQS, etc.),
le irias adjuntando politicas a este rol. Mantenelos separados para que tengas limites claros entre
lo que necesita ECS y lo que necesita tu app.

<br />

##### **El repositorio ECR en Terraform**
En lugar de crear el repositorio ECR manualmente con el CLI, vamos a gestionarlo con Terraform
para que todo este en codigo:

<br />

```hcl
# ecr.tf
resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = var.project_name
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Mantener solo las ultimas 10 imagenes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```

<br />

La politica de ciclo de vida es importante. Sin ella, tu repositorio ECR va a acumular imagenes
viejas indefinidamente, y vas a pagar por el almacenamiento. Esta politica mantiene solo las
ultimas 10 imagenes y expira el resto automaticamente.

<br />

##### **Cluster ECS, task definition y servicio**
Ahora el plato fuerte. Vamos a crear el cluster ECS, definir nuestro task y crear un servicio
que lo mantenga corriendo:

<br />

```hcl
# ecs.tf
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name = var.project_name
  }
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = var.project_name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "PORT"
          value = tostring(var.container_port)
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.project_name
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]
}
```

<br />

Estan pasando muchas cosas aca, asi que vamos a desglosarlo pieza por pieza.

<br />

El **log group de CloudWatch** es donde se van a enviar todos los logs del container. Setear
`retention_in_days` en 30 evita que los logs se acumulen para siempre y te inflen la factura.

<br />

El **cluster** es directo. Habilitamos Container Insights para mejores metricas de monitoreo.

<br />

El **task definition** es la parte mas detallada:

<br />

> * `network_mode = "awsvpc"` le da a cada task su propia interfaz de red elastica. Es requerido para Fargate.
> * `cpu` y `memory` definen el tamano de Fargate. 256 unidades de CPU (0.25 vCPU) y 512 MiB es la configuracion mas chica y funciona bien para una API liviana.
> * El bloque `container_definitions` define el container: imagen, mapeos de puertos, variables de entorno, configuracion de logs y health check.
> * El health check ejecuta `curl` contra el endpoint `/health` cada 30 segundos. Si tres chequeos consecutivos fallan, ECS marca el task como unhealthy y lo reemplaza.

<br />

El **servicio** conecta todo:

<br />

> * `desired_count = 2` significa que ECS siempre va a intentar mantener dos tasks corriendo.
> * `deployment_minimum_healthy_percent = 50` significa que durante un deployment, al menos un task (50% de 2) debe permanecer sano. Esto permite rolling updates sin downtime.
> * `deployment_maximum_percent = 200` significa que ECS puede temporalmente correr hasta cuatro tasks durante un deployment (los viejos mas los nuevos).
> * El `deployment_circuit_breaker` automaticamente hace rollback de un deployment si los nuevos tasks no logran estabilizarse. Esto evita que una imagen rota tire abajo tu servicio.

<br />

##### **Application Load Balancer**
El ALB se pone enfrente de tu servicio ECS, distribuye trafico entre los tasks, y provee un
endpoint estable para los clientes. Tambien maneja health checks para asegurarse de que el
trafico solo vaya a tasks saludables:

<br />

```hcl
# alb.tf
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.project_name}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
```

<br />

Algunos detalles importantes:

<br />

> * `target_type = "ip"` es requerido para Fargate. Con el tipo de lanzamiento EC2 usarias `instance`, pero los tasks de Fargate obtienen sus propias direcciones IP.
> * El health check golpea `/health` y espera una respuesta `200`. Si un task falla tres chequeos consecutivos, el ALB deja de enviarle trafico y ECS lo reemplaza.
> * `deregistration_delay = 30` le da a las requests en curso 30 segundos para completarse antes de que un task sea removido del target group durante deployments. El default es 300 segundos, que es demasiado para la mayoria de las APIs.

<br />

En produccion agregarias soporte HTTPS con un certificado ACM y un listener en el puerto 443.
Lo mantenemos simple con HTTP por ahora, pero no expongas APIs de produccion por HTTP plano.

<br />

##### **Auto-scaling**
Correr un numero fijo de tasks funciona, pero desperdicia plata en periodos de poco trafico y
arriesga sobrecarga durante picos. ECS se integra con Application Auto Scaling para ajustar la
cantidad de tasks basandose en metricas:

<br />

```hcl
# autoscaling.tf
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "memory" {
  name               = "${var.project_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
```

<br />

Esto es lo que hace:

<br />

> * **Minimo 2, maximo 10 tasks**. Siempre tenes al menos dos tasks corriendo para disponibilidad, y caps en diez para controlar costos.
> * **Target de CPU: 70%**. Si el promedio de CPU entre todos los tasks supera 70%, ECS agrega mas tasks. Si baja bastante por debajo de 70%, ECS remueve tasks (hasta el minimo de 2).
> * **Target de memoria: 80%**. Misma idea, pero para utilizacion de memoria.
> * **Cooldown de scale-out: 60 segundos**. Despues de agregar tasks, esperar al menos 60 segundos antes de considerar agregar mas. Esto previene el thrashing.
> * **Cooldown de scale-in: 300 segundos**. Despues de remover tasks, esperar 5 minutos antes de considerar remover mas. Esto es deliberadamente mas lento para evitar scale-down prematuro.

<br />

Target tracking es la estrategia de auto-scaling mas simple y funciona bien para la mayoria de
los workloads. Le decis a AWS "mantene la CPU alrededor de 70%" y el se da cuenta de cuantos
tasks correr. Si tus necesidades de scaling son mas complejas, podes usar step scaling policies
o scheduled scaling, pero target tracking es un buen default.

<br />

##### **Outputs**
Finalmente, defini outputs para que puedas encontrar facilmente la URL del ALB y otra informacion
util despues de deployear:

<br />

```hcl
# outputs.tf
output "alb_dns_name" {
  description = "Nombre DNS del Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "ecr_repository_url" {
  description = "URL del repositorio ECR"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "Nombre del cluster ECS"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Nombre del servicio ECS"
  value       = aws_ecs_service.app.name
}

output "cloudwatch_log_group" {
  description = "Log group de CloudWatch para los tasks de ECS"
  value       = aws_cloudwatch_log_group.app.name
}
```

<br />

##### **Deployeando con Terraform**
Con toda la configuracion lista, deployear es cuestion de ejecutar el flujo estandar de Terraform:

<br />

```bash
cd infra

# Inicializar Terraform (descargar providers, configurar backend)
terraform init

# Revisar el plan de ejecucion
terraform plan -var="container_image=123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest"

# Aplicar los cambios
terraform apply -var="container_image=123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest"
```

<br />

Terraform te va a mostrar todo lo que planea crear antes de hacer nada. Revisa el plan con
cuidado, despues escribi `yes` para continuar. El primer deployment tarda unos minutos porque
necesita crear la VPC, subnets, NAT gateway, ALB y recursos de ECS.

<br />

Cuando termine, Terraform va a imprimir los outputs. Agarra el valor de `alb_dns_name`, ese
es tu endpoint de la API.

<br />

##### **Testeando el deployment**
Verifiquemos que todo esta funcionando. Usa el DNS name del ALB del output de Terraform:

<br />

```bash
# Chequear el endpoint de health
curl http://task-api-alb-123456789.us-east-1.elb.amazonaws.com/health

# Respuesta esperada:
# {"status":"healthy","uptime":42.123,"timestamp":"2026-05-12T10:30:00.000Z"}
```

<br />

Proba crear un task:

<br />

```bash
# Crear un nuevo task
curl -X POST \
  http://task-api-alb-123456789.us-east-1.elb.amazonaws.com/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Deploy a ECS", "description": "Primer task desde produccion!"}'

# Listar todos los tasks
curl http://task-api-alb-123456789.us-east-1.elb.amazonaws.com/tasks
```

<br />

Si todo esta funcionando, deberias ver respuestas saludables. Si algo esta mal, revisa los logs
de CloudWatch:

<br />

```bash
# Ver logs recientes de los tasks de ECS
aws logs tail /ecs/task-api --follow --since 10m
```

<br />

Tambien podes chequear los eventos del servicio ECS para ver si los tasks estan iniciando y
parando correctamente:

<br />

```bash
aws ecs describe-services \
  --cluster task-api-cluster \
  --services task-api-service \
  --query 'services[0].events[:10]' \
  --output table
```

<br />

##### **Deployeando actualizaciones: el flujo de rolling deployment**
Cuando pusheas una nueva version de tu imagen Docker, necesitas decirle a ECS que la agarre.
La forma mas simple es forzar un nuevo deployment:

<br />

```bash
# Construir, etiquetar y pushear la nueva imagen
docker build -t task-api .
docker tag task-api:latest \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest
docker push \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/task-api:latest

# Forzar a ECS a pullear la nueva imagen
aws ecs update-service \
  --cluster task-api-cluster \
  --service task-api-service \
  --force-new-deployment
```

<br />

Esto es lo que pasa durante un rolling deployment:

<br />

> * ECS inicia nuevos tasks con la imagen actualizada junto a los existentes (hasta `deployment_maximum_percent`)
> * Los health checks del ALB verifican que los nuevos tasks estan sanos
> * Una vez que los nuevos tasks pasan los health checks, el ALB empieza a rutear trafico hacia ellos
> * ECS drena las conexiones de los tasks viejos (respetando `deregistration_delay`)
> * Los tasks viejos se detienen
> * Si los nuevos tasks no logran ponerse saludables, el deployment circuit breaker automaticamente hace rollback a la version anterior

<br />

Todo este proceso ocurre con cero downtime. Tus usuarios nunca ven un error durante el deployment
porque los tasks viejos siguen sirviendo trafico hasta que los nuevos estan listos.

<br />

En un pipeline CI/CD real (que cubrimos antes en la serie), automatizarias todo este flujo. Push
a main, CI construye la imagen, pushea a ECR, y dispara el deployment en ECS. Sin pasos manuales.

<br />

##### **Consideraciones de costos**
Antes de cerrar, hablemos de cuanto cuesta esto. El pricing de Fargate se basa en la CPU y
memoria que asignas a cada task, facturado por segundo con un minimo de un minuto:

<br />

> * **0.25 vCPU, 512 MiB** (nuestra configuracion): aproximadamente $0.01/hora por task
> * **Con 2 tasks corriendo 24/7**: aproximadamente $15/mes de computo
> * **NAT gateway**: alrededor de $32/mes (esto suele ser el costo mas grande para deployments chicos)
> * **ALB**: aproximadamente $16/mes mas transferencia de datos
> * **ECR**: $0.10/GB/mes de almacenamiento, los primeros 500 MB gratis
> * **CloudWatch Logs**: $0.50/GB ingestado

<br />

Para una API chica, estas mirando aproximadamente $65-80/mes en total. El NAT gateway es el
componente individual mas caro. Si el costo es una preocupacion, podrias correr tus tasks en
subnets publicas con `assign_public_ip = true` y saltarte el NAT gateway, pero esto no es
recomendado para workloads de produccion porque expone tus tasks directamente a internet.

<br />

##### **Notas finales**
Ahora tenes un deployment production-grade de tu API TypeScript en AWS ECS con Fargate. El setup
incluye una VPC apropiada con subnets publicas y privadas, un Application Load Balancer para
distribucion de trafico y health checking, auto-scaling para manejar carga variable, un
deployment circuit breaker para seguridad, y logging centralizado en CloudWatch. Todo gestionado
como codigo con Terraform.

<br />

ECS con Fargate es una excelente eleccion cuando queres orquestacion de containers sin la
complejidad de Kubernetes. Se integra estrechamente con el ecosistema AWS, requiere minimo
overhead operativo, y escala bien para la mayoria de los workloads.

<br />

En el proximo articulo vamos a ver servicios AWS mas avanzados y prepararnos para el salto a
Kubernetes con EKS. Si seguiste hasta aca, ya entendes los fundamentos de orquestacion de
containers, lo que va a hacer que Kubernetes sea mucho mas facil de aprender.

<br />

Espero que te haya resultado util y lo hayas disfrutado! Hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en las [fuentes aca](https://github.com/kainlite/tr)

<br />
