%{
  title: "Serverless authentication with Cognito",
  author: "Gabriel Garrido",
  description: "In this article we will see how to use Terraform and Go to create a serverless API using API Gateway, Lambda, and Go, and we will also handle authentication with AWS Cognito...",
  tags: ~w(golang serverless aws lambda),
  published: true,
  image: "serverless-cognito.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![serverless](/images/serverless-cognito.png){:class="mx-auto"}

##### **Introduction**
In this article we will see how to use Terraform and Go to create a serverless API using API Gateway, Lambda, and Go, and we will also handle authentication with AWS Cognito, the repo with the files can be found [here](https://github.com/kainlite/serverless-cognito).
<br />

##### **Terraform**
In this example I used terraform 0.12, and I kind of liked the new changes, it feels more like coding and a more natural way to describe things, however I think there are more bugs than usual in this version, but I really like the new output for the plan, apply, etc, getting back to the article since there is a lot of code I will gradually update the post with more notes and content or maybe another post explaining another section, but the initial version will only show the cognito part and the code to make it work and how to test it.
<br />

##### Cognito
```elixir
resource "aws_cognito_user_pool" "pool" {
  name = "api-skynetng-pw"

  username_attributes = ["email"]

  # This setting is what actually makes the confirmation code to be sent
  auto_verified_attributes = ["email"]

  email_configuration {
    source_arn = var.email_address_arn
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name = "client"

  user_pool_id = aws_cognito_user_pool.pool.id

  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH", "USER_PASSWORD_AUTH"]
}

data "aws_cognito_user_pools" "this" {
  name = var.cognito_user_pool_name

  depends_on = ["aws_cognito_user_pool.pool"]
}

```
As we can see it's really simple to have a cognito user pool working, the most important part here is the `auto_verified_attributes` because that is what makes cognito to actually send an email or an sms with the confirmation code, the rest is self-describing, it creates a pool and a client, since what we need to be able to interact with out pool is the client that part is of considerable importance even that we have most things with default values. As you might have noticed we defined two `explicit_auth_flows` and that is to be able to interact with this user pool using user and password.
<br />

##### ACM
Next let's see how we manage the certificate creation using ACM.
```elixir
#####################
# SSL custom domain #
#####################

data "aws_acm_certificate" "api" {
  domain     = var.domain_name
  depends_on = [aws_acm_certificate.api]
}

resource "aws_acm_certificate" "api" {
  domain_name       = var.domain_name
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

resource "aws_api_gateway_domain_name" "api" {
  domain_name     = var.domain_name
  certificate_arn = aws_acm_certificate.api.arn
}

```
Here basically we create the certificate using `aws_acm_certificate` and validate it automatically using the `DNS` method and the resource `aws_acm_certificate_validation`, the other resources in the file are just there because they are kind of associated but not necessarily need to be there.
<br />

##### Route53
Here we just create an alias record for the API Gateway and the validation record.
```elixir
data "aws_route53_zone" "zone" {
  name = substr(var.domain_name, 4, -1)
}

resource "aws_route53_record" "api" {
  name    = var.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.zone.zone_id

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.api.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.api.cloudfront_zone_id
  }
}

resource "aws_route53_record" "cert_validation" {
  name    = aws_acm_certificate.api.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.api.domain_validation_options.0.resource_record_type
  zone_id = data.aws_route53_zone.zone.id
  records = [aws_acm_certificate.api.domain_validation_options.0.resource_record_value]
  ttl     = 60
}

```
<br />

##### API Gateway
While this file might seem relatively simple, the API Gateway has many features and can get really complex really fast, basically what we are doing here is creating an API with a resource that accepts all method types and proxy that as it is to our lambda function.
```elixir
# https://www.terraform.io/docs/providers/aws/guides/serverless-with-aws-lambda-and-api-gateway.html

resource "aws_api_gateway_rest_api" "lambda-api" {
  name = replace(var.domain_name, ".", "-")
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.lambda-api.id
  parent_id   = aws_api_gateway_rest_api.lambda-api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.lambda-api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_base_path_mapping" "api" {
  api_id      = aws_api_gateway_rest_api.lambda-api.id
  stage_name  = aws_api_gateway_deployment.lambda-api.stage_name
  domain_name = aws_api_gateway_domain_name.api.domain_name
}

resource "aws_api_gateway_integration" "lambda-api" {
  rest_api_id = aws_api_gateway_rest_api.lambda-api.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_api_gateway_deployment" "lambda-api" {
  depends_on = [aws_api_gateway_integration.lambda-api]

  rest_api_id = aws_api_gateway_rest_api.lambda-api.id
  stage_name  = "prod"
}

resource "aws_lambda_permission" "lambda_permission" {
  action        = "lambda:InvokeFunction"
  function_name = replace(var.domain_name, ".", "-")
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lambda-api.execution_arn}/*/*/*"

  depends_on = [aws_lambda_function.api]
}

```
<br />

##### Lambda
This file has the lambda function definition, the policy and the roles needed, basically the policy is to be able to log to CloudWatch and to inspect with X-Ray, then the log group to store the logs will set the retention period by default 7 days.
```elixir
resource "aws_lambda_function" "api" {
  filename      = "../src/main.zip"
  function_name = replace(var.domain_name, ".", "-")
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "main"

  source_code_hash = filebase64sha256("../src/main.zip")
  runtime          = "go1.x"

  environment {
    variables = local.environment_variables
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "${replace(var.domain_name, ".", "-")}-lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

data "aws_iam_policy_document" "policy_for_lambda" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]

    resources = [aws_cloudwatch_log_group.lambda-api.arn]
  }
}

resource "aws_iam_role_policy" "policy_for_lambda" {
  name   = "${replace(var.domain_name, ".", "-")}-lambda"
  role   = aws_iam_role.iam_for_lambda.id
  policy = data.aws_iam_policy_document.policy_for_lambda.json
}

resource "aws_cloudwatch_log_group" "lambda-api" {
  name              = "/aws/lambda/${replace(var.domain_name, ".", "-")}"
  retention_in_days = var.log_retention_in_days
}

```
<br />

##### Variables and locals
First the variables file with the default values
```elixir
variable "profile_name" {
  default = "default"
}

variable "region" {
  default = "us-east-1"
}

variable "email_address_arn" {
  default = "arn:aws:ses:us-east-1:894527626897:identity/kainlite@gmail.com"
}

variable "cognito_user_pool_name" {
  default = "api-skynetng-pw"
}

variable "domain_name" {
  default = "api.skynetng.pw"
}

variable "log_retention_in_days" {
  default = 7
}

variable "function_name" {
  description = "Function name"
  default     = "mylambda"
}

variable "stage_name" {
  description = "Api version number"
  default     = "v1"
}

variable "environment_variables" {
  description = "Map with environment variables for the function"

  default = {
    myenvvar = "test"
  }
}

```
<br />

And last the locals file, in this small snippet we are just making a map with a computed value and the values that can come from a variable which can be quite useful in many scenarios where you don't know all the information in advance or something is dynamically assigned:
```elixir
locals {
  computed_environment_variables = {
    "COGNITO_CLIENT_ID" = aws_cognito_user_pool_client.client.id
  }
  environment_variables = merge(local.computed_environment_variables, var.environment_variables)
}

```
<br />

##### Deployment scripts
There is a small bash script to make it easier to run the deployment, AKA as compiling the code, zipping it, and running terraform to update our function or whatever we changed.
```elixir
#!/bin/bash
set -u
source config.sh

cleanup() {
    echo 'Cleaning up'
    rm -f lambda.zip
}

create_zip() {
    echo 'Zipping lambda'
    cd src
    go get ./...
    go build ./...
    mv api.skynetng.pw main
    cd ..
    zip --junk-paths -r src/main.zip src/main
}

cleanup
create_zip
cd terraform
terraform apply -auto-approve \
    -var "region=us-east-1" \
    -var "profile_name=${profile_name}" \
    -var "domain_name=${domain_name}"
cd ..

```
<br />

##### **Go**
The good thing is that everything is code, but we don't have to manage any server, we just consume services from AWS completely from code, isn't that amazing?, I apologize for the length of the file, but you will notice that it's very repetitive, in most functions we load the AWS configuration, we make a request and return a response, we're also using Gin as a router, which is pretty straight-forward and easy to use, we have only one authenticated path (`/user/profile`), and we also have another unauthenticated path which is a health check (`/app/health`), the other two paths (`/user` and `/user/validate`) are exclusively for the user creation process with cognito.
```elixir
package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws/external"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"

	"github.com/aws/aws-sdk-go/aws"
	ginadapter "github.com/awslabs/aws-lambda-go-api-proxy/gin"
	"github.com/gin-gonic/gin"
)

var ginLambda *ginadapter.GinLambda

type User struct {
	AccessToken string `json:"access_token"`
}

func getProfile(c *gin.Context) {
	user := User{}
	err := c.BindJSON(&user)

	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cfg, err := external.LoadDefaultAWSConfig()
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cognito := cognitoidentityprovider.New(cfg)
	req := cognito.GetUserRequest(&cognitoidentityprovider.GetUserInput{
		AccessToken: aws.String(user.AccessToken),
	})

	resp, err := req.Send(c)
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	c.JSON(http.StatusAccepted, gin.H{
		"user": resp,
	})
}

type UserPassword struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func createUser(c *gin.Context) {
	user := UserPassword{}
	err := c.BindJSON(&user)

	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cfg, err := external.LoadDefaultAWSConfig()
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cognito := cognitoidentityprovider.New(cfg)
	req := cognito.SignUpRequest(&cognitoidentityprovider.SignUpInput{
		ClientId:       aws.String(os.Getenv("COGNITO_CLIENT_ID")),
		Username:       aws.String(user.Username),
		Password:       aws.String(user.Password),
		ValidationData: []cognitoidentityprovider.AttributeType{cognitoidentityprovider.AttributeType{Name: aws.String("email")}},
	})

	resp, err := req.Send(c)
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	c.JSON(http.StatusAccepted, gin.H{
		"user": resp,
	})
}

type UserValidation struct {
	Username string `json:"username"`
	Code     string `json:"code"`
}

func validateUser(c *gin.Context) {
	user := UserValidation{}
	err := c.BindJSON(&user)

	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cfg, err := external.LoadDefaultAWSConfig()
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cognito := cognitoidentityprovider.New(cfg)
	req := cognito.ConfirmSignUpRequest(&cognitoidentityprovider.ConfirmSignUpInput{
		ClientId:         aws.String(os.Getenv("COGNITO_CLIENT_ID")),
		Username:         aws.String(user.Username),
		ConfirmationCode: aws.String(user.Code),
	})

	resp, err := req.Send(c)
	if err != nil {
		log.Println(resp, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	c.JSON(http.StatusAccepted, gin.H{
		"status": "Confirmed",
	})
}

func init() {
	log.Printf("Gin cold start")
	r := gin.Default()
	r.POST("/user/validate", validateUser)
	r.POST("/user", createUser)
	r.POST("/user/profile", getProfile)

	r.GET("/app/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status": "healthy",
		})
	})

	ginLambda = ginadapter.New(r)
}

func Handler(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	return ginLambda.ProxyWithContext(ctx, req)
}

func main() {
	lambda.Start(Handler)
}

```
All logs go to CloudWatch and you can also use X-Ray to diagnose issues.
<br />

##### **Testing it**
So we're going to hit the API to create, validate, and query the empty profile of the user from the terminal using curl.
```elixir
# Create the account
$ curl https://api.skynetng.pw/user -X POST -d '{ "username": "kainlite+test@gmail.com", "password": "Testing123@"  }'
OUTPUT:
{
  "user": {
    "CodeDeliveryDetails": {
      "AttributeName": "email",
      "DeliveryMedium": "EMAIL",
      "Destination": "k***+***t@g***.com"
    },
    "UserConfirmed": false,
    "UserSub": "317e9839-e9ee-4969-855d-1c13ac79662c"
  }
}

# Validate the account, this would be normally done from a webapp or mobile app, but since we're not doing the frontend we need a way to test it.
$ curl https://api.skynetng.pw/user/validate -X POST -d '{ "username": "kainlite+test@gmail.com", "code": "680641"  }'
OUTPUT:
{ "status": "Confirmed" }

# Once the account is confirmed, we craft this file with the login details to get an access token (Authentication).
$ cat auth.json
OUTPUT:
{
    "AuthParameters": {
        "USERNAME": "kainlite+test@gmail.com",
        "PASSWORD": "Testing123@"
    },
        "AuthFlow": "USER_PASSWORD_AUTH",
        "ClientId": "4o2gst5o56074cc4af90vpeujk"
}

# Then we issue this curl call to actually get the token.
$ curl -X POST --data @auth.json -H 'X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth' -H 'Content-Type: application/x-amz-json-1.1' https://cognito-idp.us-east-1.amazonaws.com/ | jq
OUTPUT:
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  4037  100  3883  100   154   3476    137  0:00:01  0:00:01 --:--:--  3614
{
  "AuthenticationResult": {
    "AccessToken": "eyJraWQiOiJJMVN1Q0VteVlVXC9OSkFVY2lLOWRNeE1VSUJzTHZDYm9KejBaaGozZG5SND0iLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiI5ZDMzNDk1MC1mOGIzLTRlZjMtOTVlYy0wNWYzODQxN2UxNTEiLCJldmVudF9pZCI6Ijc2MDVjMTI3LTcwMmItNDI3OS04ZWU5LWQyOGUxY2ZiZjVmYSIsInRva2VuX3VzZSI6ImFjY2VzcyIsInNjb3BlIjoiYXdzLmNvZ25pdG8uc2lnbmluLnVzZXIuYWRtaW4iLCJhdXRoX3RpbWUiOjE1Njc0NjI0NDAsImlzcyI6Imh0dHBzOlwvXC9jb2duaXRvLWlkcC51cy1lYXN0LTEuYW1hem9uYXdzLmNvbVwvdXMtZWFzdC0xX3IwdWdoOUR1cSIsImV4cCI6MTU2NzQ2NjA0MCwiaWF0IjoxNTY3NDYyNDQwLCJqdGkiOiJlMzE0MmJkMC02ZjQ0LTQyNGMtOTExNy01ZTg3NWZhOTg1MDQiLCJjbGllbnRfaWQiOiI0bzJnc3Q1bzU2MDc0Y2M0YWY5MHZwZXVqayIsInVzZXJuYW1lIjoiOWQzMzQ5NTAtZjhiMy00ZWYzLTk1ZWMtMDVmMzg0MTdlMTUxIn0.TjuOR6naiWKYQvuS3gNM8PJXVlL3wqg6TwNGAHqnJ5HzSRx5sQX2bbLUtY1qB7vwACyqQEdYObgGyc8CpV65yNZ9NeNjnCE4wfJMLpSRNXdTQeDpCqNlLVTC8wN33A_ksq1zqTllXRbSODk6rv3trBMs_phJqpDRdxeWR7fsgOwh8J6BcRxg-LhUYRh_IF7EQpFkbOlDi5MAQiz-8-koHf84r75fs28yIT15LVQWcwYXNoS5mUFYdHxuUKsuagdO5VremsT-Y1NQEcwUwe8JL-UwGtVv18IXHk_qrE8uovJiJ7zDKeuEah6ycI1jgTaGBBVLqCBXgf2Nb5XRJ77BUA",
    "ExpiresIn": 3600,
    "IdToken": "eyJraWQiOiJKbzNWczRLS0FmcXNtOGFlVVNPSzJcLzdcL2JweGUwNkV2Vk9nRnlcL3Njb2VZPSIsImFsZyI6IlJTMjU2In0.eyJzdWIiOiI5ZDMzNDk1MC1mOGIzLTRlZjMtOTVlYy0wNWYzODQxN2UxNTEiLCJhdWQiOiI0bzJnc3Q1bzU2MDc0Y2M0YWY5MHZwZXVqayIsImVtYWlsX3ZlcmlmaWVkIjpmYWxzZSwiZXZlbnRfaWQiOiI3NjA1YzEyNy03MDJiLTQyNzktOGVlOS1kMjhlMWNmYmY1ZmEiLCJ0b2tlbl91c2UiOiJpZCIsImF1dGhfdGltZSI6MTU2NzQ2MjQ0MCwiaXNzIjoiaHR0cHM6XC9cL2NvZ25pdG8taWRwLnVzLWVhc3QtMS5hbWF6b25hd3MuY29tXC91cy1lYXN0LTFfcjB1Z2g5RHVxIiwiY29nbml0bzp1c2VybmFtZSI6IjlkMzM0OTUwLWY4YjMtNGVmMy05NWVjLTA1ZjM4NDE3ZTE1MSIsImV4cCI6MTU2NzQ2NjA0MCwiaWF0IjoxNTY3NDYyNDQwLCJlbWFpbCI6ImthaW5saXRlQGdtYWlsLmNvbSJ9.RuwjyG_y4AgBkAVD29scmW8zF3nANGjrDt33v4wOIGAxH0nWbIDc9lMDCS57mOb02LwglyqlsJXGt-BCgjXdKvumjbehAu_a9E3KZlAjA7l4anoSHoIPN_gU5DmiBhL67OTRr4bZxQjTup6abloWt0sqiUx_gA5okH3VNi1oooCIVQ1GfJ53mxhtdUB1LiHpJ7aIwDYDqLFrrNj8f2I4r0oomAkFSEt6DjpEKXI33tCUj9AI-n9JH2wcgsvVAPGIjryfWDrgb8sEujhoZq-AjOHb3ri2B8aWnx0-DQTAVKVnxwBQZH8YAK0r2oLNxhIqZDCUEXaMpzYcDjjG83kA3Q",
    "RefreshToken": "eyJjdHkiOiJKV1QiLCJlbmMiOiJBMjU2R0NNIiwiYWxnIjoiUlNBLU9BRVAifQ.OupuJR3hZUT2bWQTA0n2YqIxN6Lqphxv_yZXjAaJSIKub66xuiF1axUFC9h9SEroWedqR0id_vmfbfH_71_EyS0HZjUlyXSde3WXefY9Yc2YNK1ChCR4rh33r3neuQg0hKx63JTIMVf9yWeFl1Mx4KEsA4eTyvN6GE8o54lGNX6fQX7KovuG5rH0iZQVb2oPFglokAk2uCB4M6p2SbUtWLO5oZYOPWwax62JHb2b5EEwDW4aAJEoWjVetbjLnQHLedYv9Ur68XeSKRtrslZAdCyFjD6Rc1oxuuBEi590CJgj3tlpJV7rSE_185NB90Sa6uU728sksub9sxnANUDY3A.jXKGBg26M4uE3dWm.qO7BO568Aa-4U55mvR-7_1CMCk7ZN7clBAVfKkFyDz6LXwkki9V2ohvm4f_joN88htr4p7AFV7Rik23-vTtTgPXVI9vBUIt37EXyjaMKPJX3B15XnYnC1-YhxjGma6IiyC1oUuiCmUIm9L1c7Jxm8ZmCBFNjc-ARXJTvWAHB3eYHk6U3WHOSB9X_MT2K9Dmrl1-q1vjP4taUKlj60jy91uwk0Ti8tVHp7ETpe4DyEcv9EuoFtEznrJDYcnYpVLyaq9Fkb43F7L3kMq_Jx4IAbWhCaeC35JJa56zAZ1eZ_mGuC5T86xChNqDElhod6m_pz33j5OyPL8rXh8ldERbB7cBB1QgePbPlr1GOvC2T8mE1Rb_gvzNU05Nm1VaeXnClV39GFBpGpEfKY6uvnWiZZICTE3LZRDIhI8Cn-9LwkAUMzqQRKYcPGZswZ68Ma_H40xB3A8pyw_RMF_QvZurUumg-RDeFS2CSnW12zhtMQhr_60Jt9vRQCbWVjBcTh40ZBO5TE8IHsulPq5uJaBEhY2_lpIga4HHjI6cqZ7J3PkRjTc6ZNzAaJiGY0cdRi2pXTeiLqm5_04BUzVbfBQytURbYoaYLxv_wXT-gR4JTLewxJyouO4l955GXK2IjXdZxyFmaXaKrKs7UuiRrkc65_Xzbn8Gj9u0beN661W1CsdymYNht5RfFsJMh85IhsxmzR7XM_2kDVQIjo5EZq5XV0SKQmVjFPYuUIQKcdkx0UsQzQisuuZarcWoDSNq-rxWJF2JbzjtkPyoaSaPxlwC8TL4HXQvT5HQ9S6VeSp0PTQj2BV4NtqzEpskJ9Nql3xrn488WpZD7NBeWkkA_bBKKiYDALoXjmEd6yvmehVtP1VBoqszHOMbikLa1FakJIGpbXqtaH3ZvLdrVCFTKCoEtMob_c4YKoiRgoqyAXew-H_znrxHagVLnJRqfYXLVFkjxGm23PKvSRSRsUXNIlBwUrh8hwL4rsyZLPTE-8aAiG-6VmVE3Xg-JvMtftC-MC5W5PAjLACf_hJP97FrCtg65dUY4-GCGnGMmbe-yLx7z0YaKzuGxccwyT08E-zfmVCeBrkeA-4niUt3xcTJkOOKnPycMWG437cFPxp7sEjw0f4CnZfwX7YHO2rB78UODCZIIqbXgmSQgt86HxNLDqcKY0gLQCIVd3VQSgyRTjOefE3BUGqUHmJ5fKt207tYq_YN6R6rKUvD6NFORmqXIY3AnfU3W1c0FF5ta56T_MW9XSxmcX5AzmT1ZUuzsuNA7gImdu9cpYabynLZgXKSIvcfix__vO84X8bWzr06McPMtRWvLmOr8X5RF9u3X7Q.WVY_SyQ6pF_ae5YP1ov2tg",
    "TokenType": "Bearer"
  },
  "ChallengeParameters": {}
}

# And to validate that we can authenticate users with our code we finally fetch the profile
$ curl https://api.skynetng.pw/user/profile -X POST -d '{ "access_token": "very_long_access_token_from_the_previous_command" }'
OUTPUT:
{
  "profile": {
    "MFAOptions": null,
    "PreferredMfaSetting": null,
    "UserAttributes": [
      {
        "Name": "sub",
        "Value": "317e9839-e9ee-4969-855d-1c13ac79662c"
      },
      {
        "Name": "email_verified",
        "Value": "false"
      },
      {
        "Name": "email",
        "Value": "kainlite@gmail.com"
      }
    ],
    "UserMFASettingList": null,
    "Username": "317e9839-e9ee-4969-855d-1c13ac79662c"
  },
  "user": {
    "access_token": "eyJraWQiOiJJMVN1Q0VteVlVXC9OSkFVY2lLOWRNeE1VSUJzTHZDYm9KejBaaGozZG5SND0iLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiI5ZDMzNDk1MC1mOGIzLTRlZjMtOTVlYy0wNWYzODQxN2UxNTEiLCJldmVudF9pZCI6Ijc2MDVjMTI3LTcwMmItNDI3OS04ZWU5LWQyOGUxY2ZiZjVmYSIsInRva2VuX3VzZSI6ImFjY2VzcyIsInNjb3BlIjoiYXdzLmNvZ25pdG8uc2lnbmluLnVzZXIuYWRtaW4iLCJhdXRoX3RpbWUiOjE1Njc0NjI0NDAsImlzcyI6Imh0dHBzOlwvXC9jb2duaXRvLWlkcC51cy1lYXN0LTEuYW1hem9uYXdzLmNvbVwvdXMtZWFzdC0xX3IwdWdoOUR1cSIsImV4cCI6MTU2NzQ2NjA0MCwiaWF0IjoxNTY3NDYyNDQwLCJqdGkiOiJlMzE0MmJkMC02ZjQ0LTQyNGMtOTExNy01ZTg3NWZhOTg1MDQiLCJjbGllbnRfaWQiOiI0bzJnc3Q1bzU2MDc0Y2M0YWY5MHZwZXVqayIsInVzZXJuYW1lIjoiOWQzMzQ5NTAtZjhiMy00ZWYzLTk1ZWMtMDVmMzg0MTdlMTUxIn0.TjuOR6naiWKYQvuS3gNM8PJXVlL3wqg6TwNGAHqnJ5HzSRx5sQX2bbLUtY1qB7vwACyqQEdYObgGyc8CpV65yNZ9NeNjnCE4wfJMLpSRNXdTQeDpCqNlLVTC8wN33A_ksq1zqTllXRbSODk6rv3trBMs_phJqpDRdxeWR7fsgOwh8J6BcRxg-LhUYRh_IF7EQpFkbOlDi5MAQiz-8-koHf84r75fs28yIT15LVQWcwYXNoS5mUFYdHxuUKsuagdO5VremsT-Y1NQEcwUwe8JL-UwGtVv18IXHk_qrE8uovJiJ7zDKeuEah6ycI1jgTaGBBVLqCBXgf2Nb5XRJ77BUA"
  }
}

```
I have added most info in as comments in the snippet, note that I also used my test domain `skynetng.pw` with the subdomain `api` for all tests.
<br />

##### **Closing notes**
This post was heavily inspired by [this post](https://a.l3x.in/2018/07/25/lambda-api-custom-domain-tutorial.html) from Alexander, kudos to him for the great work!, this post expands on that and adds the certificate with ACM, it also handles a basic AWS Cognito configuration and the necessary go code to make it work, there are other ways to accomplish the same, but what I like about this approach is that you can have some endpoints or paths without authentication and you can use authentication, etc on-demand. This article is a bit different but I will try to re-shape it in the following weeks, and also cover more of the content displayed here, let me know if you have any comments or suggestions!

In some near future I will build upon this article in another article adding a few cool things, for example to allow an user to upload an image to an S3 bucket and fetch that with a friendly name using Cloudfront (In a secure manner, and only able to upload/update his/her profile picture, while being able to fetch anyone profile pic), the idea is to have a fully functional small API using AWS services and serverless facilities with common tasks that you can find in any functional website.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Serverless authentication with Cognito",
  author: "Gabriel Garrido",
  description: "In this article we will see how to use Terraform and Go to create a serverless API using API Gateway, Lambda, and Go, and we will also handle authentication with AWS Cognito...",
  tags: ~w(golang serverless aws lambda),
  published: true,
  image: "serverless-cognito.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### Traduccion en proceso

![serverless](/images/serverless-cognito.png){:class="mx-auto"}

##### **Introduction**
In this article we will see how to use Terraform and Go to create a serverless API using API Gateway, Lambda, and Go, and we will also handle authentication with AWS Cognito, the repo with the files can be found [here](https://github.com/kainlite/serverless-cognito).
<br />

##### **Terraform**
In this example I used terraform 0.12, and I kind of liked the new changes, it feels more like coding and a more natural way to describe things, however I think there are more bugs than usual in this version, but I really like the new output for the plan, apply, etc, getting back to the article since there is a lot of code I will gradually update the post with more notes and content or maybe another post explaining another section, but the initial version will only show the cognito part and the code to make it work and how to test it.
<br />

##### Cognito
```elixir
resource "aws_cognito_user_pool" "pool" {
  name = "api-skynetng-pw"

  username_attributes = ["email"]

  # This setting is what actually makes the confirmation code to be sent
  auto_verified_attributes = ["email"]

  email_configuration {
    source_arn = var.email_address_arn
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name = "client"

  user_pool_id = aws_cognito_user_pool.pool.id

  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH", "USER_PASSWORD_AUTH"]
}

data "aws_cognito_user_pools" "this" {
  name = var.cognito_user_pool_name

  depends_on = ["aws_cognito_user_pool.pool"]
}

```
As we can see it's really simple to have a cognito user pool working, the most important part here is the `auto_verified_attributes` because that is what makes cognito to actually send an email or an sms with the confirmation code, the rest is self-describing, it creates a pool and a client, since what we need to be able to interact with out pool is the client that part is of considerable importance even that we have most things with default values. As you might have noticed we defined two `explicit_auth_flows` and that is to be able to interact with this user pool using user and password.
<br />

##### ACM
Next let's see how we manage the certificate creation using ACM.
```elixir
#####################
# SSL custom domain #
#####################

data "aws_acm_certificate" "api" {
  domain     = var.domain_name
  depends_on = [aws_acm_certificate.api]
}

resource "aws_acm_certificate" "api" {
  domain_name       = var.domain_name
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

resource "aws_api_gateway_domain_name" "api" {
  domain_name     = var.domain_name
  certificate_arn = aws_acm_certificate.api.arn
}

```
Here basically we create the certificate using `aws_acm_certificate` and validate it automatically using the `DNS` method and the resource `aws_acm_certificate_validation`, the other resources in the file are just there because they are kind of associated but not necessarily need to be there.
<br />

##### Route53
Here we just create an alias record for the API Gateway and the validation record.
```elixir
data "aws_route53_zone" "zone" {
  name = substr(var.domain_name, 4, -1)
}

resource "aws_route53_record" "api" {
  name    = var.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.zone.zone_id

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.api.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.api.cloudfront_zone_id
  }
}

resource "aws_route53_record" "cert_validation" {
  name    = aws_acm_certificate.api.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.api.domain_validation_options.0.resource_record_type
  zone_id = data.aws_route53_zone.zone.id
  records = [aws_acm_certificate.api.domain_validation_options.0.resource_record_value]
  ttl     = 60
}

```
<br />

##### API Gateway
While this file might seem relatively simple, the API Gateway has many features and can get really complex really fast, basically what we are doing here is creating an API with a resource that accepts all method types and proxy that as it is to our lambda function.
```elixir
# https://www.terraform.io/docs/providers/aws/guides/serverless-with-aws-lambda-and-api-gateway.html

resource "aws_api_gateway_rest_api" "lambda-api" {
  name = replace(var.domain_name, ".", "-")
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.lambda-api.id
  parent_id   = aws_api_gateway_rest_api.lambda-api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.lambda-api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_base_path_mapping" "api" {
  api_id      = aws_api_gateway_rest_api.lambda-api.id
  stage_name  = aws_api_gateway_deployment.lambda-api.stage_name
  domain_name = aws_api_gateway_domain_name.api.domain_name
}

resource "aws_api_gateway_integration" "lambda-api" {
  rest_api_id = aws_api_gateway_rest_api.lambda-api.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_api_gateway_deployment" "lambda-api" {
  depends_on = [aws_api_gateway_integration.lambda-api]

  rest_api_id = aws_api_gateway_rest_api.lambda-api.id
  stage_name  = "prod"
}

resource "aws_lambda_permission" "lambda_permission" {
  action        = "lambda:InvokeFunction"
  function_name = replace(var.domain_name, ".", "-")
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lambda-api.execution_arn}/*/*/*"

  depends_on = [aws_lambda_function.api]
}

```
<br />

##### Lambda
This file has the lambda function definition, the policy and the roles needed, basically the policy is to be able to log to CloudWatch and to inspect with X-Ray, then the log group to store the logs will set the retention period by default 7 days.
```elixir
resource "aws_lambda_function" "api" {
  filename      = "../src/main.zip"
  function_name = replace(var.domain_name, ".", "-")
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "main"

  source_code_hash = filebase64sha256("../src/main.zip")
  runtime          = "go1.x"

  environment {
    variables = local.environment_variables
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "${replace(var.domain_name, ".", "-")}-lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

data "aws_iam_policy_document" "policy_for_lambda" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]

    resources = [aws_cloudwatch_log_group.lambda-api.arn]
  }
}

resource "aws_iam_role_policy" "policy_for_lambda" {
  name   = "${replace(var.domain_name, ".", "-")}-lambda"
  role   = aws_iam_role.iam_for_lambda.id
  policy = data.aws_iam_policy_document.policy_for_lambda.json
}

resource "aws_cloudwatch_log_group" "lambda-api" {
  name              = "/aws/lambda/${replace(var.domain_name, ".", "-")}"
  retention_in_days = var.log_retention_in_days
}

```
<br />

##### Variables and locals
First the variables file with the default values
```elixir
variable "profile_name" {
  default = "default"
}

variable "region" {
  default = "us-east-1"
}

variable "email_address_arn" {
  default = "arn:aws:ses:us-east-1:894527626897:identity/kainlite@gmail.com"
}

variable "cognito_user_pool_name" {
  default = "api-skynetng-pw"
}

variable "domain_name" {
  default = "api.skynetng.pw"
}

variable "log_retention_in_days" {
  default = 7
}

variable "function_name" {
  description = "Function name"
  default     = "mylambda"
}

variable "stage_name" {
  description = "Api version number"
  default     = "v1"
}

variable "environment_variables" {
  description = "Map with environment variables for the function"

  default = {
    myenvvar = "test"
  }
}

```
<br />

And last the locals file, in this small snippet we are just making a map with a computed value and the values that can come from a variable which can be quite useful in many scenarios where you don't know all the information in advance or something is dynamically assigned:
```elixir
locals {
  computed_environment_variables = {
    "COGNITO_CLIENT_ID" = aws_cognito_user_pool_client.client.id
  }
  environment_variables = merge(local.computed_environment_variables, var.environment_variables)
}

```
<br />

##### Deployment scripts
There is a small bash script to make it easier to run the deployment, AKA as compiling the code, zipping it, and running terraform to update our function or whatever we changed.
```elixir
#!/bin/bash
set -u
source config.sh

cleanup() {
    echo 'Cleaning up'
    rm -f lambda.zip
}

create_zip() {
    echo 'Zipping lambda'
    cd src
    go get ./...
    go build ./...
    mv api.skynetng.pw main
    cd ..
    zip --junk-paths -r src/main.zip src/main
}

cleanup
create_zip
cd terraform
terraform apply -auto-approve \
    -var "region=us-east-1" \
    -var "profile_name=${profile_name}" \
    -var "domain_name=${domain_name}"
cd ..

```
<br />

##### **Go**
The good thing is that everything is code, but we don't have to manage any server, we just consume services from AWS completely from code, isn't that amazing?, I apologize for the length of the file, but you will notice that it's very repetitive, in most functions we load the AWS configuration, we make a request and return a response, we're also using Gin as a router, which is pretty straight-forward and easy to use, we have only one authenticated path (`/user/profile`), and we also have another unauthenticated path which is a health check (`/app/health`), the other two paths (`/user` and `/user/validate`) are exclusively for the user creation process with cognito.
```elixir
package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws/external"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"

	"github.com/aws/aws-sdk-go/aws"
	ginadapter "github.com/awslabs/aws-lambda-go-api-proxy/gin"
	"github.com/gin-gonic/gin"
)

var ginLambda *ginadapter.GinLambda

type User struct {
	AccessToken string `json:"access_token"`
}

func getProfile(c *gin.Context) {
	user := User{}
	err := c.BindJSON(&user)

	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cfg, err := external.LoadDefaultAWSConfig()
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cognito := cognitoidentityprovider.New(cfg)
	req := cognito.GetUserRequest(&cognitoidentityprovider.GetUserInput{
		AccessToken: aws.String(user.AccessToken),
	})

	resp, err := req.Send(c)
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	c.JSON(http.StatusAccepted, gin.H{
		"user": resp,
	})
}

type UserPassword struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func createUser(c *gin.Context) {
	user := UserPassword{}
	err := c.BindJSON(&user)

	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cfg, err := external.LoadDefaultAWSConfig()
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cognito := cognitoidentityprovider.New(cfg)
	req := cognito.SignUpRequest(&cognitoidentityprovider.SignUpInput{
		ClientId:       aws.String(os.Getenv("COGNITO_CLIENT_ID")),
		Username:       aws.String(user.Username),
		Password:       aws.String(user.Password),
		ValidationData: []cognitoidentityprovider.AttributeType{cognitoidentityprovider.AttributeType{Name: aws.String("email")}},
	})

	resp, err := req.Send(c)
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	c.JSON(http.StatusAccepted, gin.H{
		"user": resp,
	})
}

type UserValidation struct {
	Username string `json:"username"`
	Code     string `json:"code"`
}

func validateUser(c *gin.Context) {
	user := UserValidation{}
	err := c.BindJSON(&user)

	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cfg, err := external.LoadDefaultAWSConfig()
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	cognito := cognitoidentityprovider.New(cfg)
	req := cognito.ConfirmSignUpRequest(&cognitoidentityprovider.ConfirmSignUpInput{
		ClientId:         aws.String(os.Getenv("COGNITO_CLIENT_ID")),
		Username:         aws.String(user.Username),
		ConfirmationCode: aws.String(user.Code),
	})

	resp, err := req.Send(c)
	if err != nil {
		log.Println(resp, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"err": err.Error(),
		})
		return
	}

	c.JSON(http.StatusAccepted, gin.H{
		"status": "Confirmed",
	})
}

func init() {
	log.Printf("Gin cold start")
	r := gin.Default()
	r.POST("/user/validate", validateUser)
	r.POST("/user", createUser)
	r.POST("/user/profile", getProfile)

	r.GET("/app/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status": "healthy",
		})
	})

	ginLambda = ginadapter.New(r)
}

func Handler(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	return ginLambda.ProxyWithContext(ctx, req)
}

func main() {
	lambda.Start(Handler)
}

```
All logs go to CloudWatch and you can also use X-Ray to diagnose issues.
<br />

##### **Testing it**
So we're going to hit the API to create, validate, and query the empty profile of the user from the terminal using curl.
```elixir
# Create the account
$ curl https://api.skynetng.pw/user -X POST -d '{ "username": "kainlite+test@gmail.com", "password": "Testing123@"  }'
OUTPUT:
{
  "user": {
    "CodeDeliveryDetails": {
      "AttributeName": "email",
      "DeliveryMedium": "EMAIL",
      "Destination": "k***+***t@g***.com"
    },
    "UserConfirmed": false,
    "UserSub": "317e9839-e9ee-4969-855d-1c13ac79662c"
  }
}

# Validate the account, this would be normally done from a webapp or mobile app, but since we're not doing the frontend we need a way to test it.
$ curl https://api.skynetng.pw/user/validate -X POST -d '{ "username": "kainlite+test@gmail.com", "code": "680641"  }'
OUTPUT:
{ "status": "Confirmed" }

# Once the account is confirmed, we craft this file with the login details to get an access token (Authentication).
$ cat auth.json
OUTPUT:
{
    "AuthParameters": {
        "USERNAME": "kainlite+test@gmail.com",
        "PASSWORD": "Testing123@"
    },
        "AuthFlow": "USER_PASSWORD_AUTH",
        "ClientId": "4o2gst5o56074cc4af90vpeujk"
}

# Then we issue this curl call to actually get the token.
$ curl -X POST --data @auth.json -H 'X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth' -H 'Content-Type: application/x-amz-json-1.1' https://cognito-idp.us-east-1.amazonaws.com/ | jq
OUTPUT:
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  4037  100  3883  100   154   3476    137  0:00:01  0:00:01 --:--:--  3614
{
  "AuthenticationResult": {
    "AccessToken": "eyJraWQiOiJJMVN1Q0VteVlVXC9OSkFVY2lLOWRNeE1VSUJzTHZDYm9KejBaaGozZG5SND0iLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiI5ZDMzNDk1MC1mOGIzLTRlZjMtOTVlYy0wNWYzODQxN2UxNTEiLCJldmVudF9pZCI6Ijc2MDVjMTI3LTcwMmItNDI3OS04ZWU5LWQyOGUxY2ZiZjVmYSIsInRva2VuX3VzZSI6ImFjY2VzcyIsInNjb3BlIjoiYXdzLmNvZ25pdG8uc2lnbmluLnVzZXIuYWRtaW4iLCJhdXRoX3RpbWUiOjE1Njc0NjI0NDAsImlzcyI6Imh0dHBzOlwvXC9jb2duaXRvLWlkcC51cy1lYXN0LTEuYW1hem9uYXdzLmNvbVwvdXMtZWFzdC0xX3IwdWdoOUR1cSIsImV4cCI6MTU2NzQ2NjA0MCwiaWF0IjoxNTY3NDYyNDQwLCJqdGkiOiJlMzE0MmJkMC02ZjQ0LTQyNGMtOTExNy01ZTg3NWZhOTg1MDQiLCJjbGllbnRfaWQiOiI0bzJnc3Q1bzU2MDc0Y2M0YWY5MHZwZXVqayIsInVzZXJuYW1lIjoiOWQzMzQ5NTAtZjhiMy00ZWYzLTk1ZWMtMDVmMzg0MTdlMTUxIn0.TjuOR6naiWKYQvuS3gNM8PJXVlL3wqg6TwNGAHqnJ5HzSRx5sQX2bbLUtY1qB7vwACyqQEdYObgGyc8CpV65yNZ9NeNjnCE4wfJMLpSRNXdTQeDpCqNlLVTC8wN33A_ksq1zqTllXRbSODk6rv3trBMs_phJqpDRdxeWR7fsgOwh8J6BcRxg-LhUYRh_IF7EQpFkbOlDi5MAQiz-8-koHf84r75fs28yIT15LVQWcwYXNoS5mUFYdHxuUKsuagdO5VremsT-Y1NQEcwUwe8JL-UwGtVv18IXHk_qrE8uovJiJ7zDKeuEah6ycI1jgTaGBBVLqCBXgf2Nb5XRJ77BUA",
    "ExpiresIn": 3600,
    "IdToken": "eyJraWQiOiJKbzNWczRLS0FmcXNtOGFlVVNPSzJcLzdcL2JweGUwNkV2Vk9nRnlcL3Njb2VZPSIsImFsZyI6IlJTMjU2In0.eyJzdWIiOiI5ZDMzNDk1MC1mOGIzLTRlZjMtOTVlYy0wNWYzODQxN2UxNTEiLCJhdWQiOiI0bzJnc3Q1bzU2MDc0Y2M0YWY5MHZwZXVqayIsImVtYWlsX3ZlcmlmaWVkIjpmYWxzZSwiZXZlbnRfaWQiOiI3NjA1YzEyNy03MDJiLTQyNzktOGVlOS1kMjhlMWNmYmY1ZmEiLCJ0b2tlbl91c2UiOiJpZCIsImF1dGhfdGltZSI6MTU2NzQ2MjQ0MCwiaXNzIjoiaHR0cHM6XC9cL2NvZ25pdG8taWRwLnVzLWVhc3QtMS5hbWF6b25hd3MuY29tXC91cy1lYXN0LTFfcjB1Z2g5RHVxIiwiY29nbml0bzp1c2VybmFtZSI6IjlkMzM0OTUwLWY4YjMtNGVmMy05NWVjLTA1ZjM4NDE3ZTE1MSIsImV4cCI6MTU2NzQ2NjA0MCwiaWF0IjoxNTY3NDYyNDQwLCJlbWFpbCI6ImthaW5saXRlQGdtYWlsLmNvbSJ9.RuwjyG_y4AgBkAVD29scmW8zF3nANGjrDt33v4wOIGAxH0nWbIDc9lMDCS57mOb02LwglyqlsJXGt-BCgjXdKvumjbehAu_a9E3KZlAjA7l4anoSHoIPN_gU5DmiBhL67OTRr4bZxQjTup6abloWt0sqiUx_gA5okH3VNi1oooCIVQ1GfJ53mxhtdUB1LiHpJ7aIwDYDqLFrrNj8f2I4r0oomAkFSEt6DjpEKXI33tCUj9AI-n9JH2wcgsvVAPGIjryfWDrgb8sEujhoZq-AjOHb3ri2B8aWnx0-DQTAVKVnxwBQZH8YAK0r2oLNxhIqZDCUEXaMpzYcDjjG83kA3Q",
    "RefreshToken": "eyJjdHkiOiJKV1QiLCJlbmMiOiJBMjU2R0NNIiwiYWxnIjoiUlNBLU9BRVAifQ.OupuJR3hZUT2bWQTA0n2YqIxN6Lqphxv_yZXjAaJSIKub66xuiF1axUFC9h9SEroWedqR0id_vmfbfH_71_EyS0HZjUlyXSde3WXefY9Yc2YNK1ChCR4rh33r3neuQg0hKx63JTIMVf9yWeFl1Mx4KEsA4eTyvN6GE8o54lGNX6fQX7KovuG5rH0iZQVb2oPFglokAk2uCB4M6p2SbUtWLO5oZYOPWwax62JHb2b5EEwDW4aAJEoWjVetbjLnQHLedYv9Ur68XeSKRtrslZAdCyFjD6Rc1oxuuBEi590CJgj3tlpJV7rSE_185NB90Sa6uU728sksub9sxnANUDY3A.jXKGBg26M4uE3dWm.qO7BO568Aa-4U55mvR-7_1CMCk7ZN7clBAVfKkFyDz6LXwkki9V2ohvm4f_joN88htr4p7AFV7Rik23-vTtTgPXVI9vBUIt37EXyjaMKPJX3B15XnYnC1-YhxjGma6IiyC1oUuiCmUIm9L1c7Jxm8ZmCBFNjc-ARXJTvWAHB3eYHk6U3WHOSB9X_MT2K9Dmrl1-q1vjP4taUKlj60jy91uwk0Ti8tVHp7ETpe4DyEcv9EuoFtEznrJDYcnYpVLyaq9Fkb43F7L3kMq_Jx4IAbWhCaeC35JJa56zAZ1eZ_mGuC5T86xChNqDElhod6m_pz33j5OyPL8rXh8ldERbB7cBB1QgePbPlr1GOvC2T8mE1Rb_gvzNU05Nm1VaeXnClV39GFBpGpEfKY6uvnWiZZICTE3LZRDIhI8Cn-9LwkAUMzqQRKYcPGZswZ68Ma_H40xB3A8pyw_RMF_QvZurUumg-RDeFS2CSnW12zhtMQhr_60Jt9vRQCbWVjBcTh40ZBO5TE8IHsulPq5uJaBEhY2_lpIga4HHjI6cqZ7J3PkRjTc6ZNzAaJiGY0cdRi2pXTeiLqm5_04BUzVbfBQytURbYoaYLxv_wXT-gR4JTLewxJyouO4l955GXK2IjXdZxyFmaXaKrKs7UuiRrkc65_Xzbn8Gj9u0beN661W1CsdymYNht5RfFsJMh85IhsxmzR7XM_2kDVQIjo5EZq5XV0SKQmVjFPYuUIQKcdkx0UsQzQisuuZarcWoDSNq-rxWJF2JbzjtkPyoaSaPxlwC8TL4HXQvT5HQ9S6VeSp0PTQj2BV4NtqzEpskJ9Nql3xrn488WpZD7NBeWkkA_bBKKiYDALoXjmEd6yvmehVtP1VBoqszHOMbikLa1FakJIGpbXqtaH3ZvLdrVCFTKCoEtMob_c4YKoiRgoqyAXew-H_znrxHagVLnJRqfYXLVFkjxGm23PKvSRSRsUXNIlBwUrh8hwL4rsyZLPTE-8aAiG-6VmVE3Xg-JvMtftC-MC5W5PAjLACf_hJP97FrCtg65dUY4-GCGnGMmbe-yLx7z0YaKzuGxccwyT08E-zfmVCeBrkeA-4niUt3xcTJkOOKnPycMWG437cFPxp7sEjw0f4CnZfwX7YHO2rB78UODCZIIqbXgmSQgt86HxNLDqcKY0gLQCIVd3VQSgyRTjOefE3BUGqUHmJ5fKt207tYq_YN6R6rKUvD6NFORmqXIY3AnfU3W1c0FF5ta56T_MW9XSxmcX5AzmT1ZUuzsuNA7gImdu9cpYabynLZgXKSIvcfix__vO84X8bWzr06McPMtRWvLmOr8X5RF9u3X7Q.WVY_SyQ6pF_ae5YP1ov2tg",
    "TokenType": "Bearer"
  },
  "ChallengeParameters": {}
}

# And to validate that we can authenticate users with our code we finally fetch the profile
$ curl https://api.skynetng.pw/user/profile -X POST -d '{ "access_token": "very_long_access_token_from_the_previous_command" }'
OUTPUT:
{
  "profile": {
    "MFAOptions": null,
    "PreferredMfaSetting": null,
    "UserAttributes": [
      {
        "Name": "sub",
        "Value": "317e9839-e9ee-4969-855d-1c13ac79662c"
      },
      {
        "Name": "email_verified",
        "Value": "false"
      },
      {
        "Name": "email",
        "Value": "kainlite@gmail.com"
      }
    ],
    "UserMFASettingList": null,
    "Username": "317e9839-e9ee-4969-855d-1c13ac79662c"
  },
  "user": {
    "access_token": "eyJraWQiOiJJMVN1Q0VteVlVXC9OSkFVY2lLOWRNeE1VSUJzTHZDYm9KejBaaGozZG5SND0iLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiI5ZDMzNDk1MC1mOGIzLTRlZjMtOTVlYy0wNWYzODQxN2UxNTEiLCJldmVudF9pZCI6Ijc2MDVjMTI3LTcwMmItNDI3OS04ZWU5LWQyOGUxY2ZiZjVmYSIsInRva2VuX3VzZSI6ImFjY2VzcyIsInNjb3BlIjoiYXdzLmNvZ25pdG8uc2lnbmluLnVzZXIuYWRtaW4iLCJhdXRoX3RpbWUiOjE1Njc0NjI0NDAsImlzcyI6Imh0dHBzOlwvXC9jb2duaXRvLWlkcC51cy1lYXN0LTEuYW1hem9uYXdzLmNvbVwvdXMtZWFzdC0xX3IwdWdoOUR1cSIsImV4cCI6MTU2NzQ2NjA0MCwiaWF0IjoxNTY3NDYyNDQwLCJqdGkiOiJlMzE0MmJkMC02ZjQ0LTQyNGMtOTExNy01ZTg3NWZhOTg1MDQiLCJjbGllbnRfaWQiOiI0bzJnc3Q1bzU2MDc0Y2M0YWY5MHZwZXVqayIsInVzZXJuYW1lIjoiOWQzMzQ5NTAtZjhiMy00ZWYzLTk1ZWMtMDVmMzg0MTdlMTUxIn0.TjuOR6naiWKYQvuS3gNM8PJXVlL3wqg6TwNGAHqnJ5HzSRx5sQX2bbLUtY1qB7vwACyqQEdYObgGyc8CpV65yNZ9NeNjnCE4wfJMLpSRNXdTQeDpCqNlLVTC8wN33A_ksq1zqTllXRbSODk6rv3trBMs_phJqpDRdxeWR7fsgOwh8J6BcRxg-LhUYRh_IF7EQpFkbOlDi5MAQiz-8-koHf84r75fs28yIT15LVQWcwYXNoS5mUFYdHxuUKsuagdO5VremsT-Y1NQEcwUwe8JL-UwGtVv18IXHk_qrE8uovJiJ7zDKeuEah6ycI1jgTaGBBVLqCBXgf2Nb5XRJ77BUA"
  }
}

```
I have added most info in as comments in the snippet, note that I also used my test domain `skynetng.pw` with the subdomain `api` for all tests.
<br />

##### **Closing notes**
This post was heavily inspired by [this post](https://a.l3x.in/2018/07/25/lambda-api-custom-domain-tutorial.html) from Alexander, kudos to him for the great work!, this post expands on that and adds the certificate with ACM, it also handles a basic AWS Cognito configuration and the necessary go code to make it work, there are other ways to accomplish the same, but what I like about this approach is that you can have some endpoints or paths without authentication and you can use authentication, etc on-demand. This article is a bit different but I will try to re-shape it in the following weeks, and also cover more of the content displayed here, let me know if you have any comments or suggestions!

In some near future I will build upon this article in another article adding a few cool things, for example to allow an user to upload an image to an S3 bucket and fetch that with a friendly name using Cloudfront (In a secure manner, and only able to upload/update his/her profile picture, while being able to fetch anyone profile pic), the idea is to have a fully functional small API using AWS services and serverless facilities with common tasks that you can find in any functional website.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
