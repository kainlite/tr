%{
  title: "DevOps from Zero to Hero: Infrastructure as Code with Terraform",
  author: "Gabriel Garrido",
  description: "We will explore Infrastructure as Code principles, learn the Terraform workflow, manage remote state, and provision a VPC with subnets using Terraform...",
  tags: ~w(devops terraform iac aws beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article seven of the DevOps from Zero to Hero series. In the previous article we explored
AWS networking: VPCs, subnets, route tables, and security groups. Now it is time to stop clicking
around in the AWS console and start defining infrastructure the same way we define application code:
in files, under version control, with repeatable results.

<br />

This is Infrastructure as Code (IaC), and it is one of the most important practices in modern DevOps.
If you have ever manually created an EC2 instance, realized you forgot a tag, created another one
differently, and then had no idea which was "the right one," you already understand the problem IaC
solves.

<br />

We will cover what IaC is, walk through the core Terraform workflow, learn how to manage state safely,
and build a real VPC with public and private subnets using HCL files. If you want to go deeper after
this, check out [Getting started with Terraform modules](/blog/getting_started_with_terraform_modules)
and [Brief introduction to Terratest](/blog/brief_introduction_to_terratest).

<br />

Let's get into it.

<br />

##### **What is Infrastructure as Code?**
IaC means defining your infrastructure (servers, networks, databases, load balancers, DNS records) in
declarative configuration files rather than creating them manually through a web console.

<br />

> * **Reproducibility**: Recreate your entire infrastructure from scratch with a single command. No more "it works in staging but not in production" because someone configured something differently.
> * **Version control**: Every change is tracked in Git. You can see who changed what, when, and why.
> * **Collaboration**: Infrastructure changes go through pull requests just like code changes.
> * **Drift detection**: IaC tools detect when real state drifts from declared state and bring it back in line.
> * **Documentation**: Your code IS your documentation. Always up to date because it is the source of truth.

<br />

##### **IaC vs ClickOps**
"ClickOps" is the term for managing infrastructure by clicking through a cloud console. It is fine for
learning but falls apart in teams:

<br />

> * **No audit trail**: Someone changes a security group rule. Three months later, nobody remembers who or why.
> * **Snowflake servers**: Each environment is slightly different because different people configured them at different times.
> * **No reproducibility**: Could you recreate your production environment from scratch? How long would it take?
> * **Human error**: At 2 AM you accidentally delete a production database because you were in the wrong tab.
> * **Knowledge silos**: Only one person knows how the network is configured because they set it up manually.

<br />

IaC eliminates all of these problems. Infrastructure defined in code, reviewed by the team, tracked
in Git, reproducible at any time.

<br />

##### **Why Terraform?**
Several IaC tools exist:

<br />

> * **CloudFormation**: AWS-native, JSON/YAML. AWS-only, verbose, but deep AWS integration.
> * **Pulumi**: Infrastructure in real programming languages (TypeScript, Python, Go). Great DX, smaller community.
> * **AWS CDK**: Generates CloudFormation using TypeScript or Python. AWS-only, nicer than raw CloudFormation.
> * **Terraform**: HashiCorp's tool using HCL. Works across AWS, GCP, Azure, Kubernetes, and hundreds of providers.

<br />

We use Terraform because it works across clouds, has the largest ecosystem, and is what most teams use.
The concepts (state, plans, declarative config) transfer to any IaC tool.

<br />

##### **Terraform basics: the building blocks**
Terraform uses HCL (HashiCorp Configuration Language), a declarative language for describing infrastructure.

<br />

**Providers** are plugins that let Terraform talk to a cloud or service:

<br />

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

<br />

**Resources** describe a piece of infrastructure:

<br />

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"
  tags = { Name = "web-server" }
}
```

<br />

**Data sources** read information without creating anything:

<br />

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}
```

<br />

**Variables** parameterize your configuration:

<br />

```hcl
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
```

<br />

**Outputs** extract values after creation:

<br />

```hcl
output "instance_public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web.public_ip
}
```

<br />

##### **The Terraform workflow: init, plan, apply, destroy**

**terraform init** downloads providers and sets up the backend:

<br />

```bash
$ terraform init
Initializing provider plugins...
- Installing hashicorp/aws v5.82.1...
Terraform has been successfully initialized!
```

<br />

**terraform plan** shows what would change without changing anything:

<br />

```bash
$ terraform plan
  # aws_instance.web will be created
  + resource "aws_instance" "web" {
      + ami           = "ami-0c55b159cbfafe1f0"
      + instance_type = "t3.micro"
    }
Plan: 1 to add, 0 to change, 0 to destroy.
```

<br />

The symbols: `+` create, `~` modify, `-` destroy, `-/+` replace. Always read the plan before applying.

<br />

**terraform apply** makes changes real (asks for confirmation):

<br />

```bash
$ terraform apply
aws_instance.web: Creating...
aws_instance.web: Creation complete after 32s [id=i-0abc123def456789]
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

<br />

**terraform destroy** tears everything down when you no longer need it.

<br />

##### **State management**
Terraform records what it created in a state file. By default this is local (`terraform.tfstate`),
which breaks in teams:

<br />

> * **No sharing**: Teammates cannot run Terraform without the state file.
> * **No locking**: Two concurrent applies can corrupt state or create duplicates.
> * **Risk of loss**: Laptop dies, state is gone, Terraform forgets your infrastructure.

<br />

The solution is remote state with S3 + DynamoDB locking:

<br />

```bash
# Create S3 bucket for state (one-time setup)
aws s3api create-bucket --bucket my-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket my-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for locking
aws dynamodb create-table --table-name terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

<br />

Then configure the backend:

<br />

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}
```

<br />

Now state is shared, versioned, encrypted, and locked during applies.

<br />

##### **Practical example: provisioning a VPC**
Let's build a VPC with public and private subnets, an internet gateway, route tables, and a security
group, the same architecture from the networking article, but as code.

<br />

**variables.tf**

<br />

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "allowed_ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}
```

