%{
  title: "Brief introduction to terratest",
  author: "Gabriel Garrido",
  description: "In this article we will see the basics to have tests for your terraform code using a re-usable pattern, we will use the code from the last article...",
  tags: ~w(kubernetes terratest golang terraform),
  published: true,
  image: "terraform.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In this article we will see the basics to have tests for your terraform code using a re-usable pattern, we will use the code from the last article [Serverless authentication with Cognito](/blog/serverless_authentication_with_cognito_and_golang), so refer to that one before starting this one if you want to know how did we get here. Also as a side note this is a very basic example on how to get started with terratest.
<br />

[Terratest](https://github.com/gruntwork-io/terratest) is a Go library that makes it easier to write automated tests for your infrastructure code, it supports Terraform, Docker, Packer, SSH, AWS, GCP, Kubernetes, Helm, and much more, also as it's written as a Go library you have access to all the existing APIs.
<br />

##### **The code**
There are comments all over the code to explain each part, but what I want to highlight here is the pattern being used with the module `test-structure`, this module allows us to split the test in sections and skip parts that we don't need or want to run, so we have 3 stages here: `cleanup`, `deploy`, and `validate`, this lets you use `SKIP_stage`, for example `SKIP_cleanup` when you run your tests with `go test -timeout 90m .` (I added some extra bits, that I usually use, like timeout by default it's 10 minutes I believe and it's often too short), to only run `validate` and `cleanup`, it can be useful while developing a module to test without having to wait for everything to be re-created.
```elixir
package test

import (
    "crypto/tls"
    "fmt"
    "testing"
    "time"

    http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
    "github.com/gruntwork-io/terratest/modules/retry"
    "github.com/gruntwork-io/terratest/modules/terraform"
    test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// Main function, define stages and run.
func TestTerraformAws(t *testing.T) {
    t.Parallel()

    // Pick a random AWS region to test in. This helps ensure your code works in all regions.
    // awsRegion := aws.GetRandomStableRegion(t, nil, nil)
    awsRegion := "us-east-1"

    workingDir := "../terraform"

    // At the end of the test, undeploy the web app using Terraform
    defer test_structure.RunTestStage(t, "cleanup", func() {
        destroyTerraform(t, workingDir)
    })

    // Deploy the web app using Terraform
    test_structure.RunTestStage(t, "deploy", func() {
        deployTerraform(t, awsRegion, workingDir)
    })

    // Validate that the ASG deployed and is responding to HTTP requests
    test_structure.RunTestStage(t, "validate", func() {
        validateAPIGateway(t, workingDir)
    })
}

// Validate that the API Gateway has been deployed and is working
func validateAPIGateway(t *testing.T, workingDir string) {
    // Load the Terraform Options saved by the earlier deploy_terraform stage
    terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

    // Run `terraform output` to get the value of an output variable
    url := terraform.Output(t, terraformOptions, "URL")

    // It can take a few minutes for the API GW and CloudFront to finish spinning up, so retry a few times
    //  maxRetries := 30
    timeBetweenRetries := 15 * time.Second

    // Setup a TLS configuration to submit with the helper, a blank struct is acceptable
    tlsConfig := tls.Config{}

    // Verify that the API Gateway returns a proper response
    apigw := retry.DoInBackgroundUntilStopped(t, fmt.Sprintf("Check URL %s", url), timeBetweenRetries, func() {
        http_helper.HttpGetWithCustomValidation(t, fmt.Sprintf("%s/app/health", url), &tlsConfig, func(statusCode int, body string) bool {
            return statusCode == 200
        })
    })

    // Stop checking the API Gateway
    apigw.Done()
}

// Deploy the resources using Terraform
func deployTerraform(t *testing.T, awsRegion string, workingDir string) {
    terraformOptions := &terraform.Options{
        // The path to where our Terraform code is located
        TerraformDir: workingDir,
    }

    // Save the Terraform Options struct, instance name, and instance text so future test stages can use it
    test_structure.SaveTerraformOptions(t, workingDir, terraformOptions)

    // This will run `terraform init` and `terraform apply` and fail the test if there are any errors
    terraform.InitAndApply(t, terraformOptions)
}

// Destroy the resources using Terraform
func destroyTerraform(t *testing.T, workingDir string) {
    // Load the Terraform Options saved by the earlier deploy_terraform stage
    terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

    terraform.Destroy(t, terraformOptions)
}
```
Some high level notes on each stage:

`deploy`: This stage will take care of running init and then apply.

`validate`: This stage will take care of running a probe to check if our API is up and if the return code is `200`.

`cleanup`: This stage will take care of running destroy and cleaning up everything.
<br />

##### **Dep**
Currently terratest uses dep, so you will need this file `Gopkg.toml` and `dep` installed to be able to install the dependencies with `dep ensure -v`.
```elixir
[[constraint]]
  name = "github.com/gruntwork-io/terratest"
  version = "0.18.6"
```
<br />

##### **Dockerfile**
Also you can use this small dockerfile that does all that for you, in this example using the code from the previously mentioned article.
```elixir
FROM golang:alpine
MAINTAINER "kainlite <kainlite@gmail.com>"

ARG TERRAFORM_VERSION=0.12.8
ENV TERRAFORM_VERSION=$TERRAFORM_VERSION

RUN apk --no-cache add curl git unzip gcc g++ make ca-certificates && \
    curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh

RUN mkdir tmp && \
    curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o tmp/terraform.zip && \
    unzip tmp/terraform.zip -d /usr/local/bin && \
    rm -rf tmp/

ARG GOPROJECTPATH=/go/src/github.com/kainlite/serverless-cognito
COPY ./ $GOPROJECTPATH

WORKDIR $GOPROJECTPATH/test

RUN dep ensure -v

CMD ["go", "test", " -timeout", "90m", "."]
```
<br />

##### **Manually testing it**
First we check that the URL actually works, and that everything is in place.
```elixir
$ curl https://api.skynetng.pw/app/health
# OUTPUT:
# {"status":"healthy"}
```
<br />

Next we can test it using our validate stage, using terratest:
```elixir
$ SKIP_deploy=true SKIP_cleanup=true go test -timeout 90m .
# OUTPUT:
# ok      github.com/kainlite/test        1.117s
```
This works because in the terraform code we have an output called `URL` which is `https://api.skynetng.pw`, then we add at the end `/app/health` and check if it return a `200` code, otherwise we wait and retry until it does or times out.
<br />

### Closing notes
And that's all for now, in the next piece I will cover how to automate this deployment using a CI/CD tool, so you can have truly repeatable infrastructure, which can be of big importance when working on various modules, versions and deployments.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Introduccion rapida a terratest",
  author: "Gabriel Garrido",
  description: "Veremos como usar terratest para probar nuestro codigo hcl o terraform...",
  tags: ~w(kubernetes terratest golang terraform),
  published: true,
  image: "terraform.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En este artículo vamos a ver los conceptos básicos para realizar tests en tu código de terraform usando un patrón reutilizable. Usaremos el código del artículo anterior [Autenticación serverless con Cognito](/blog/serverless_authentication_with_cognito_and_golang), por lo que te recomiendo leer ese primero si querés saber cómo llegamos hasta acá. Además, como nota aparte, este es un ejemplo muy básico de cómo empezar con terratest.
<br />

[Terratest](https://github.com/gruntwork-io/terratest) es una librería en Go que facilita escribir tests automatizados para tu infraestructura, soporta Terraform, Docker, Packer, SSH, AWS, GCP, Kubernetes, Helm, y mucho más. Como está escrita en Go, tenés acceso a todas las APIs existentes.
<br />

##### **El código**
Hay comentarios por todo el código para explicar cada parte, pero lo que quiero destacar acá es el patrón que usamos con el módulo `test-structure`. Este módulo nos permite dividir el test en secciones y saltarnos partes que no necesitemos o que no queramos correr. Tenemos 3 etapas: `cleanup`, `deploy` y `validate`. Esto te permite usar `SKIP_etapa`, por ejemplo, `SKIP_cleanup` cuando corras tus tests con `go test -timeout 90m .` (agregué algunos bits adicionales que suelo usar, como el timeout, que por defecto creo que es de 10 minutos y suele ser demasiado corto), para correr solo `validate` y `cleanup`. Esto es útil cuando estás desarrollando un módulo y querés testear sin tener que esperar a que todo se recree.
```elixir
package test

import (
    "crypto/tls"
    "fmt"
    "testing"
    "time"

    http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
    "github.com/gruntwork-io/terratest/modules/retry"
    "github.com/gruntwork-io/terratest/modules/terraform"
    test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

// Función principal, define etapas y ejecuta.
func TestTerraformAws(t *testing.T) {
    t.Parallel()

    // Elige una región aleatoria de AWS para testear. Esto ayuda a asegurar que el código funcione en todas las regiones.
    // awsRegion := aws.GetRandomStableRegion(t, nil, nil)
    awsRegion := "us-east-1"

    workingDir := "../terraform"

    // Al final del test, elimina la app web usando Terraform
    defer test_structure.RunTestStage(t, "cleanup", func() {
        destroyTerraform(t, workingDir)
    })

    // Despliega la app web usando Terraform
    test_structure.RunTestStage(t, "deploy", func() {
        deployTerraform(t, awsRegion, workingDir)
    })

    // Valida que el ASG esté desplegado y responda a solicitudes HTTP
    test_structure.RunTestStage(t, "validate", func() {
        validateAPIGateway(t, workingDir)
    })
}

// Valida que el API Gateway haya sido desplegado y esté funcionando
func validateAPIGateway(t *testing.T, workingDir string) {
    // Carga las opciones de Terraform guardadas por la etapa deploy_terraform anterior
    terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

    // Ejecuta `terraform output` para obtener el valor de una variable de salida
    url := terraform.Output(t, terraformOptions, "URL")

    // Puede tardar unos minutos en que el API GW y CloudFront terminen de levantarse, por lo que se reintenta varias veces
    //  maxRetries := 30
    timeBetweenRetries := 15 * time.Second

    // Configuración TLS en blanco para usar con el helper
    tlsConfig := tls.Config{}

    // Verifica que el API Gateway devuelva una respuesta correcta
    apigw := retry.DoInBackgroundUntilStopped(t, fmt.Sprintf("Check URL %s", url), timeBetweenRetries, func() {
        http_helper.HttpGetWithCustomValidation(t, fmt.Sprintf("%s/app/health", url), &tlsConfig, func(statusCode int, body string) bool {
            return statusCode == 200
        })
    })

    // Deja de verificar el API Gateway
    apigw.Done()
}

// Despliega los recursos usando Terraform
func deployTerraform(t *testing.T, awsRegion string, workingDir string) {
    terraformOptions := &terraform.Options{
        // Ruta al código de Terraform
        TerraformDir: workingDir,
    }

    // Guarda las opciones de Terraform para que las futuras etapas del test puedan usarlas
    test_structure.SaveTerraformOptions(t, workingDir, terraformOptions)

    // Esto ejecutará `terraform init` y `terraform apply` y fallará si hay errores
    terraform.InitAndApply(t, terraformOptions)
}

// Destruye los recursos usando Terraform
func destroyTerraform(t *testing.T, workingDir string) {
    // Carga las opciones de Terraform guardadas por la etapa deploy_terraform anterior
    terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

    terraform.Destroy(t, terraformOptions)
}
```
Algunas notas generales sobre cada etapa:

`deploy`: Esta etapa se encarga de ejecutar init y luego apply.

`validate`: Esta etapa se encarga de ejecutar una comprobación para verificar si nuestra API está arriba y si el código de retorno es `200`.

`cleanup`: Esta etapa se encarga de ejecutar destroy y limpiar todo.
<br />

##### **Dep**
Actualmente terratest usa `dep`, por lo que vas a necesitar este archivo `Gopkg.toml` y tener `dep` instalado para poder instalar las dependencias con `dep ensure -v`.
```elixir
[[constraint]]
  name = "github.com/gruntwork-io/terratest"
  version = "0.18.6"
```
<br />

##### **Dockerfile**
También podés usar este pequeño `Dockerfile` que hace todo por vos. En este ejemplo estamos usando el código del artículo previamente mencionado.
```elixir
FROM golang:alpine
MAINTAINER "kainlite <kainlite@gmail.com>"

ARG TERRAFORM_VERSION=0.12.8
ENV TERRAFORM_VERSION=$TERRAFORM_VERSION

RUN apk --no-cache add curl git unzip gcc g++ make ca-certificates && \
    curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh

RUN mkdir tmp && \
    curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o tmp/terraform.zip && \
    unzip tmp/terraform.zip -d /usr/local/bin && \
    rm -rf tmp/

ARG GOPROJECTPATH=/go/src/github.com/kainlite/serverless-cognito
COPY ./ $GOPROJECTPATH

WORKDIR $GOPROJECTPATH/test

RUN dep ensure -v

CMD ["go", "test", " -timeout", "90m", "."]
```
<br />

##### **Testeándolo manualmente**
Primero verificamos que la URL realmente funcione y que todo esté en su lugar.
```elixir
$ curl https://api.skynetng.pw/app/health
# OUTPUT:
# {"status":"healthy"}
```
<br />

Luego podemos testearlo usando nuestra etapa `validate`, utilizando terratest:
```elixir
$ SKIP_deploy=true SKIP_cleanup=true go test -timeout 90m .
# OUTPUT:
# ok      github.com/kainlite/test        1.117s
```
Esto funciona porque en el código de terraform tenemos una salida llamada `URL`, que es `https://api.skynetng.pw`, luego le agregamos `/app/health` al final y verificamos si devuelve un código `200`, de lo contrario, esperamos y reintentamos hasta que lo haga o se agote el tiempo.
<br />

### Notas finales
Y eso es todo por ahora. En la próxima parte, voy a cubrir cómo automatizar este despliegue usando una herramienta de CI/CD, para que puedas tener una infraestructura verdaderamente repetible, lo cual puede ser muy importante cuando trabajás en varios módulos, versiones y despliegues.
<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo pueda corregir.

<br />
