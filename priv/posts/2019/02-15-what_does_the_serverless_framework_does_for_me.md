%{
  title: "What does the serverless framework does for me",
  author: "Gabriel Garrido",
  description: "The Serverless Framework helps you develop and deploy your AWS Lambda functions, along with the AWS infrastructure resources they require. It's a CLI that offers structure...",
  tags: ~w(serverless golang),
  published: true,
  image: "serverless.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![serveless](/images/serverless.png){:class="mx-auto"}

### **Introduction**
The [serverless framework](https://serverless.com/) is a nice tool to manage all your cloud functions. from their page:
<br />

> The Serverless Framework helps you develop and deploy your AWS Lambda functions, along with the AWS infrastructure resources they require. It's a CLI that offers structure, automation and best practices out-of-the-box, allowing you to focus on building sophisticated, event-driven, serverless architectures, comprised of Functions and Events.
<br />

### **Let's take the golang example for a spin**
So let's generate a project with the serverless framework and see everything that it does for us.
```elixir
mkdir foo && cd "$_" &&  serverless create -t aws-go
# OUTPUT:
# Serverless: Generating boilerplate...
#  _______                             __
# |   _   .-----.----.--.--.-----.----|  .-----.-----.-----.
# |   |___|  -__|   _|  |  |  -__|   _|  |  -__|__ --|__ --|
# |____   |_____|__|  \___/|_____|__| |__|_____|_____|_____|
# |   |   |             The Serverless Application Framework
# |       |                           serverless.com, v1.36.1
#  -------'
#
# Serverless: Successfully generated boilerplate for template: "aws-go"
# Serverless: NOTE: Please update the "service" property in serverless.yml with your service name
```
Got you a bit of command line fu right there with the "$_" (it means the first parameter of the previous command)
<br />

Okay all peachy but what just happened? We initialized a serverless framework project with the template aws-go (as you probably figured by now) the serverless framework can handle different languages and cloud providers, in this example we picked aws and go (there is another template for go called aws-go-dep which as the name indicates uses dep to manage dependencies), enough talking.
<br />

**Let's take a look at the files**
```elixir
tree .
# OUTPUT:
# ├── hello
# │   └── main.go
# ├── Makefile
# ├── serverless.yml
# └── world
#     └── main.go
#
# 2 directories, 4 files
```
We got a manifest `serverless.yml` a `Makefile` (which you can use to build your functions (to validate syntax errors for instance or run in test mode before pushing them to AWS, it will also be used to build them while deploying)
<br />

**The manifest file indicates a lot of things, I will add comments to the _code_**
```elixir
frameworkVersion: ">=1.28.0 <2.0.0"

provider:
  name: aws
  runtime: go1.x

# Which files needs to be included and which to be ignored
package:
 exclude:
   - ./**
 include:
   - ./bin/**

# The functions and the handlers (the actual function definition in the code), and events which then will be translated into API Gateway endpoints for your functions
functions:
  hello:
    handler: bin/hello
    events:
      - http:
          path: hello
          method: get
  world:
    handler: bin/world
    events:
      - http:
          path: world
          method: get
```
<br />

**Let's take a look at the hello function / file**
```elixir
package main

import (
    "bytes"
    "context"
    "encoding/json"

    "github.com/aws/aws-lambda-go/events"
    "github.com/aws/aws-lambda-go/lambda"
)

// Response is of type APIGatewayProxyResponse since we're leveraging the
// AWS Lambda Proxy Request functionality (default behavior)
//
// https://serverless.com/framework/docs/providers/aws/events/apigateway/#lambda-proxy-integration
type Response events.APIGatewayProxyResponse

// Handler is our lambda handler invoked by the `lambda.Start` function call
func Handler(ctx context.Context) (Response, error) {
    var buf bytes.Buffer

    body, err := json.Marshal(map[string]interface{}{
        "message": "Go Serverless v1.0! Your function executed successfully!",
    })
    if err != nil {
        return Response{StatusCode: 404}, err
    }
    json.HTMLEscape(&buf, body)

    resp := Response{
        StatusCode:      200,
        IsBase64Encoded: false,
        Body:            buf.String(),
        Headers: map[string]string{
            "Content-Type":           "application/json",
            "X-MyCompany-Func-Reply": "hello-handler",
        },
    }

    return resp, nil
}

func main() {
    lambda.Start(Handler)
}
```
This function only returns some text with some headers, every lambda function requires the lambda.Start with your function name as an entrypoint, in this case Handler, the context is usually used to pass data between calls or functions. The rest of the code is pretty straight forward go code, it builds a json object and returns it along with some headers.
<br />

##### **Let's deploy it**
```elixir
serverless deploy
# OUTPUT:
# Serverless: WARNING: Missing "tenant" and "app" properties in serverless.yml. Without these properties, you can not publish the service to the Serverless Platform.
# Serverless: Packaging service...
# Serverless: Excluding development dependencies...
# Serverless: Uploading CloudFormation file to S3...
# Serverless: Uploading artifacts...
# Serverless: Uploading service .zip file to S3 (10.88 MB)...
# Serverless: Validating template...
# Serverless: Updating Stack...
# Serverless: Checking Stack update progress...
# ............
# Serverless: Stack update finished...
# Service Information
# service: aws-go
# stage: dev
# region: us-east-1
# stack: aws-go-dev
# api keys:
#   None
# endpoints:
#   GET - https://cfr9zyw3r1.execute-api.us-east-1.amazonaws.com/dev/hello
#   GET - https://cfr9zyw3r1.execute-api.us-east-1.amazonaws.com/dev/world
# functions:
#   hello: aws-go-dev-hello
#   world: aws-go-dev-world
# layers:
#   None
```
So a lot happened here, the deploy function compiled our binary, packaged it, uploaded that package to s3, created a cloudformation stack and after everything was completed, returned the endpoints that were defined, as you can see the framework enabled us to create and deploy a function (two actually) really easily which totally simplifies the process of managing functions and events.
<br />

**And test it**
```elixir
curl -v https://cfr9zyw3r1.execute-api.us-east-1.amazonaws.com/dev/hello
# OUTPUT:
# *   Trying 99.84.27.2...
# * TCP_NODELAY set
# * Connected to cfr9zyw3r1.execute-api.us-east-1.amazonaws.com (99.84.27.2) port 443 (#0)
# * ALPN, offering h2
# * ALPN, offering http/1.1
# * successfully set certificate verify locations:
# *   CAfile: /etc/ssl/certs/ca-certificates.crt
#   CApath: none
# * TLSv1.3 (OUT), TLS handshake, Client hello (1):
# * TLSv1.3 (IN), TLS handshake, Server hello (2):
# * TLSv1.2 (IN), TLS handshake, Certificate (11):
# * TLSv1.2 (IN), TLS handshake, Server key exchange (12):
# * TLSv1.2 (IN), TLS handshake, Server finished (14):
# * TLSv1.2 (OUT), TLS handshake, Client key exchange (16):
# * TLSv1.2 (OUT), TLS change cipher, Change cipher spec (1):
# * TLSv1.2 (OUT), TLS handshake, Finished (20):
# * TLSv1.2 (IN), TLS handshake, Finished (20):
# * SSL connection using TLSv1.2 / ECDHE-RSA-AES128-GCM-SHA256
# * ALPN, server accepted to use h2
# * Server certificate:
# *  subject: CN=*.execute-api.us-east-1.amazonaws.com
# *  start date: Oct  9 00:00:00 2018 GMT
# *  expire date: Oct  9 12:00:00 2019 GMT
# *  subjectAltName: host "cfr9zyw3r1.execute-api.us-east-1.amazonaws.com" matched cert's "*.execute-api.us-east-1.amazonaws.com"
# *  issuer: C=US; O=Amazon; OU=Server CA 1B; CN=Amazon
# *  SSL certificate verify ok.
# * Using HTTP2, server supports multi-use
# * Connection state changed (HTTP/2 confirmed)
# * Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
# * Using Stream ID: 1 (easy handle 0x55944b9d7db0)
# > GET /dev/hello HTTP/2
# > Host: cfr9zyw3r1.execute-api.us-east-1.amazonaws.com
# > User-Agent: curl/7.63.0
# > Accept: */*
# >
# * Connection state changed (MAX_CONCURRENT_STREAMS == 128)!
# < HTTP/2 200
# < content-type: application/json
# < content-length: 70
# < date: Sat, 16 Feb 2019 04:32:04 GMT
# < x-amzn-requestid: cf4c6094-31a3-11e9-b61e-bb2138b2f390
# < x-amz-apigw-id: VLPKmHj4oAMFbbw=
# < x-mycompany-func-reply: hello-handler
# < x-amzn-trace-id: Root=1-5c679243-d4f945debb1a2b675c41675f;Sampled=0
# < x-cache: Miss from cloudfront
# < via: 1.1 655473215401ef909f449b92f216caa1.cloudfront.net (CloudFront)
# < x-amz-cf-id: LOHG0oG-WbGKpTnlGz-VDVqb9DxXQX-kgJJEUkchh1v_zLfUqNCpEQ==
# <
# * Connection #0 to host cfr9zyw3r1.execute-api.us-east-1.amazonaws.com left intact
# {"message":"Go Serverless v1.0! Your function executed successfully!"}%
```
As expected we can see the headers x-my-company-func-reply and the json object that it created for us.
<br />

### **Cleanup**
```elixir
serverless remove
# OUTPUT:
# Serverless: WARNING: Missing "tenant" and "app" properties in serverless.yml. Without these properties, you can not publish the service to the Serverless Platform.
# Serverless: Getting all objects in S3 bucket...
# Serverless: Removing objects in S3 bucket...
# Serverless: Removing Stack...
# Serverless: Checking Stack removal progress...
# ...............
# Serverless: Stack removal finished...
```
This will as you expect remove everything that was created with the deploy command.
<br />

In the next article we will explore how to do create and deploy a function like this one by hand.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Para que sirve el serverless framework",
  author: "Gabriel Garrido",
  description: "El Serverless Framework es imprescindible a la hora de crear, manejar y depurar tus funciones lambdas...",
  tags: ~w(serverless golang),
  published: true,
  image: "serverless.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### Traduccion en proceso

![serveless](/images/serverless.png){:class="mx-auto"}

### **Introducción**
El [framework serverless](https://serverless.com/) es una excelente herramienta para gestionar todas tus funciones en la nube. Desde su página:

> El Serverless Framework te ayuda a desarrollar y desplegar tus funciones de AWS Lambda, junto con los recursos de infraestructura de AWS que requieren. Es una CLI que ofrece estructura, automatización y mejores prácticas listas para usar, permitiéndote enfocarte en construir arquitecturas sofisticadas, impulsadas por eventos y sin servidor, compuestas por funciones y eventos.
<br />

### **Probemos el ejemplo en Go**
Vamos a generar un proyecto con el framework serverless y ver todo lo que hace por nosotros.
```elixir
mkdir foo && cd "$_" &&  serverless create -t aws-go
# OUTPUT:
# Serverless: Generating boilerplate...
#  _______                             __
# |   _   .-----.----.--.--.-----.----|  .-----.-----.-----.
# |   |___|  -__|   _|  |  |  -__|   _|  |  -__|__ --|__ --|
# |____   |_____|__|  \___/|_____|__| |__|_____|_____|_____|
# |   |   |             The Serverless Application Framework
# |       |                           serverless.com, v1.36.1
#  -------'
#
# Serverless: Successfully generated boilerplate for template: "aws-go"
# Serverless: NOTE: Please update the "service" property in serverless.yml with your service name
```
Te tiré un poco de magia de la línea de comandos con el `$_` (significa el primer parámetro del comando anterior).
<br />

¿Todo bien hasta acá, pero qué acaba de pasar? Inicializamos un proyecto del framework serverless con la plantilla `aws-go` (como ya habrás imaginado) el framework serverless puede manejar diferentes lenguajes y proveedores de nube. En este ejemplo elegimos AWS y Go (hay otra plantilla para Go llamada `aws-go-dep` que, como su nombre indica, usa `dep` para gestionar dependencias), pero suficiente charla.
<br />

### **Veamos los archivos**
```elixir
tree .
# OUTPUT:
# ├── hello
# │   └── main.go
# ├── Makefile
# ├── serverless.yml
# └── world
#     └── main.go
#
# 2 directories, 4 files
```
Tenemos un manifiesto `serverless.yml`, un `Makefile` (que podés usar para compilar tus funciones, validar errores de sintaxis o ejecutar en modo de prueba antes de subirlas a AWS, y que también será utilizado para compilarlas al desplegarlas).
<br />

### **El archivo del manifiesto indica muchas cosas, le agregaré comentarios al _código_**
```elixir
frameworkVersion: ">=1.28.0 <2.0.0"

provider:
  name: aws
  runtime: go1.x

# Archivos que deben incluirse y los que deben ser ignorados
package:
 exclude:
   - ./**
 include:
   - ./bin/**

# Las funciones y los manejadores (la definición real de la función en el código), y los eventos que luego se traducen en endpoints de API Gateway para tus funciones
functions:
  hello:
    handler: bin/hello
    events:
      - http:
          path: hello
          method: get
  world:
    handler: bin/world
    events:
      - http:
          path: world
          method: get
```
<br />

### **Veamos la función hello**
```elixir
package main

import (
    "bytes"
    "context"
    "encoding/json"

    "github.com/aws/aws-lambda-go/events"
    "github.com/aws/aws-lambda-go/lambda"
)

// Response es de tipo APIGatewayProxyResponse ya que estamos aprovechando la
// funcionalidad de AWS Lambda Proxy Request (comportamiento por defecto)
//
// https://serverless.com/framework/docs/providers/aws/events/apigateway/#lambda-proxy-integration
type Response events.APIGatewayProxyResponse

// Handler es nuestro manejador lambda invocado por la llamada a `lambda.Start`
func Handler(ctx context.Context) (Response, error) {
    var buf bytes.Buffer

    body, err := json.Marshal(map[string]interface{}{
        "message": "¡Go Serverless v1.0! Tu función se ejecutó correctamente.",
    })
    if err != nil {
        return Response{StatusCode: 404}, err
    }
    json.HTMLEscape(&buf, body)

    resp := Response{
        StatusCode:      200,
        IsBase64Encoded: false,
        Body:            buf.String(),
        Headers: map[string]string{
            "Content-Type":           "application/json",
            "X-MyCompany-Func-Reply": "hello-handler",
        },
    }

    return resp, nil
}

func main() {
    lambda.Start(Handler)
}
```
Esta función simplemente devuelve un texto con algunos encabezados. Cada función Lambda requiere de `lambda.Start` con el nombre de tu función como punto de entrada, en este caso `Handler`. El `context` generalmente se utiliza para pasar datos entre llamadas o funciones. El resto del código es bastante directo: construye un objeto JSON y lo devuelve junto con algunos encabezados.
<br />

##### **Vamos a desplegarlo**
```elixir
serverless deploy
# OUTPUT:
# Serverless: Packaging service...
# Serverless: Uploading CloudFormation file to S3...
# Serverless: Uploading artifacts...
# Serverless: Uploading service .zip file to S3 (10.88 MB)...
# Serverless: Validating template...
# Serverless: Updating Stack...
# Serverless: Checking Stack update progress...
# ............
# Serverless: Stack update finished...
# Service Information
# service: aws-go
# stage: dev
# region: us-east-1
# stack: aws-go-dev
# api keys:
#   None
# endpoints:
#   GET - https://cfr9zyw3r1.execute-api.us-east-1.amazonaws.com/dev/hello
#   GET - https://cfr9zyw3r1.execute-api.us-east-1.amazonaws.com/dev/world
# functions:
#   hello: aws-go-dev-hello
#   world: aws-go-dev-world
# layers:
#   None
```
Entonces, pasó mucho aquí: el comando `deploy` compiló nuestro binario, lo empaquetó, subió ese paquete a S3, creó un stack de CloudFormation, y después de que todo se completó, nos devolvió los endpoints que habíamos definido. Como ves, el framework nos permitió crear y desplegar una función (en realidad dos) muy fácilmente, simplificando totalmente el proceso de gestionar funciones y eventos.
<br />

##### **Y lo probamos**
```elixir
curl -v https://cfr9zyw3r1.execute-api.us-east-1.amazonaws.com/dev/hello
# OUTPUT:
# *   Trying 99.84.27.2...
# ...
# {"message":"¡Go Serverless v1.0! Tu función se ejecutó correctamente."}%
```
Como era de esperar, podemos ver los encabezados `x-my-company-func-reply` y el objeto JSON que creó para nosotros.
<br />

### **Limpiar todo**
```elixir
serverless remove
# OUTPUT:
# Serverless: Removing Stack...
# Serverless: Checking Stack removal progress...
# ...............
# Serverless: Stack removal finished...
```
Esto, como esperabas, eliminará todo lo que se creó con el comando `deploy`.
<br />

En el próximo artículo vamos a explorar cómo crear y desplegar una función como esta manualmente.
<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo corrija.

<br />