<br />

**main.tf**

<br />

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-igw" }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.environment}-public-${count.index + 1}", Tier = "public" }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.environment}-private-${count.index + 1}", Tier = "private" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.environment}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "web" {
  name        = "${var.environment}-web-sg"
  description = "Allow HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.main.id
  tags = { Name = "${var.environment}-web-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 80
  to_port   = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 443
  to_port   = 443
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4 = var.allowed_ssh_cidr
  from_port = 22
  to_port   = 22
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}
```

<br />

**outputs.tf**

<br />

```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "security_group_id" {
  value = aws_security_group.web.id
}
```

<br />

What this creates:

<br />

> * **VPC** with DNS support using the configured CIDR block
> * **Internet Gateway** attached to the VPC for public internet access
> * **Public subnets** across availability zones with automatic public IP assignment
> * **Private subnets** with no internet route, keeping resources isolated
> * **Route tables** directing public traffic through the gateway
> * **Security group** allowing HTTP, HTTPS, SSH inbound and all outbound

<br />

##### **Variables and tfvars**
Use `.tfvars` files for environment-specific values:

<br />

```hcl
# terraform.tfvars (dev defaults)
aws_region  = "us-east-1"
environment = "dev"
vpc_cidr    = "10.0.0.0/16"

# prod.tfvars
# aws_region           = "us-east-1"
# environment          = "prod"
# vpc_cidr             = "10.1.0.0/16"
# public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
# private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
# allowed_ssh_cidr     = "203.0.113.0/24"
```

<br />

```bash
# Uses terraform.tfvars automatically
terraform plan

# Uses a specific file
terraform plan -var-file="prod.tfvars"

# Or pass directly
terraform plan -var="environment=staging"

