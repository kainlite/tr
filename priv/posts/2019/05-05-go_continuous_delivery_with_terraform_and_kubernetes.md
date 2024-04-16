%{
  title: "Go continuous delivery with Terraform and Kubernetes",
  author: "Gabriel Garrido",
  description: "In this article we will continue where we left off the last time: Go continuous integration with Travis CI and Docker...",
  tags: ~w(golang travis terraform cicd),
  published: true,
  image: "travis-ci-docker.png"
}
---

![travis](/images/travis-ci-docker.png){:class="mx-auto"}

##### **Introduction**
In this article we will continue where we left off the last time [Go continuous integration with Travis CI and Docker](/blog/go_continuous_integration_with_travis_ci_and_docker), the files used here can be found [HERE](https://github.com/kainlite/whatismyip-go/tree/continuos-delivery), and we will be creating our terraform cluster with a load balancer and generating our kubeconfig file based on the certs provided by terraform on travis and then finally creating a basic deployment and validate that everything works.
<br />

##### **DigitalOcean**
We need to create a token so terraform can create resources using DO API. Go to your account then in the menu on the left click API, then you should see something like this:
![image](/images/terraform-do-token-1.png){:class="mx-auto"}
Once there click generate token (give it a meaningful name to you), and make sure it can write.
![image](/images/terraform-do-token-2.png){:class="mx-auto"}
<br />

##### **Terraform**
As the next step it would be good to set the token for terraform, so let's examine all files and see what they are going to do, but first we're going to provide the secrets to our app via environment variables, and I've found quite useful to use `direnv` on many projects, so the content of the first file `.envrc` would look something like:
```elixir
export TF_VAR_DO_TOKEN=insert_your_token_here

```
and after that you will need to allow it's execution by running `direnv allow`.
<br />

The first terraform file that we are going to check is `provider.tf`:
```elixir
# Configure the digitalocean provider with it's token
variable "DO_TOKEN" {}

provider "digitalocean" {
  token = "${var.DO_TOKEN}"
}

```
As we're using environment variables we need to declare it and then set it in the provider, for now we only need the token.
<br />

Then the `kubernetes.tf` file:
```elixir
# Create the cluster
resource "digitalocean_kubernetes_cluster" "dev-k8s" {
  name    = "dev-k8s"
  region  = "nyc1"
  version = "1.14.1-do.2"

  node_pool {
    name       = "dev-k8s-nodes"
    size       = "s-1vcpu-2gb"
    node_count = 1
    tags       = ["dev-k8s-nodes"]
  }
}

```
This file will be the responsible of creating the kubernetes cluster, as it's our development cluster we only need one node.
<br />

Next the file `lb.tf`:
```elixir
# Create a load balancer associated with our cluster
resource "digitalocean_loadbalancer" "public" {
  name   = "loadbalancer-1"
  region = "nyc1"

  forwarding_rule {
    entry_port     = 80
    entry_protocol = "http"

    target_port     = 30000
    target_protocol = "http"
  }

  healthcheck {
    port     = 30000
    protocol = "tcp"
  }

  droplet_tag = "dev-k8s-nodes"
}

```
This one is particularly interesting because it will provide a point of access to our applications (port 80 on it's public IP address), and it also uses a basic health check.
<br />

And last but not least the `output.tf` file:
```elixir
# Export the kubectl configuration file
resource "local_file" "kubernetes_config" {
  content  = "${digitalocean_kubernetes_cluster.dev-k8s.kube_config.0.raw_config}"
  filename = "kubeconfig.yaml"
}

# Print the load balancer ip
output "digitalocean_loadbalancer" {
  value       = "${digitalocean_loadbalancer.public.ip}"
  description = "The public IP address of the load balancer."
}

```
This file will print the kubernetes config file that we need to be able to use `kubectl`, and also the IP address of our load balancer.
<br />

So what do we do with all of this?, first you will need to run `terraform init` inside the terraform folder to download plugins and providers, once that is done you can run `terraform plan` to see what changes terraform wants to make or `terraform apply` to do the changes. How is that going to look?:
```elixir
# Initialize terraform
$ terraform init                                                                                                                                                                                             
                                                                                                                                                                                                                                                                                 
Initializing provider plugins...                                                                                                                                                                                                                                                 
- Checking for available provider plugins on https://releases.hashicorp.com...                                                                                                                                                                                                   
- Downloading plugin for provider "local" (1.2.2)...                                                                                                                                                                                                                             
- Downloading plugin for provider "digitalocean" (1.2.0)...                                                                                                                                                                                                                      
                                                                                                                                                                                                                                                                                 
The following providers do not have any version constraints in configuration,                                                                                                                                                                                                    
so the latest version was installed.                                                                                                                                                                                                                                             
                                                                                                                                                                                                                                                                                 
To prevent automatic upgrades to new major versions that may contain breaking                                                                                                                                                                                                    
changes, it is recommended to add version = "..." constraints to the                                                                                                                                                                                                             
corresponding provider blocks in configuration, with the constraint strings                                                                                                                                                                                                      
suggested below.                                                                                                                                                                                                                                                                 
                                                                                                                                                                                                                                                                                 
* provider.digitalocean: version = "~> 1.2"                                                                                                                                                                                                                                      
* provider.local: version = "~> 1.2"                                                                                                                                                                                                                                             
                                                                                                                                                                                                                                                                                 
Terraform has been successfully initialized!                                                                                                                                                                                                                                     
                                                                                                                                                                                                                                                                                 
You may now begin working with Terraform. Try running "terraform plan" to see                                                                                                                                                                                                    
any changes that are required for your infrastructure. All Terraform commands                                                                                                                                                                                                    
should now work.                                                                                                                                                                                                                                                                 
                                                                                                                                                                                                                                                                                 
If you ever set or change modules or backend configuration for Terraform,                                                                                                                                                                                                        
rerun this command to reinitialize your working directory. If you forget, other                                                                                                                                                                                                  
commands will detect it and remind you to do so if necessary.                 

# Apply
$ terraform apply
digitalocean_kubernetes_cluster.dev-k8s: Creating...
  cluster_subnet:              "" => "<computed>"
  created_at:                  "" => "<computed>"
  endpoint:                    "" => "<computed>"
  ipv4_address:                "" => "<computed>"
  kube_config.#:               "" => "<computed>"
  name:                        "" => "dev-k8s"
  node_pool.#:                 "" => "1"
  node_pool.0.id:              "" => "<computed>"
  node_pool.0.name:            "" => "dev-k8s-nodes"
  node_pool.0.node_count:      "" => "1"
  node_pool.0.nodes.#:         "" => "<computed>"
  node_pool.0.size:            "" => "s-1vcpu-2gb"
  node_pool.0.tags.#:          "" => "1"
  node_pool.0.tags.3897066636: "" => "dev-k8s-nodes"
  region:                      "" => "nyc1"
  service_subnet:              "" => "<computed>"
  status:                      "" => "<computed>"
  updated_at:                  "" => "<computed>"
  version:                     "" => "1.14.1-do.2"
digitalocean_loadbalancer.public: Creating...
  algorithm:                              "" => "round_robin"
  droplet_ids.#:                          "" => "<computed>"
  droplet_tag:                            "" => "dev-k8s-nodes"
  enable_proxy_protocol:                  "" => "false"
  forwarding_rule.#:                      "" => "1"
  forwarding_rule.0.entry_port:           "" => "8000"
  forwarding_rule.0.entry_protocol:       "" => "http"
  forwarding_rule.0.target_port:          "" => "30000"
  forwarding_rule.0.target_protocol:      "" => "http"
  forwarding_rule.0.tls_passthrough:      "" => "false"
  healthcheck.#:                          "" => "1"
  healthcheck.0.check_interval_seconds:   "" => "10"
  healthcheck.0.healthy_threshold:        "" => "5"
  healthcheck.0.port:                     "" => "30000"
  healthcheck.0.protocol:                 "" => "tcp"
  healthcheck.0.response_timeout_seconds: "" => "5"
  healthcheck.0.unhealthy_threshold:      "" => "3"
  ip:                                     "" => "<computed>"
  name:                                   "" => "loadbalancer-1"
  redirect_http_to_https:                 "" => "false"
  region:                                 "" => "nyc1"
  status:                                 "" => "<computed>"
  sticky_sessions.#:                      "" => "<computed>"
  urn:                                    "" => "<computed>"
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (10s elapsed)
digitalocean_loadbalancer.public: Still creating... (10s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (20s elapsed)
digitalocean_loadbalancer.public: Still creating... (20s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (30s elapsed)
digitalocean_loadbalancer.public: Still creating... (30s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (40s elapsed)
digitalocean_loadbalancer.public: Still creating... (40s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (50s elapsed)
digitalocean_loadbalancer.public: Still creating... (50s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (1m0s elapsed)
digitalocean_loadbalancer.public: Still creating... (1m0s elapsed)
digitalocean_loadbalancer.public: Creation complete after 1m1s (ID: e1e75c4c-94f8-481f-bd44-f2883849e4af)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (1m10s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (1m20s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (1m30s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (1m40s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (1m50s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (2m0s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (2m10s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (2m20s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (2m30s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Still creating... (2m40s elapsed)
digitalocean_kubernetes_cluster.dev-k8s: Creation complete after 2m43s (ID: 592d58c9-98c1-4285-b098-cbc9378e9f89)
local_file.kubernetes_config: Creating...
  content:  "" => "apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURKekNDQWcrZ0F3SUJBZ0lDQm5Vd0RRWUpLb1pJaHZjTkFRRUxCUUF3TXpFVk1CTUdBMVVFQ2hNTVJHbG4KYVhSaGJFOWpaV0Z1TVJvd0dBWURWUVFERXhGck9ITmhZWE1nUTJ4MWMzUmxjaUJEUVRBZUZ3MHhPVEExTURVeQpNREUwTWpkYUZ3MHpPVEExTURVeU1ERTBNamRhTURNeEZUQVRCZ05WQkFvVERFUnBaMmwwWVd4UFkyVmhiakVhCk1CZ0dBMVVFQXhNUmF6aHpZV0Z6SUVOc2RYTjBaWElnUTBFd2dnRWlNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0SUIKRHdBd2dnRUtBb0lCQVFEZWdIRnpBd3o1dlVTWngrOHJqQktmcGt0SS9SLzQ4dG01eE50VE9NcmsvWEx3bDczRApXa01ZWFNzdjJOOTVOdFhIb3B5VUNobGppa2NOSEpJdFdzV0xsVU1lY0UrYlBWY054djR0YVlMRWJVbTNVSW4zCnFxalN0dmN6NU0wSFpNYlU3UVFHM2F5VFFKeE1FUTVzQWpFYkN1MEZuWERvdkpQR3cwczhHUTlWOXBBaVFDcE4KZnVMQUpTQTBZZ2RpVDJBN3RUNkV4N1ZzY256VUFWbllRRGE4VG00cHR5RXlpTHpJTzB6NFdJMTBRK1RKV2VkeQpQa2JwVjBQMklQQlhmb3Ntd2k3N0JFT3NFYUZLdmNSQzBrUm9oT1pqM3E0T1lPTDJRMkNkTnV0dElWL1MzckllCmc2RjFWRXNEdEhKajhRUHA1U0NZUXdOekNLcnlMSjNGRXJ4NUFnTUJBQUdqUlRCRE1BNEdBMVVkRHdFQi93UUUKQXdJQmhqQVNCZ05WSFJNQkFmOEVDREFHQVFIL0FnRUFNQjBHQTFVZERnUVdCQlRFQS9PVG9qRUk1bGVnemlFRwpRLzFyNlltZFFqQU5CZ2txaGtpRzl3MEJBUXNGQUFPQ0FRRUFSK3piZjcyOVJLUDVuQlJsQ2hPMEE5R3p6bXl4Cm1GSnc3WlYyc3hvdmwzUmUvR3NCR0FKS1ZkNkVjYWZSUklZWDgybUZWeENrQXNab1BSWFM1MlRVcXVxcWJqT0cKUWp3dXoyc3NiKzArK1lJVDhUek84MDJiZThqNFVrbG9FeFRyVkI0aFIwcjFILysxbFlYKys2cDBGK21KTG9EKwpIVDVkeCtvM1JiREVBUC82T1lkaWFIYnNIMFEyQXFsRk5uU0doeTVrSC82a3RqV3JwdUR4VVp2NUxMTTdCdDlHCjMvMGozcU0xSnpTNXBrNkhsU1lwcitYY09ybDlrYlVKZ1VvZzJmWGhITUVWL0dXNW1ldTUyV2xhRzJkdWpnM2sKQUhLTlRPNkxnWEs3UEVOQjdYeTFFL2UrOHBDOXc5MjNsUVdHclBvSGdZdkwzZzUvcXNBdEZtNDN6dz09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K
    server: https://592d58c9-98c1-4285-b098-cbc9378e9f89.k8s.ondigitalocean.com
  name: do-nyc1-dev-k8s
contexts:
- context:
    cluster: do-nyc1-dev-k8s
    user: do-nyc1-dev-k8s-admin
  name: do-nyc1-dev-k8s
current-context: do-nyc1-dev-k8s
kind: Config
preferences: {}
users:
- name: do-nyc1-dev-k8s-admin
  user:
    client-certificate-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURyVENDQXBXZ0F3SUJBZ0lDQm5Vd0RRWUpLb1pJaHZjTkFRRUxCUUF3TXpFVk1CTUdBMVVFQ2hNTVJHbG4KYVhSaGJFOWpaV0Z1TVJvd0dBWURWUVFERXhGck9ITmhZWE1nUTJ4MWMzUmxjaUJEUVRBZUZ3MHhPVEExTURVeQpNREUzTURoYUZ3MHhPVEExTVRJeU1ERTNNRGhhTUg4eEN6QUpCZ05WQkFZVEFsVlRNUXN3Q1FZRFZRUUlFd0pPCldURVJNQThHQTFVRUJ4TUlUbVYzSUZsdmNtc3hIVEFiQmdOVkJBb1RGR3M0YzJGaGN6cGhkWFJvWlc1MGFXTmgKZEdWa01URXdMd1lEVlFRREV5ZzJaVFE0TjJVNU5ESXlaV0kyWTJFek5tWXpNek5oT0dSak5URXpNamt4TUdSbApNbU0wTm1JM01JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBemxodzg0QzR4dnlBCnVGWWNFb1M5VEY2L09FOXd5WWwvNnhZbzI5Nzc3QU9pSHp4clo2RUE2dHh5YkI0VHUyMnM5bWR3SGNhSE40OXMKYTd4YmZ2NnA1Z0l3R1FTRUx5ZVZJUVp1NjVQSzFEQUtVN3ZINVloc2FsNnByN202WTZ4YktJeDNsVDFYeGVpSApFVHhWUW5IU0hITngyZ2lJRVJmbEt4dnFnL0g1M1Ntd3I3WlFsWHlNb3huQ3Uxd3ZXMGsyNnJzVnBJQzBCa0NNClBlTGdzQkswc01EalUvTXBzUElkRm4vSzF1dWRNYWhGTnJIdng5NkJ5bmlsaFFFMDBQaGwrNDNnWEFhRFhtNVMKRFJ4UWc3TzFpNW04dVRmUDRIWjFGU0kxUlZPWVRkQjZtSHdEV2lTVE9xZDc2TGJEWlFyT1djNURBanc1R3JjKwpIMThrcnNzQlV3SURBUUFCbzM4d2ZUQU9CZ05WSFE4QkFmOEVCQU1DQmFBd0hRWURWUjBsQkJZd0ZBWUlLd1lCCkJRVUhBd0lHQ0NzR0FRVUZCd01CTUF3R0ExVWRFd0VCL3dRQ01BQXdIUVlEVlIwT0JCWUVGUGtkWTN0SmNRQzMKa01LbGhNZU1aTzhRR3RQVU1COEdBMVVkSXdRWU1CYUFGTVFEODVPaU1Ram1WNkRPSVFaRC9XdnBpWjFDTUEwRwpDU3FHU0liM0RRRUJDd1VBQTRJQkFRQW5aNXFtTlBEYWMyNTNnNkl1NkcrSjdna2o5NUhiOVFlNE5VNG5ib0NVCjJQRmF0K3pPelF6NlhPTVRWUk9ESlJrQlJvU2pyK2gvTFFBZFFBcWk5V244bkducG9SaHRad0s0eXozS1czUlAKSXRaaURsdXpyeVZScFVQSUMxbDh1TVBzTVEveDUzaFVvYUZzODFiTExVMVE0NWJLUDRHQUgybGo4OE5HKzNMcwpQVUQxUGQ3b1Z5K0QvZUJBdDZYYnYrNms5SGxwNHovNzE4WjJjVUFnSWphNFRGSExaNmpuM2R2TWg3SnlDLzZnCm0vL0tpb1o3WGo4Zm96YS93U3B2ZlhiSkkzUjd1RHRZMmhLbmZ6VE1iZFY5RjdkM0UxREE5aUlheEx6V2o1TzgKNktTVDlBbXV4WDU1Q2VFMGhpT1ptQ2dGS1NFazVsQXFFNDNqL3VDT1MyYTQKLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
    client-key-data: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFb3dJQkFBS0NBUUVBemxodzg0QzR4dnlBdUZZY0VvUzlURjYvT0U5d3lZbC82eFlvMjk3NzdBT2lIenhyClo2RUE2dHh5YkI0VHUyMnM5bWR3SGNhSE40OXNhN3hiZnY2cDVnSXdHUVNFTHllVklRWnU2NVBLMURBS1U3dkgKNVloc2FsNnByN202WTZ4YktJeDNsVDFYeGVpSEVUeFZRbkhTSEhOeDJnaUlFUmZsS3h2cWcvSDUzU213cjdaUQpsWHlNb3huQ3Uxd3ZXMGsyNnJzVnBJQzBCa0NNUGVMZ3NCSzBzTURqVS9NcHNQSWRGbi9LMXV1ZE1haEZOckh2Cng5NkJ5bmlsaFFFMDBQaGwrNDNnWEFhRFhtNVNEUnhRZzdPMWk1bTh1VGZQNEhaMUZTSTFSVk9ZVGRCNm1Id0QKV2lTVE9xZDc2TGJEWlFyT1djNURBanc1R3JjK0gxOGtyc3NCVXdJREFRQUJBb0lCQUVpaS9XL2FXakZCNVpYKwpTZmVDM3BncHFpcUtYR3UxaVdBWjl0d2ZUSk15WERtZXJUaFhodGttTE9rK1ZUZmZUY21YYy9JblZxWUtTT0pMCjlmRm9lQ3BOanR6ZnFDQnBVS2ZGZWZwWGxrakhlSHN0V1JyRndWUllhbWMvZkF0bU90aTFTY3N4UXRxYUZpSE4KR1Q1QWp2UVE5MzBIRDg3a21IbHFaRTE2T3JqTk4vZXJYMGc3NGRnUDdVVDdoRU94R04zY1B6L2JzUTVZVXlkTwp5SE1WdlpUZG9UUzhpQnROWUQwV1VhSFVqaHRkdDRLQUJBbzZNMzJoeFVxVzV3cU1USmpjeFNxYTRvMWg3OVZVCmxmYVFqQjlBNGo0cndCaXBjd1VOL0lKTzZuUElyaml0dHYvS00xaXdSSHJXQ3pBa1pCLzU2Q1cyR1NpK3dQbGwKYUoyWVNTRUNnWUVBOXZ3Q0xNTTZoWHJaT2NlcWkvOUpYanlWaWRVNEhoR1Q3MG9FNThBbmtXdExqQUZvNTVVTwo5OXZwZW4xeEJEdHVIUHVVakx1b0c2WXJlMElVb3gzUGZ1VzNEVU8vaG5jcXk3VGU3QkFjd203bjdpSExlU2VQCmc4TkR1Z1NJcEZML28ra1kySGd1eThyTUNWa3c3VXMwakxYMVRzeEFHallFQlByTVFmeDBtUXNDZ1lFQTFlQ3MKdDRBRXk3T3gvcUlPNFhGZzc1NFdxZzdiWW13bDFxNTRJVU9RSTBPOGJPOUZzWlo5TEJUYU1mekdlaWlLbVNYcwo2U01YVk5yazQvNU0yUTYyN1dBVk5hODhXQzU2Q2xCM3JnM1QzTnE1anR6ZHZtSDUxU3hPaWxkZXFkTDNXQTZlCm9JTkZJVGlrL29zNzBrSnBON2N0Y1V2MEdXYjUwc050NlV5U05ka0NnWUVBcFZ3WWdLdTlOTDBKVHh3VlhXSHcKVnoyc3lQbU9kdU5CN29YYVB1ZHlGblNGd2hqM2lZVk0zam5JV2hBK2FKejVua0g2TlRjMjJEd3JCSDA3bi9KSAppQ2g0cEZMbG1qdVMxWXdsYkZ0bFJmQkhMREpJTHJlRDZLNEZYRGZJM0d3TmFFcWFMZVJaUUd4b3F5R2lGbDJ4CnN6dm9IM2UwdTFmSzNTS2xPdEN4cC8wQ2dZQmZFK2YwRXpjT2p5MmJjdE9HcU81YzF6eGdFUWE1OURYRi8vMXIKWEN1aFlhVk1EL285ZmhiYkY5SC8wczB3MVFENElBSDNpaC8vR3VnUjZxU2pBWVdVZE5nNDYxTzZKNzhkQXJTUgpiWmczWUF5SlUrcEhqaXFQOTRoYXU0aGJtbXRXZS9sTWhjNmZmQnp0QTF4dWxoTk1MMlJHTDJ1dU56YnIyUER0CmU1cXIwUUtCZ0V3UjBCTi9UaVpCVVZYbWFlUXhuck1hamlIRDRzd1BHQklpWldJWEpMZGEySmNCZFRsbmZaL1cKY05KaU1nY0dXZlUyZktUMEZBd0NjWE5QK3lXRXdJNTBWQUoreWR5WWZBL2tsbUxxTFR1QVNldXRiVTc4aWlrUQpoclFuMXc3cUZuVFJZYklCOElueVRpZ1EwZVQwUUlXOEtnNzJlUFVNZzhZUjEzMmtiSmhYCi0tLS0tRU5EIFJTQSBQUklWQVRFIEtFWS0tLS0tCg==
"
  filename: "" => "kubeconfig.yaml"
local_file.kubernetes_config: Creation complete after 0s (ID: 134e8fecc682966cfc21b46a96afbfb88f85dc2a)

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

```
This will create our cluster in DigitalOcean, remember to destroy it after you're done using it with `terraform destroy`, if you don't use a plan you will be prompted for a confirmation when you do `terraform apply`, review and say `yes`.
<br />

##### **Travis**
We did some additions to our `.travis.yml` file, which are mostly to prepare `kubectl` and to also trigger a deployment if the build succeeded.
```elixir
language: go

services:
  - docker

before_install:
- docker build --no-cache -t ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT} .
- docker run ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT} /go/src/github.com/kainlite/whatismyip-go/whatismyip-go.test
- docker run -d -p 127.0.0.1:8000:8000 ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT}

script:
  - curl 127.0.0.1:8000
  - echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
  - docker push ${TRAVIS_REPO_SLUG}:${TRAVIS_COMMIT}

after_success:
  - echo ${KUBERNETES_CA} | base64 -d > k8s-ca.pem
  - echo ${KUBERNETES_CLIENT_CA} | base64 -d > k8s-client-ca.pem
  - echo ${KUBERNETES_CLIENT_KEY} | base64 -d > k8s-key.pem
  - curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
  - envsubst < ./kubernetes/manifest.yml.template > ./kubernetes/manifest.yml
  - chmod u+x ./kubectl
  - ./kubectl config set-cluster dev-k8s --server=${KUBERNETES_ENDPOINT} --certificate-authority=k8s-ca.pem
  - ./kubectl config set-credentials dev-k8s --client-certificate=k8s-client-ca.pem --client-key=k8s-key.pem
  - ./kubectl config set-context dev-k8s --cluster=dev-k8s --namespace=default --user=dev-k8s
  - ./kubectl config use-context dev-k8s
  - ./kubectl apply -f ./kubernetes/manifest.yml

```
As shown in the screenshot we took the base64 encoded certificates and loaded them into travis as environment variables (KUBERNETES_CA, KUBERNETES_CLIENT_CA, KUBERNETES_CLIENT_KEY, KUBERNETES_ENDPOINT), then we decode that into files, create the configuration using kubectl and set it as active and then we apply the deployment with the newly rendered hash.
<br />

This is how it should look in travis:
![image](/images/terraform-do-environment-variables.png){:class="mx-auto"}

Let's take a look at the generated kubernetes configuration and what values you should take into account:
```elixir
apiVersion: v1                                                                                                                                                                                                                                                                   
clusters:                                                                                                                                                                                                                                                                        
- cluster:                                                                                                                                                                                                                                                                       
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURKekNDQWcrZ0F3SUJBZ0lDQm5Vd0RRWUpLb1pJaHZjTkFRRUxCUUF3TXpFVk1CTUdBMVVFQ2hNTVJHbG4KYVhSaGJFOWpaV0Z1TVJvd0dBWURWUVFERXhGck9ITmhZWE1nUTJ4MWMzUmxjaUJEUVRBZUZ3MHhPVEExTURVeQpNREUwTWpkYUZ3MHpPVEExTURVeU1ER
TBNamRhTURNeEZUQVRCZ05WQkFvVERFUnBaMmwwWVd4UFkyVmhiakVhCk1CZ0dBMVVFQXhNUmF6aHpZV0Z6SUVOc2RYTjBaWElnUTBFd2dnRWlNQTBHQ1NxR1NJYjNEUUVCQVFVQUE0SUIKRHdBd2dnRUtBb0lCQVFEZWdIRnpBd3o1dlVTWngrOHJqQktmcGt0SS9SLzQ4dG01eE50VE9NcmsvWEx3bDczRApXa01ZWFNzdjJOOTVOdFhIb3B5VUNobGppa2NOSEpJdF
dzV0xsVU1lY0UrYlBWY054djR0YVlMRWJVbTNVSW4zCnFxalN0dmN6NU0wSFpNYlU3UVFHM2F5VFFKeE1FUTVzQWpFYkN1MEZuWERvdkpQR3cwczhHUTlWOXBBaVFDcE4KZnVMQUpTQTBZZ2RpVDJBN3RUNkV4N1ZzY256VUFWbllRRGE4VG00cHR5RXlpTHpJTzB6NFdJMTBRK1RKV2VkeQpQa2JwVjBQMklQQlhmb3Ntd2k3N0JFT3NFYUZLdmNSQzBrUm9oT1pqM3E
0T1lPTDJRMkNkTnV0dElWL1MzckllCmc2RjFWRXNEdEhKajhRUHA1U0NZUXdOekNLcnlMSjNGRXJ4NUFnTUJBQUdqUlRCRE1BNEdBMVVkRHdFQi93UUUKQXdJQmhqQVNCZ05WSFJNQkFmOEVDREFHQVFIL0FnRUFNQjBHQTFVZERnUVdCQlRFQS9PVG9qRUk1bGVnemlFRwpRLzFyNlltZFFqQU5CZ2txaGtpRzl3MEJBUXNGQUFPQ0FRRUFSK3piZjcyOVJLUDVuQlJs
Q2hPMEE5R3p6bXl4Cm1GSnc3WlYyc3hvdmwzUmUvR3NCR0FKS1ZkNkVjYWZSUklZWDgybUZWeENrQXNab1BSWFM1MlRVcXVxcWJqT0cKUWp3dXoyc3NiKzArK1lJVDhUek84MDJiZThqNFVrbG9FeFRyVkI0aFIwcjFILysxbFlYKys2cDBGK21KTG9EKwpIVDVkeCtvM1JiREVBUC82T1lkaWFIYnNIMFEyQXFsRk5uU0doeTVrSC82a3RqV3JwdUR4VVp2NUxMTTdCd
DlHCjMvMGozcU0xSnpTNXBrNkhsU1lwcitYY09ybDlrYlVKZ1VvZzJmWGhITUVWL0dXNW1ldTUyV2xhRzJkdWpnM2sKQUhLTlRPNkxnWEs3UEVOQjdYeTFFL2UrOHBDOXc5MjNsUVdHclBvSGdZdkwzZzUvcXNBdEZtNDN6dz09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K                                                                  
    server: https://592d58c9-98c1-4285-b098-cbc9378e9f89.k8s.ondigitalocean.com                                                                                                                                                                                                  
  name: do-nyc1-dev-k8s                                                                                                                                                                                                                                                          
contexts:                                                                                                                                                                                                                                                                        
- context:                                                                                                                                                                                                                                                                       
    cluster: do-nyc1-dev-k8s                                                                                                                                                                                                                                                     
    user: do-nyc1-dev-k8s-admin                                                                                                                                                                                                                                                  
  name: do-nyc1-dev-k8s                                                                                                                                                                                                                                                          
current-context: do-nyc1-dev-k8s                                                                                                                                                                                                                                                 
kind: Config                                                                                                                                                                                                                                                                     
preferences: {}                                                                                                                                                                                                                                                                  
users:                                                                                                                                                                                                                                                                           
- name: do-nyc1-dev-k8s-admin                                                                                                                                                                                                                                                    
  user:                                                                                                                                                                                                                                                                          
    client-certificate-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURyVENDQXBXZ0F3SUJBZ0lDQm5Vd0RRWUpLb1pJaHZjTkFRRUxCUUF3TXpFVk1CTUdBMVVFQ2hNTVJHbG4KYVhSaGJFOWpaV0Z1TVJvd0dBWURWUVFERXhGck9ITmhZWE1nUTJ4MWMzUmxjaUJEUVRBZUZ3MHhPVEExTURVeQpNREUzTURoYUZ3MHhPVEExTVRJeU1ERTNN
RGhhTUg4eEN6QUpCZ05WQkFZVEFsVlRNUXN3Q1FZRFZRUUlFd0pPCldURVJNQThHQTFVRUJ4TUlUbVYzSUZsdmNtc3hIVEFiQmdOVkJBb1RGR3M0YzJGaGN6cGhkWFJvWlc1MGFXTmgKZEdWa01URXdMd1lEVlFRREV5ZzJaVFE0TjJVNU5ESXlaV0kyWTJFek5tWXpNek5oT0dSak5URXpNamt4TUdSbApNbU0wTm1JM01JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT
0NBUThBTUlJQkNnS0NBUUVBemxodzg0QzR4dnlBCnVGWWNFb1M5VEY2L09FOXd5WWwvNnhZbzI5Nzc3QU9pSHp4clo2RUE2dHh5YkI0VHUyMnM5bWR3SGNhSE40OXMKYTd4YmZ2NnA1Z0l3R1FTRUx5ZVZJUVp1NjVQSzFEQUtVN3ZINVloc2FsNnByN202WTZ4YktJeDNsVDFYeGVpSApFVHhWUW5IU0hITngyZ2lJRVJmbEt4dnFnL0g1M1Ntd3I3WlFsWHlNb3huQ3
Uxd3ZXMGsyNnJzVnBJQzBCa0NNClBlTGdzQkswc01EalUvTXBzUElkRm4vSzF1dWRNYWhGTnJIdng5NkJ5bmlsaFFFMDBQaGwrNDNnWEFhRFhtNVMKRFJ4UWc3TzFpNW04dVRmUDRIWjFGU0kxUlZPWVRkQjZtSHdEV2lTVE9xZDc2TGJEWlFyT1djNURBanc1R3JjKwpIMThrcnNzQlV3SURBUUFCbzM4d2ZUQU9CZ05WSFE4QkFmOEVCQU1DQmFBd0hRWURWUjBsQkJ
Zd0ZBWUlLd1lCCkJRVUhBd0lHQ0NzR0FRVUZCd01CTUF3R0ExVWRFd0VCL3dRQ01BQXdIUVlEVlIwT0JCWUVGUGtkWTN0SmNRQzMKa01LbGhNZU1aTzhRR3RQVU1COEdBMVVkSXdRWU1CYUFGTVFEODVPaU1Ram1WNkRPSVFaRC9XdnBpWjFDTUEwRwpDU3FHU0liM0RRRUJDd1VBQTRJQkFRQW5aNXFtTlBEYWMyNTNnNkl1NkcrSjdna2o5NUhiOVFlNE5VNG5ib0NV
CjJQRmF0K3pPelF6NlhPTVRWUk9ESlJrQlJvU2pyK2gvTFFBZFFBcWk5V244bkducG9SaHRad0s0eXozS1czUlAKSXRaaURsdXpyeVZScFVQSUMxbDh1TVBzTVEveDUzaFVvYUZzODFiTExVMVE0NWJLUDRHQUgybGo4OE5HKzNMcwpQVUQxUGQ3b1Z5K0QvZUJBdDZYYnYrNms5SGxwNHovNzE4WjJjVUFnSWphNFRGSExaNmpuM2R2TWg3SnlDLzZnCm0vL0tpb1o3W
Go4Zm96YS93U3B2ZlhiSkkzUjd1RHRZMmhLbmZ6VE1iZFY5RjdkM0UxREE5aUlheEx6V2o1TzgKNktTVDlBbXV4WDU1Q2VFMGhpT1ptQ2dGS1NFazVsQXFFNDNqL3VDT1MyYTQKLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=                                                                                                      
    client-key-data: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFb3dJQkFBS0NBUUVBemxodzg0QzR4dnlBdUZZY0VvUzlURjYvT0U5d3lZbC82eFlvMjk3NzdBT2lIenhyClo2RUE2dHh5YkI0VHUyMnM5bWR3SGNhSE40OXNhN3hiZnY2cDVnSXdHUVNFTHllVklRWnU2NVBLMURBS1U3dkgKNVloc2FsNnByN202WTZ4YktJeDNsVDFYeGVp
SEVUeFZRbkhTSEhOeDJnaUlFUmZsS3h2cWcvSDUzU213cjdaUQpsWHlNb3huQ3Uxd3ZXMGsyNnJzVnBJQzBCa0NNUGVMZ3NCSzBzTURqVS9NcHNQSWRGbi9LMXV1ZE1haEZOckh2Cng5NkJ5bmlsaFFFMDBQaGwrNDNnWEFhRFhtNVNEUnhRZzdPMWk1bTh1VGZQNEhaMUZTSTFSVk9ZVGRCNm1Id0QKV2lTVE9xZDc2TGJEWlFyT1djNURBanc1R3JjK0gxOGtyc3NCV
XdJREFRQUJBb0lCQUVpaS9XL2FXakZCNVpYKwpTZmVDM3BncHFpcUtYR3UxaVdBWjl0d2ZUSk15WERtZXJUaFhodGttTE9rK1ZUZmZUY21YYy9JblZxWUtTT0pMCjlmRm9lQ3BOanR6ZnFDQnBVS2ZGZWZwWGxrakhlSHN0V1JyRndWUllhbWMvZkF0bU90aTFTY3N4UXRxYUZpSE4KR1Q1QWp2UVE5MzBIRDg3a21IbHFaRTE2T3JqTk4vZXJYMGc3NGRnUDdVVDdoRU
94R04zY1B6L2JzUTVZVXlkTwp5SE1WdlpUZG9UUzhpQnROWUQwV1VhSFVqaHRkdDRLQUJBbzZNMzJoeFVxVzV3cU1USmpjeFNxYTRvMWg3OVZVCmxmYVFqQjlBNGo0cndCaXBjd1VOL0lKTzZuUElyaml0dHYvS00xaXdSSHJXQ3pBa1pCLzU2Q1cyR1NpK3dQbGwKYUoyWVNTRUNnWUVBOXZ3Q0xNTTZoWHJaT2NlcWkvOUpYanlWaWRVNEhoR1Q3MG9FNThBbmtXdEx
qQUZvNTVVTwo5OXZwZW4xeEJEdHVIUHVVakx1b0c2WXJlMElVb3gzUGZ1VzNEVU8vaG5jcXk3VGU3QkFjd203bjdpSExlU2VQCmc4TkR1Z1NJcEZML28ra1kySGd1eThyTUNWa3c3VXMwakxYMVRzeEFHallFQlByTVFmeDBtUXNDZ1lFQTFlQ3MKdDRBRXk3T3gvcUlPNFhGZzc1NFdxZzdiWW13bDFxNTRJVU9RSTBPOGJPOUZzWlo5TEJUYU1mekdlaWlLbVNYcwo2
U01YVk5yazQvNU0yUTYyN1dBVk5hODhXQzU2Q2xCM3JnM1QzTnE1anR6ZHZtSDUxU3hPaWxkZXFkTDNXQTZlCm9JTkZJVGlrL29zNzBrSnBON2N0Y1V2MEdXYjUwc050NlV5U05ka0NnWUVBcFZ3WWdLdTlOTDBKVHh3VlhXSHcKVnoyc3lQbU9kdU5CN29YYVB1ZHlGblNGd2hqM2lZVk0zam5JV2hBK2FKejVua0g2TlRjMjJEd3JCSDA3bi9KSAppQ2g0cEZMbG1qd
VMxWXdsYkZ0bFJmQkhMREpJTHJlRDZLNEZYRGZJM0d3TmFFcWFMZVJaUUd4b3F5R2lGbDJ4CnN6dm9IM2UwdTFmSzNTS2xPdEN4cC8wQ2dZQmZFK2YwRXpjT2p5MmJjdE9HcU81YzF6eGdFUWE1OURYRi8vMXIKWEN1aFlhVk1EL285ZmhiYkY5SC8wczB3MVFENElBSDNpaC8vR3VnUjZxU2pBWVdVZE5nNDYxTzZKNzhkQXJTUgpiWmczWUF5SlUrcEhqaXFQOTRoYX
U0aGJtbXRXZS9sTWhjNmZmQnp0QTF4dWxoTk1MMlJHTDJ1dU56YnIyUER0CmU1cXIwUUtCZ0V3UjBCTi9UaVpCVVZYbWFlUXhuck1hamlIRDRzd1BHQklpWldJWEpMZGEySmNCZFRsbmZaL1cKY05KaU1nY0dXZlUyZktUMEZBd0NjWE5QK3lXRXdJNTBWQUoreWR5WWZBL2tsbUxxTFR1QVNldXRiVTc4aWlrUQpoclFuMXc3cUZuVFJZYklCOElueVRpZ1EwZVQwUUl
XOEtnNzJlUFVNZzhZUjEzMmtiSmhYCi0tLS0tRU5EIFJTQSBQUklWQVRFIEtFWS0tLS0tCg==    

```
Never do that, don't share your configuration or anybody will be able to use your cluster, also be careful not to commit it to your repo, in this example it's no longer valid because after running the examples I destroyed the cluster with `terraform destroy`. Now there are four values of interest for us: certificate-authority-data: KUBERNETES_CA, client-certificate-data: KUBERNETES_CLIENT_CA, client-key-data: KUBERNETES_CLIENT_KEY and server: KUBERNETES_ENDPOINT, with these variables we can re-create our kubernetes configuration easily using kubectl, be aware that we're not decoding to save it in travis, we do that in the travis configuration file (`.travis.yml`).
<br />

##### **Kubernetes**
So after all that, we still need to have a deployment template to deploy our application, and it's a template because we need to replace the SHA of the current build in the manifest before committing it to the Kubernetes API, so let's check it `manifest.yml.template`:
```elixir
---
apiVersion: v1
kind: Service
metadata:
  name: whatismyip-go-service
spec:
  type: NodePort
  ports:
  - port: 8000
    targetPort: 8000
    nodePort: 30000
  selector:
    app: whatismyip-go
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whatismyip-go-deployment
  namespace: default
  labels:
    app: whatismyip-go
spec:
  replicas: 1
  selector:
    matchLabels:
      app: whatismyip-go
  template:
    metadata:
      labels:
        app: whatismyip-go
    spec:
      containers:
        - name: whatismyip-go
          image: kainlite/whatismyip-go:${TRAVIS_COMMIT}
          ports:
            - containerPort: 8000
              name: http

```
Here we expose our service in the port 30000 as a NodePort, and deploy the current SHA (replaced during execution by travis)

<br />
##### **Testing everything**
Validate that the deployment went well by checking our kubernetes cluster:
```elixir
$ kubectl get pods --kubeconfig=./kubeconfig.yaml                                                                                                                                                
NAME                                        READY   STATUS    RESTARTS   AGE                                                                                                                                                                                                     
whatismyip-go-deployment-5ff9894d8c-f48nx   1/1     Running   0          9s     

```
<br />

First we test the load balancer, and as we will see the ip is not right, it's the internal ip of the load balancer and not our public ip address.
```elixir
$ curl -v 159.203.156.153
*   Trying 159.203.156.153...                                                                                                                                                                                                                                                    
* TCP_NODELAY set                                                                                                                                                                                                                                                                
* Connected to 159.203.156.153 (159.203.156.153) port 80 (#0)                                                                                                                                                                                                                    
> GET / HTTP/1.1                                                                                                                                                                                                                                                                 
> Host: 159.203.156.153                                                                                                                                                                                                                                                          
> User-Agent: curl/7.64.1                                                                                                                                                                                                                                                        
> Accept: */*                                                                                                                                                                                                                                                                    
>                                                                                                                                                                                                                                                                                
< HTTP/1.1 200 OK                                                                                                                                                                                                                                                                
< Date: Sun, 05 May 2019 21:14:28 GMT                                                                                                                                                                                                                                            
< Content-Length: 12                                                                                                                                                                                                                                                             
< Content-Type: text/plain; charset=utf-8                                                                                                                                                                                                                                        
<                                                                                                                                                                                                                                                                                
* Connection #0 to host 159.203.156.153 left intact                                                                                                                                                                                                                              
10.136.5.237* Closing connection 0 

```
<br />

But if we hit our service directly we can see the correct IP address, this could be improved but it's left as an exercise for the avid reader ◕_◕.
```elixir
$ curl -v 142.93.207.200:30000                                                                                                                                                                   
*   Trying 142.93.207.200...                                                                                                                                                                                                                                                     
* TCP_NODELAY set                                                                                                                                                                                                                                                                
* Connected to 142.93.207.200 (142.93.207.200) port 30000 (#0)                                                                                                                                                                                                                   
> GET / HTTP/1.1                                                                                                                                                                                                                                                                 
> Host: 142.93.207.200:30000                                                                                                                                                                                                                                                     
> User-Agent: curl/7.64.1                                                                                                                                                                                                                                                        
> Accept: */*                                                                                                                                                                                                                                                                    
>                                                                                                                                                                                                                                                                                
< HTTP/1.1 200 OK                                                                                                                                                                                                                                                                
< Date: Sun, 05 May 2019 21:35:13 GMT                                                                                                                                                                                                                                            
< Content-Length: 12                                                                                                                                                                                                                                                             
< Content-Type: text/plain; charset=utf-8                                                                                                                                                                                                                                        
<                                                                                                                                                                                                                                                                                
* Connection #0 to host 142.93.207.200 left intact                                                                                                                                                                                                                               
111.138.53.63* Closing connection 0  

```
<br />

Finally let's check what we should see in travis:
![image](/images/terraform-do-travis-result-1.png){:class="mx-auto"}
<br />

As we can see everything went well and our deployment applied successfully in our cluster
![image](/images/terraform-do-travis-result-2.png){:class="mx-auto"}
<br />

##### **Closing notes**
I will be posting some articles about CI and CD and good practices that DevOps/SREs should have in mind, tips, tricks, and full deployment examples, this is the second part of a possible series of three articles (Next one should be about the same but using Jenkins) with a complete but basic example of CI first and then CD. This can of course change and any feedback would be greatly appreciated :).

In this example many things could be improved, for example we use a node port and there is no firewall so we can hit our app directly via nodeport or using the load balancer, we should add some firewall rules so only the load balancer is able to talk to the node port range (30000-32767).

Also be aware that for production this setup will not be sufficient but for a development environment would suffice initially.

Some useful links for [travis](https://docs.travis-ci.com/user/job-lifecycle/) and [terraform](https://www.terraform.io/docs/providers/do/r/kubernetes_cluster.html).
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
