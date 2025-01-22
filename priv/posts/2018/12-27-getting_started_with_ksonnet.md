%{
  title: "Getting started with ksonnet",
  author: "Gabriel Garrido",
  description: "This tutorial will show you how to create a simple application and also how to deploy it to kubernetes using ksonnet...",
  tags: ~w(kubernetes jsonnet ksonnet tooling),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

### **Introduction**

This tutorial will show you how to create a simple application and also how to deploy it to kubernetes using [ksonnet](https://ksonnet.io/), in the examples I will be using [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube) or you can [check out this repo](https://github.com/kainlite/kainlite.github.io) that has a good overview of minikube, once installed and started (`minikube start`) that command will download and configure the local environment, if you have been following the previous posts you already have minikube installed and working, before we dive into an example let's review some terminology from ksonnet (extracted from the [official documentation](https://ksonnet.io/docs/concepts/)):
<br />

#### Application
A ksonnet application represents a well-structured directory of Kubernetes manifests (this is generated using the `ks init`).
<br />

#### Environment
An environment consists of four elements, some of which can be pulled from your current kubeconfig context: Name, Server, Namespace, API version. The environment determines to which cluster you're going to deploy the application.
<br />

#### Component
A component can be as simple as a Kubernetes resource (a Pod, Deployment, etc), or a fully working stack for example EFK/ELK, you can generate components using `ks generate`.
<br />

#### Prototype
Prototype + Parameters = Component. Think of a prototype as a base template before you apply the parameters, to set a name, replicas, etc for the resource, you can explore some system prototypes with `ks prototype`.
<br />

#### Parameter
It gives live to a component with dynamic values, you can use `ks param` to view or modify params, there are App params (global), Component params, and Environment params (overrides app params).
<br />

#### Module
Modules provide a way for you to share components across environments. More concisely, a module refers to a subdirectory in components/ containing its own params.libsonnet. To create a module `ks module create <module name>`.
<br />

#### Part
It provides a way to organize and re-use code.
<br />

#### Package
A package is a set of related prototypes and associates helper libraries, it allows you to create and share packages between applications.
<br />

#### Registry
It's essentially a repository for packages, it supports the incubator registry, github, filesystem, and Helm.
<br />

#### Manifest
The same old YAML or JSON manifest but this time written in [Jsonnet](https://jsonnet.org/learning/tutorial.html), basically Jsonnet is a simple extension of JSON.
<br />

Phew, that's a lot of names and terminology at once, let's get started with the terminal already.
<br />

### Let's get started
This command will generate the following folder structure `ks init wordpress`:
```elixir
INFO Using context "minikube" from kubeconfig file "~/.kube/config"
INFO Creating environment "default" with namespace "default", pointing to "version:v1.12.4" cluster at address "https://192.168.99.100:8443"
INFO Generating ksonnet-lib data at path '~/k8s-examples/wordpress/lib/ksonnet-lib/v1.12.4'

$ ls -l |  awk '{ print $9 }'
app.yaml        <--- Defines versions, namespace, cluster address, app name, registry.
components      <--- Components by default it's empty and has a params file.
environments    <--- By default there is only one environment called default.
lib             <--- Here we can find the ksonnet helpers that match the Kubernetes API with the common resources (Pods, Deployments, etc).
vendor          <--- Here is where the installed packages/apps go, it can be seen as a dependencies folder.
```
<br />

Let's generate a _deployed-service_ and inspect it's context:
```elixir
$ ks generate deployed-service wordpress \
  --image bitnami/wordpress:5.0.2 \
  --type ClusterIP

INFO Writing component at '~/k8s-examples/wordpress/components/wordpress.jsonnet'
```
At the moment of this writing the latest version of Wordpress is 5.0.2, it's always recommended to use static version numbers instead of tags like latest (because latest can not be latest).
<br />

Let's see how our component looks like:
```elixir
local env = std.extVar("__ksonnet/environments");
local params = std.extVar("__ksonnet/params").components.wordpress;
[
  {
    "apiVersion": "v1",
    "kind": "Service",
    "metadata": {
      "name": params.name
    },
    "spec": {
      "ports": [
        {
          "port": params.servicePort,
          "targetPort": params.containerPort
        }
      ],
      "selector": {
        "app": params.name
      },
      "type": params.type
    }
  },
  {
    "apiVersion": "apps/v1beta2",
    "kind": "Deployment",
    "metadata": {
      "name": params.name
    },
    "spec": {
      "replicas": params.replicas,
      "selector": {
        "matchLabels": {
          "app": params.name
        },
      },
      "template": {
        "metadata": {
          "labels": {
            "app": params.name
          }
        },
        "spec": {
          "containers": [
            {
              "image": params.image,
              "name": params.name,
              "ports": [
                {
                  "containerPort": params.containerPort
                }
              ]
            }
          ]
        }
      }
    }
  }
]
```
It's just another template for some known resources, a [service](https://kubernetes.io/docs/concepts/services-networking/service/) and a [deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) that's where the name came from: _deployed-service_, but where are those params coming from?

<br />
If we run `ks show default`:
```elixir
---
apiVersion: v1
kind: Service
metadata:
  labels:
    ksonnet.io/component: wordpress
  name: wordpress
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: wordpress
  type: ClusterIP
---
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  labels:
    ksonnet.io/component: wordpress
  name: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - image: bitnami/wordpress:5.0.2
        name: wordpress
        ports:
        - containerPort: 80
```
<br />
We will see what our package will generate in *YAML* with some good defaults. And by default if you remember from the definitions a component needs a params file to fill the blanks in this case it is `components/params.libsonnet`:
```elixir
{
  global: {
    // User-defined global parameters; accessible to all component and environments, Ex:
    // replicas: 4,
  },
  components: {
    // Component-level parameters, defined initially from 'ks prototype use ...'
    // Each object below should correspond to a component in the components/ directory
    wordpress: {
      containerPort: 80,
      image: "bitnami/wordpress:5.0.2",
      name: "wordpress",
      replicas: 1,
      servicePort: 80,
      type: "ClusterIP",
    },
  },
}
```
But that's not enough to run wordpress is it?, No is not, we need a database with persistent storage for it to work properly, so we will need to generate and extend another _deployed-service_.
<br />

The next step would be to create another component:
```elixir
$ ks generate deployed-service mariadb \
  --image bitnami/mariadb:10.1.37 \
  --type ClusterIP

INFO Writing component at '/home/kainlite/Webs/k8s-examples/wordpress/components/mariadb.jsonnet'
```
The latest stable version of MariaDB 10.1 GA at the moment of this writting is 10.1.37.
<br />

Then we will need to add a persistent volume and also tell Wordpress to use this MariaDB instance. How do we do that, we will need to modify a few files, like this (in order to re-use things I placed the mysql variables in the global section, for this example that will simplify things, but it might not be the best approach for a production environment):
The resulting `components/params.json` will be:
```elixir
{
  global: {
    // User-defined global parameters; accessible to all component and environments, Ex:
    // replicas: 4,
    mariadbEmptyPassword: "no",
    mariadbUser: "mywordpressuser",
    mariadbPassword: "mywordpresspassword",
    mariadbDatabase: "bitnami_wordpress",
  },
  components: {
    // Component-level parameters, defined initially from 'ks prototype use ...'
    // Each object below should correspond to a component in the components/ directory
    wordpress: {
      containerPort: 80,
      image: "bitnami/wordpress:5.0.2",
      name: "wordpress",
      replicas: 1,
      servicePort: 80,
      type: "ClusterIP",
    },
    mariadb: {
      containerPort: 3306,
      image: "bitnami/mariadb:10.1.37",
      name: "mariadb",
      replicas: 1,
      servicePort: 3306,
      type: "ClusterIP",
    },
  },
}
```
<br />

The resulting `components/wordpress.jsonnet` will be:
```elixir
local env = std.extVar("__ksonnet/environments");
local params = std.extVar("__ksonnet/params").components.wordpress;
[
  {
    "apiVersion": "v1",
    "kind": "Service",
    "metadata": {
      "name": params.name
    },
    "spec": {
      "ports": [
        {
          "port": params.servicePort,
          "targetPort": params.containerPort
        }
      ],
      "selector": {
        "app": params.name
      },
      "type": params.type
    }
  },
  {
    "apiVersion": "apps/v1beta2",
    "kind": "Deployment",
    "metadata": {
      "name": params.name
    },
    "spec": {
      "replicas": params.replicas,
      "selector": {
        "matchLabels": {
          "app": params.name
        },
      },
      "template": {
        "metadata": {
          "labels": {
            "app": params.name
          }
        },
        "spec": {
          "containers": [
            {
              "image": params.image,
              "name": params.name,
              "ports": [
                {
                  "containerPort": params.containerPort
                }
              ],
              "env": [
                {
                    "name": "WORDPRESS_DATABASE_USER",
                    "value": params.mariadbUser,
                },
                {
                    "name": "WORDPRESS_DATABASE_PASSWORD",
                    "value": params.mariadbPassword,
                },
                {
                    "name": "WORDPRESS_DATABASE_NAME",
                    "value": params.mariadbDatabase,
                },
                {
                    "name": "WORDPRESS_HOST",
                    "value": "mariadb",
                }
              ]
            }
          ]
        }
      }
    }
  }
]
```
The only thing that changed here is `spec.containers.env` which wasn't present before.
<br />

The resulting `components/mariadb.jsonnet` will be:
```elixir
local env = std.extVar("__ksonnet/environments");
local params = std.extVar("__ksonnet/params").components.mariadb;
[
{
    "apiVersion": "v1",
        "kind": "Service",
        "metadata": {
            "name": params.name
        },
        "spec": {
            "ports": [
            {
                "port": params.servicePort,
                "targetPort": params.containerPort
            }
            ],
            "selector": {
                "app": params.name
            },
            "type": params.type
        }
},
{
    "apiVersion": "apps/v1beta2",
    "kind": "Deployment",
    "metadata": {
        "name": params.name
    },
    "spec": {
        "replicas": params.replicas,
        "selector": {
            "matchLabels": {
                "app": params.name
            },
        },
        "template": {
            "metadata": {
                "labels": {
                    "app": params.name
                }
            },
            "spec": {
                "containers": [
                {
                    "image": params.image,
                    "name": params.name,
                    "ports": [
                    {
                        "containerPort": params.containerPort
                    },
                    ],
                    "env": [
                    {
                        "name": "ALLOW_EMPTY_PASSWORD",
                        "value": params.mariadbEmptyPassword,
                    },
                    {
                        "name": "MARIADB_USER",
                        "value": params.mariadbUser,
                    },
                    {
                        "name": "MARIADB_PASSWORD",
                        "value": params.mariadbPassword,
                    },
                    {
                        "name": "MARIADB_ROOT_PASSWORD",
                        "value": params.mariadbPassword,
                    },
                    {
                        "name": "MARIADB_DATABASE",
                        "value": params.mariadbDatabase,
                    },
                    ],
                    "volumeMounts": [
                    {
                        "mountPath": "/var/lib/mysql",
                        "name": "mariadb"
                    }
                    ]
                }
                ],
                "volumes": [
                {
                    "name": "mariadb",
                    "hostPath": {
                        "path": "/home/docker/mariadb-data"
                    }
                }
                ]
            }
        }
    }
}
]
```
I know, I know, that is a lot of JSON, I trust you have a decent scroll :).
<br />

The only things that changed here are `spec.containers.env`, `spec.containers.volumeMount` and `spec.volumes` which weren't present before, that's all you need to make wordpress work with mariadb.
<br />

This post only scratched the surface of what Ksonnet and Jsonnet can do, in another post I will describe more advances features with less _JSON_ / _YAML_. There are a lot of things that can be improved and we will cover those things in the next post, if you want to see all the source code for this post go [here](https://github.com/kainlite/ksonnet-wordpress-example).
<br />

Let's clean up `ks delete default`:
```elixir
INFO Deleting services mariadb
INFO Deleting deployments mariadb
INFO Deleting services wordpress
INFO Deleting deployments wordpress
```
<br />

### Notes

If you want to check the wordpress installation via browser you can do `minikube proxy` and then look up the following URL: [Wordpress](http://localhost:8001/api/v1/namespaces/default/services/wordpress/proxy/) (I'm using the default namespace here and the service name is wordpress, if you use ingress you don't need to do this step)
<br />

I'm not aware if Ksonnet supports releases and rollbacks like Helm, but it seems it could be emulated using git tags and just some git hooks.
<br />

If everything goes well, you should see something like this in the logs:
```elixir
$ kubectl logs -f wordpress-5b4d6bd47c-bdtmw

Welcome to the Bitnami wordpress container
Subscribe to project updates by watching https://github.com/bitnami/bitnami-docker-wordpress
Submit issues and feature requests at https://github.com/bitnami/bitnami-docker-wordpress/issues

nami    INFO  Initializing apache
apache  INFO  ==> Patching httpoxy...
apache  INFO  ==> Configuring dummy certificates...
nami    INFO  apache successfully initialized
nami    INFO  Initializing php
nami    INFO  php successfully initialized
nami    INFO  Initializing mysql-client
nami    INFO  mysql-client successfully initialized
nami    INFO  Initializing libphp
nami    INFO  libphp successfully initialized
nami    INFO  Initializing wordpress
mysql-c INFO  Trying to connect to MySQL server
mysql-c INFO  Found MySQL server listening at mariadb:3306
mysql-c INFO  MySQL server listening and working at mariadb:3306
wordpre INFO
wordpre INFO  ########################################################################
wordpre INFO   Installation parameters for wordpress:
wordpre INFO     First Name: FirstName
wordpre INFO     Last Name: LastName
wordpre INFO     Username: user
wordpre INFO     Password: **********
wordpre INFO     Email: user@example.com
wordpre INFO     Blog Name: User's Blog!
wordpre INFO     Table Prefix: wp_
wordpre INFO   (Passwords are not shown for security reasons)
wordpre INFO  ########################################################################
wordpre INFO
nami    INFO  wordpress successfully initialized
INFO  ==> Starting wordpress...
[Thu Dec 27 04:30:59.684053 2018] [ssl:warn] [pid 116] AH01909: localhost:443:0 server certificate does NOT include an ID which matches the server name
[Thu Dec 27 04:30:59.684690 2018] [ssl:warn] [pid 116] AH01909: localhost:443:0 server certificate does NOT include an ID which matches the server name
[Thu Dec 27 04:30:59.738783 2018] [ssl:warn] [pid 116] AH01909: localhost:443:0 server certificate does NOT include an ID which matches the server name
[Thu Dec 27 04:30:59.739701 2018] [ssl:warn] [pid 116] AH01909: localhost:443:0 server certificate does NOT include an ID which matches the server name
[Thu Dec 27 04:30:59.765798 2018] [mpm_prefork:notice] [pid 116] AH00163: Apache/2.4.37 (Unix) OpenSSL/1.1.0j PHP/7.2.13 configured -- resuming normal operations
[Thu Dec 27 04:30:59.765874 2018] [core:notice] [pid 116] AH00094: Command line: 'httpd -f /bitnami/apache/conf/httpd.conf -D FOREGROUND'
172.17.0.1 - - [27/Dec/2018:04:31:00 +0000] "GET / HTTP/1.1" 200 3718
172.17.0.1 - - [27/Dec/2018:04:31:01 +0000] "GET /wp-includes/js/wp-embed.min.js?ver=5.0.2 HTTP/1.1" 200 753
172.17.0.1 - - [27/Dec/2018:04:31:01 +0000] "GET /wp-includes/css/dist/block-library/theme.min.css?ver=5.0.2 HTTP/1.1" 200 452
172.17.0.1 - - [27/Dec/2018:04:31:01 +0000] "GET /wp-includes/css/dist/block-library/style.min.css?ver=5.0.2 HTTP/1.1" 200 4281
172.17.0.1 - - [27/Dec/2018:04:31:01 +0000] "GET /wp-content/themes/twentynineteen/style.css?ver=1.1 HTTP/1.1" 200 19371
172.17.0.1 - - [27/Dec/2018:04:31:01 +0000] "GET /wp-content/themes/twentynineteen/print.css?ver=1.1 HTTP/1.1" 200 1230
```

And that folks is all I have for now, be sure to check out the [Ksonnet official documentation](https://ksonnet.io/docs/) and `ks help` to know more about what ksonnet can do to help you deploy your applications to any kubernetes cluster.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Primeros pasos con ksonnet",
  author: "Gabriel Garrido",
  description: "En este tutorial vamos a ver como crear y desplegar una aplicacion en kubernetes usando ksonnet...",
  tags: ~w(kubernetes jsonnet ksonnet tooling),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### **Introducción**

Este tutorial te mostrará cómo crear una aplicación simple y también cómo desplegarla en Kubernetes usando [ksonnet](https://ksonnet.io/). En los ejemplos, usaré [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube) o puedes [consultar este repositorio](https://github.com/kainlite/kainlite.github.io) que tiene una buena visión general de minikube. Una vez instalado y arrancado (`minikube start`), ese comando descargará y configurará el entorno local. Si has estado siguiendo las publicaciones anteriores, ya tienes minikube instalado y funcionando. Antes de sumergirnos en un ejemplo, revisemos alguna terminología de ksonnet (extraída de la [documentación oficial](https://ksonnet.io/docs/concepts/)):

<br />

#### Aplicación

Una aplicación ksonnet representa un directorio bien estructurado de manifiestos de Kubernetes (esto se genera usando `ks init`).

<br />

#### Entorno

Un entorno consiste en cuatro elementos, algunos de los cuales pueden obtenerse de tu contexto kubeconfig actual: Nombre, Servidor, Espacio de nombres, Versión de API. El entorno determina a qué clúster vas a desplegar la aplicación.

<br />

#### Componente

Un componente puede ser tan simple como un recurso de Kubernetes (un Pod, Deployment, etc.), o una pila completamente funcional, por ejemplo EFK/ELK. Puedes generar componentes usando `ks generate`.

<br />

#### Prototipo

Prototipo + Parámetros = Componente. Piensa en un prototipo como una plantilla base antes de aplicar los parámetros, para establecer un nombre, réplicas, etc., para el recurso. Puedes explorar algunos prototipos del sistema con `ks prototype`.

<br />

#### Parámetro

Da vida a un componente con valores dinámicos. Puedes usar `ks param` para ver o modificar parámetros. Hay parámetros de Aplicación (globales), parámetros de Componente y parámetros de Entorno (anulan los parámetros de la aplicación).

<br />

#### Módulo

Los módulos proporcionan una forma de compartir componentes entre entornos. Más concisamente, un módulo se refiere a un subdirectorio en components/ que contiene su propio params.libsonnet. Para crear un módulo: `ks module create <nombre_del_módulo>`.

<br />

#### Parte

Proporciona una forma de organizar y reutilizar código.

<br />

#### Paquete

Un paquete es un conjunto de prototipos relacionados y bibliotecas auxiliares asociadas. Te permite crear y compartir paquetes entre aplicaciones.

<br />

#### Registro

Es esencialmente un repositorio para paquetes; soporta el registro de incubadora, GitHub, sistema de archivos y Helm.

<br />

#### Manifiesto

El mismo antiguo manifiesto YAML o JSON pero esta vez escrito en [Jsonnet](https://jsonnet.org/learning/tutorial.html); básicamente, Jsonnet es una extensión simple de JSON.

<br />

Uf, son muchos nombres y terminología a la vez. Comencemos ya con el terminal.

<br />

### Empecemos

Este comando generará la siguiente estructura de carpetas `ks init wordpress`:

```elixir
INFO Using context "minikube" from kubeconfig file "~/.kube/config"
INFO Creating environment "default" with namespace "default", pointing to "version:v1.12.4" cluster at address "https://192.168.99.100:8443"
INFO Generating ksonnet-lib data at path '~/k8s-examples/wordpress/lib/ksonnet-lib/v1.12.4'

$ ls -l |  awk '{ print $9 }'
app.yaml        <--- Define versiones, espacio de nombres, dirección del clúster, nombre de la aplicación, registro.
components      <--- Componentes; por defecto está vacío y tiene un archivo de parámetros.
environments    <--- Por defecto solo hay un entorno llamado default.
lib             <--- Aquí podemos encontrar los ayudantes de ksonnet que coinciden con la API de Kubernetes con los recursos comunes (Pods, Deployments, etc.).
vendor          <--- Aquí es donde se instalan los paquetes/aplicaciones; puede verse como una carpeta de dependencias.
```

<br />

Generemos un _deployed-service_ e inspeccionemos su contexto:

```elixir
$ ks generate deployed-service wordpress \
      --image bitnami/wordpress:5.0.2 \
      --type ClusterIP

INFO Writing component at '~/k8s-examples/wordpress/components/wordpress.jsonnet'
```

Al momento de escribir esto, la última versión de WordPress es 5.0.2. Siempre se recomienda usar números de versión estáticos en lugar de etiquetas como 'latest' (porque 'latest' puede no ser el más reciente).

<br />

Veamos cómo se ve nuestro componente:

```elixir
local env = std.extVar("__ksonnet/environments");
local params = std.extVar("__ksonnet/params").components.wordpress;
[
  {
    "apiVersion": "v1",
    "kind": "Service",
    "metadata": {
      "name": params.name
    },
    "spec": {
      "ports": [
        {
          "port": params.servicePort,
          "targetPort": params.containerPort
        }
      ],
      "selector": {
        "app": params.name
      },
      "type": params.type
    }
  },
  {
    "apiVersion": "apps/v1beta2",
    "kind": "Deployment",
    "metadata": {
      "name": params.name
    },
    "spec": {
      "replicas": params.replicas,
      "selector": {
        "matchLabels": {
          "app": params.name
        },
      },
      "template": {
        "metadata": {
          "labels": {
            "app": params.name
          }
        },
        "spec": {
          "containers": [
            {
              "image": params.image,
              "name": params.name,
              "ports": [
                {
                  "containerPort": params.containerPort
                }
              ]
            }
          ]
        }
      }
    }
  }
]
```

Es solo otra plantilla para algunos recursos conocidos, un [Service](https://kubernetes.io/docs/concepts/services-networking/service/) y un [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/); de ahí proviene el nombre: _deployed-service_. Pero, ¿de dónde vienen esos parámetros?

<br />

Si ejecutamos `ks show default`:

```elixir
---
apiVersion: v1
kind: Service
metadata:
  labels:
    ksonnet.io/component: wordpress
  name: wordpress
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: wordpress
  type: ClusterIP
---
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  labels:
    ksonnet.io/component: wordpress
  name: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - image: bitnami/wordpress:5.0.2
        name: wordpress
        ports:
        - containerPort: 80
```

<br />

Veremos lo que nuestro paquete generará en *YAML* con algunos buenos valores predeterminados. Y por defecto, si recuerdas de las definiciones, un componente necesita un archivo de parámetros para llenar los espacios en blanco; en este caso es `components/params.libsonnet`:

```elixir
{
  global: {
    // Parámetros globales definidos por el usuario; accesibles para todos los componentes y entornos, Ej:
    // replicas: 4,
  },
  components: {
    // Parámetros a nivel de componente, definidos inicialmente desde 'ks prototype use ...'
    // Cada objeto a continuación debería corresponder a un componente en el directorio components/
    wordpress: {
      containerPort: 80,
      image: "bitnami/wordpress:5.0.2",
      name: "wordpress",
      replicas: 1,
      servicePort: 80,
      type: "ClusterIP",
    },
  },
}
```

Pero eso no es suficiente para ejecutar WordPress, ¿verdad? No, no lo es. Necesitamos una base de datos con almacenamiento persistente para que funcione correctamente, así que necesitaremos generar y extender otro _deployed-service_.

<br />

El siguiente paso sería crear otro componente:

```elixir
$ ks generate deployed-service mariadb \
      --image bitnami/mariadb:10.1.37 \
      --type ClusterIP

INFO Writing component at '/home/kainlite/Webs/k8s-examples/wordpress/components/mariadb.jsonnet'
```

La última versión estable de MariaDB 10.1 GA al momento de escribir esto es 10.1.37.

<br />

Luego necesitaremos agregar un volumen persistente y también decirle a WordPress que use esta instancia de MariaDB. ¿Cómo hacemos eso? Necesitaremos modificar algunos archivos, de esta manera (para reutilizar cosas, coloqué las variables de MySQL en la sección global; para este ejemplo eso simplificará las cosas, pero podría no ser el mejor enfoque para un entorno de producción):

El `components/params.json` resultante será:

```elixir
{
  global: {
    // Parámetros globales definidos por el usuario; accesibles para todos los componentes y entornos, Ej:
    // replicas: 4,
    mariadbEmptyPassword: "no",
    mariadbUser: "mywordpressuser",
    mariadbPassword: "mywordpresspassword",
    mariadbDatabase: "bitnami_wordpress",
  },
  components: {
    // Parámetros a nivel de componente, definidos inicialmente desde 'ks prototype use ...'
    // Cada objeto a continuación debería corresponder a un componente en el directorio components/
    wordpress: {
      containerPort: 80,
      image: "bitnami/wordpress:5.0.2",
      name: "wordpress",
      replicas: 1,
      servicePort: 80,
      type: "ClusterIP",
    },
    mariadb: {
      containerPort: 3306,
      image: "bitnami/mariadb:10.1.37",
      name: "mariadb",
      replicas: 1,
      servicePort: 3306,
      type: "ClusterIP",
    },
  },
}
```

<br />

El `components/wordpress.jsonnet` resultante será:

```elixir
local env = std.extVar("__ksonnet/environments");
local params = std.extVar("__ksonnet/params").components.wordpress;
[
  {
    "apiVersion": "v1",
    "kind": "Service",
    "metadata": {
      "name": params.name
    },
    "spec": {
      "ports": [
        {
          "port": params.servicePort,
          "targetPort": params.containerPort
        }
      ],
      "selector": {
        "app": params.name
      },
      "type": params.type
    }
  },
  {
    "apiVersion": "apps/v1beta2",
    "kind": "Deployment",
    "metadata": {
      "name": params.name
    },
    "spec": {
      "replicas": params.replicas,
      "selector": {
        "matchLabels": {
          "app": params.name
        },
      },
      "template": {
        "metadata": {
          "labels": {
            "app": params.name
          }
        },
        "spec": {
          "containers": [
            {
              "image": params.image,
              "name": params.name,
              "ports": [
                {
                  "containerPort": params.containerPort
                }
              ],
              "env": [
                {
                    "name": "WORDPRESS_DATABASE_USER",
                    "value": params.mariadbUser,
                },
                {
                    "name": "WORDPRESS_DATABASE_PASSWORD",
                    "value": params.mariadbPassword,
                },
                {
                    "name": "WORDPRESS_DATABASE_NAME",
                    "value": params.mariadbDatabase,
                },
                {
                    "name": "WORDPRESS_HOST",
                    "value": "mariadb",
                }
              ]
            }
          ]
        }
      }
    }
  }
]
```

Lo único que cambió aquí es `spec.containers.env`, que no estaba presente antes.

<br />

El `components/mariadb.jsonnet` resultante será:

```elixir
local env = std.extVar("__ksonnet/environments");
local params = std.extVar("__ksonnet/params").components.mariadb;
[
{
    "apiVersion": "v1",
        "kind": "Service",
        "metadata": {
            "name": params.name
        },
        "spec": {
            "ports": [
            {
                "port": params.servicePort,
                "targetPort": params.containerPort
            }
            ],
            "selector": {
                "app": params.name
            },
            "type": params.type
        }
},
{
    "apiVersion": "apps/v1beta2",
    "kind": "Deployment",
    "metadata": {
        "name": params.name
    },
    "spec": {
        "replicas": params.replicas,
        "selector": {
            "matchLabels": {
                "app": params.name
            },
        },
        "template": {
            "metadata": {
                "labels": {
                    "app": params.name
                }
            },
            "spec": {
                "containers": [
                {
                    "image": params.image,
                    "name": params.name,
                    "ports": [
                    {
                        "containerPort": params.containerPort
                    },
                    ],
                    "env": [
                    {
                        "name": "ALLOW_EMPTY_PASSWORD",
                        "value": params.mariadbEmptyPassword,
                    },
                    {
                        "name": "MARIADB_USER",
                        "value": params.mariadbUser,
                    },
                    {
                        "name": "MARIADB_PASSWORD",
                        "value": params.mariadbPassword,
                    },
                    {
                        "name": "MARIADB_ROOT_PASSWORD",
                        "value": params.mariadbPassword,
                    },
                    {
                        "name": "MARIADB_DATABASE",
                        "value": params.mariadbDatabase,
                    },
                    ],
                    "volumeMounts": [
                    {
                        "mountPath": "/var/lib/mysql",
                        "name": "mariadb"
                    }
                    ]
                }
                ],
                "volumes": [
                {
                    "name": "mariadb",
                    "hostPath": {
                        "path": "/home/docker/mariadb-data"
                    }
                }
                ]
            }
        }
    }
}
]
```

Lo sé, lo sé, eso es mucho JSON. Confío en que tienes un buen scroll :).

<br />

Las únicas cosas que cambiaron aquí son `spec.containers.env`, `spec.containers.volumeMount` y `spec.volumes`, que no estaban presentes antes. Eso es todo lo que necesitas para hacer que WordPress funcione con MariaDB.

<br />

Esta publicación solo rasca la superficie de lo que Ksonnet y Jsonnet pueden hacer. En otra publicación describiré características más avanzadas con menos _JSON_ / _YAML_. Hay muchas cosas que se pueden mejorar y cubriremos esas cosas en la siguiente publicación. Si deseas ver todo el código fuente de esta publicación, ve [aquí](https://github.com/kainlite/ksonnet-wordpress-example).

<br />

Limpiemos con `ks delete default`:

```elixir
INFO Deleting services mariadb
INFO Deleting deployments mariadb
INFO Deleting services wordpress
INFO Deleting deployments wordpress
```

<br />

### Notas

Si deseas verificar la instalación de WordPress a través del navegador, puedes hacer `minikube proxy` y luego acceder a la siguiente URL: [WordPress](http://localhost:8001/api/v1/namespaces/default/services/wordpress/proxy/) (estoy usando el espacio de nombres por defecto aquí y el nombre del servicio es wordpress; si usas ingress no necesitas hacer este paso).

<br />

No estoy al tanto de si Ksonnet soporta lanzamientos y rollbacks como Helm, pero parece que podría emularse usando etiquetas de git y algunos hooks de git.

<br />

Si todo va bien, deberías ver algo como esto en los logs:

```elixir
$ kubectl logs -f wordpress-5b4d6bd47c-bdtmw

Welcome to the Bitnami wordpress container
Subscribe to project updates by watching https://github.com/bitnami/bitnami-docker-wordpress
Submit issues and feature requests at https://github.com/bitnami/bitnami-docker-wordpress/issues

nami    INFO  Initializing apache
apache  INFO  ==> Patching httpoxy...
apache  INFO  ==> Configuring dummy certificates...
nami    INFO  apache successfully initialized
nami    INFO  Initializing php
nami    INFO  php successfully initialized
nami    INFO  Initializing mysql-client
nami    INFO  mysql-client successfully initialized
nami    INFO  Initializing libphp
nami    INFO  libphp successfully initialized
nami    INFO  Initializing wordpress
mysql-c INFO  Trying to connect to MySQL server
mysql-c INFO  Found MySQL server listening at mariadb:3306
mysql-c INFO  MySQL server listening and working at mariadb:3306
wordpre INFO
wordpre INFO  ########################################################################
wordpre INFO   Installation parameters for wordpress:
wordpre INFO     First Name: FirstName
wordpre INFO     Last Name: LastName
wordpre INFO     Username: user
wordpre INFO     Password: **********
wordpre INFO     Email: user@example.com
wordpre INFO     Blog Name: User's Blog!
wordpre INFO     Table Prefix: wp_
wordpre INFO   (Passwords are not shown for security reasons)
wordpre INFO  ########################################################################
wordpre INFO
nami    INFO  wordpress successfully initialized
INFO  ==> Starting wordpress...
[Thu Dec 27 04:30:59.684053 2018] [ssl:warn] [pid 116] AH01909: localhost:443:0 server certificate does NOT include an ID which matches the server name
[Thu Dec 27 04:30:59.684690 2018] [ssl:warn] [pid 116] AH01909: localhost:443:0 server certificate does NOT include an ID which matches the server name
[Thu Dec 27 04:30:59.738783 2018] [ssl:warn] [pid 116] AH01909: localhost:443:0 server certificate does NOT include an ID which matches the server name
[Thu Dec 27 04:30:59.739701 2018] [ssl:warn] [pid 116] AH01909: localhost:443:0 server certificate does NOT include an ID which matches the server name
[Thu Dec 27 04:30:59.765798 2018] [mpm_prefork:notice] [pid 116] AH00163: Apache/2.4.37 (Unix) OpenSSL/1.1.0j PHP/7.2.13 configured -- resuming normal operations
[Thu Dec 27 04:30:59.765874 2018] [core:notice] [pid 116] AH00094: Command line: 'httpd -f /bitnami/apache/conf/httpd.conf -D FOREGROUND'
172.17.0.1 - - [27/Dec/2018:04:31:00 +0000] "GET / HTTP/1.1" 200 3718
172.17.0.1 - - [27/Dec/2018:04:31:01 +0000] "GET /wp-includes/js/wp-embed.min.js?ver=5.0.2 HTTP/1.1" 200 753
172.17.0.1 - - [27/Dec/2018:04:31:01 +0000] "GET /wp-includes/css/dist/block-library/theme.min.css?ver=5.0.2 HTTP/1.1" 200 452
172.17.0.1 - - [27/Dec/2018:04:31:01 +0000] "GET /wp-includes/css/dist/block-library/style.min.css?ver=5.0.2 HTTP/1.1" 200 4281
172.17.0.1 - - [27/Dec/2018:04:31:01 +0000] "GET /wp-content/themes/twentynineteen/style.css?ver=1.1 HTTP/1.1" 200 19371
172.17.0.1 - - [27/Dec/2018:04:31:01 +0000] "GET /wp-content/themes/twentynineteen/print.css?ver=1.1 HTTP/1.1" 200 1230
```

Y eso es todo por ahora. Asegúrate de revisar la [documentación oficial de Ksonnet](https://ksonnet.io/docs/) y `ks help` para saber más sobre lo que Ksonnet puede hacer para ayudarte a desplegar tus aplicaciones en cualquier clúster de Kubernetes.

<br />

### Errata

Si encuentras algún error o tienes alguna sugerencia, por favor envíame un mensaje para que pueda corregirlo.

<br />