# Or use environment variables
export TF_VAR_environment="staging"
```

<br />

Precedence (lowest to highest): defaults, `terraform.tfvars`, `*.auto.tfvars`, `-var-file`, `-var`,
`TF_VAR_` env vars.

<br />

##### **Running the example**

```bash
terraform init       # Download providers
terraform fmt        # Format code
terraform validate   # Check syntax
terraform plan       # Preview changes
terraform apply      # Create infrastructure
terraform output     # Show outputs
terraform state list # List managed resources
terraform destroy    # Clean up when done
```

<br />

##### **Best practices**
A few things to keep in mind:

<br />

> * **Never commit state files** to Git. They contain sensitive data. Use remote state.
> * **Do commit `.terraform.lock.hcl`**. It pins provider versions like `package-lock.json`.
> * **Be careful with `.tfvars`**. If they contain secrets, use environment variables or a secrets manager instead.
> * **Tag everything** with `ManagedBy = "terraform"` so you can distinguish IaC-managed resources from manual ones.
> * **Use `plan -out=tfplan`** in CI/CD to save a plan file and apply exactly what was reviewed.

<br />

##### **Closing notes**
Infrastructure as Code changes how you think about infrastructure. Instead of fragile, manually
configured environments, you get reproducible, version-controlled definitions that anyone on the team
can read and modify.

<br />

Terraform is not the only tool, but it is a great starting point. The declarative approach (describe
what you want, Terraform figures out how to get there) makes it accessible, and the plan-before-apply
workflow gives you a safety net that clicking through a console never could.

<br />

Start small. One resource, one plan, one apply. Then add more. Before long your entire infrastructure
lives in a handful of files and you will wonder how you ever managed without it.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: Infraestructura como Codigo con Terraform",
  author: "Gabriel Garrido",
  description: "Vamos a explorar los principios de Infraestructura como Codigo, aprender el workflow de Terraform, gestionar estado remoto, y aprovisionar una VPC con subnets usando Terraform...",
  tags: ~w(devops terraform iac aws beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al septimo articulo de la serie DevOps from Zero to Hero. En el articulo anterior exploramos
networking en AWS: VPCs, subnets, tablas de rutas y security groups. Ahora es momento de dejar de
hacer click en la consola de AWS y empezar a definir infraestructura como definimos codigo de
aplicaciones: en archivos, bajo control de versiones, con resultados repetibles.

<br />

Esto es Infraestructura como Codigo (IaC), y es una de las practicas mas importantes en DevOps
moderno. Si alguna vez creaste una instancia EC2 manualmente, te diste cuenta de que te olvidaste un
tag, creaste otra diferente, y despues no sabias cual era "la correcta," ya entendes el problema que
IaC resuelve.

<br />

Vamos a cubrir que es IaC, el workflow de Terraform, gestion de estado segura, y construir una VPC
real con subnets publicas y privadas usando archivos HCL. Si queres profundizar despues, mira
[Getting started with Terraform modules](/blog/getting_started_with_terraform_modules) y
[Brief introduction to Terratest](/blog/brief_introduction_to_terratest).

<br />

Vamos a meternos de lleno.

<br />

##### **Que es Infraestructura como Codigo?**
IaC significa definir tu infraestructura (servidores, redes, bases de datos, balanceadores, registros
DNS) en archivos de configuracion declarativos en lugar de crearlos manualmente por una consola web.

<br />

> * **Reproducibilidad**: Podes recrear toda tu infraestructura desde cero con un solo comando.
> * **Control de versiones**: Cada cambio queda registrado en Git. Sabes quien cambio que, cuando y por que.
> * **Colaboracion**: Los cambios de infraestructura pasan por pull requests igual que los de codigo.
> * **Deteccion de drift**: Las herramientas detectan cuando el estado real se desvio del declarado y lo corrigen.
> * **Documentacion**: Tu codigo ES tu documentacion. Siempre actualizada porque es la fuente de verdad.

<br />

##### **IaC vs ClickOps**
"ClickOps" es gestionar infraestructura haciendo click en la consola. Esta bien para aprender pero
se cae en equipos:

<br />

> * **Sin auditoria**: Alguien cambia una regla de security group. Tres meses despues, nadie se acuerda quien ni por que.
> * **Servidores snowflake**: Cada entorno es diferente porque distintas personas los configuraron en distintos momentos.
> * **Sin reproducibilidad**: Podrias recrear tu entorno de produccion desde cero? Cuanto tardarias?
> * **Error humano**: A las 2 AM borraste accidentalmente una base de datos de produccion porque estabas en la solapa equivocada.
> * **Silos de conocimiento**: Solo una persona sabe como esta la red porque la armo manualmente.

<br />

IaC elimina todos estos problemas. Infraestructura definida en codigo, revisada por el equipo,
registrada en Git, reproducible en cualquier momento.

<br />

##### **Por que Terraform?**
Varias herramientas de IaC existen:

<br />

> * **CloudFormation**: Nativo de AWS, JSON/YAML. Solo AWS, verboso, pero integracion profunda.
> * **Pulumi**: Infraestructura en lenguajes reales (TypeScript, Python, Go). Gran DX, comunidad mas chica.
> * **AWS CDK**: Genera CloudFormation con TypeScript o Python. Solo AWS, mejor que CloudFormation crudo.
> * **Terraform**: Herramienta de HashiCorp con HCL. Funciona con AWS, GCP, Azure, Kubernetes y cientos de providers.

<br />

Usamos Terraform porque funciona entre clouds, tiene el ecosistema mas grande, y es lo que la mayoria
de los equipos usa. Los conceptos (estado, planes, config declarativa) se transfieren a cualquier
herramienta de IaC.

<br />

##### **Conceptos basicos de Terraform**
Terraform usa HCL (HashiCorp Configuration Language), un lenguaje declarativo para describir infraestructura.

<br />

**Providers** son plugins para hablar con un cloud o servicio:

<br />

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

<br />

**Resources** describen una pieza de infraestructura:

<br />

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"
  tags = { Name = "web-server" }
}
```

