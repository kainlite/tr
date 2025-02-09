%{
  title: "Sending emails with AWS Lambda and SES from a HTML form",
  author: "Gabriel Garrido",
  description: "This article is part of the serverless series, in this article we will see how to create a serverless
  function in AWS Lambda to send an email coming from the HTML form in the site...",
  tags: ~w(golang serverless),
  published: true,
  image: "aws-lambda-ses.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![lambda](/images/aws-lambda-ses.webp){:class="mx-auto"}

##### **Serverless series**
Part I: [Serving static websites with s3 and cloudfront](/blog/serving_static_sites_with_s3_and_cloudfront), so refer to that one before starting this one if you want to know how did we get here.
<br />

Part II: [Sending emails with AWS Lambda and SES from a HTML form](/blog/sending_emails_with_lambda_and_ses), **You are here**.
<br />

##### **Introduction**
This article is part of the serverless series, in this article we will see how to create a serverless function in AWS Lambda to send an email coming from the HTML form in the site the source code can be [found here](https://github.com/kainlite/aws-serverless-go-ses-example), that is the go version but if you prefer node you can use [this one](https://github.com/kainlite/aws-serverless-nodejs-ses-example).
<br />

##### **Serverless framework**
**As usual I will be using the serverless framework to manage our functions, create the project**
```elixir
mkdir techsquad-functions && cd techsquad-functions && serverless create -t aws-go
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

After creating the project we can update the serverless manifest as follow:
```elixir
service: sendMail

frameworkVersion: ">=1.28.0 <2.0.0"

provider:
  name: aws
  runtime: go1.x
  region: us-east-1
  memorySize: 128
  versionFunctions: false
  stage: 'prod'

  iamRoleStatements:
    - Effect: "Allow"
      Action:
        - "ses:*"
        - "lambda:*"
      Resource:
        - "*"

package:
 exclude:
   - ./**
 include:
   - ./send_mail/send_mail

functions:
  send_mail:
    handler: send_mail/send_mail
    events:
      - http:
          path: sendMail
          method: post
```
The interesting parts here are the IAM permissions and the function send_mail, the rest is pretty much standard, we define a function and the event HTTP POST for the API Gateway, where our executable can be found and we also request permissions to send emails via SES.
<br />

**Deploy the function**
```elixir
make deploy
# OUTPUT:
# rm -rf ./send_mail/send_mail
# env GOOS=linux go build -ldflags="-s -w" -o send_mail/send_mail send_mail/main.go
# sls deploy --verbose
# Serverless: WARNING: Missing "tenant" and "app" properties in serverless.yml. Without these properties, you can not publish the service to the Serverless Platform.
# Serverless: Packaging service...
# Serverless: Excluding development dependencies...
# Serverless: Uploading CloudFormation file to S3...
# Serverless: Uploading artifacts...
# Serverless: Uploading service .zip file to S3 (7.31 MB)...
# Serverless: Validating template...
# Serverless: Updating Stack...
# Serverless: Checking Stack update progress...
# CloudFormation - UPDATE_IN_PROGRESS - AWS::CloudFormation::Stack - sendMail-prod
# CloudFormation - UPDATE_IN_PROGRESS - AWS::Lambda::Function - SendUnderscoremailLambdaFunction
# CloudFormation - UPDATE_COMPLETE - AWS::Lambda::Function - SendUnderscoremailLambdaFunction
# CloudFormation - CREATE_IN_PROGRESS - AWS::ApiGateway::Deployment - ApiGatewayDeployment1549246566486
# CloudFormation - CREATE_IN_PROGRESS - AWS::ApiGateway::Deployment - ApiGatewayDeployment1549246566486
# CloudFormation - CREATE_COMPLETE - AWS::ApiGateway::Deployment - ApiGatewayDeployment1549246566486
# CloudFormation - UPDATE_COMPLETE_CLEANUP_IN_PROGRESS - AWS::CloudFormation::Stack - sendMail-prod
# CloudFormation - DELETE_IN_PROGRESS - AWS::ApiGateway::Deployment - ApiGatewayDeployment1549246013644
# CloudFormation - DELETE_COMPLETE - AWS::ApiGateway::Deployment - ApiGatewayDeployment1549246013644
# CloudFormation - UPDATE_COMPLETE - AWS::CloudFormation::Stack - sendMail-prod
# Serverless: Stack update finished...
# Service Information
# service: sendMail
# stage: prod
# region: us-east-1
# stack: sendMail-prod
# api keys:
#   None
# endpoints:
#   POST - https://m8ebtlirjg.execute-api.us-east-1.amazonaws.com/prod/sendMail
# functions:
#   send_mail: sendMail-prod-send_mail
# layers:
#   None
#
# Stack Outputs
# ServiceEndpoint: https://m8ebtlirjg.execute-api.us-east-1.amazonaws.com/prod
# ServerlessDeploymentBucketName: sendmail-prod-serverlessdeploymentbucket-1vbmb6gwt8559
```
Everything looks right, so what's next? the source code.
<br />

##### **Lambda**
This is basically the full source code for this function, as you will see it's really simple:
```elixir
package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ses"
)

type Response events.APIGatewayProxyResponse

type RequestData struct {
	Email   string
	Message string
}

// This could be env vars
const (
	Sender    = "web@serverless.techsquad.rocks"
	Recipient = "kainlite@gmail.com"
	CharSet   = "UTF-8"
)

func Handler(ctx context.Context, request events.APIGatewayProxyRequest) (Response, error) {
	fmt.Printf("Request: %+v\n", request)

	fmt.Printf("Processing request data for request %s.\n", request.RequestContext.RequestID)
	fmt.Printf("Body size = %d.\n", len(request.Body))

	var requestData RequestData
	json.Unmarshal([]byte(request.Body), &requestData)

	fmt.Printf("RequestData: %+v", requestData)
	var result string
	if len(requestData.Email) > 0 && len(requestData.Message) > 0 {
		result, _ = send(requestData.Email, requestData.Message)
	}

	resp := Response{
		StatusCode:      200,
		IsBase64Encoded: false,
		Body:            result,
		Headers: map[string]string{
			"Content-Type":           "application/json",
			"X-MyCompany-Func-Reply": "send-mail-handler",
		},
	}

	return resp, nil
}

func send(Email string, Message string) (string, error) {
	// This could be an env var
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String("us-east-1")},
	)

	// Create an SES session.
	svc := ses.New(sess)

	// Assemble the email.
	input := &ses.SendEmailInput{
		Destination: &ses.Destination{
			CcAddresses: []*string{},
			ToAddresses: []*string{
				aws.String(Recipient),
			},
		},
		Message: &ses.Message{
			Body: &ses.Body{
				Html: &ses.Content{
					Charset: aws.String(CharSet),
					Data:    aws.String(Message),
				},
				Text: &ses.Content{
					Charset: aws.String(CharSet),
					Data:    aws.String(Message),
				},
			},
			Subject: &ses.Content{
				Charset: aws.String(CharSet),
				Data:    aws.String(Email),
			},
		},
		// We are using the same sender because it needs to be validated in SES.
		Source: aws.String(Sender),

		// Uncomment to use a configuration set
		//ConfigurationSetName: aws.String(ConfigurationSet),
	}

	// Attempt to send the email.
	result, err := svc.SendEmail(input)

	// Display error messages if they occur.
	if err != nil {
		if aerr, ok := err.(awserr.Error); ok {
			switch aerr.Code() {
			case ses.ErrCodeMessageRejected:
				fmt.Println(ses.ErrCodeMessageRejected, aerr.Error())
			case ses.ErrCodeMailFromDomainNotVerifiedException:
				fmt.Println(ses.ErrCodeMailFromDomainNotVerifiedException, aerr.Error())
			case ses.ErrCodeConfigurationSetDoesNotExistException:
				fmt.Println(ses.ErrCodeConfigurationSetDoesNotExistException, aerr.Error())
			default:
				fmt.Println(aerr.Error())
			}
		} else {
			// Print the error, cast err to awserr.Error to get the Code and
			// Message from an error.
			fmt.Println(err.Error())
		}

		return "there was an unexpected error", err
	}

	fmt.Println("Email Sent to address: " + Recipient)
	fmt.Println(result)
	return "sent!", err
}

func main() {
	lambda.Start(Handler)
}
```
The code is pretty much straight forward it only expects 2 parameters and it will send an email and return sent! if everything went well. You can debug and compile your function before uploading by issuing the command `make` (This is really useful), and if you use `make deploy` you will save lots of time by only deploying working files.
<br />

##### **SES**
For this to work you will need to verify/validate your domain in SES.
<br />

Go to `SES->Domains->Verify a New Domain`.
![image](/images/aws-ses-validate-domain.webp){:class="mx-auto"}
<br />

After putting your domain in, you will see something like this:
![image](/images/aws-ses-validation-and-dkim.webp){:class="mx-auto"}
<br />

As I don't have this domain in Route53 I don't have a button to add the records to it (which makes everything simpler and faster), but it's easy enough just create a few dns records and wait a few minutes until you get something like this:
![image](/images/aws-ses-validation-ok.webp){:class="mx-auto"}
<br />

**After that just test it**
```elixir
serverless invoke -f send_mail -d '{ "Email": "kainlite@gmail.com", "Message": "test" }'
# OUTPUT:
{
    "statusCode": 200,
    "headers": {
        "Content-Type": "application/json",
        "X-MyCompany-Func-Reply": "send-mail-handler"
    },
    "body": ""
}
```
After hitting enter the message popped up right away in my inbox :).
<br />

**Another option is to use [httpie](https://devhints.io/httpie)**
```elixir
echo '{ "email": "kainlite@gmail.com", "message": "test2" }' | http https://m8ebtlirjg.execute-api.us-east-1.amazonaws.com/prod/sendMail
# OUTPUT:
# HTTP/1.1 200 OK
# Access-Control-Allow-Origin: *
# Connection: keep-alive
# Content-Length: 32
# Content-Type: application/json
# Date: Sun, 03 Feb 2019 02:24:25 GMT
# Via: 1.1 3421ea0c15d4fdc0bcb792131861cb1f.cloudfront.net (CloudFront)
# X-Amz-Cf-Id: kGK4R9kTpcWjZap8aeyPu0vdiCtpQ4gnhCAtCeeA6OJufzaTDL__0w==
# X-Amzn-Trace-Id: Root=1-5c5650d9-7c3c8fcc5e303ca480739560;Sampled=0
# X-Cache: Miss from cloudfront
# x-amz-apigw-id: UgGR7FlWIAMF75Q=
# x-amzn-RequestId: d2f45b14-275a-11e9-a8f3-47d675eed13e
#
# sent!
```
<br />

**OR [curl](https://devhints.io/curl)**
```elixir
curl -i -X POST https://m8ebtlirjg.execute-api.us-east-1.amazonaws.com/prod/sendMail -d '{ "email": "kainlite@gmail.com", "message": "test3" }'
# OUTPUT:
# HTTP/2 200
# content-type: application/json
# content-length: 32
# date: Sun, 03 Feb 2019 02:28:04 GMT
# x-amzn-requestid: 55cc72d0-275b-11e9-99bd-91c3fab78a2f
# access-control-allow-origin: *
# x-amz-apigw-id: UgG0OEigoAMF-Yg=
# x-amzn-trace-id: Root=1-5c5651b4-fc5427b4798e14dc61fe161e;Sampled=0
# x-cache: Miss from cloudfront
# via: 1.1 2167e4d6cf81822217c1ea31b3d3ba7e.cloudfront.net (CloudFront)
# x-amz-cf-id: FttmBoeUaSwQ2AArTgVmI5br51zwVMfUrVpXPLGm1HacV4yS9IYMHA==
#
# sent!
```

And that's all for now, see you in the next article.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Enviando correos electronicos con AWS Lambda y SES desde un formulario HTML",
  author: "Gabriel Garrido",
  description: "Este articulo es parte de una serie, vamos a crear una funcion en AWS lambda para enviar un email desde
  el formulario del sitio estatico...",
  tags: ~w(golang serverless),
  published: true,
  image: "aws-lambda-ses.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![lambda](/images/aws-lambda-ses.webp){:class="mx-auto"}

##### **Serie sobre Serverless**
Parte I: [Sirviendo sitios web estáticos con S3 y CloudFront](/blog/serving_static_sites_with_s3_and_cloudfront), es recomendable revisar esa parte antes de empezar con esta para entender cómo llegamos hasta aquí.
<br />

Parte II: [Enviando emails con AWS Lambda y SES desde un formulario HTML](/blog/sending_emails_with_lambda_and_ses), **Estás aquí**.
<br />

##### **Introducción**
Este artículo forma parte de la serie sobre tecnologías serverless. Aquí veremos cómo crear una función serverless en AWS Lambda para enviar un email desde un formulario HTML en el sitio. El código fuente lo podés encontrar [acá](https://github.com/kainlite/aws-serverless-go-ses-example) para la versión en Go, pero si preferís Node.js, podés usar [esta versión](https://github.com/kainlite/aws-serverless-nodejs-ses-example).
<br />

##### **Framework Serverless**
**Como de costumbre, voy a usar el framework Serverless para gestionar nuestras funciones. Creamos el proyecto:**
```elixir
mkdir techsquad-functions && cd techsquad-functions && serverless create -t aws-go
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

Después de crear el proyecto, actualizamos el manifiesto de serverless de la siguiente manera:
```elixir
service: sendMail

frameworkVersion: ">=1.28.0 <2.0.0"

provider:
  name: aws
  runtime: go1.x
  region: us-east-1
  memorySize: 128
  versionFunctions: false
  stage: 'prod'

  iamRoleStatements:
    - Effect: "Allow"
      Action:
        - "ses:*"
        - "lambda:*"
      Resource:
        - "*"

package:
 exclude:
   - ./**
 include:
   - ./send_mail/send_mail

functions:
  send_mail:
    handler: send_mail/send_mail
    events:
      - http:
          path: sendMail
          method: post
```
Las partes interesantes aquí son los permisos de IAM y la función `send_mail`. El resto es bastante estándar: definimos una función y el evento HTTP POST para el API Gateway, donde se encuentra nuestro ejecutable, y también solicitamos permisos para enviar emails a través de SES.
<br />

**Desplegamos la función**
```elixir
make deploy
# OUTPUT:
# rm -rf ./send_mail/send_mail
# env GOOS=linux go build -ldflags="-s -w" -o send_mail/send_mail send_mail/main.go
# sls deploy --verbose
# ...
# Serverless: Stack update finished...
# Service Information
# service: sendMail
# stage: prod
# region: us-east-1
# stack: sendMail-prod
# api keys:
#   None
# endpoints:
#   POST - https://m8ebtlirjg.execute-api.us-east-1.amazonaws.com/prod/sendMail
# functions:
#   send_mail: sendMail-prod-send_mail
# layers:
#   None
#
# Stack Outputs
# ServiceEndpoint: https://m8ebtlirjg.execute-api.us-east-1.amazonaws.com/prod
# ServerlessDeploymentBucketName: sendmail-prod-serverlessdeploymentbucket-1vbmb6gwt8559
```
Todo se ve bien, ¿qué sigue? El código fuente.
<br />

##### **Lambda**
Este es básicamente el código fuente completo de esta función. Como verás, es bastante simple:
```elixir
package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ses"
)

type Response events.APIGatewayProxyResponse

type RequestData struct {
	Email   string
	Message string
}

// Este valor podría ser una variable de entorno
const (
	Sender    = "web@serverless.techsquad.rocks"
	Recipient = "kainlite@gmail.com"
	CharSet   = "UTF-8"
)

func Handler(ctx context.Context, request events.APIGatewayProxyRequest) (Response, error) {
	fmt.Printf("Request: %+v\n", request)

	fmt.Printf("Processing request data for request %s.\n", request.RequestContext.RequestID)
	fmt.Printf("Body size = %d.\n", len(request.Body))

	var requestData RequestData
	json.Unmarshal([]byte(request.Body), &requestData)

	fmt.Printf("RequestData: %+v", requestData)
	var result string
	if len(requestData.Email) > 0 && len(requestData.Message) > 0 {
		result, _ = send(requestData.Email, requestData.Message)
	}

	resp := Response{
		StatusCode:      200,
		IsBase64Encoded: false,
		Body:            result,
		Headers: map[string]string{
			"Content-Type":           "application/json",
			"X-MyCompany-Func-Reply": "send-mail-handler",
		},
	}

	return resp, nil
}

func send(Email string, Message string) (string, error) {
	// Esto podría ser una variable de entorno
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String("us-east-1")},
	)

	// Creamos una sesión en SES.
	svc := ses.New(sess)

	// Armamos el correo electrónico.
	input := &ses.SendEmailInput{
		Destination: &ses.Destination{
			CcAddresses: []*string{},
			ToAddresses: []*string{
				aws.String(Recipient),
			},
		},
		Message: &ses.Message{
			Body: &ses.Body{
				Html: &ses.Content{
					Charset: aws.String(CharSet),
					Data:    aws.String(Message),
				},
				Text: &ses.Content{
					Charset: aws.String(CharSet),
					Data:    aws.String(Message),
				},
			},
			Subject: &ses.Content{
				Charset: aws.String(CharSet),
				Data:    aws.String(Email),
			},
		},
		// Usamos el mismo remitente porque necesita estar validado en SES.
		Source: aws.String(Sender),

		// Descomentar para usar un conjunto de configuración
		//ConfigurationSetName: aws.String(ConfigurationSet),
	}

	// Intentamos enviar el correo electrónico.
	result, err := svc.SendEmail(input)

	// Mostramos los mensajes de error si los hay.
	if err != nil {
		if aerr, ok := err.(awserr.Error); ok {
			switch aerr.Code() {
			case ses.ErrCodeMessageRejected:
				fmt.Println(ses.ErrCodeMessageRejected, aerr.Error())
			case ses.ErrCodeMailFromDomainNotVerifiedException:
				fmt.Println(ses.ErrCodeMailFromDomainNotVerifiedException, aerr.Error())
			case ses.ErrCodeConfigurationSetDoesNotExistException:
				fmt.Println(ses.ErrCodeConfigurationSetDoesNotExistException, aerr.Error())
			default:
				fmt.Println(aerr.Error())
			}
		} else {
			fmt.Println(err.Error())
		}

		return "hubo un error inesperado", err
	}

	fmt.Println("Email enviado a la dirección: " + Recipient)
	fmt.Println(result)
	return "¡Enviado!", err
}

func main() {
	lambda.Start(Handler)
}
```
El código es bastante directo: solo espera 2 parámetros, enviará un email y devolverá "sent!" si todo salió bien. Podés depurar y compilar tu función antes de subirla ejecutando el comando `make` (muy útil), y si usás `make deploy`, ahorrarás tiempo al desplegar solo los archivos que funcionan.
<br />

##### **SES**
Para que esto funcione, vas a necesitar verificar/validar tu dominio en SES.
<br />

Andá a `SES->Domains->Verify a New Domain`.
![image](/images/aws-ses-validate-domain.webp){:class="mx-auto"}
<br />

Después de ingresar tu dominio, verás algo como esto:
![image](/images/aws-ses-validation-and-dkim.webp){:class="mx-auto"}
<br />

Como no tengo este dominio en Route53, no tengo el botón para agregar los registros (lo que lo haría más simple y rápido), pero es fácil, solo tenés que crear unos registros DNS y esperar unos minutos hasta que obtengas algo como esto:
![image](/images/aws-ses-validation-ok.webp){:class="mx-auto"}
<br />

**Después de eso, probalo**
```elixir
serverless invoke -f send_mail -d '{ "Email": "kainlite@gmail.com", "Message

": "test" }'
# OUTPUT:
{
    "statusCode": 200,
    "headers": {
        "Content-Type": "application/json",
        "X-MyCompany-Func-Reply": "send-mail-handler"
    },
    "body": ""
}
```
Después de presionar Enter, el mensaje apareció de inmediato en mi bandeja de entrada :).
<br />

**Otra opción es usar [httpie](https://devhints.io/httpie)**
```elixir
echo '{ "email": "kainlite@gmail.com", "message": "test2" }' | http https://m8ebtlirjg.execute-api.us-east-1.amazonaws.com/prod/sendMail
# OUTPUT:
# HTTP/1.1 200 OK
# ...
# sent!
```
<br />

**O [curl](https://devhints.io/curl)**
```elixir
curl -i -X POST https://m8ebtlirjg.execute-api.us-east-1.amazonaws.com/prod/sendMail -d '{ "email": "kainlite@gmail.com", "message": "test3" }'
# OUTPUT:
# HTTP/2 200
# ...
# sent!
```

Y eso es todo por ahora, nos vemos en el próximo artículo.
<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo corrija.

<br />
