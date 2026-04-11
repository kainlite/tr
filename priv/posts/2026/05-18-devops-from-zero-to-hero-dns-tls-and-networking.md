%{
  title: "DevOps from Zero to Hero: DNS, TLS, and Making Your App Reachable",
  author: "Gabriel Garrido",
  description: "We will cover DNS fundamentals, Route53 hosted zones and routing policies, TLS certificates with AWS Certificate Manager, and connect it all to our ALB so users can reach our app over HTTPS...",
  tags: ~w(devops aws dns tls networking beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article ten of the DevOps from Zero to Hero series. In article eight we deployed our
TypeScript API to ECS with Fargate and put an Application Load Balancer in front of it. That
setup works, but right now the only way to reach the API is through an ugly auto-generated ALB
hostname like `task-api-alb-123456789.us-east-1.elb.amazonaws.com`. No one wants to type that
into a browser, and no one should be sending real traffic over plain HTTP.

<br />

In this article we are going to fix both of those problems. We will register a domain name, set
up DNS so that a clean URL like `api.yourdomain.com` points to our load balancer, and configure
TLS so all traffic is encrypted with HTTPS. By the end, your application will be reachable at a
real domain with a valid certificate, exactly like a production service should be.

<br />

Let's get into it.

<br />

##### **DNS fundamentals: how your browser finds a server**
DNS (Domain Name System) is the phonebook of the internet. When you type `google.com` into your
browser, your computer does not magically know which IP address to connect to. It asks the DNS
system, and DNS translates that human-readable name into a machine-readable IP address.

<br />

Here is the simplified flow of what happens when you visit `api.yourdomain.com`:

<br />

```plaintext
1. Browser asks: "What is the IP for api.yourdomain.com?"
2. Your OS checks its local cache. Not found.
3. Your OS asks your ISP's recursive resolver.
4. Resolver asks a root nameserver: "Who handles .com?"
5. Root says: "Ask the .com TLD nameserver."
6. Resolver asks the .com TLD: "Who handles yourdomain.com?"
7. TLD says: "Ask ns-1234.awsdns-56.org (the authoritative nameserver)."
8. Resolver asks the authoritative nameserver: "What is api.yourdomain.com?"
9. Authoritative nameserver responds: "It is an A record pointing to 54.23.45.67."
10. Browser connects to 54.23.45.67.
```

<br />

This entire process usually takes less than 100 milliseconds. Once resolved, the result is cached
at multiple levels so subsequent requests are almost instant.

<br />

##### **DNS record types you need to know**
DNS is not just about mapping names to IP addresses. There are several record types, each serving
a different purpose:

<br />

> * **A record**: Maps a domain name to an IPv4 address. Example: `api.yourdomain.com -> 54.23.45.67`. This is the most basic record type.
> * **AAAA record**: Same as A, but for IPv6 addresses. Example: `api.yourdomain.com -> 2600:1f18:243:...`. As IPv6 adoption grows, you will see more of these.
> * **CNAME record**: Maps a domain name to another domain name (an alias). Example: `www.yourdomain.com -> yourdomain.com`. The resolver follows the chain until it reaches an A record. Important: you cannot use a CNAME at the zone apex (the bare domain like `yourdomain.com`).
> * **NS record**: Specifies the authoritative nameservers for a domain. When you register a domain, the registrar needs to know which nameservers hold the DNS records for that domain.
> * **MX record**: Specifies mail servers for a domain. Not relevant for this article, but you will encounter these if you ever set up email.
> * **TXT record**: Holds arbitrary text. Used for domain verification (proving you own a domain), SPF records for email, and TLS certificate validation (which we will use later).

<br />

##### **TTL: how long DNS answers are cached**
Every DNS record has a TTL (Time To Live), measured in seconds. It tells resolvers how long to
cache the answer before asking again.

<br />

> * **High TTL (86400 = 24 hours)**: Good for records that rarely change. Reduces DNS queries, faster for users. Bad for quick changes since you have to wait for caches to expire.
> * **Low TTL (60 = 1 minute)**: Good when you expect to change records frequently (during migrations, failovers). More DNS queries, slightly higher latency on first request.
> * **Common strategy**: Keep TTL high for normal operations. Before a planned migration, lower the TTL a day or two in advance, do the change, verify it works, then raise the TTL back up.

<br />

A common mistake is forgetting about TTL when doing a migration. If your TTL is 24 hours and you
change an A record, some users will still be hitting the old IP for up to 24 hours. Plan ahead.

<br />

##### **Route53: AWS's DNS service**
Route53 is AWS's managed DNS service. It is highly available, globally distributed, and integrates
natively with other AWS services. The name comes from the fact that DNS uses port 53.

<br />

The core concept in Route53 is the **hosted zone**. A hosted zone is a container for DNS records
that belong to a single domain. When you create a hosted zone for `yourdomain.com`, Route53 assigns
four nameservers to it. You then configure your domain registrar to point at those nameservers.

<br />

There are two types of hosted zones:

<br />

> * **Public hosted zone**: Resolves queries from the public internet. This is what you need for your user-facing application.
> * **Private hosted zone**: Resolves queries only within a VPC. Useful for internal service discovery (e.g., `database.internal.yourdomain.com`).

<br />

##### **Route53 routing policies**
Route53 supports several routing policies that go beyond simple "name to IP" resolution:

<br />

> * **Simple routing**: One record, one or more values. Route53 returns all values in random order. This is the default and what we will use in this article.
> * **Weighted routing**: Distribute traffic across multiple resources by weight. For example, send 90% of traffic to version 1 and 10% to version 2. Great for canary deployments.
> * **Failover routing**: Active-passive setup. Route53 sends traffic to the primary resource. If a health check fails, it automatically switches to a secondary resource.
> * **Latency-based routing**: Route users to the region with the lowest latency. If you have servers in us-east-1 and eu-west-1, European users automatically get routed to eu-west-1.
> * **Geolocation routing**: Route based on the user's geographic location. Useful for compliance (keep EU user data in the EU) or serving localized content.

<br />

For most applications starting out, simple routing is all you need. As you grow and deploy to
multiple regions, the other policies become incredibly valuable.

<br />

##### **Domain registration and nameserver delegation**
Before you can use Route53 for DNS, you need a domain name. You have two options:

<br />

> * **Register through Route53**: AWS acts as both your registrar and DNS provider. This is the simplest option because the nameserver delegation happens automatically.
> * **Register elsewhere and delegate to Route53**: Buy your domain from a registrar like Namecheap, GoDaddy, or Cloudflare, then update the nameservers to point at the Route53 hosted zone's NS records.

<br />

If you registered your domain elsewhere, the process looks like this:

<br />

```plaintext
1. Create a hosted zone in Route53 for yourdomain.com
2. Route53 assigns four NS records (e.g., ns-1234.awsdns-56.org)
3. Go to your registrar's dashboard
4. Replace the default nameservers with the four Route53 NS records
5. Wait for propagation (can take up to 48 hours, usually much faster)
6. Now Route53 is authoritative for yourdomain.com
```

<br />

Once the delegation is complete, any DNS records you create in your Route53 hosted zone will be
the ones the internet sees.

<br />

##### **Route53 Alias records: a special AWS feature**
Standard DNS has a limitation: you cannot put a CNAME record at the zone apex (the bare domain
like `yourdomain.com`). This is a problem because AWS resources like ALBs and CloudFront
distributions do not have static IP addresses, so you cannot use an A record either.

<br />

Route53 solves this with **Alias records**. An Alias record looks like an A or AAAA record to DNS
clients, but behind the scenes it resolves to another AWS resource. Think of it as a CNAME that
works at the zone apex.

<br />

> * **No charge**: Route53 does not charge for queries to Alias records that point at AWS resources.
> * **Zone apex compatible**: You can create an Alias record for `yourdomain.com` pointing at your ALB.
> * **Health check aware**: Alias records can inherit health checks from the target resource.

<br />

We will use an Alias record to point our domain at our Application Load Balancer.

<br />

##### **TLS/SSL: why HTTPS matters**
Right now our ALB is serving traffic over HTTP on port 80. Every request and response travels
across the internet in plain text. Anyone between the user and your server (ISPs, Wi-Fi operators,
anyone on the same network) can read the data, modify it, or inject content.

<br />

TLS (Transport Layer Security) encrypts the connection between the user's browser and your server.
When you see the padlock icon and `https://` in your browser, that means TLS is in use.

<br />

Why HTTPS matters:

<br />

> * **Confidentiality**: Data in transit is encrypted. Passwords, API keys, personal information are all protected.
> * **Integrity**: Data cannot be modified in transit. No one can inject ads, malware, or tracking scripts into your responses.
> * **Authentication**: The certificate proves that the server is who it claims to be. This prevents man-in-the-middle attacks.
> * **SEO and trust**: Google has used HTTPS as a ranking signal since 2014. Browsers mark HTTP sites as "Not Secure." Users trust HTTPS sites more.
> * **Required for modern features**: HTTP/2, service workers, geolocation API, and many other browser features require HTTPS.

<br />

In short, there is no good reason to serve production traffic over HTTP.

<br />

##### **How TLS works (the short version)**
When your browser connects to an HTTPS server, a process called the TLS handshake happens before
any application data is exchanged:

<br />

```plaintext
Client                              Server
  |                                    |
  |--- ClientHello (supported ciphers) -->|
  |                                    |
  |<-- ServerHello + Certificate -------|
  |                                    |
  |--- Key exchange material ---------->|
  |                                    |
  |<-- Key exchange material -----------|
  |                                    |
  |   (Both sides derive session key)  |
  |                                    |
  |<== Encrypted application data ====>|
```

<br />

> * **ClientHello**: The browser sends the TLS versions and cipher suites it supports.
> * **ServerHello**: The server picks a cipher suite and sends its certificate (which contains the server's public key).
> * **Certificate validation**: The browser checks that the certificate was issued by a trusted Certificate Authority (CA), is not expired, and matches the domain name.
> * **Key exchange**: Both sides exchange key material and derive a shared session key.
> * **Encrypted communication**: All subsequent data is encrypted with the session key using symmetric encryption (much faster than asymmetric).

<br />

The important takeaway is that you need a valid TLS certificate for your domain. That is where
AWS Certificate Manager comes in.

<br />

##### **AWS Certificate Manager (ACM)**
ACM is a free service that lets you provision, manage, and deploy TLS certificates for use with
AWS services like ALB, CloudFront, and API Gateway.

<br />

The key benefits:

<br />

> * **Free**: Public certificates are free when used with AWS services. No need to pay a CA.
> * **Auto-renewal**: ACM automatically renews certificates before they expire. No more 3 AM pages because a certificate expired.
> * **DNS validation**: You prove domain ownership by adding a CNAME record to your DNS. This is fully automatable with Terraform.
> * **Managed private keys**: ACM stores the private key securely. You never have to handle it yourself.

<br />

The process for getting a certificate with ACM looks like this:

<br />

```plaintext
1. Request a certificate for api.yourdomain.com (and optionally *.yourdomain.com)
2. ACM gives you a CNAME record to add to your DNS
3. You add the CNAME record to your Route53 hosted zone
4. ACM validates that you own the domain
5. Certificate is issued (usually within minutes)
6. ACM auto-renews it every 13 months
```

<br />

DNS validation is preferred over email validation because it can be fully automated and does not
require someone to click a link in an email.

<br />

##### **Connecting it all: the full picture**
Let's put together everything we have discussed. Here is how all the pieces connect to make your
application reachable over HTTPS at a real domain:

<br />

```plaintext
User's browser
     |
     | (DNS query: api.yourdomain.com)
     v
Route53 hosted zone
     |
     | (Alias record -> ALB)
     v
Application Load Balancer
     |
     |--- Port 443 (HTTPS) -> Forward to target group (with ACM certificate)
     |--- Port 80  (HTTP)  -> Redirect to HTTPS
     |
     v
ECS Fargate tasks (your API containers)
```

<br />

> * **Route53** resolves `api.yourdomain.com` to the ALB's address using an Alias record.
> * **ACM** provides the TLS certificate that the ALB uses for HTTPS termination.
> * **ALB** terminates TLS, meaning the encrypted connection ends at the ALB. Traffic between the ALB and your ECS tasks travels over HTTP within your VPC (which is fine because it is on a private network).
> * **HTTP to HTTPS redirect**: The ALB listens on port 80 and automatically redirects to port 443, so users who type `http://` still end up on HTTPS.

<br />

##### **Terraform: Route53 hosted zone**
Let's write the Terraform code. We will build on the infrastructure from article eight. First,
the Route53 hosted zone:

<br />

```hcl
# dns.tf
variable "domain_name" {
  description = "The root domain name"
  type        = string
  default     = "yourdomain.com"
}

variable "api_subdomain" {
  description = "Subdomain for the API"
  type        = string
  default     = "api"
}

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name = var.domain_name
  }
}
```

<br />

This creates a public hosted zone. Route53 automatically creates the NS and SOA records. After
applying this, you need to copy the four NS records and configure them at your domain registrar.
You only need to do this once.

<br />

You can output the nameservers so you know what to set:

<br />

```hcl
output "nameservers" {
  description = "Nameservers for the hosted zone. Set these at your registrar."
  value       = aws_route53_zone.main.name_servers
}
```

<br />

##### **Terraform: ACM certificate with DNS validation**
Next, we request a TLS certificate and validate it automatically through DNS:

<br />

```hcl
# acm.tf
resource "aws_acm_certificate" "app" {
  domain_name               = "${var.api_subdomain}.${var.domain_name}"
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.api_subdomain}.${var.domain_name}"
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}
```

<br />

Let's break this down:

<br />

> * `aws_acm_certificate` requests the certificate. We request it for `api.yourdomain.com` with a wildcard SAN (`*.yourdomain.com`) so it covers any subdomain.
> * `validation_method = "DNS"` tells ACM we will prove domain ownership by adding DNS records.
> * `create_before_destroy = true` ensures that when renewing, the new certificate is created before the old one is destroyed. This prevents downtime.
> * `aws_route53_record.acm_validation` creates the CNAME records that ACM requires for validation. The `for_each` loop handles the case where the certificate covers multiple domain names.
> * `aws_acm_certificate_validation` is a waiter resource. Terraform will block here until ACM confirms the certificate is validated and issued. This usually takes 2-5 minutes.

<br />

##### **Terraform: ALB HTTPS listener and HTTP redirect**
In article eight, we created an ALB with only an HTTP listener. Now we are going to add an HTTPS
listener and change the HTTP listener to redirect to HTTPS:

<br />

```hcl
# alb.tf (updated)

# Change the existing HTTP listener to redirect
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Add HTTPS listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
```

<br />

Important details:

<br />

> * The HTTP listener now returns a **301 redirect** to HTTPS. This is a permanent redirect, so browsers and search engines will remember it and go directly to HTTPS next time.
> * The HTTPS listener references the validated ACM certificate. Note that we reference `aws_acm_certificate_validation.app.certificate_arn`, not the certificate directly. This ensures Terraform waits for validation to complete before creating the listener.
> * `ssl_policy` controls which TLS versions and cipher suites the ALB accepts. `ELBSecurityPolicy-TLS13-1-2-2021-06` supports TLS 1.2 and 1.3, which is the current best practice. Older policies that allow TLS 1.0 or 1.1 should not be used.

<br />

You also need to update the ALB security group to allow HTTPS traffic:

<br />

```hcl
# security_groups.tf (updated)
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere (for redirect)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
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
```

<br />

We keep port 80 open so that the redirect works. If you close port 80, users who type `http://`
will get a connection timeout instead of a redirect.

<br />

##### **Terraform: Route53 record pointing to the ALB**
Finally, we create the DNS record that points our domain at the load balancer:

<br />

```hcl
# dns.tf (continued)
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}
```

<br />

This is an Alias record. Even though it is `type = "A"`, it does not contain a hardcoded IP
address. Instead, it points to the ALB's DNS name. Route53 resolves the ALB's current IP addresses
behind the scenes and returns them to the client.

<br />

`evaluate_target_health = true` means that if the ALB has no healthy targets, Route53 will not
return this record in DNS queries. This is useful in multi-region setups with failover routing.

<br />

##### **Health checks**
Health checks are how AWS determines whether your application is actually working. There are two
levels of health checks in our setup:

<br />

**ALB target group health checks**

<br />

We already configured these in article eight. The ALB periodically sends HTTP requests to your
ECS tasks on a path you define (like `/health`). If a task fails consecutive checks, the ALB
stops sending it traffic and ECS replaces it.

<br />

```hcl
# Already in our target group from article 8
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
```

<br />

**Route53 health checks**

<br />

Route53 health checks operate at the DNS level. They monitor an endpoint and can trigger DNS
failover if the endpoint goes down. These are particularly useful when you have resources in
multiple regions:

<br />

```hcl
# route53_health.tf
resource "aws_route53_health_check" "api" {
  fqdn              = "${var.api_subdomain}.${var.domain_name}"
  port               = 443
  type               = "HTTPS"
  resource_path      = "/health"
  failure_threshold  = 3
  request_interval   = 30
  measure_latency    = true

  tags = {
    Name = "${var.api_subdomain}.${var.domain_name}-health-check"
  }
}
```

<br />

> * `type = "HTTPS"` means Route53 connects over TLS to check the endpoint.
> * `failure_threshold = 3` means three consecutive failures mark the endpoint as unhealthy.
> * `request_interval = 30` checks every 30 seconds. You can set this to 10 for faster detection, but it costs more.
> * `measure_latency = true` tracks latency metrics in CloudWatch.

<br />

For a single-region setup, Route53 health checks are optional but nice to have for monitoring. For
multi-region with failover routing, they are essential.

<br />

##### **The full Terraform configuration**
Let's put it all together in one view so you can see how the pieces connect:

<br />

```hcl
# Full dns.tf
variable "domain_name" {
  description = "The root domain name"
  type        = string
  default     = "yourdomain.com"
}

variable "api_subdomain" {
  description = "Subdomain for the API"
  type        = string
  default     = "api"
}

# Hosted zone
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name = var.domain_name
  }
}

# ACM certificate
resource "aws_acm_certificate" "app" {
  domain_name               = "${var.api_subdomain}.${var.domain_name}"
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.api_subdomain}.${var.domain_name}"
  }
}

# DNS validation records for ACM
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# DNS record pointing to ALB
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

# Outputs
output "nameservers" {
  description = "Nameservers for the hosted zone. Set these at your registrar."
  value       = aws_route53_zone.main.name_servers
}

output "app_url" {
  description = "The HTTPS URL for the API"
  value       = "https://${var.api_subdomain}.${var.domain_name}"
}
```

<br />

##### **Applying the changes**
Run `terraform plan` first to see what will be created:

<br />

```bash
terraform plan
```

<br />

You should see new resources for the hosted zone, ACM certificate, validation records, HTTPS
listener, and the DNS record. Once you are satisfied with the plan:

<br />

```bash
terraform apply
```

<br />

The `aws_acm_certificate_validation` resource will block until the certificate is validated. This
usually takes 2-5 minutes. If it takes longer than 10 minutes, check that the validation CNAME
records were created correctly in the hosted zone and that your nameservers are properly delegated.

<br />

After the apply completes, update your nameservers at your registrar if you have not already. Then
verify everything works:

<br />

```bash
# Check DNS resolution
dig api.yourdomain.com

# Test HTTPS
curl -v https://api.yourdomain.com/health

# Test HTTP redirect
curl -v http://api.yourdomain.com/health
# Should return a 301 redirect to https://
```

<br />

##### **Debugging DNS issues**
DNS problems are some of the most frustrating to debug because of caching. Here are the tools and
techniques you need:

<br />

```bash
# Query a specific nameserver directly (bypass cache)
dig @ns-1234.awsdns-56.org api.yourdomain.com

# Check all record types
dig api.yourdomain.com ANY

# Trace the full resolution path
dig +trace api.yourdomain.com

# Check nameserver delegation
dig yourdomain.com NS

# Check TXT records (useful for ACM validation)
dig _acme-challenge.api.yourdomain.com TXT
```

<br />

Common issues and how to fix them:

<br />

> * **"NXDOMAIN" (domain not found)**: Your nameservers are not delegated correctly. Check the NS records at your registrar.
> * **Old IP address returned**: DNS caching. Wait for the TTL to expire, or use `dig @8.8.8.8` to check Google's resolvers directly.
> * **ACM validation stuck**: The CNAME record name and value must match exactly what ACM expects. Check for trailing dots or typos.
> * **Certificate not valid for domain**: The certificate's Common Name or SAN does not match the domain. Make sure you requested the certificate for the correct domain name.

<br />

##### **A note about CloudFront (CDN)**
So far we have connected users directly to our ALB through Route53. This works well, but for
applications that serve static assets (images, CSS, JavaScript) or have users spread across the
globe, you should consider putting CloudFront in front of your ALB.

<br />

CloudFront is AWS's CDN (Content Delivery Network). It caches your content at edge locations
around the world, so users get responses from a server that is geographically close to them
instead of from your origin region.

<br />

```plaintext
Without CloudFront:
  User in Tokyo -> Route53 -> ALB in us-east-1 (200ms latency)

With CloudFront:
  User in Tokyo -> Route53 -> CloudFront edge in Tokyo (cached, 20ms)
                                    |
                                    v (cache miss only)
                              ALB in us-east-1
```

<br />

Benefits of CloudFront:

<br />

> * **Lower latency**: Content served from the nearest edge location.
> * **Reduced origin load**: Cached responses do not hit your ALB or ECS tasks.
> * **DDoS protection**: CloudFront integrates with AWS Shield for DDoS mitigation.
> * **Free ACM certificates**: CloudFront uses ACM certificates from us-east-1 (this is a requirement, the certificate must be in us-east-1 regardless of where your origin is).

<br />

We will not set up CloudFront in this article since it deserves its own deep dive, but keep it in
mind for when you need to optimize performance for a global audience.

<br />

##### **Cost breakdown**
Let's look at what this setup costs:

<br />

> * **Route53 hosted zone**: $0.50/month per hosted zone.
> * **Route53 queries**: $0.40 per million queries. For most applications this is negligible.
> * **Route53 health checks**: $0.50/month for a basic HTTPS health check. $1.00/month with latency measurement.
> * **ACM certificates**: Free when used with AWS services (ALB, CloudFront, API Gateway).
> * **ALB**: The ALB was already part of our ECS setup. No additional cost for HTTPS termination.

<br />

Total additional cost for DNS and TLS: roughly $1-2/month. This is one of the cheapest and highest
value improvements you can make to your infrastructure.

<br />

##### **Security best practices**
Before we wrap up, here are some security practices to keep in mind:

<br />

> * **Always redirect HTTP to HTTPS**: Never serve production traffic over plain HTTP.
> * **Use a modern TLS policy**: `ELBSecurityPolicy-TLS13-1-2-2021-06` or newer. Disable TLS 1.0 and 1.1.
> * **Enable HSTS**: Add the `Strict-Transport-Security` header in your application to tell browsers to always use HTTPS. This prevents downgrade attacks.
> * **Use separate certificates per environment**: Do not reuse production certificates in staging. ACM is free, so there is no reason not to have separate certificates.
> * **Monitor certificate expiry**: Even though ACM auto-renews, set up a CloudWatch alarm for certificate expiry as a safety net. If DNS validation fails for some reason, auto-renewal will fail silently.

<br />

##### **Closing notes**
Your application is now reachable at a real domain over HTTPS. We covered a lot of ground in this
article: DNS fundamentals and record types, Route53 hosted zones and routing policies, TLS
certificates with ACM, HTTPS termination at the ALB, HTTP to HTTPS redirects, health checks at
both the ALB and DNS level, and the Terraform code to provision all of it.

<br />

This is a milestone in the series. Your TypeScript API is now running in containers on ECS,
behind a load balancer, with auto-scaling, accessible at a clean URL over an encrypted connection.
That is a production-grade setup.

<br />

In the next article, we will look at monitoring and observability so you can see what your
application is doing in production and catch problems before your users do.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: DNS, TLS, y Como Hacer Tu App Accesible",
  author: "Gabriel Garrido",
  description: "Vamos a cubrir fundamentos de DNS, hosted zones y politicas de ruteo en Route53, certificados TLS con AWS Certificate Manager, y conectar todo a nuestro ALB para que los usuarios lleguen a nuestra app por HTTPS...",
  tags: ~w(devops aws dns tls networking beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo diez de la serie DevOps desde Cero. En el articulo ocho deployeamos nuestra
API TypeScript a ECS con Fargate y pusimos un Application Load Balancer adelante. Esa configuracion
funciona, pero ahora mismo la unica forma de llegar a la API es a traves de un hostname auto-generado
del ALB como `task-api-alb-123456789.us-east-1.elb.amazonaws.com`. Nadie quiere escribir eso en un
navegador, y nadie deberia estar mandando trafico real por HTTP plano.

<br />

En este articulo vamos a resolver esos dos problemas. Vamos a registrar un dominio, configurar DNS
para que una URL limpia como `api.tudominio.com` apunte a nuestro load balancer, y configurar TLS
para que todo el trafico este cifrado con HTTPS. Al final, tu aplicacion va a ser accesible desde un
dominio real con un certificado valido, exactamente como deberia ser un servicio en produccion.

<br />

Vamos a meternos de lleno.

<br />

##### **Fundamentos de DNS: como tu navegador encuentra un servidor**
DNS (Domain Name System) es la guia telefonica de internet. Cuando escribis `google.com` en tu
navegador, tu computadora no sabe magicamente a que direccion IP conectarse. Le pregunta al sistema
DNS, y DNS traduce ese nombre legible para humanos en una direccion IP legible para maquinas.

<br />

Aca esta el flujo simplificado de lo que pasa cuando visitas `api.tudominio.com`:

<br />

```plaintext
1. El navegador pregunta: "Cual es la IP de api.tudominio.com?"
2. Tu SO revisa su cache local. No la encuentra.
3. Tu SO le pregunta al resolver recursivo de tu ISP.
4. El resolver le pregunta a un nameserver raiz: "Quien maneja .com?"
5. El raiz dice: "Preguntale al nameserver TLD de .com."
6. El resolver le pregunta al TLD de .com: "Quien maneja tudominio.com?"
7. El TLD dice: "Preguntale a ns-1234.awsdns-56.org (el nameserver autoritativo)."
8. El resolver le pregunta al nameserver autoritativo: "Que es api.tudominio.com?"
9. El nameserver autoritativo responde: "Es un registro A apuntando a 54.23.45.67."
10. El navegador se conecta a 54.23.45.67.
```

<br />

Todo este proceso generalmente tarda menos de 100 milisegundos. Una vez resuelto, el resultado se
cachea en multiples niveles para que las peticiones siguientes sean casi instantaneas.

<br />

##### **Tipos de registros DNS que necesitas conocer**
DNS no se trata solo de mapear nombres a direcciones IP. Hay varios tipos de registros, cada uno
con un proposito diferente:

<br />

> * **Registro A**: Mapea un nombre de dominio a una direccion IPv4. Ejemplo: `api.tudominio.com -> 54.23.45.67`. Este es el tipo de registro mas basico.
> * **Registro AAAA**: Igual que A, pero para direcciones IPv6. Ejemplo: `api.tudominio.com -> 2600:1f18:243:...`. A medida que crece la adopcion de IPv6, vas a ver mas de estos.
> * **Registro CNAME**: Mapea un nombre de dominio a otro nombre de dominio (un alias). Ejemplo: `www.tudominio.com -> tudominio.com`. El resolver sigue la cadena hasta llegar a un registro A. Importante: no podes usar un CNAME en el apex de zona (el dominio pelado como `tudominio.com`).
> * **Registro NS**: Especifica los nameservers autoritativos para un dominio. Cuando registras un dominio, el registrador necesita saber que nameservers tienen los registros DNS de ese dominio.
> * **Registro MX**: Especifica los servidores de correo para un dominio. No es relevante para este articulo, pero te los vas a cruzar si alguna vez configuras email.
> * **Registro TXT**: Contiene texto arbitrario. Se usa para verificacion de dominio (probar que sos duenio de un dominio), registros SPF para email y validacion de certificados TLS (que vamos a usar mas adelante).

<br />

##### **TTL: cuanto tiempo se cachean las respuestas DNS**
Cada registro DNS tiene un TTL (Time To Live), medido en segundos. Le dice a los resolvers cuanto
tiempo cachear la respuesta antes de volver a preguntar.

<br />

> * **TTL alto (86400 = 24 horas)**: Bueno para registros que rara vez cambian. Reduce consultas DNS, mas rapido para los usuarios. Malo para cambios rapidos porque tenes que esperar a que expiren los caches.
> * **TTL bajo (60 = 1 minuto)**: Bueno cuando esperas cambiar registros frecuentemente (durante migraciones, failovers). Mas consultas DNS, latencia ligeramente mayor en la primera peticion.
> * **Estrategia comun**: Mantene el TTL alto para operaciones normales. Antes de una migracion planificada, baja el TTL uno o dos dias antes, hace el cambio, verifica que funciona, y despues subi el TTL de vuelta.

<br />

Un error comun es olvidarse del TTL cuando haces una migracion. Si tu TTL es de 24 horas y cambias
un registro A, algunos usuarios van a seguir pegandole a la IP vieja hasta por 24 horas. Planifica
con anticipacion.

<br />

##### **Route53: el servicio DNS de AWS**
Route53 es el servicio de DNS gestionado de AWS. Es altamente disponible, distribuido globalmente y
se integra nativamente con otros servicios de AWS. El nombre viene del hecho de que DNS usa el
puerto 53.

<br />

El concepto central en Route53 es la **hosted zone**. Una hosted zone es un contenedor para registros
DNS que pertenecen a un solo dominio. Cuando creas una hosted zone para `tudominio.com`, Route53 le
asigna cuatro nameservers. Despues configuras tu registrador de dominios para que apunte a esos
nameservers.

<br />

Hay dos tipos de hosted zones:

<br />

> * **Hosted zone publica**: Resuelve consultas desde internet publico. Esto es lo que necesitas para tu aplicacion de cara al usuario.
> * **Hosted zone privada**: Resuelve consultas solo dentro de una VPC. Util para service discovery interno (por ejemplo, `database.internal.tudominio.com`).

<br />

##### **Politicas de ruteo de Route53**
Route53 soporta varias politicas de ruteo que van mas alla de la simple resolucion "nombre a IP":

<br />

> * **Ruteo simple**: Un registro, uno o mas valores. Route53 devuelve todos los valores en orden aleatorio. Este es el predeterminado y el que vamos a usar en este articulo.
> * **Ruteo ponderado**: Distribuye trafico entre multiples recursos por peso. Por ejemplo, mandar 90% del trafico a la version 1 y 10% a la version 2. Genial para deployments canary.
> * **Ruteo por failover**: Configuracion activo-pasivo. Route53 manda trafico al recurso primario. Si un health check falla, automaticamente cambia al recurso secundario.
> * **Ruteo por latencia**: Rutea usuarios a la region con menor latencia. Si tenes servidores en us-east-1 y eu-west-1, los usuarios europeos se rutean automaticamente a eu-west-1.
> * **Ruteo por geolocalizacion**: Rutea segun la ubicacion geografica del usuario. Util para compliance (mantener datos de usuarios de la UE en la UE) o servir contenido localizado.

<br />

Para la mayoria de las aplicaciones que recien arrancan, el ruteo simple es todo lo que necesitas.
A medida que crecas y deployees en multiples regiones, las otras politicas se vuelven increiblemente
valiosas.

<br />

##### **Registro de dominio y delegacion de nameservers**
Antes de poder usar Route53 para DNS, necesitas un nombre de dominio. Tenes dos opciones:

<br />

> * **Registrar a traves de Route53**: AWS actua como registrador y proveedor de DNS. Esta es la opcion mas simple porque la delegacion de nameservers pasa automaticamente.
> * **Registrar en otro lado y delegar a Route53**: Comprar tu dominio en un registrador como Namecheap, GoDaddy o Cloudflare, y despues actualizar los nameservers para que apunten a los registros NS de la hosted zone de Route53.

<br />

Si registraste tu dominio en otro lado, el proceso se ve asi:

<br />

```plaintext
1. Crear una hosted zone en Route53 para tudominio.com
2. Route53 asigna cuatro registros NS (ej: ns-1234.awsdns-56.org)
3. Ir al dashboard de tu registrador
4. Reemplazar los nameservers predeterminados con los cuatro NS de Route53
5. Esperar la propagacion (puede tardar hasta 48 horas, generalmente mucho mas rapido)
6. Ahora Route53 es autoritativo para tudominio.com
```

<br />

Una vez que la delegacion esta completa, cualquier registro DNS que crees en tu hosted zone de
Route53 va a ser el que internet vea.

<br />

##### **Registros Alias de Route53: una feature especial de AWS**
El DNS estandar tiene una limitacion: no podes poner un registro CNAME en el apex de zona (el
dominio pelado como `tudominio.com`). Esto es un problema porque los recursos de AWS como los ALBs
y las distribuciones de CloudFront no tienen direcciones IP estaticas, asi que tampoco podes usar
un registro A.

<br />

Route53 resuelve esto con los **registros Alias**. Un registro Alias se ve como un registro A o
AAAA para los clientes DNS, pero detras de escena resuelve a otro recurso de AWS. Pensalo como un
CNAME que funciona en el apex de zona.

<br />

> * **Sin costo**: Route53 no cobra por consultas a registros Alias que apuntan a recursos de AWS.
> * **Compatible con apex de zona**: Podes crear un registro Alias para `tudominio.com` apuntando a tu ALB.
> * **Health check integrado**: Los registros Alias pueden heredar health checks del recurso destino.

<br />

Vamos a usar un registro Alias para apuntar nuestro dominio a nuestro Application Load Balancer.

<br />

##### **TLS/SSL: por que importa HTTPS**
Ahora mismo nuestro ALB esta sirviendo trafico por HTTP en el puerto 80. Cada peticion y respuesta
viaja por internet en texto plano. Cualquier persona entre el usuario y tu servidor (ISPs,
operadores de Wi-Fi, cualquiera en la misma red) puede leer los datos, modificarlos o inyectar
contenido.

<br />

TLS (Transport Layer Security) cifra la conexion entre el navegador del usuario y tu servidor.
Cuando ves el icono del candado y `https://` en tu navegador, eso significa que TLS esta en uso.

<br />

Por que importa HTTPS:

<br />

> * **Confidencialidad**: Los datos en transito estan cifrados. Passwords, API keys, informacion personal, todo esta protegido.
> * **Integridad**: Los datos no pueden ser modificados en transito. Nadie puede inyectar publicidad, malware o scripts de tracking en tus respuestas.
> * **Autenticacion**: El certificado prueba que el servidor es quien dice ser. Esto previene ataques man-in-the-middle.
> * **SEO y confianza**: Google usa HTTPS como senal de ranking desde 2014. Los navegadores marcan sitios HTTP como "No Seguro." Los usuarios confian mas en sitios HTTPS.
> * **Requerido para features modernas**: HTTP/2, service workers, API de geolocalizacion y muchas otras features del navegador requieren HTTPS.

<br />

En resumen, no hay ninguna buena razon para servir trafico de produccion por HTTP.

<br />

##### **Como funciona TLS (la version corta)**
Cuando tu navegador se conecta a un servidor HTTPS, un proceso llamado TLS handshake ocurre antes
de que se intercambie cualquier dato de aplicacion:

<br />

```plaintext
Cliente                              Servidor
  |                                    |
  |--- ClientHello (cifrados soportados) -->|
  |                                    |
  |<-- ServerHello + Certificado -------|
  |                                    |
  |--- Material de intercambio de claves -->|
  |                                    |
  |<-- Material de intercambio de claves ---|
  |                                    |
  |   (Ambos lados derivan clave de sesion) |
  |                                    |
  |<== Datos de aplicacion cifrados ===>|
```

<br />

> * **ClientHello**: El navegador envia las versiones de TLS y suites de cifrado que soporta.
> * **ServerHello**: El servidor elige una suite de cifrado y envia su certificado (que contiene la clave publica del servidor).
> * **Validacion del certificado**: El navegador verifica que el certificado fue emitido por una Autoridad Certificadora (CA) confiable, no esta expirado y coincide con el nombre de dominio.
> * **Intercambio de claves**: Ambos lados intercambian material de claves y derivan una clave de sesion compartida.
> * **Comunicacion cifrada**: Todos los datos subsiguientes se cifran con la clave de sesion usando cifrado simetrico (mucho mas rapido que el asimetrico).

<br />

Lo importante que te tenes que llevar es que necesitas un certificado TLS valido para tu dominio.
Ahi es donde entra AWS Certificate Manager.

<br />

##### **AWS Certificate Manager (ACM)**
ACM es un servicio gratuito que te permite provisionar, gestionar y deployear certificados TLS para
usar con servicios de AWS como ALB, CloudFront y API Gateway.

<br />

Los beneficios clave:

<br />

> * **Gratis**: Los certificados publicos son gratis cuando se usan con servicios de AWS. No necesitas pagarle a una CA.
> * **Auto-renovacion**: ACM renueva automaticamente los certificados antes de que expiren. Se acabaron los pages a las 3 AM porque un certificado expiro.
> * **Validacion por DNS**: Probas que sos duenio del dominio agregando un registro CNAME a tu DNS. Esto es completamente automatizable con Terraform.
> * **Claves privadas gestionadas**: ACM guarda la clave privada de forma segura. Nunca tenes que manejarla vos mismo.

<br />

El proceso para obtener un certificado con ACM se ve asi:

<br />

```plaintext
1. Solicitar un certificado para api.tudominio.com (y opcionalmente *.tudominio.com)
2. ACM te da un registro CNAME para agregar a tu DNS
3. Agregas el registro CNAME a tu hosted zone de Route53
4. ACM valida que sos duenio del dominio
5. El certificado se emite (generalmente en minutos)
6. ACM lo auto-renueva cada 13 meses
```

<br />

La validacion por DNS es preferible a la validacion por email porque se puede automatizar
completamente y no requiere que alguien haga click en un link en un email.

<br />

##### **Conectando todo: el panorama completo**
Vamos a juntar todo lo que discutimos. Asi es como todas las piezas se conectan para hacer tu
aplicacion accesible por HTTPS en un dominio real:

<br />

```plaintext
Navegador del usuario
     |
     | (Consulta DNS: api.tudominio.com)
     v
Hosted zone de Route53
     |
     | (Registro Alias -> ALB)
     v
Application Load Balancer
     |
     |--- Puerto 443 (HTTPS) -> Forward al target group (con certificado ACM)
     |--- Puerto 80  (HTTP)  -> Redirect a HTTPS
     |
     v
Tareas ECS Fargate (tus containers de la API)
```

<br />

> * **Route53** resuelve `api.tudominio.com` a la direccion del ALB usando un registro Alias.
> * **ACM** provee el certificado TLS que el ALB usa para terminacion HTTPS.
> * **ALB** termina TLS, lo que significa que la conexion cifrada termina en el ALB. El trafico entre el ALB y tus tareas ECS viaja por HTTP dentro de tu VPC (lo cual esta bien porque es una red privada).
> * **Redirect HTTP a HTTPS**: El ALB escucha en el puerto 80 y automaticamente redirige al puerto 443, asi que usuarios que escriben `http://` igual terminan en HTTPS.

<br />

##### **Terraform: hosted zone de Route53**
Escribamos el codigo Terraform. Vamos a construir sobre la infraestructura del articulo ocho.
Primero, la hosted zone de Route53:

<br />

```hcl
# dns.tf
variable "domain_name" {
  description = "The root domain name"
  type        = string
  default     = "yourdomain.com"
}

variable "api_subdomain" {
  description = "Subdomain for the API"
  type        = string
  default     = "api"
}

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name = var.domain_name
  }
}
```

<br />

Esto crea una hosted zone publica. Route53 automaticamente crea los registros NS y SOA. Despues
de aplicar esto, necesitas copiar los cuatro registros NS y configurarlos en tu registrador de
dominios. Solo necesitas hacer esto una vez.

<br />

Podes hacer output de los nameservers para saber que configurar:

<br />

```hcl
output "nameservers" {
  description = "Nameservers for the hosted zone. Set these at your registrar."
  value       = aws_route53_zone.main.name_servers
}
```

<br />

##### **Terraform: certificado ACM con validacion DNS**
Despues, solicitamos un certificado TLS y lo validamos automaticamente a traves de DNS:

<br />

```hcl
# acm.tf
resource "aws_acm_certificate" "app" {
  domain_name               = "${var.api_subdomain}.${var.domain_name}"
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.api_subdomain}.${var.domain_name}"
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}
```

<br />

Desglosemos esto:

<br />

> * `aws_acm_certificate` solicita el certificado. Lo pedimos para `api.tudominio.com` con un SAN wildcard (`*.tudominio.com`) para que cubra cualquier subdominio.
> * `validation_method = "DNS"` le dice a ACM que vamos a probar ownership del dominio agregando registros DNS.
> * `create_before_destroy = true` asegura que al renovar, el nuevo certificado se crea antes de destruir el viejo. Esto previene downtime.
> * `aws_route53_record.acm_validation` crea los registros CNAME que ACM requiere para validacion. El loop `for_each` maneja el caso donde el certificado cubre multiples nombres de dominio.
> * `aws_acm_certificate_validation` es un recurso que espera. Terraform va a bloquear aca hasta que ACM confirme que el certificado esta validado y emitido. Esto generalmente tarda 2-5 minutos.

<br />

##### **Terraform: listener HTTPS del ALB y redirect HTTP**
En el articulo ocho, creamos un ALB con solo un listener HTTP. Ahora vamos a agregar un listener
HTTPS y cambiar el listener HTTP para que redirija a HTTPS:

<br />

```hcl
# alb.tf (actualizado)

# Cambiar el listener HTTP existente para redirigir
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Agregar listener HTTPS
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
```

<br />

Detalles importantes:

<br />

> * El listener HTTP ahora devuelve un **redirect 301** a HTTPS. Es un redirect permanente, asi que los navegadores y motores de busqueda lo van a recordar e ir directo a HTTPS la proxima vez.
> * El listener HTTPS referencia el certificado ACM validado. Nota que referenciamos `aws_acm_certificate_validation.app.certificate_arn`, no el certificado directamente. Esto asegura que Terraform espere a que la validacion se complete antes de crear el listener.
> * `ssl_policy` controla que versiones de TLS y suites de cifrado acepta el ALB. `ELBSecurityPolicy-TLS13-1-2-2021-06` soporta TLS 1.2 y 1.3, que es la mejor practica actual. Politicas viejas que permiten TLS 1.0 o 1.1 no deberian usarse.

<br />

Tambien necesitas actualizar el security group del ALB para permitir trafico HTTPS:

<br />

```hcl
# security_groups.tf (actualizado)
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere (for redirect)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
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
```

<br />

Mantenemos el puerto 80 abierto para que el redirect funcione. Si cerras el puerto 80, los
usuarios que escriban `http://` van a recibir un timeout de conexion en lugar de un redirect.

<br />

##### **Terraform: registro Route53 apuntando al ALB**
Finalmente, creamos el registro DNS que apunta nuestro dominio al load balancer:

<br />

```hcl
# dns.tf (continuacion)
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}
```

<br />

Este es un registro Alias. Aunque es `type = "A"`, no contiene una direccion IP hardcodeada. En
cambio, apunta al DNS name del ALB. Route53 resuelve las direcciones IP actuales del ALB detras de
escena y se las devuelve al cliente.

<br />

`evaluate_target_health = true` significa que si el ALB no tiene targets saludables, Route53 no
va a devolver este registro en consultas DNS. Esto es util en configuraciones multi-region con
ruteo por failover.

<br />

##### **Health checks**
Los health checks son la forma en que AWS determina si tu aplicacion esta realmente funcionando. Hay
dos niveles de health checks en nuestra configuracion:

<br />

**Health checks del target group del ALB**

<br />

Ya los configuramos en el articulo ocho. El ALB periodicamente envia peticiones HTTP a tus tareas
ECS en un path que vos definis (como `/health`). Si una tarea falla checks consecutivos, el ALB deja
de mandarle trafico y ECS la reemplaza.

<br />

```hcl
# Ya esta en nuestro target group del articulo 8
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
```

<br />

**Health checks de Route53**

<br />

Los health checks de Route53 operan a nivel DNS. Monitorean un endpoint y pueden triggear failover
DNS si el endpoint se cae. Son particularmente utiles cuando tenes recursos en multiples regiones:

<br />

```hcl
# route53_health.tf
resource "aws_route53_health_check" "api" {
  fqdn              = "${var.api_subdomain}.${var.domain_name}"
  port               = 443
  type               = "HTTPS"
  resource_path      = "/health"
  failure_threshold  = 3
  request_interval   = 30
  measure_latency    = true

  tags = {
    Name = "${var.api_subdomain}.${var.domain_name}-health-check"
  }
}
```

<br />

> * `type = "HTTPS"` significa que Route53 se conecta por TLS para verificar el endpoint.
> * `failure_threshold = 3` significa que tres fallas consecutivas marcan el endpoint como unhealthy.
> * `request_interval = 30` verifica cada 30 segundos. Podes ponerlo en 10 para deteccion mas rapida, pero cuesta mas.
> * `measure_latency = true` trackea metricas de latencia en CloudWatch.

<br />

Para una configuracion de una sola region, los health checks de Route53 son opcionales pero estan
buenos para monitoreo. Para multi-region con ruteo por failover, son esenciales.

<br />

##### **La configuracion Terraform completa**
Juntemos todo en una sola vista para que puedas ver como las piezas se conectan:

<br />

```hcl
# Full dns.tf
variable "domain_name" {
  description = "The root domain name"
  type        = string
  default     = "yourdomain.com"
}

variable "api_subdomain" {
  description = "Subdomain for the API"
  type        = string
  default     = "api"
}

# Hosted zone
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name = var.domain_name
  }
}

# Certificado ACM
resource "aws_acm_certificate" "app" {
  domain_name               = "${var.api_subdomain}.${var.domain_name}"
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.api_subdomain}.${var.domain_name}"
  }
}

# Registros de validacion DNS para ACM
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

# Esperar validacion del certificado
resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# Registro DNS apuntando al ALB
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

# Outputs
output "nameservers" {
  description = "Nameservers for the hosted zone. Set these at your registrar."
  value       = aws_route53_zone.main.name_servers
}

output "app_url" {
  description = "The HTTPS URL for the API"
  value       = "https://${var.api_subdomain}.${var.domain_name}"
}
```

<br />

##### **Aplicando los cambios**
Ejecuta `terraform plan` primero para ver que se va a crear:

<br />

```bash
terraform plan
```

<br />

Deberias ver nuevos recursos para la hosted zone, certificado ACM, registros de validacion, listener
HTTPS y el registro DNS. Una vez que estes conforme con el plan:

<br />

```bash
terraform apply
```

<br />

El recurso `aws_acm_certificate_validation` va a bloquear hasta que el certificado este validado.
Esto generalmente tarda 2-5 minutos. Si tarda mas de 10 minutos, verifica que los registros CNAME
de validacion se crearon correctamente en la hosted zone y que tus nameservers estan correctamente
delegados.

<br />

Despues de que el apply se complete, actualiza tus nameservers en tu registrador si todavia no lo
hiciste. Despues verifica que todo funcione:

<br />

```bash
# Verificar resolucion DNS
dig api.tudominio.com

# Probar HTTPS
curl -v https://api.tudominio.com/health

# Probar redirect HTTP
curl -v http://api.tudominio.com/health
# Deberia devolver un redirect 301 a https://
```

<br />

##### **Debuggeando problemas de DNS**
Los problemas de DNS son de los mas frustrantes de debuggear por el caching. Aca estan las
herramientas y tecnicas que necesitas:

<br />

```bash
# Consultar un nameserver especifico directamente (saltear cache)
dig @ns-1234.awsdns-56.org api.tudominio.com

# Verificar todos los tipos de registro
dig api.tudominio.com ANY

# Trazar el camino completo de resolucion
dig +trace api.tudominio.com

# Verificar delegacion de nameservers
dig tudominio.com NS

# Verificar registros TXT (util para validacion ACM)
dig _acme-challenge.api.tudominio.com TXT
```

<br />

Problemas comunes y como solucionarlos:

<br />

> * **"NXDOMAIN" (dominio no encontrado)**: Tus nameservers no estan correctamente delegados. Verifica los registros NS en tu registrador.
> * **Se devuelve IP vieja**: Caching de DNS. Espera a que expire el TTL, o usa `dig @8.8.8.8` para verificar los resolvers de Google directamente.
> * **Validacion ACM trabada**: El nombre y valor del registro CNAME deben coincidir exactamente con lo que ACM espera. Verifica puntos al final o typos.
> * **Certificado no valido para el dominio**: El Common Name o SAN del certificado no coincide con el dominio. Asegurate de haber solicitado el certificado para el nombre de dominio correcto.

<br />

##### **Una nota sobre CloudFront (CDN)**
Hasta ahora conectamos usuarios directamente a nuestro ALB a traves de Route53. Esto funciona bien,
pero para aplicaciones que sirven assets estaticos (imagenes, CSS, JavaScript) o tienen usuarios
distribuidos por todo el mundo, deberias considerar poner CloudFront adelante de tu ALB.

<br />

CloudFront es el CDN (Content Delivery Network) de AWS. Cachea tu contenido en edge locations
alrededor del mundo, asi que los usuarios reciben respuestas de un servidor que esta geograficamente
cerca de ellos en lugar de desde tu region de origen.

<br />

```plaintext
Sin CloudFront:
  Usuario en Tokio -> Route53 -> ALB en us-east-1 (200ms de latencia)

Con CloudFront:
  Usuario en Tokio -> Route53 -> Edge de CloudFront en Tokio (cacheado, 20ms)
                                    |
                                    v (solo en cache miss)
                              ALB en us-east-1
```

<br />

Beneficios de CloudFront:

<br />

> * **Menor latencia**: Contenido servido desde la edge location mas cercana.
> * **Menor carga en el origen**: Las respuestas cacheadas no pegan en tu ALB ni en tus tareas ECS.
> * **Proteccion DDoS**: CloudFront se integra con AWS Shield para mitigacion de DDoS.
> * **Certificados ACM gratis**: CloudFront usa certificados ACM de us-east-1 (esto es un requisito, el certificado debe estar en us-east-1 sin importar donde este tu origen).

<br />

No vamos a configurar CloudFront en este articulo ya que merece su propio deep dive, pero tenelo
en mente para cuando necesites optimizar performance para una audiencia global.

<br />

##### **Desglose de costos**
Veamos cuanto cuesta esta configuracion:

<br />

> * **Hosted zone de Route53**: $0.50/mes por hosted zone.
> * **Consultas Route53**: $0.40 por millon de consultas. Para la mayoria de las aplicaciones esto es despreciable.
> * **Health checks de Route53**: $0.50/mes para un health check HTTPS basico. $1.00/mes con medicion de latencia.
> * **Certificados ACM**: Gratis cuando se usan con servicios de AWS (ALB, CloudFront, API Gateway).
> * **ALB**: El ALB ya era parte de nuestra configuracion ECS. Sin costo adicional por terminacion HTTPS.

<br />

Costo adicional total por DNS y TLS: aproximadamente $1-2/mes. Esta es una de las mejoras mas
baratas y de mayor valor que podes hacer a tu infraestructura.

<br />

##### **Mejores practicas de seguridad**
Antes de cerrar, aca van algunas practicas de seguridad a tener en cuenta:

<br />

> * **Siempre redirigir HTTP a HTTPS**: Nunca sirvas trafico de produccion por HTTP plano.
> * **Usar una politica TLS moderna**: `ELBSecurityPolicy-TLS13-1-2-2021-06` o mas nueva. Deshabilitar TLS 1.0 y 1.1.
> * **Habilitar HSTS**: Agrega el header `Strict-Transport-Security` en tu aplicacion para decirle a los navegadores que siempre usen HTTPS. Esto previene ataques de downgrade.
> * **Usar certificados separados por entorno**: No reutilices certificados de produccion en staging. ACM es gratis, asi que no hay razon para no tener certificados separados.
> * **Monitorear expiracion de certificados**: Aunque ACM auto-renueva, configura una alarma de CloudWatch para la expiracion del certificado como red de seguridad. Si la validacion DNS falla por alguna razon, la auto-renovacion va a fallar silenciosamente.

<br />

##### **Notas de cierre**
Tu aplicacion ahora es accesible en un dominio real por HTTPS. Cubrimos mucho terreno en este
articulo: fundamentos de DNS y tipos de registros, hosted zones y politicas de ruteo de Route53,
certificados TLS con ACM, terminacion HTTPS en el ALB, redirects de HTTP a HTTPS, health checks
tanto a nivel ALB como DNS, y el codigo Terraform para provisionar todo.

<br />

Este es un hito en la serie. Tu API TypeScript ahora esta corriendo en containers en ECS, detras
de un load balancer, con auto-scaling, accesible en una URL limpia por una conexion cifrada. Eso es
una configuracion de grado produccion.

<br />

En el proximo articulo, vamos a ver monitoreo y observabilidad para que puedas ver que esta haciendo
tu aplicacion en produccion y detectar problemas antes de que lo hagan tus usuarios.

<br />

Espero que te haya resultado util y que lo hayas disfrutado, hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se corrija.

Tambien, podes revisar el codigo fuente y los cambios en los [fuentes aca](https://github.com/kainlite/tr)

<br />