<br />

**Data sources** leen informacion sin crear nada:

<br />

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}
```

<br />

**Variables** parametrizan tu configuracion:

<br />

```hcl
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}
```

<br />

**Outputs** extraen valores despues de la creacion:

<br />

```hcl
output "instance_public_ip" {
  value = aws_instance.web.public_ip
}
```

<br />

##### **El workflow de Terraform: init, plan, apply, destroy**

**terraform init** descarga providers y configura el backend:

<br />

```bash
$ terraform init
Initializing provider plugins...
- Installing hashicorp/aws v5.82.1...
Terraform has been successfully initialized!
```

<br />

**terraform plan** muestra que cambiaria sin cambiar nada:

<br />

```bash
$ terraform plan
  # aws_instance.web will be created
  + resource "aws_instance" "web" {
      + ami           = "ami-0c55b159cbfafe1f0"
      + instance_type = "t3.micro"
    }
Plan: 1 to add, 0 to change, 0 to destroy.
```

<br />

Los simbolos: `+` crear, `~` modificar, `-` destruir, `-/+` reemplazar. Siempre lee el plan antes
de aplicar.

<br />

**terraform apply** hace los cambios reales (pide confirmacion):

<br />

```bash
$ terraform apply
aws_instance.web: Creating...
aws_instance.web: Creation complete after 32s [id=i-0abc123def456789]
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

<br />

**terraform destroy** tira todo abajo cuando ya no lo necesitas.

<br />

##### **Gestion de estado**
Terraform registra lo que creo en un archivo de estado. Por defecto es local (`terraform.tfstate`),
lo cual falla en equipos:

<br />

> * **Sin compartir**: Tus companeros no pueden correr Terraform sin el archivo de estado.
> * **Sin locking**: Dos applies concurrentes pueden corromper el estado o crear duplicados.
> * **Riesgo de perdida**: Se muere tu compu, perdiste el estado, Terraform se olvida de tu infra.

<br />

La solucion es estado remoto con S3 + DynamoDB locking:

<br />

```bash
# Crear bucket S3 para estado (una sola vez)
aws s3api create-bucket --bucket my-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket my-terraform-state \
  --versioning-configuration Status=Enabled

# Crear tabla DynamoDB para locking
aws dynamodb create-table --table-name terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

<br />

Despues configura el backend:

<br />

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}
```

<br />

Ahora el estado es compartido, versionado, encriptado y bloqueado durante applies.

<br />

##### **Ejemplo practico: aprovisionando una VPC**
Armemos una VPC con subnets publicas y privadas, internet gateway, tablas de rutas y security group.
La misma arquitectura del articulo de networking, pero como codigo.

<br />

**variables.tf**

