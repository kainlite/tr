%{
  title: "Creating a lambda function with terraform",
  author: "Gabriel Garrido",
  description: "Here we will see how to use terraform to manage lambda functions, it will be a simple hello world in
  node.js, available as gist...",
  tags: ~w(terraform lambda serverless aws),
  published: true,
  image: "terraform.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![terraform](/images/terraform-lambda.png){:class="mx-auto"}

##### **Introduction**
Here we will see how to use terraform to manage lambda functions, it will be a simple hello world in node.js, available as a [gist here](https://gist.github.com/smithclay/e026b10980214cbe95600b82f67b4958), note that I did not create this example but it's really close to the official documentation but shorter, you can see another example with [python here](https://github.com/terraform-providers/terraform-provider-aws/tree/master/examples/lambda).
<br />

Before you start make sure you already have your account configured for [awscli](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html) and [terraform](https://learn.hashicorp.com/terraform/getting-started/install.html) installed.
<br />

##### **Configuration files**
First of all we need to get our terraform file or files (in a normal case scenario, but since this is a hello world it is easier to have everything in the same file), I have added some comments of what each part does as you can see.
```elixir
# Set the region where the lambda function will be created
variable "aws_region" {
  default = "us-east-1"
}

# Assign the region to the provider in this case AWS
provider "aws" {
  region          = "${var.aws_region}"
}

# Archive the code or project that we want to run
data "archive_file" "lambda_zip" {
    type          = "zip"
    source_file   = "index.js"
    output_path   = "lambda_function.zip"
}

# Create the function
resource "aws_lambda_function" "test_lambda" {
  filename         = "lambda_function.zip"
  function_name    = "test_lambda"
  role             = "${aws_iam_role.iam_for_lambda_tf.arn}"
  handler          = "index.handler"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  runtime          = "nodejs8.10"
}

# Necessary permissions to create/run the function 
resource "aws_iam_role" "iam_for_lambda_tf" {
  name = "iam_for_lambda_tf"

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

```
<br />

##### **The code itself**
Then we need the code that we need or want to run there.
```elixir
// 'Hello World' nodejs6.10 runtime AWS Lambda function
exports.handler = (event, context, callback) => {
    console.log('Hello world!');
    callback(null, 'It works!');
}

```
<br />

##### **Initialize terraform**
First of all we will need to initialize terraform like in the gist below, this will download the necessary plugins that we used in the code, otherwise it won't be able to run.
```elixir
$ terraform init                                                                                                                                                                                                                           
                                                                                                                                                                                                                                                                                 
Initializing provider plugins...                                                                                                                                                                                                                                                 
- Checking for available provider plugins on https://releases.hashicorp.com...                                                                                                                                                                                                   
- Downloading plugin for provider "aws" (2.8.0)...                                                                                                                                                                                                                               
- Downloading plugin for provider "archive" (1.2.1)...                                                                                                                                                                                                                           
                                                                                                                                                                                                                                                                                 
The following providers do not have any version constraints in configuration,                                                                                                                                                                                                    
so the latest version was installed.                                                                                                                                                                                                                                             
                                                                                                                                                                                                                                                                                 
To prevent automatic upgrades to new major versions that may contain breaking                                                                                                                                                                                                    
changes, it is recommended to add version = "..." constraints to the                                                                                                                                                                                                             
corresponding provider blocks in configuration, with the constraint strings                                                                                                                                                                                                      
suggested below.                                                                                                                                                                                                                                                                 
                                                                                                                                                                                                                                                                                 
* provider.archive: version = "~> 1.2"                                                                                                                                                                                                                                           
* provider.aws: version = "~> 2.8"                                                                                                                                                                                                                                               
                                                                                                                                                                                                                                                                                 
Terraform has been successfully initialized!                                                                                                                                                                                                                                     
                                                                                                                                                                                                                                                                                 
You may now begin working with Terraform. Try running "terraform plan" to see                                                                                                                                                                                                    
any changes that are required for your infrastructure. All Terraform commands                                                                                                                                                                                                    
should now work.                                                                                                                                                                                                                                                                 
                                                                                                                                                                                                                                                                                 
If you ever set or change modules or backend configuration for Terraform,                                                                                                                                                                                                        
rerun this command to reinitialize your working directory. If you forget, other                                                                                                                                                                                                  
commands will detect it and remind you to do so if necessary. 

```
<br />

##### **Apply the changes**
The next step would be to apply the changes, you can also plan to an outfile and then apply from that file, but also apply works, this command will take care of doing everything that we defined, it will archive the code, the IAM role and the function itself.
```elixir
$ terraform apply
data.archive_file.lambda_zip: Refreshing state...

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + aws_iam_role.iam_for_lambda_tf
      id:                             <computed>
      arn:                            <computed>
      assume_role_policy:             "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Action\": \"sts:AssumeRole\",
      \"Principal\": {
        \"Service\": \"lambda.amazonaws.com\"
      },
      \"Effect\": \"Allow\",
      \"Sid\": \"\"
    }
  ]
}
"
      create_date:                    <computed>
      force_detach_policies:          "false"
      max_session_duration:           "3600"
      name:                           "iam_for_lambda_tf"
      path:                           "/"
      unique_id:                      <computed>

  + aws_lambda_function.test_lambda
      id:                             <computed>
      arn:                            <computed>
      filename:                       "lambda_function.zip"
      function_name:                  "test_lambda"
      handler:                        "index.handler"
      invoke_arn:                     <computed>
      last_modified:                  <computed>
      memory_size:                    "128"
      publish:                        "false"
      qualified_arn:                  <computed>
      reserved_concurrent_executions: "-1"
      role:                           "${aws_iam_role.iam_for_lambda_tf.arn}"
      runtime:                        "nodejs6.10"
      source_code_hash:               "iMkBKAlTzgvS8FWKCCaHBqVrw/AvdC1cL13vYV0nTnA="
      source_code_size:               <computed>
      timeout:                        "3"
      tracing_config.#:               <computed>
      version:                        <computed>


Plan: 2 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

aws_iam_role.iam_for_lambda_tf: Creating...
  arn:                   "" => "<computed>"
  assume_role_policy:    "" => "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Action\": \"sts:AssumeRole\",
      \"Principal\": {
        \"Service\": \"lambda.amazonaws.com\"
      },
      \"Effect\": \"Allow\",
      \"Sid\": \"\"
    }
  ]
}
"
  create_date:           "" => "<computed>"
  force_detach_policies: "" => "false"
  max_session_duration:  "" => "3600"
  name:                  "" => "iam_for_lambda_tf"
  path:                  "" => "/"
  unique_id:             "" => "<computed>"
aws_iam_role.iam_for_lambda_tf: Creation complete after 2s (ID: iam_for_lambda_tf)
aws_lambda_function.test_lambda: Creating...
  arn:                            "" => "<computed>"
  filename:                       "" => "lambda_function.zip"
  function_name:                  "" => "test_lambda"
  handler:                        "" => "index.handler"
  invoke_arn:                     "" => "<computed>"
  last_modified:                  "" => "<computed>"
  memory_size:                    "" => "128"
  publish:                        "" => "false"
  qualified_arn:                  "" => "<computed>"
  reserved_concurrent_executions: "" => "-1"
  role:                           "" => "arn:aws:iam::894527626897:role/iam_for_lambda_tf"
  runtime:                        "" => "nodejs6.10"
  source_code_hash:               "" => "iMkBKAlTzgvS8FWKCCaHBqVrw/AvdC1cL13vYV0nTnA="
  source_code_size:               "" => "<computed>"
  timeout:                        "" => "3"
  tracing_config.#:               "" => "<computed>"
  version:                        "" => "<computed>"
aws_lambda_function.test_lambda: Creation complete after 8s (ID: test_lambda)

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

```
<br />

##### **Running the function**
Then the last step would be to run our function to see if it actually works, in this case we're using the awscli but you can use the AWS console as well, the result will be the same.
```elixir
$ aws lambda invoke --function-name$ test_lambda --invocation-type RequestResponse --log-type Tail - | jq '.LogResult' -r | base64 --decode                                                                                                
START RequestId: 760a31c6-8ba4-48ac-9a8f-0cf0ec7bf7ac Version: $LATEST
2019-04-27T20:14:23.630Z        760a31c6-8ba4-48ac-9a8f-0cf0ec7bf7ac    Hello world!
END RequestId: 760a31c6-8ba4-48ac-9a8f-0cf0ec7bf7ac
REPORT RequestId: 760a31c6-8ba4-48ac-9a8f-0cf0ec7bf7ac  Duration: 75.06 ms      Billed Duration: 100 ms         Memory Size: 128 MB     Max Memory Used: 48 MB  

```

<br />
##### **Clean up**
Remember to clean up before leaving.
```elixir
$ terraform destroy
data.archive_file.lambda_zip: Refreshing state...
aws_iam_role.iam_for_lambda_tf: Refreshing state... (ID: iam_for_lambda_tf)
aws_lambda_function.test_lambda: Refreshing state... (ID: test_lambda)

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  - aws_iam_role.iam_for_lambda_tf

  - aws_lambda_function.test_lambda


Plan: 0 to add, 0 to change, 2 to destroy.

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

aws_lambda_function.test_lambda: Destroying... (ID: test_lambda)
aws_lambda_function.test_lambda: Destruction complete after 1s
aws_iam_role.iam_for_lambda_tf: Destroying... (ID: iam_for_lambda_tf)
aws_iam_role.iam_for_lambda_tf: Destruction complete after 2s

Destroy complete! Resources: 2 destroyed.

```

I don't know about you, but I'm going to keep using the [serverless framework](https://serverless.com/) for now, but it's good to see that we have alternatives and with some effort can give us the same functionality.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Creating a lambda function with terraform",
  author: "Gabriel Garrido",
  description: "Here we will see how to use terraform to manage lambda functions, it will be a simple hello world in
  node.js, available as gist...",
  tags: ~w(terraform lambda serverless aws),
  published: true,
  image: "terraform.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### Traduccion en proceso

![terraform](/images/terraform-lambda.png){:class="mx-auto"}

##### **Introduction**
Here we will see how to use terraform to manage lambda functions, it will be a simple hello world in node.js, available as a [gist here](https://gist.github.com/smithclay/e026b10980214cbe95600b82f67b4958), note that I did not create this example but it's really close to the official documentation but shorter, you can see another example with [python here](https://github.com/terraform-providers/terraform-provider-aws/tree/master/examples/lambda).
<br />

Before you start make sure you already have your account configured for [awscli](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html) and [terraform](https://learn.hashicorp.com/terraform/getting-started/install.html) installed.
<br />

##### **Configuration files**
First of all we need to get our terraform file or files (in a normal case scenario, but since this is a hello world it is easier to have everything in the same file), I have added some comments of what each part does as you can see.
```elixir
# Set the region where the lambda function will be created
variable "aws_region" {
  default = "us-east-1"
}

# Assign the region to the provider in this case AWS
provider "aws" {
  region          = "${var.aws_region}"
}

# Archive the code or project that we want to run
data "archive_file" "lambda_zip" {
    type          = "zip"
    source_file   = "index.js"
    output_path   = "lambda_function.zip"
}

# Create the function
resource "aws_lambda_function" "test_lambda" {
  filename         = "lambda_function.zip"
  function_name    = "test_lambda"
  role             = "${aws_iam_role.iam_for_lambda_tf.arn}"
  handler          = "index.handler"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  runtime          = "nodejs8.10"
}

# Necessary permissions to create/run the function 
resource "aws_iam_role" "iam_for_lambda_tf" {
  name = "iam_for_lambda_tf"

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

```
<br />

##### **The code itself**
Then we need the code that we need or want to run there.
```elixir
// 'Hello World' nodejs6.10 runtime AWS Lambda function
exports.handler = (event, context, callback) => {
    console.log('Hello world!');
    callback(null, 'It works!');
}

```
<br />

##### **Initialize terraform**
First of all we will need to initialize terraform like in the gist below, this will download the necessary plugins that we used in the code, otherwise it won't be able to run.
```elixir
$ terraform init                                                                                                                                                                                                                           
                                                                                                                                                                                                                                                                                 
Initializing provider plugins...                                                                                                                                                                                                                                                 
- Checking for available provider plugins on https://releases.hashicorp.com...                                                                                                                                                                                                   
- Downloading plugin for provider "aws" (2.8.0)...                                                                                                                                                                                                                               
- Downloading plugin for provider "archive" (1.2.1)...                                                                                                                                                                                                                           
                                                                                                                                                                                                                                                                                 
The following providers do not have any version constraints in configuration,                                                                                                                                                                                                    
so the latest version was installed.                                                                                                                                                                                                                                             
                                                                                                                                                                                                                                                                                 
To prevent automatic upgrades to new major versions that may contain breaking                                                                                                                                                                                                    
changes, it is recommended to add version = "..." constraints to the                                                                                                                                                                                                             
corresponding provider blocks in configuration, with the constraint strings                                                                                                                                                                                                      
suggested below.                                                                                                                                                                                                                                                                 
                                                                                                                                                                                                                                                                                 
* provider.archive: version = "~> 1.2"                                                                                                                                                                                                                                           
* provider.aws: version = "~> 2.8"                                                                                                                                                                                                                                               
                                                                                                                                                                                                                                                                                 
Terraform has been successfully initialized!                                                                                                                                                                                                                                     
                                                                                                                                                                                                                                                                                 
You may now begin working with Terraform. Try running "terraform plan" to see                                                                                                                                                                                                    
any changes that are required for your infrastructure. All Terraform commands                                                                                                                                                                                                    
should now work.                                                                                                                                                                                                                                                                 
                                                                                                                                                                                                                                                                                 
If you ever set or change modules or backend configuration for Terraform,                                                                                                                                                                                                        
rerun this command to reinitialize your working directory. If you forget, other                                                                                                                                                                                                  
commands will detect it and remind you to do so if necessary. 

```
<br />

##### **Apply the changes**
The next step would be to apply the changes, you can also plan to an outfile and then apply from that file, but also apply works, this command will take care of doing everything that we defined, it will archive the code, the IAM role and the function itself.
```elixir
$ terraform apply
data.archive_file.lambda_zip: Refreshing state...

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + aws_iam_role.iam_for_lambda_tf
      id:                             <computed>
      arn:                            <computed>
      assume_role_policy:             "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Action\": \"sts:AssumeRole\",
      \"Principal\": {
        \"Service\": \"lambda.amazonaws.com\"
      },
      \"Effect\": \"Allow\",
      \"Sid\": \"\"
    }
  ]
}
"
      create_date:                    <computed>
      force_detach_policies:          "false"
      max_session_duration:           "3600"
      name:                           "iam_for_lambda_tf"
      path:                           "/"
      unique_id:                      <computed>

  + aws_lambda_function.test_lambda
      id:                             <computed>
      arn:                            <computed>
      filename:                       "lambda_function.zip"
      function_name:                  "test_lambda"
      handler:                        "index.handler"
      invoke_arn:                     <computed>
      last_modified:                  <computed>
      memory_size:                    "128"
      publish:                        "false"
      qualified_arn:                  <computed>
      reserved_concurrent_executions: "-1"
      role:                           "${aws_iam_role.iam_for_lambda_tf.arn}"
      runtime:                        "nodejs6.10"
      source_code_hash:               "iMkBKAlTzgvS8FWKCCaHBqVrw/AvdC1cL13vYV0nTnA="
      source_code_size:               <computed>
      timeout:                        "3"
      tracing_config.#:               <computed>
      version:                        <computed>


Plan: 2 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

aws_iam_role.iam_for_lambda_tf: Creating...
  arn:                   "" => "<computed>"
  assume_role_policy:    "" => "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Action\": \"sts:AssumeRole\",
      \"Principal\": {
        \"Service\": \"lambda.amazonaws.com\"
      },
      \"Effect\": \"Allow\",
      \"Sid\": \"\"
    }
  ]
}
"
  create_date:           "" => "<computed>"
  force_detach_policies: "" => "false"
  max_session_duration:  "" => "3600"
  name:                  "" => "iam_for_lambda_tf"
  path:                  "" => "/"
  unique_id:             "" => "<computed>"
aws_iam_role.iam_for_lambda_tf: Creation complete after 2s (ID: iam_for_lambda_tf)
aws_lambda_function.test_lambda: Creating...
  arn:                            "" => "<computed>"
  filename:                       "" => "lambda_function.zip"
  function_name:                  "" => "test_lambda"
  handler:                        "" => "index.handler"
  invoke_arn:                     "" => "<computed>"
  last_modified:                  "" => "<computed>"
  memory_size:                    "" => "128"
  publish:                        "" => "false"
  qualified_arn:                  "" => "<computed>"
  reserved_concurrent_executions: "" => "-1"
  role:                           "" => "arn:aws:iam::894527626897:role/iam_for_lambda_tf"
  runtime:                        "" => "nodejs6.10"
  source_code_hash:               "" => "iMkBKAlTzgvS8FWKCCaHBqVrw/AvdC1cL13vYV0nTnA="
  source_code_size:               "" => "<computed>"
  timeout:                        "" => "3"
  tracing_config.#:               "" => "<computed>"
  version:                        "" => "<computed>"
aws_lambda_function.test_lambda: Creation complete after 8s (ID: test_lambda)

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

```
<br />

##### **Running the function**
Then the last step would be to run our function to see if it actually works, in this case we're using the awscli but you can use the AWS console as well, the result will be the same.
```elixir
$ aws lambda invoke --function-name$ test_lambda --invocation-type RequestResponse --log-type Tail - | jq '.LogResult' -r | base64 --decode                                                                                                
START RequestId: 760a31c6-8ba4-48ac-9a8f-0cf0ec7bf7ac Version: $LATEST
2019-04-27T20:14:23.630Z        760a31c6-8ba4-48ac-9a8f-0cf0ec7bf7ac    Hello world!
END RequestId: 760a31c6-8ba4-48ac-9a8f-0cf0ec7bf7ac
REPORT RequestId: 760a31c6-8ba4-48ac-9a8f-0cf0ec7bf7ac  Duration: 75.06 ms      Billed Duration: 100 ms         Memory Size: 128 MB     Max Memory Used: 48 MB  

```

<br />
##### **Clean up**
Remember to clean up before leaving.
```elixir
$ terraform destroy
data.archive_file.lambda_zip: Refreshing state...
aws_iam_role.iam_for_lambda_tf: Refreshing state... (ID: iam_for_lambda_tf)
aws_lambda_function.test_lambda: Refreshing state... (ID: test_lambda)

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  - aws_iam_role.iam_for_lambda_tf

  - aws_lambda_function.test_lambda


Plan: 0 to add, 0 to change, 2 to destroy.

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

aws_lambda_function.test_lambda: Destroying... (ID: test_lambda)
aws_lambda_function.test_lambda: Destruction complete after 1s
aws_iam_role.iam_for_lambda_tf: Destroying... (ID: iam_for_lambda_tf)
aws_iam_role.iam_for_lambda_tf: Destruction complete after 2s

Destroy complete! Resources: 2 destroyed.

```

I don't know about you, but I'm going to keep using the [serverless framework](https://serverless.com/) for now, but it's good to see that we have alternatives and with some effort can give us the same functionality.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
