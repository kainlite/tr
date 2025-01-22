%{
  title: "Create an AWS lambda function in Go",
  author: "Gabriel Garrido",
  description: "In this article we will create a lambda function and an API Gateway route like we did with the serverless framework but only using AWS tools, we will be using the same generated...",
  tags: ~w(golang serverless terraform),
  published: true,
  image: "lambda-helloworld-example.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In this article we will create a lambda function and an API Gateway route like we did with the serverless framework but only using AWS tools, we will be using the same generated code for our function from the last article [What does the serverless framework does for me](/blog/what_does_the_serverless_framework_does_for_me), so refer to that one before starting this one if you want to know how did we get here. Also as a side note this is a very basic example on how to get started with lambda without any additional tool.
<br />

##### **Let's see the code one more time**
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

With that code as a starting point, now we need to build, package, upload, and deploy our function:
<br />

**Build**
```elixir
GOOS=linux go build main.go
```
<br />

**Package**
```elixir
zip main.zip ./main
# OUTPUT:
#   adding: main (deflated 51%)
```
<br />

**Create the role**

Go to IAM > Roles > Create.
Then select Lambda, assign a name and a description and then get the ARN for this role. Note that with the serverless framework this is done automatically for us, so we don't need to create a new role for each
<br />

**Upload / Deploy**
```elixir
aws lambda create-function \
  --region us-east-1 \
  --function-name helloworld \
  --memory 128 \
  --role arn:aws:iam::894527626897:role/testing-aws-go \
  --runtime go1.x \
  --zip-file fileb://main.zip \
  --handler main

# OUTPUT:
# {
#     "FunctionName": "helloworld",
#     "FunctionArn": "arn:aws:lambda:us-east-1:894527626897:function:helloworld",
#     "Runtime": "go1.x",
#     "Role": "arn:aws:iam::894527626897:role/testing-aws-go",
#     "Handler": "main",
#     "CodeSize": 4346283,
#     "Description": "",
#     "Timeout": 3,
#     "MemorySize": 128,
#     "LastModified": "2019-02-16T15:44:10.610+0000",
#     "CodeSha256": "02/PQBeQuCC8JS1TLjyU38oiUwiyQSmKJXjya25XpFA=",
#     "Version": "$LATEST",
#     "TracingConfig": {
#         "Mode": "PassThrough"
#     },
#     "RevisionId": "7c9030e5-4a26-4f7e-968d-3a4f65dfde21"
# }
```
Note that your function-name must match the name of your Lambda handler name (Handler). Note that this role might be insecure in some scenarios if you grant too much permissions, so try to restrict it as much as possible as with any role and policy.
<br />

**Test the function**
```elixir
aws lambda invoke --function-name helloworld --log-type Tail /dev/stdout
# OUTPUT:
# {"statusCode":200,"headers":{"Content-Type":"application/json","X-MyCompany-Func-Reply":"hello-handler"},"body":"{\"message\":\"Go Serverless v1.0! Your function executed successfully!\"}"}{
#     "StatusCode": 200,
#     "LogResult": "U1RBUlQgUmVxdWVzdElkOiBmZTRmMWE4Zi1kYzAyLTQyYWQtYjBlYy0wMjA5YjY4MDY1YWQgVmVyc2lvbjogJExBVEVTVApFTkQgUmVxdWVzdElkOiBmZTRmMWE4Zi1kYzAyLTQyYWQtYjBlYy0wMjA5YjY4MDY1YWQKUkVQT1JUIFJlcXVlc3RJZDogZmU0ZjFhOGYtZGMwMi00MmFkLWIwZWMtMDIwOWI2ODA2NWFkCUR1cmF0aW9uOiAxMy4xOSBtcwlCaWxsZWQgRHVyYXRpb246IDEwMCBtcyAJTWVtb3J5IFNpemU6IDEyOCBNQglNYXggTWVtb3J5IFVzZWQ6IDQ1IE1CCQo=",
#     "ExecutedVersion": "$LATEST"
# }
```
Everything looks about right, so what's next? We will eventually need to communicate with this code from an external source, so let's see how we can do that with the API Gateway. Also the log is encoded in base64, so if you want to see what the log result was do the following.
<br />

**Check the logs**
```elixir
echo "U1RBUlQgUmVxdWVzdElkOiBmZTRmMWE4Zi1kYzAyLTQyYWQtYjBlYy0wMjA5YjY4MDY1YWQgVmVyc2lvbjogJExBVEVTVApFTkQgUmVxdWVzdElkOiBmZTRmMWE4Zi1kYzAyLTQyYWQtYjBlYy0wMjA5YjY4MDY1YWQKUkVQT1JUIFJlcXVlc3RJZDogZmU0ZjFhOGYtZGMwMi00MmFkLWIwZWMtMDIwOWI2ODA2NWFkCUR1cmF0aW9uOiAxMy4xOSBtcwlCaWxsZWQgRHVyYXRpb246IDEwMCBtcyAJTWVtb3J5IFNpemU6IDEyOCBNQglNYXggTWVtb3J5IFVzZWQ6IDQ1IE1CCQo=" | base64 -d
# OUTPUT:
# START RequestId: fe4f1a8f-dc02-42ad-b0ec-0209b68065ad Version: $LATEST
# END RequestId: fe4f1a8f-dc02-42ad-b0ec-0209b68065ad
# REPORT RequestId: fe4f1a8f-dc02-42ad-b0ec-0209b68065ad  Duration: 13.19 ms      Billed Duration: 100 ms         Memory Size: 128 MB     Max Memory Used: 45 MB
```
You should also be able to see this same output in CloudWatch.
<br />

##### **API Gateway**

To make this step simpler I decided to use the AWS Console instead of the CLI it will also cut down the size of this article substantially.
<br />

**Now we need to create the API Gateway endpoint**

Note that you only have to go to Lambda->Functions->helloworld->Add triggers->API Gateway. And then complete as shown in the image, when you save this new trigger you will get the resource that then can be used to test the API Gateway integration.
![img](/images/lambda-helloworld-example.webp){:class="mx-auto"}
<br />

The endpoint will show as follows (Click on API Gateway):
    ![image](/images/lambda-helloworld-example-endpoint.webp){:class="mx-auto"}
<br />

**Test the API**
```elixir
curl -v https://r8efasfb26.execute-api.us-east-1.amazonaws.com/default/helloworld
# OUTPUT:
# *   Trying 54.236.123.239...
# * TCP_NODELAY set
# * Connected to r8efasfb26.execute-api.us-east-1.amazonaws.com (54.236.123.239) port 443 (#0)
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
# *  start date: Sep 20 00:00:00 2018 GMT
# *  expire date: Oct 20 12:00:00 2019 GMT
# *  subjectAltName: host "r8efasfb26.execute-api.us-east-1.amazonaws.com" matched cert's "*.execute-api.us-east-1.amazonaws.com"
# *  issuer: C=US; O=Amazon; OU=Server CA 1B; CN=Amazon
# *  SSL certificate verify ok.
# * Using HTTP2, server supports multi-use
# * Connection state changed (HTTP/2 confirmed)
# * Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
# * Using Stream ID: 1 (easy handle 0x56394c766db0)
# > GET /default/helloworld HTTP/2
# > Host: r8efasfb26.execute-api.us-east-1.amazonaws.com
# > User-Agent: curl/7.63.0
# > Accept: */*
# >
# * Connection state changed (MAX_CONCURRENT_STREAMS == 128)!
# < HTTP/2 200
# < date: Sat, 16 Feb 2019 17:17:58 GMT
# < content-type: application/json
# < content-length: 70
# < x-amzn-requestid: ce5c5863-320e-11e9-9e76-875e7540974c
# < x-amz-apigw-id: VM_XAGhoIAMFqoQ=
# < x-mycompany-func-reply: hello-handler
# < x-amzn-trace-id: Root=1-5c6845c6-920cfc7da3cfd94f3e644647;Sampled=0
# <
# * Connection #0 to host r8efasfb26.execute-api.us-east-1.amazonaws.com left intact
# {"message":"Go Serverless v1.0! Your function executed successfully!"}
```

If you ask me that was a lot of effort to handle without automation, maybe AWS SAM or the serverless framework can make things easier and let you focus on your application rather than the boilerplate required for it to run.
<br />

### Clean up
Always remember to clean up and delete everything that you created (to avoid surprises and save money), in this article I will leave that as an exercise for the reader :)
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Creando a funcion en AWS lambda con Go",
  author: "Gabriel Garrido",
  description: "En este articulo creamos una funcion lambda y un API Gateway como hicimos con el serverless framework pero solo vamos a usar las herramientas de AWS...",
  tags: ~w(golang serverless terraform),
  published: true,
  image: "lambda-helloworld-example.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### **Introducción**