<br />

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "allowed_ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}
```

<br />

**main.tf**

<br />

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-igw" }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.environment}-public-${count.index + 1}", Tier = "public" }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.environment}-private-${count.index + 1}", Tier = "private" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.environment}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "web" {
  name        = "${var.environment}-web-sg"
  description = "Allow HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.main.id
  tags = { Name = "${var.environment}-web-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 80
  to_port   = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 443
  to_port   = 443
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4 = var.allowed_ssh_cidr
  from_port = 22
  to_port   = 22
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}
```

<br />

**outputs.tf**

<br />

```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "security_group_id" {
  value = aws_security_group.web.id
}
```

<br />

Que crea esto:

<br />

> * **VPC** con soporte DNS usando el CIDR configurado
> * **Internet Gateway** adjunto a la VPC para acceso a internet publico
> * **Subnets publicas** en distintas zonas de disponibilidad con IP publica automatica
> * **Subnets privadas** sin ruta a internet, manteniendo los recursos aislados
> * **Tablas de rutas** dirigiendo trafico publico a traves del gateway
> * **Security group** permitiendo HTTP, HTTPS, SSH entrante y todo el saliente

<br />

##### **Variables y tfvars**
Usa archivos `.tfvars` para valores especificos por entorno:

<br />

```hcl
# terraform.tfvars (dev por defecto)
aws_region  = "us-east-1"
environment = "dev"
vpc_cidr    = "10.0.0.0/16"

# prod.tfvars
# aws_region           = "us-east-1"
# environment          = "prod"
# vpc_cidr             = "10.1.0.0/16"
# public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
# private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
# allowed_ssh_cidr     = "203.0.113.0/24"
```

<br />

```bash
# Usa terraform.tfvars automaticamente
terraform plan

# Usa un archivo especifico
terraform plan -var-file="prod.tfvars"

# O pasa directamente
terraform plan -var="environment=staging"

# O usa variables de entorno
export TF_VAR_environment="staging"
```

<br />

Precedencia (menor a mayor): defaults, `terraform.tfvars`, `*.auto.tfvars`, `-var-file`, `-var`,
`TF_VAR_` env vars.

<br />

##### **Ejecutando el ejemplo**

```bash
terraform init       # Descargar providers
terraform fmt        # Formatear codigo
terraform validate   # Verificar sintaxis
terraform plan       # Preview de cambios
terraform apply      # Crear infraestructura
terraform output     # Mostrar outputs
terraform state list # Listar recursos gestionados
terraform destroy    # Limpiar cuando termines
```

<br />

##### **Buenas practicas**
Algunas cosas a tener en cuenta:

<br />

> * **Nunca commitees archivos de estado** a Git. Contienen datos sensibles. Usa estado remoto.
> * **Si commitea `.terraform.lock.hcl`**. Fija versiones de providers como `package-lock.json`.
> * **Cuidado con `.tfvars`**. Si tienen secretos, usa variables de entorno o un gestor de secretos.
> * **Taggealo todo** con `ManagedBy = "terraform"` para distinguir recursos gestionados por IaC de los manuales.
> * **Usa `plan -out=tfplan`** en CI/CD para guardar un plan y aplicar exactamente lo revisado.

<br />

##### **Notas finales**
La Infraestructura como Codigo cambia como pensas sobre la infraestructura. En lugar de entornos
fragiles configurados a mano, tenes definiciones reproducibles, versionadas y revisables que
cualquiera del equipo puede leer y modificar.

<br />

Terraform no es la unica herramienta, pero es un gran punto de partida. El enfoque declarativo
(describis lo que queres, Terraform se encarga de como llegar) lo hace accesible, y el workflow de
plan-antes-de-apply te da una red de seguridad que hacer click en una consola nunca podria darte.

<br />

Empeza de a poco. Un recurso, un plan, un apply. Despues agrega mas. Antes de que te des cuenta,
toda tu infraestructura va a estar en un punado de archivos y te vas a preguntar como hiciste sin
esto.

<br />

Espero que te haya resultado util y lo hayas disfrutado! Hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en las [fuentes aca](https://github.com/kainlite/tr)

<br />
