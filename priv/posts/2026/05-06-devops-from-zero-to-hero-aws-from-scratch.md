%{
  title: "DevOps from Zero to Hero: AWS from Scratch",
  author: "Gabriel Garrido",
  description: "We will set up an AWS account from scratch, configure IAM with least privilege, understand VPC networking, security groups, and get familiar with the key services we will use throughout this series...",
  tags: ~w(devops aws iam vpc beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article six of the DevOps from Zero to Hero series. We have covered DevOps concepts,
built a TypeScript API, learned version control, automated testing, and set up CI/CD. Now it is
time to talk about the cloud. We will set up an AWS account the right way, configure IAM with
least privilege, install the AWS CLI, understand VPC networking and security groups, and overview
the key services we will use throughout the rest of this series.

<br />

Let's get into it.

<br />

##### **Creating your AWS account**
Go to [aws.amazon.com](https://aws.amazon.com) and click "Create an AWS Account." You need an
email, a credit card, and a phone number. AWS will not charge you for creating the account, and
many services have a free tier for 12 months. When you create the account, you get a root user
with unrestricted access to everything. Never use it for daily work. Here is what to do immediately:

<br />

> * **Enable MFA on root**: Go to IAM, click on the root user, and set up multi-factor authentication with an authenticator app like Google Authenticator or Authy
> * **Create an IAM admin user**: We will cover this next. From here on, you log in with the IAM user, not root
> * **Set up a billing alarm**: Go to CloudWatch and create an alarm when estimated charges exceed $10
> * **Store root credentials securely**: Save the password and MFA recovery codes in a password manager, then stop using root

<br />

##### **IAM: Identity and Access Management**
IAM controls who can do what in your AWS account. There are four main concepts:

<br />

> * **Users**: Individual people or applications, each with their own credentials
> * **Groups**: Collections of users. Attach permissions to the group, then add users to it
> * **Roles**: Temporary identities assumed by users, services, or applications (e.g., an EC2 instance assuming a role to read from S3)
> * **Policies**: JSON documents defining what actions are allowed or denied on which resources

<br />

**The principle of least privilege**: give every identity only the permissions it needs. If
credentials get leaked, the blast radius is limited to what that identity was allowed to do.

<br />

**Creating an IAM admin user:**

<br />

1. Go to IAM console, click "Users," then "Create user."
2. Name it `admin`, check "Provide user access to the AWS Management Console."
3. Attach the `AdministratorAccess` policy directly.
4. Save the sign-in URL and credentials, log in as this user, and enable MFA.

<br />

**Writing a custom IAM policy:**

<br />

Here is a least-privilege policy allowing upload and download from a specific S3 bucket:

<br />

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadWrite",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-app-uploads",
        "arn:aws:s3:::my-app-uploads/*"
      ]
    }
  ]
}
```

<br />

> * **Version**: Always `"2012-10-17"` (the policy language version, not a date you change)
> * **Effect**: `"Allow"` or `"Deny"`. Deny always wins
> * **Action**: Specific API calls being permitted
> * **Resource**: AWS resources identified by ARN. Note we need both the bucket and `/*` for objects inside it

<br />

**IAM best practices:**

<br />

> * **Never use root** except for billing and account emergencies
> * **Use groups** to manage permissions, not individual user policies
> * **Use roles instead of access keys** for EC2, Lambda, and ECS
> * **Enable MFA** on every human user
> * **Rotate access keys** every 90 days

<br />

##### **AWS CLI setup and configuration**
The AWS CLI lets you interact with AWS from your terminal. Install it:

<br />

```bash
# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# macOS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
aws --version
```

<br />

Create an access key in IAM for your admin user, then configure:

<br />

```bash
aws configure
# AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
# AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# Default region name [None]: us-east-1
# Default output format [None]: json
```

<br />

**Named profiles** let you manage multiple accounts (dev, staging, prod):

<br />

```bash
aws configure --profile dev
aws configure --profile staging
aws configure --profile prod

# Use a specific profile
aws s3 ls --profile dev

# Or set via environment variable
export AWS_PROFILE=dev
aws sts get-caller-identity
```

<br />

Set your default to dev so you never accidentally run commands against production.

<br />

##### **VPC: Virtual Private Cloud**
A VPC is your own isolated network inside AWS. Every resource you launch lives inside a VPC. You
get a default VPC in each region, but for production create custom VPCs with explicit control.

<br />

**Key concepts:**

<br />

> * **CIDR block**: The IP range for your VPC (e.g., `10.0.0.0/16` gives 65,536 IPs). Chosen at creation, cannot be changed later
> * **Subnets**: Subdivisions of your VPC, each in a specific availability zone
> * **Availability zones (AZs)**: Physically separate data centers within a region for fault tolerance

<br />

**Public vs private subnets:**

<br />

> * **Public subnets** have a route to the internet through an Internet Gateway. Use for load balancers and bastion hosts
> * **Private subnets** have no direct internet route. Use for app servers and databases. They reach the internet outbound through a NAT gateway

<br />

**Route tables** tell traffic where to go. Public subnets route `0.0.0.0/0` to the Internet
Gateway; private subnets route it through the NAT Gateway. Here is a typical production VPC:

<br />

```plaintext
                        Region: us-east-1
 ┌──────────────────────────────────────────────────────────┐
 │                    VPC: 10.0.0.0/16                      │
 │                                                          │
 │  ┌─────────────────────┐    ┌─────────────────────┐      │
 │  │   AZ: us-east-1a    │    │   AZ: us-east-1b    │      │
 │  │                     │    │                     │      │
 │  │ ┌─────────────────┐ │    │ ┌─────────────────┐ │      │
 │  │ │ Public Subnet   │ │    │ │ Public Subnet   │ │      │
 │  │ │ 10.0.1.0/24     │ │    │ │ 10.0.2.0/24     │ │      │
 │  │ │ [Load Balancer] │ │    │ │ [NAT Gateway]   │ │      │
 │  │ └─────────────────┘ │    │ └─────────────────┘ │      │
 │  │ ┌─────────────────┐ │    │ ┌─────────────────┐ │      │
 │  │ │ Private Subnet  │ │    │ │ Private Subnet  │ │      │
 │  │ │ 10.0.3.0/24     │ │    │ │ 10.0.4.0/24     │ │      │
 │  │ │ [App Server]    │ │    │ │ [App Server]    │ │      │
 │  │ │ [Database]      │ │    │ │ [Database]      │ │      │
 │  │ └─────────────────┘ │    │ └─────────────────┘ │      │
 │  └─────────────────────┘    └─────────────────────┘      │
 │                                                          │
 │                    [Internet Gateway]                     │
 └──────────────────────────────────────────────────────────┘
                            │
                        Internet
```

<br />

High availability (two AZs), security (databases in private subnets), and outbound access through
NAT. We will build this VPC with Terraform in a later article.

<br />

##### **Security groups**
Security groups are virtual firewalls for your resources. They are stateful (allow inbound on port
80 and the response is automatically allowed outbound), allow-only (no deny rules, unlisted traffic
is denied), and instance-level (attached to resources, not subnets).

<br />

**Web server security group example:**

<br />

```plaintext
Security Group: web-server-sg

Inbound Rules:
  HTTP       TCP  80     0.0.0.0/0       Allow HTTP from anywhere
  HTTPS      TCP  443    0.0.0.0/0       Allow HTTPS from anywhere
  SSH        TCP  22     203.0.113.50/32 Allow SSH from my IP only

Outbound Rules:
  All        All  All    0.0.0.0/0       Allow all outbound
```

<br />

**Database security group referencing the web server group:**

<br />

```plaintext
Security Group: database-sg

Inbound Rules:
  PostgreSQL TCP  5432   web-server-sg   Allow Postgres from web servers only

Outbound Rules:
  All        All  All    0.0.0.0/0       Allow all outbound
```

<br />

The database references `web-server-sg` as the source, so any instance with that group can reach
the database. No IP tracking needed. Best practices: never open SSH to `0.0.0.0/0`, use security
group references instead of IPs for internal communication, and create separate groups per role.

<br />

##### **Key AWS services overview**
AWS has over 200 services. Here are the core ones for this series:

<br />

> * **EC2**: Virtual servers. Choose OS, CPU, memory. Pay by the second
> * **S3**: Object storage for files. Used for assets, backups, logs, static hosting. 99.999999999% durability
> * **RDS**: Managed databases (PostgreSQL, MySQL, etc.). AWS handles backups, patching, failover
> * **ECS**: Runs Docker containers on EC2 or Fargate (serverless). Handles scheduling and scaling
> * **Lambda**: Serverless functions. Pay only for compute time consumed. Great for event-driven workloads
> * **Route 53**: DNS service with health checks and routing policies
> * **ACM**: Free SSL/TLS certificates. Attach to load balancers or CloudFront
> * **Secrets Manager**: Stores passwords, API keys, tokens with automatic rotation

<br />

##### **AWS Free Tier and surprise bills**
Three free tier types:

<br />

> * **12-month free**: 750 hours/month t2.micro/t3.micro EC2, 5GB S3, 750 hours/month RDS single-AZ
> * **Always free**: 1M Lambda requests/month, 25GB DynamoDB, 1M SNS notifications
> * **Short-term trials**: Service-specific trials (e.g., 750 hours Redshift for 2 months)

<br />

**How to avoid surprise bills:**

<br />

> * **Set up billing alerts** in CloudWatch and **AWS Budgets** with notifications at 50%, 80%, 100%
> * **Check billing dashboard** weekly while learning
> * **Terminate unused resources**: stopped EC2 instances still incur EBS charges
> * **Watch NAT gateways**: ~$32/month even with zero traffic
> * **Watch data transfer**: outbound data from AWS costs money

<br />

Set up a billing alarm with the CLI:

<br />

```bash
# Create an SNS topic for billing alerts
aws sns create-topic --name billing-alerts --profile dev

# Subscribe your email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:billing-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --profile dev

# Create CloudWatch alarm for charges over $10
aws cloudwatch put-metric-alarm \
  --alarm-name "billing-alarm-10-usd" \
  --alarm-description "Alarm when charges exceed $10" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:billing-alerts \
  --region us-east-1 \
  --profile dev
```

<br />

Billing metrics are only available in `us-east-1`, regardless of where your resources live.

<br />

##### **The AWS Well-Architected Framework**
AWS defines six pillars for well-designed cloud systems:

<br />

> * **Operational Excellence**: Automate operations, respond to events, define standards
> * **Security**: Protect data with IAM, encryption, and detective controls
> * **Reliability**: Recover from failures, meet demand, test recovery procedures
> * **Performance Efficiency**: Right-size instances, choose correct storage, monitor performance
> * **Cost Optimization**: Avoid waste with reserved/spot instances and right-sizing
> * **Sustainability**: Minimize environmental impact, optimize utilization

<br />

We will apply these principles as we build real infrastructure in upcoming articles.

<br />

##### **Closing notes**
AWS can feel overwhelming, but most apps only use a handful of services. Once you understand IAM,
VPC, and the core compute and storage services, you have the foundation for everything else. Key
takeaways: never use root, always apply least privilege, understand public vs private subnets, and
set up billing alerts before you forget. In the next article, we will start building real
infrastructure with Terraform, defining VPCs, subnets, security groups, and EC2 instances as code.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: AWS desde Cero",
  author: "Gabriel Garrido",
  description: "Vamos a configurar una cuenta de AWS desde cero, configurar IAM con minimo privilegio, entender el networking de VPC, security groups, y familiarizarnos con los servicios clave que vamos a usar a lo largo de esta serie...",
  tags: ~w(devops aws iam vpc beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo seis de la serie DevOps from Zero to Hero. Ya cubrimos conceptos de DevOps,
construimos una API en TypeScript, aprendimos control de versiones, testing automatizado, y
configuramos CI/CD. Ahora es momento de hablar de la nube. Vamos a configurar una cuenta de AWS
correctamente, configurar IAM con minimo privilegio, instalar el CLI, entender VPC y security
groups, y repasar los servicios clave de la serie.

<br />

Vamos a meternos de lleno.

<br />

##### **Creando tu cuenta de AWS**
Anda a [aws.amazon.com](https://aws.amazon.com) y hace clic en "Create an AWS Account." Necesitas
email, tarjeta de credito y telefono. AWS no te cobra por crear la cuenta, y muchos servicios
tienen free tier por 12 meses. Te dan un usuario root con acceso sin restricciones a todo. Nunca
lo uses para el trabajo diario. Lo que tenes que hacer inmediatamente:

<br />

> * **Habilitar MFA en root**: Anda a IAM, configura autenticacion multifactor con Google Authenticator o Authy
> * **Crear un usuario admin de IAM**: Lo cubrimos a continuacion. De aca en mas, te logeas con el usuario IAM
> * **Configurar alarma de facturacion**: Crea una alarma en CloudWatch cuando los cargos superen $10
> * **Guardar credenciales de root**: Anotalas en un gestor de contraseñas y deja de usar root

<br />

##### **IAM: Identity and Access Management**
IAM controla quien puede hacer que en tu cuenta de AWS. Cuatro conceptos principales:

<br />

> * **Users**: Personas o aplicaciones individuales, cada una con sus propias credenciales
> * **Groups**: Colecciones de usuarios. Adjuntas permisos al grupo y agregas usuarios
> * **Roles**: Identidades temporales que asumen usuarios, servicios o aplicaciones (ej: una instancia EC2 asumiendo un role para leer de S3)
> * **Policies**: Documentos JSON que definen que acciones estan permitidas o denegadas sobre cuales recursos

<br />

**El principio de minimo privilegio**: dale a cada identidad solo los permisos que necesita. Si se
filtran credenciales, el radio de impacto se limita a lo permitido.

<br />

**Creando un usuario admin de IAM:**

<br />

1. Anda a la consola de IAM, clic en "Users," despues "Create user."
2. Nombrado `admin`, marca "Provide user access to the AWS Management Console."
3. Adjunta la policy `AdministratorAccess` directamente.
4. Guarda la URL de login y credenciales, logueate como este usuario y habilita MFA.

<br />

**Escribiendo una policy de IAM personalizada:**

<br />

Aca hay una policy de minimo privilegio que permite subir y descargar de un bucket S3 especifico:

<br />

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadWrite",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-app-uploads",
        "arn:aws:s3:::my-app-uploads/*"
      ]
    }
  ]
}
```

<br />

> * **Version**: Siempre `"2012-10-17"` (version del lenguaje de policies, no una fecha que cambias)
> * **Effect**: `"Allow"` o `"Deny"`. Deny siempre gana
> * **Action**: Llamadas API especificas permitidas
> * **Resource**: Recursos AWS identificados por ARN. Necesitas el bucket y `/*` para los objetos

<br />

**Mejores practicas de IAM:**

<br />

> * **Nunca uses root** excepto facturacion y emergencias
> * **Usa grupos** para permisos, no policies individuales por usuario
> * **Usa roles** en lugar de access keys para EC2, Lambda y ECS
> * **Habilita MFA** en cada usuario humano
> * **Rota access keys** cada 90 dias

<br />

##### **Configuracion del AWS CLI**
El AWS CLI te permite interactuar con AWS desde tu terminal. Instalacion:

<br />

```bash
# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# macOS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
aws --version
```

<br />

Crea un access key en IAM para tu usuario admin, despues configura:

<br />

```bash
aws configure
# AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
# AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# Default region name [None]: us-east-1
# Default output format [None]: json
```

<br />

**Perfiles con nombre** para multiples cuentas (dev, staging, prod):

<br />

```bash
aws configure --profile dev
aws configure --profile staging
aws configure --profile prod

# Usar un perfil especifico
aws s3 ls --profile dev

# O configurar via variable de entorno
export AWS_PROFILE=dev
aws sts get-caller-identity
```

<br />

Configura tu default apuntando a dev para nunca ejecutar comandos contra produccion por accidente.

<br />

##### **VPC: Virtual Private Cloud**
Una VPC es tu propia red aislada dentro de AWS. Cada recurso vive dentro de una VPC. Tenes una
VPC default en cada region, pero para produccion crea VPCs personalizadas.

<br />

**Conceptos clave:**

<br />

> * **Bloque CIDR**: Rango de IPs de tu VPC (ej: `10.0.0.0/16` = 65,536 IPs). Se elige al crear, no se puede cambiar
> * **Subnets**: Subdivisiones de la VPC, cada una en una zona de disponibilidad especifica
> * **Zonas de disponibilidad (AZs)**: Data centers separados fisicamente dentro de una region

<br />

**Subnets publicas vs privadas:**

<br />

> * **Publicas**: Ruta a internet via Internet Gateway. Para load balancers y bastion hosts
> * **Privadas**: Sin ruta directa a internet. Para app servers y bases de datos. Salida via NAT gateway

<br />

**Tablas de ruteo** dictan a donde va el trafico. Las subnets publicas rutean `0.0.0.0/0` al
Internet Gateway; las privadas al NAT Gateway. VPC tipica de produccion:

<br />

```plaintext
                        Region: us-east-1
 ┌──────────────────────────────────────────────────────────┐
 │                    VPC: 10.0.0.0/16                      │
 │                                                          │
 │  ┌─────────────────────┐    ┌─────────────────────┐      │
 │  │   AZ: us-east-1a    │    │   AZ: us-east-1b    │      │
 │  │                     │    │                     │      │
 │  │ ┌─────────────────┐ │    │ ┌─────────────────┐ │      │
 │  │ │ Subnet Publica  │ │    │ │ Subnet Publica  │ │      │
 │  │ │ 10.0.1.0/24     │ │    │ │ 10.0.2.0/24     │ │      │
 │  │ │ [Load Balancer] │ │    │ │ [NAT Gateway]   │ │      │
 │  │ └─────────────────┘ │    │ └─────────────────┘ │      │
 │  │ ┌─────────────────┐ │    │ ┌─────────────────┐ │      │
 │  │ │ Subnet Privada  │ │    │ │ Subnet Privada  │ │      │
 │  │ │ 10.0.3.0/24     │ │    │ │ 10.0.4.0/24     │ │      │
 │  │ │ [App Server]    │ │    │ │ [App Server]    │ │      │
 │  │ │ [Database]      │ │    │ │ [Database]      │ │      │
 │  │ └─────────────────┘ │    │ └─────────────────┘ │      │
 │  └─────────────────────┘    └─────────────────────┘      │
 │                                                          │
 │                    [Internet Gateway]                     │
 └──────────────────────────────────────────────────────────┘
                            │
                        Internet
```

<br />

Alta disponibilidad (dos AZs), seguridad (bases de datos en subnets privadas), y acceso saliente
via NAT. Vamos a construir esta VPC con Terraform mas adelante.

<br />

##### **Security groups**
Security groups son firewalls virtuales para tus recursos. Son stateful (permitir entrada en
puerto 80 y la respuesta se permite de salida automaticamente), solo permiten (sin regla que
permita = denegado), y a nivel de instancia (se adjuntan a recursos, no subnets).

<br />

**Ejemplo de security group para web server:**

<br />

```plaintext
Security Group: web-server-sg

Reglas de Entrada:
  HTTP       TCP  80     0.0.0.0/0       Permitir HTTP
  HTTPS      TCP  443    0.0.0.0/0       Permitir HTTPS
  SSH        TCP  22     203.0.113.50/32 SSH solo desde mi IP

Reglas de Salida:
  Todo       Todo Todo   0.0.0.0/0       Permitir toda salida
```

<br />

**Security group de base de datos referenciando el grupo web:**

<br />

```plaintext
Security Group: database-sg

Reglas de Entrada:
  PostgreSQL TCP  5432   web-server-sg   Solo desde web servers

Reglas de Salida:
  Todo       Todo Todo   0.0.0.0/0       Permitir toda salida
```

<br />

La base de datos referencia `web-server-sg` como origen. Cualquier instancia con ese grupo puede
llegar a la DB, sin trackeo de IPs. Mejores practicas: nunca abras SSH a `0.0.0.0/0`, usa
referencias a security groups para comunicacion interna, y crea grupos separados por rol.

<br />

##### **Resumen de servicios clave de AWS**
AWS tiene mas de 200 servicios. Los que vamos a usar en la serie:

<br />

> * **EC2**: Servidores virtuales. Elegis OS, CPU, memoria. Pagas por segundo
> * **S3**: Storage de objetos. Para assets, backups, logs, hosting estatico. 99.999999999% durabilidad
> * **RDS**: Bases de datos administradas (PostgreSQL, MySQL, etc.). AWS maneja backups, parches, failover
> * **ECS**: Corre contenedores Docker en EC2 o Fargate (serverless). Maneja scheduling y scaling
> * **Lambda**: Funciones serverless. Pagas solo por tiempo de computo. Ideal para workloads event-driven
> * **Route 53**: Servicio DNS con health checks y politicas de ruteo
> * **ACM**: Certificados SSL/TLS gratuitos. Adjuntar a load balancers o CloudFront
> * **Secrets Manager**: Almacena contraseñas, API keys, tokens con rotacion automatica

<br />

##### **Free Tier y como evitar facturas sorpresa**
El free tier tiene tres tipos:

<br />

> * **12 meses gratis**: 750 hs/mes EC2 t2/t3.micro, 5GB S3, 750 hs/mes RDS single-AZ
> * **Siempre gratis**: 1M requests Lambda/mes, 25GB DynamoDB, 1M notificaciones SNS
> * **Pruebas cortas**: Trials por servicio (ej: 750 hs Redshift por 2 meses)

<br />

**Para evitar sorpresas:**

<br />

> * **Alarmas de facturacion** en CloudWatch y **AWS Budgets** con alertas al 50%, 80%, 100%
> * **Revisa facturacion** semanalmente mientras aprendes
> * **Termina recursos sin usar**: instancias EC2 detenidas igual generan cargos de EBS
> * **Ojo con NAT gateways**: ~$32/mes incluso sin trafico
> * **Ojo con transferencia de datos**: datos salientes de AWS cuestan plata

<br />

Configurar alarma de facturacion con CLI:

<br />

```bash
# Crear topic SNS
aws sns create-topic --name billing-alerts --profile dev

# Subscribir email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:billing-alerts \
  --protocol email \
  --notification-endpoint tu-email@example.com \
  --profile dev

# Crear alarma CloudWatch para cargos mayores a $10
aws cloudwatch put-metric-alarm \
  --alarm-name "billing-alarm-10-usd" \
  --alarm-description "Alarma cuando cargos superan $10" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:billing-alerts \
  --region us-east-1 \
  --profile dev
```

<br />

Las metricas de facturacion solo estan en `us-east-1`, sin importar donde esten tus recursos.

<br />

##### **El AWS Well-Architected Framework**
AWS define seis pilares para sistemas bien diseñados:

<br />

> * **Excelencia Operacional**: Automatizar operaciones, responder a eventos, definir estandares
> * **Seguridad**: Proteger datos con IAM, encriptacion y controles detectivos
> * **Confiabilidad**: Recuperarse de fallas, cumplir demanda, probar procedimientos de recuperacion
> * **Eficiencia de Rendimiento**: Dimensionar correctamente instancias, monitorear rendimiento
> * **Optimizacion de Costos**: Evitar desperdicio con instancias reservadas/spot y right-sizing
> * **Sustentabilidad**: Minimizar impacto ambiental, optimizar utilizacion

<br />

Vamos a aplicar estos principios mientras construimos infraestructura real.

<br />

##### **Notas finales**
AWS puede sentirse abrumador, pero la mayoria de las apps solo usan un puniado de servicios. Una
vez que entendes IAM, VPC y los servicios core de computo y storage, tenes la base para todo.
Puntos clave: nunca uses root, siempre aplica minimo privilegio, entende subnets publicas vs
privadas, y configura alertas de facturacion antes de olvidarte. En el proximo articulo, vamos a
construir infraestructura real con Terraform, definiendo VPCs, subnets, security groups e
instancias EC2 como codigo.

<br />

Espero que te haya resultado util y lo hayas disfrutado, hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que lo corrija.

Tambien, podes revisar el codigo fuente y los cambios en los [fuentes aca](https://github.com/kainlite/tr)

<br />