En este artículo vamos a crear una función Lambda y una ruta en API Gateway, como hicimos con el framework serverless, pero utilizando únicamente las herramientas de AWS. Usaremos el mismo código generado para nuestra función del artículo anterior [¿Qué hace el framework serverless por mí?](/blog/what_does_the_serverless_framework_does_for_me). Si querés saber cómo llegamos hasta acá, te recomiendo que lo leas primero. Este es un ejemplo básico de cómo empezar con Lambda sin ninguna herramienta adicional.
<br />

### **Veamos el código nuevamente**
```elixir
package main

import (
    "bytes"
    "context"
    "encoding/json"

    "github.com/aws/aws-lambda-go/events"
    "github.com/aws/aws-lambda-go/lambda"
)

// Response es del tipo APIGatewayProxyResponse ya que estamos aprovechando
// la funcionalidad de AWS Lambda Proxy Request (comportamiento por defecto)
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

Con este código como punto de partida, ahora necesitamos compilar, empaquetar, subir y desplegar nuestra función:
<br />

### **Compilar**
```elixir
GOOS=linux go build main.go
```
<br />

### **Empaquetar**
```elixir
zip main.zip ./main
# OUTPUT:
#   adding: main (deflated 51%)
```
<br />

### **Crear el rol**

Ve a IAM > Roles > Crear.\
Luego selecciona Lambda, asigna un nombre y una descripción, y obtené el ARN de este rol. Con el framework serverless esto se hace automáticamente, así que no es necesario crear un nuevo rol cada vez.
<br />

### **Subir / Desplegar**
```elixir
aws lambda create-function \
  --region us-east-1 \
  --function-name helloworld \
  --memory 128 \
  --role arn:aws:iam::894527626897:role/testing-aws-go \
  --runtime go1.x \
  --zip-file fileb://main.zip \
  --handler main

