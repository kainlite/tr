%{
  title: "Getting started with terraform modules",
  author: "Gabriel Garrido",
  description: "In this article we will see a subtle introduction to terraform modules, how to pass data into the module, get something from the module and create a resource (GKE cluster)...",
  tags: ~w(kubernetes gcp terraform),
  published: true,
  image: "terraform.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![terraform](/images/terraform.webp){:class="mx-auto"}

##### **Introduction**
In this article we will see a subtle introduction to terraform modules, how to pass data into the module, get something from the module and create a resource (GKE cluster), it's intended to be as simple as possible just to be aware of what a module is composed of, or how can you do your own modules, sometimes it makes sense to have modules to abstract implementations that you use over several projects, or things that are often repeated along the project. So let's see what it takes to create and use a module. The source code for this article can be found [here](https://github.com/kainlite/terraform-module-example). Note that in this example I'm using GCP since they give you $300 USD for a year to try their services and it looks pretty good so far, after sign-up you will need to go to IAM, then create a service account and after that export the the key (this is required for the terraform provider to talk to GCP).
<br />

##### **Composition of a module**
A module can be any folder with a `main.tf` file in it, yes, that is the only _required_ file for a module to be usable, but the recommendation is that you also put a `README.md` file with a description of the module if it's intended to be used by people if it's a sub-module it's not necessary, also you will need a file called `variables.tf` and other `outputs.tf` of course if it's a big module that cannot be splitted into sub-modules you can split those files for convenience or readability, variables should have descriptions so the tooling can show you what are they for, you can read more about the basics for a module [here](https://www.terraform.io/docs/modules/index.html).
<br />

Before moving on let's see the folder structure of our project:
```elixir
├── account.json
├── LICENSE
├── main.tf
├── module
│   ├── main.tf
│   ├── outputs.tf
│   └── variables.tf
├── README.md
└── terraform.tfvars

1 directory, 8 files
```
<br />

##### **Okay enough talking, show me the code**
###### **The project**
Let's start with the `main.tf` that will call our module, notice that I added a few additional comments but it's pretty much straight forward, we set the provider, then we define some variables, call our module and print some output (output can also be used to pass data between modules).
```elixir
# Set the provider to be able to talk to GCP
provider "google" {
  credentials = "${file("account.json")}"
  project     = "${var.project_name}"
  region      = "${var.region}"
}

# Variable definition
variable "project_name" {
  default = "testinggcp"
  type    = "string"
}

variable "cluster_name" {
  default = "demo-terraform-cluster"
  type    = "string"
}

variable "region" {
  default = "us-east1"
  type    = "string"
}

variable "zone" {
  default = "us-east1-c"
  type    = "string"
}

# Call our module and pass the var zone in, and get cluster_name out
module "terraform-gke" {
  source = "./module"
  zone = "${var.zone}"
  cluster_name = "${var.cluster_name}"
}

# Print the value of k8s_master_version
output "kubernetes-version" {
  value = module.terraform-gke.k8s_master_version
}

```
<br />

Then `terraform.tfvars` has some values to override the defaults that we defined:
```elixir
project_name = "testingcontainerengine"
cluster_name = "demo-cluster"
region = "us-east1"
zone = "us-east1-c"

```
<br />

###### **The module**
Now into the module itself, this module will create a GKE cluster, and while it's not a good practice to have a module as a wrapper but for this example we will forget about that rule for a while, this is the `main.tf` file:
```elixir
# Create the cluster
resource "google_container_cluster" "gke-cluster" {
  name               = "${var.cluster_name}"
  network            = "default"
  zone               = "${var.zone}"
  initial_node_count = 3
}

```
<br />

The `variables.tf` file:
```elixir
variable "cluster_name" {
  default = "terraform-module-demo"
  type    = "string"
}

variable "zone" {
  default = "us-east1-b"
  type    = "string"
}

variable "region" {
  default = "us-east1"
  type = "string"
}

```
<br />

And finally the `outputs.tf` file:
```elixir
output "k8s_endpoint" {
  value = "${google_container_cluster.gke-cluster.endpoint}"
}

output "k8s_master_version" {
  value = "${google_container_cluster.gke-cluster.master_version}"
}

output "k8s_instance_group_urls" {
  value = "${google_container_cluster.gke-cluster.instance_group_urls.0}"
}

output "k8s_master_auth_client_certificate" {
  value = "${google_container_cluster.gke-cluster.master_auth.0.client_certificate}"
}

output "k8s_master_auth_client_key" {
  value = "${google_container_cluster.gke-cluster.master_auth.0.client_key}"
}

output "k8s_master_auth_cluster_ca_certificate" {
  value = "${google_container_cluster.gke-cluster.master_auth.0.cluster_ca_certificate}"
}

```
Notice that we have a lot more outputs than the one we decided to print out, but you can play with that and experiment if you want :)
<br />

###### **Testing it**
First we need to initialize our project so terraform can put modules, provider files, etc in place, it's a good practice to version things and to move between versions that way everything can be tested and if something is not working as expected you can always rollback to the previous state.
```elixir
$ terraform init 
Initializing the backend...

Initializing provider plugins...
- Checking for available provider plugins...
- Downloading plugin for provider "google" (terraform-providers/google) 2.9.1...

The following providers do not have any version constraints in configuration,
so the latest version was installed.

To prevent automatic upgrades to new major versions that may contain breaking
changes, it is recommended to add version = "..." constraints to the
corresponding provider blocks in configuration, with the constraint strings
suggested below.

* provider.google: version = "~> 2.9"

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.

```
<br />

Then we will just run it.
```elixir
 $ terraform apply

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.terraform-gke.google_container_cluster.gke-cluster will be created
  + resource "google_container_cluster" "gke-cluster" {
      + additional_zones            = (known after apply)
      + cluster_autoscaling         = (known after apply)
      + cluster_ipv4_cidr           = (known after apply)
      + enable_binary_authorization = (known after apply)
      + enable_kubernetes_alpha     = false
      + enable_legacy_abac          = false
      + enable_tpu                  = (known after apply)
      + endpoint                    = (known after apply)
      + id                          = (known after apply)
      + initial_node_count          = 3
      + instance_group_urls         = (known after apply)
      + ip_allocation_policy        = (known after apply)
      + location                    = (known after apply)
      + logging_service             = (known after apply)
      + master_version              = (known after apply)
      + monitoring_service          = (known after apply)
      + name                        = "demo-cluster"
      + network                     = "default"
      + node_locations              = (known after apply)
      + node_version                = (known after apply)
      + project                     = (known after apply)
      + region                      = (known after apply)
      + services_ipv4_cidr          = (known after apply)
      + subnetwork                  = (known after apply)
      + zone                        = "us-east1-c"

      + addons_config {
          + horizontal_pod_autoscaling {
              + disabled = (known after apply)
            }

          + http_load_balancing {
              + disabled = (known after apply)
            }

          + kubernetes_dashboard {
              + disabled = (known after apply)
            }

          + network_policy_config {
              + disabled = (known after apply)
            }
        }

      + master_auth {
          + client_certificate     = (known after apply)
          + client_key             = (sensitive value)
          + cluster_ca_certificate = (known after apply)
          + password               = (sensitive value)
          + username               = (known after apply)

          + client_certificate_config {
              + issue_client_certificate = (known after apply)
            }
        }

      + network_policy {
          + enabled  = (known after apply)
          + provider = (known after apply)
        }

      + node_config {
          + disk_size_gb      = (known after apply)
          + disk_type         = (known after apply)
          + guest_accelerator = (known after apply)
          + image_type        = (known after apply)
          + labels            = (known after apply)
          + local_ssd_count   = (known after apply)
          + machine_type      = (known after apply)
          + metadata          = (known after apply)
          + min_cpu_platform  = (known after apply)
          + oauth_scopes      = (known after apply)
          + preemptible       = (known after apply)
          + service_account   = (known after apply)
          + tags              = (known after apply)

          + taint {
              + effect = (known after apply)
              + key    = (known after apply)
              + value  = (known after apply)
            }

          + workload_metadata_config {
              + node_metadata = (known after apply)
            }
        }

      + node_pool {
          + initial_node_count  = (known after apply)
          + instance_group_urls = (known after apply)
          + max_pods_per_node   = (known after apply)
          + name                = (known after apply)
          + name_prefix         = (known after apply)
          + node_count          = (known after apply)
          + version             = (known after apply)

          + autoscaling {
              + max_node_count = (known after apply)
              + min_node_count = (known after apply)
            }

          + management {
              + auto_repair  = (known after apply)
              + auto_upgrade = (known after apply)
            }

          + node_config {
              + disk_size_gb      = (known after apply)
              + disk_type         = (known after apply)
              + guest_accelerator = (known after apply)
              + image_type        = (known after apply)
              + labels            = (known after apply)
              + local_ssd_count   = (known after apply)
              + machine_type      = (known after apply)
              + metadata          = (known after apply)
              + min_cpu_platform  = (known after apply)
              + oauth_scopes      = (known after apply)
              + preemptible       = (known after apply)
              + service_account   = (known after apply)
              + tags              = (known after apply)

              + taint {
                  + effect = (known after apply)
                  + key    = (known after apply)
                  + value  = (known after apply)
                }

              + workload_metadata_config {
                  + node_metadata = (known after apply)
                }
            }
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.terraform-gke.google_container_cluster.gke-cluster: Creating...
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [10s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [20s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [30s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [40s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [50s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m0s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m10s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m20s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m30s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m40s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m50s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [2m0s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [2m10s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [2m20s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [2m30s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Creation complete after 2m35s [id=demo-cluster]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

kubernetes-version = 1.12.8-gke.10

```
If we check the output we will see that the name of the cluster matches the one from our variables and at the end we can see the output that the module produced.
<br />

##### **Closing notes**
As you can see, creating a module is pretty simple and with good planing and practice it can save you a lot of effort along big projects or while working on multiple projects, let me know your thoughts about it. Always remember to destroy the resources that you're not going to use with `terraform destroy`.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Primeros pasos con modulos en terraform",
  author: "Gabriel Garrido",
  description: "Este articulo es una introduccion a modulos en terraform...",
  tags: ~w(kubernetes gcp terraform),
  published: true,
  image: "terraform.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![terraform](/images/terraform.webp){:class="mx-auto"}

##### **Introducción**
En este artículo vamos a ver una introducción sutil a los módulos de Terraform, cómo pasar datos a un módulo, obtener algo del módulo y crear un recurso (un clúster GKE). La idea es que sea lo más simple posible para entender de qué está compuesto un módulo y cómo podés crear los tuyos. A veces tiene sentido usar módulos para abstraer implementaciones que usás en varios proyectos o cosas que se repiten frecuentemente dentro del proyecto. Así que veamos qué se necesita para crear y usar un módulo. El código fuente para este artículo lo podés encontrar [aquí](https://github.com/kainlite/terraform-module-example). En este ejemplo estoy usando GCP, ya que te dan $300 USD por un año para probar sus servicios, y hasta ahora parece bastante bueno. Después de registrarte, tenés que ir a IAM, crear una cuenta de servicio y exportar la clave (esto es necesario para que el proveedor de Terraform pueda hablar con GCP).
<br />

##### **Composición de un módulo**
Un módulo puede ser cualquier carpeta que contenga un archivo `main.tf`. Sí, ese es el único archivo _requerido_ para que un módulo sea usable, pero la recomendación es que también agregues un archivo `README.md` con una descripción del módulo si está pensado para ser utilizado por otras personas. Si es un submódulo, esto no es necesario. También vas a necesitar un archivo llamado `variables.tf` y otro `outputs.tf`. Por supuesto, si es un módulo grande que no se puede dividir en submódulos, podés dividir estos archivos por conveniencia o para mejorar la legibilidad. Las variables deberían tener descripciones para que las herramientas puedan mostrar para qué sirven. Podés leer más sobre los fundamentos de un módulo [aquí](https://www.terraform.io/docs/modules/index.html).
<br />

Antes de avanzar, veamos la estructura de carpetas de nuestro proyecto:
```elixir
├── account.json
├── LICENSE
├── main.tf
├── module
│   ├── main.tf
│   ├── outputs.tf
│   └── variables.tf
├── README.md
└── terraform.tfvars

1 directory, 8 files
```
<br />

##### **Bueno, basta de hablar, mostrame el código**
###### **El proyecto**
Empecemos con el archivo `main.tf` que va a llamar a nuestro módulo. Fijate que agregué algunos comentarios adicionales, pero es bastante directo: configuramos el proveedor, definimos algunas variables, llamamos a nuestro módulo y mostramos una salida (la salida también se puede usar para pasar datos entre módulos).
```elixir
# Configurar el proveedor para poder hablar con GCP
provider "google" {
  credentials = "${file("account.json")}"
  project     = "${var.project_name}"
  region      = "${var.region}"
}

# Definición de variables
variable "project_name" {
  default = "testinggcp"
  type    = "string"
}

variable "cluster_name" {
  default = "demo-terraform-cluster"
  type    = "string"
}

variable "region" {
  default = "us-east1"
  type    = "string"
}

variable "zone" {
  default = "us-east1-c"
  type    = "string"
}

# Llamar a nuestro módulo y pasar la variable zone, y obtener cluster_name
module "terraform-gke" {
  source = "./module"
  zone = "${var.zone}"
  cluster_name = "${var.cluster_name}"
}

# Imprimir el valor de k8s_master_version
output "kubernetes-version" {
  value = module.terraform-gke.k8s_master_version
}

```
<br />

Después, el archivo `terraform.tfvars` tiene algunos valores para sobrescribir los predeterminados que definimos:
```elixir
project_name = "testingcontainerengine"
cluster_name = "demo-cluster"
region = "us-east1"
zone = "us-east1-c"

```
<br />

###### **El módulo**
Ahora veamos el propio módulo. Este módulo va a crear un clúster GKE, y aunque no es una buena práctica usar un módulo como un wrapper, para este ejemplo vamos a olvidar esa regla por un rato. Este es el archivo `main.tf`:
```elixir
# Crear el clúster
resource "google_container_cluster" "gke-cluster" {
  name               = "${var.cluster_name}"
  network            = "default"
  zone               = "${var.zone}"
  initial_node_count = 3
}

```
<br />

El archivo `variables.tf`:
```elixir
variable "cluster_name" {
  default = "terraform-module-demo"
  type    = "string"
}

variable "zone" {
  default = "us-east1-b"
  type    = "string"
}

variable "region" {
  default = "us-east1"
  type = "string"
}

```
<br />

Y finalmente el archivo `outputs.tf`:
```elixir
output "k8s_endpoint" {
  value = "${google_container_cluster.gke-cluster.endpoint}"
}

output "k8s_master_version" {
  value = "${google_container_cluster.gke-cluster.master_version}"
}

output "k8s_instance_group_urls" {
  value = "${google_container_cluster.gke-cluster.instance_group_urls.0}"
}

output "k8s_master_auth_client_certificate" {
  value = "${google_container_cluster.gke-cluster.master_auth.0.client_certificate}"
}

output "k8s_master_auth_client_key" {
  value = "${google_container_cluster.gke-cluster.master_auth.0.client_key}"
}

output "k8s_master_auth_cluster_ca_certificate" {
  value = "${google_container_cluster.gke-cluster.master_auth.0.cluster_ca_certificate}"
}

```
Notá que tenemos muchos más outputs que el que decidimos mostrar, pero podés jugar con eso y experimentar si querés :)
<br />

###### **Probándolo**
Primero necesitamos inicializar nuestro proyecto para que Terraform pueda colocar los módulos, archivos de proveedor, etc. en su lugar. Es una buena práctica versionar las cosas y moverse entre versiones, de esa manera todo puede ser probado y, si algo no funciona como se espera, siempre podés hacer un rollback al estado anterior.
```elixir
$ terraform init 
Initializing the backend...

Initializing provider plugins...
- Checking for available provider plugins...
- Downloading plugin for provider "google" (terraform-providers/google) 2.9.1...

The following providers do not have any version constraints in configuration,
so the latest version was installed.

To prevent automatic upgrades to new major versions that may contain breaking
changes, it is recommended to add version = "..." constraints to the
corresponding provider blocks in configuration, with the constraint strings
suggested below.

* provider.google: version = "~> 2.9"

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.

```
<br />

Luego simplemente lo ejecutamos.
```elixir
 $ terraform apply

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.terraform-gke.google_container_cluster.gke-cluster will be created
  + resource "google_container_cluster" "gke-cluster" {
      + additional_zones            = (known after apply)
      + cluster_autoscaling         = (known after apply)
      + cluster_ipv4_cidr           = (known after apply)
      + enable_binary_authorization = (known after apply)
      + enable_kubernetes_alpha     = false
      + enable_legacy_abac          = false
      + enable_tpu                  = (known after apply)
      + endpoint                    = (known after apply)
      + id                          = (known after apply)
      + initial_node_count          = 3
      + instance_group_urls         = (known after apply)
      + ip_allocation_policy        = (known after apply)
      + location                    = (known after apply)
      + logging_service             = (known after apply)
      + master_version              = (known after apply)
      + monitoring_service          = (known after apply)
      + name                        = "demo-cluster"
      + network                     = "default"
      + node_locations              = (known after apply)
      + node_version                = (known after apply)
      + project                     = (known after apply)
      + region                      = (known after apply)
      + services_ipv4_cidr          = (known after apply)
      + subnetwork                  = (known after apply)
      + zone                        = "us-east1-c"

      + addons_config {
          + horizontal_pod_autoscaling {
              + disabled = (known after apply)
            }

          + http_load_balancing {
              + disabled = (known after apply)
            }

          + kubernetes_dashboard {
              + disabled = (known after apply)
            }

          + network_policy_config {
              + disabled = (known after apply)
            }
        }

      + master_auth {
          + client_certificate     = (known after apply)
          + client_key             = (sensitive value)
          + cluster_ca_certificate = (known after apply)
          + password               = (sensitive value)
          + username               = (known after apply)

          + client_certificate_config {
              + issue_client_certificate = (known after apply)
            }
        }

      + network_policy {
          + enabled  = (known after apply)
          + provider = (known after apply)
        }

      + node_config {
          + disk_size_gb      = (known after apply)
          + disk_type         = (known after apply)
          + guest_accelerator = (known after apply)
          + image_type        = (known after apply)
          + labels            = (known after apply)
          + local_ssd_count   = (known after apply)
          + machine_type      = (known after apply)
          + metadata          = (known after apply)
          + min_cpu_platform  = (known after apply)
          + oauth_scopes      = (known after apply)
          + preemptible       = (known after apply)
          + service_account   = (known after apply)
          + tags              = (known after apply)

          + taint {
              + effect = (known after apply)
              + key    = (known after apply)
              + value  = (known after apply)
            }

          + workload_metadata_config {
              + node_metadata = (known after apply)
            }
        }

      + node_pool {
          + initial_node_count  = (known after apply)
          + instance_group_urls = (known after apply)
          + max_pods_per_node   = (known after apply)
          + name                = (known after apply)
          + name_prefix         = (known after apply)
          + node_count          = (known after apply)
          + version             = (known after apply)

          + autoscaling {
              + max_node_count = (known after apply)
              + min_node_count = (known after apply)
            }

          + management {
              + auto_repair  = (known after apply)
              + auto_upgrade = (known after apply)
            }

          + node_config {
              + disk_size_gb      = (known after apply)
              + disk_type         = (known after apply)
              + guest_accelerator = (known after apply)
              + image_type        = (known after apply)
              + labels            = (known after apply)
              + local_ssd_count   = (known after apply)
              + machine_type      = (known after apply)
              + metadata          = (known after apply)
              + min_cpu_platform  = (known after apply)
              + oauth_scopes      = (known after apply)
              + preemptible       = (known after apply)
              + service_account   = (known after apply)
              + tags              = (known after apply)

              + taint {
                  + effect = (known after apply)
                  + key    = (known after apply)
                  + value  = (known after apply)
                }

              + workload_metadata_config {
                  + node_metadata = (known after apply)
                }
            }
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.terraform-gke.google_container_cluster.gke-cluster: Creating...
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [10s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [20s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [30s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [40s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [50s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m0s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m10s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m20s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m30s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m40s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [1m50s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [2m0s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [2m10s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [2m20s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Still creating... [2m30s elapsed]
module.terraform-gke.google_container_cluster.gke-cluster: Creation complete after 2m35s [id=demo-cluster]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

kubernetes-version = 1.12.8-gke.10

```
##### **Notas finales**
Como podés ver, crear un módulo es bastante simple y, con una buena planificación y práctica, te puede ahorrar mucho esfuerzo en proyectos grandes o cuando trabajás en varios proyectos al mismo tiempo. Contame qué te parece. Siempre acordate de destruir los recursos que no vas a usar con `terraform destroy`.
<br />

### Erratas
Si encontrás algún error o tenés alguna sugerencia, por favor mandame un mensaje así lo arreglo.

<br />