# OUTPUT:
# {
#     "FunctionName": "helloworld",
#     "FunctionArn": "arn:aws:lambda:us-east-1:894527626897:function:helloworld",
#     "Runtime": "go1.x",
#     "Role": "arn:aws:iam::894527626897:role/testing-aws-go",
#     "Handler": "main",
#     "CodeSize": 4346283,
#     "Description": "",
#     "Timeout": 3,
#     "MemorySize": 128,
#     "LastModified": "2019-02-16T15:44:10.610+0000",
#     "CodeSha256": "02/PQBeQuCC8JS1TLjyU38oiUwiyQSmKJXjya25XpFA=",
#     "Version": "$LATEST",
#     "TracingConfig": {
#         "Mode": "PassThrough"
#     },
#     "RevisionId": "7c9030e5-4a26-4f7e-968d-3a4f65dfde21"
# }
```
Ten en cuenta que el nombre de tu función (`function-name`) debe coincidir con el nombre de tu manejador Lambda (`Handler`). Este rol podría ser inseguro si le das demasiados permisos, así que tratá de restringirlo lo más posible, como con cualquier rol y política.
<br />

### **Probar la función**
```elixir
aws lambda invoke --function-name helloworld --log-type Tail /dev/stdout
# OUTPUT:
# {"statusCode":200,"headers":{"Content-Type":"application/json","X-MyCompany-Func-Reply":"hello-handler"},"body":"{\"message\":\"Go Serverless v1.0! Your function executed successfully!\"}"}
```
Todo parece estar bien. Lo siguiente es comunicarnos con este código desde una fuente externa, así que vamos a ver cómo hacerlo con API Gateway. Además, los logs están codificados en base64, así que si querés ver el resultado del log, hacé lo siguiente.
<br />

### **Ver los logs**
```elixir
echo "U1RBUlQgUmVxdWVzdElkOiBmZTRmMWE4Zi1kYzAyLTQyYWQtYjBlYy0wMjA5YjY4MDY1YWQgVmVyc2lvbjogJExBVEVTVApFTkQgUmVxdWVzdElkOiBmZTRmMWE4Zi1kYzAyLTQyYWQtYjBlYy0wMjA5YjY4MDY1YWQKUkVQT1JUIFJlcXVlc3RJZDogZmU0ZjFhOGYtZGMwMi00MmFkLWIwZWMtMDIwOWI2ODA2NWFkCUR1cmF0aW9uOiAxMy4xOSBtcwlCaWxsZWQgRHVyYXRpb246IDEwMCBtcyAJTWVtb3J5IFNpemU6IDEyOCBNQglNYXggTWVtb3J5IFVzZWQ6IDQ1IE1CCQo=" | base64 -d
# OUTPUT:
# START RequestId: fe4f1a8f-dc02-42ad-b0ec-0209b68065ad Version: $LATEST
# END RequestId: fe4f1a8f-dc02-42ad-b0ec-0209b68065ad
# REPORT RequestId: fe4f1a8f-dc02-42ad-b0ec-0209b68065ad  Duration: 13.19 ms      Billed Duration: 100 ms         Memory Size: 128 MB     Max Memory Used: 45 MB
```
También deberías poder ver este mismo output en CloudWatch.
<br />

### **API Gateway**

Para simplificar este paso, decidí usar la consola de AWS en lugar de la CLI. También acorta bastante el tamaño de este artículo.
<br />

### **Crear el endpoint en API Gateway**

Solo tenés que ir a Lambda -> Funciones -> helloworld -> Add triggers -> API Gateway. Completá los campos como se muestra en la imagen, y cuando guardes este nuevo disparador, obtendrás el recurso que luego se podrá usar para probar la integración de API Gateway.
![img](/images/lambda-helloworld-example.webp){:class="mx-auto"}
<br />

El endpoint se verá así (hacé clic en API Gateway):
![image](/images/lambda-helloworld-example-endpoint.webp){:class="mx-auto"}
<br />

### **Probar el API**
```elixir
curl -v https://r8efasfb26.execute-api.us-east-1.amazonaws.com/default/helloworld
# OUTPUT:
# *   Trying 54.236.123.239...
# * TCP_NODELAY set
# * Connected to r8efasfb26.execute-api.us-east-1.amazonaws.com (54.236.123.239) port 443 (#0)
# ...
# {"message":"¡Go Serverless v1.0! Tu función se ejecutó correctamente!"}
```

Si me lo preguntás, fue mucho esfuerzo manejar esto sin automatización. Tal vez AWS SAM o el framework serverless puedan hacer las cosas más fáciles y permitirte enfocarte en tu aplicación en lugar de en el boilerplate necesario para que funcione.
<br />

### Limpiar
Siempre recordá limpiar y eliminar todo lo que creaste (para evitar sorpresas y ahorrar dinero). En este artículo, dejaré eso como un ejercicio para vos :)
<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo corrija.

<br />
