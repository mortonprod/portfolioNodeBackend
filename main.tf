terraform {
  backend "s3" {
    # CAN SET THIS HERE ON IN MAKE FILE.
    bucket         = "wgl-site-terraform-state"
    key            = "wgl-site"
    region         = "eu-west-2"
    dynamodb_table = "wgl-site-terraform-state"
  }
}

provider "aws" {
  region = "${var.aws_region}"
}

module "cloudfrontEdge-s3-module" {
  source       = "modules/cloudfrontEdge-s3-module"
  name         = "${var.name}"
  aws_region   = "${var.aws_region}"
  domain_names = "${var.domain_names}"
  asset_folder = "${var.asset_folder}"
}

//////// SES

data "archive_file" "file" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# data "aws_iam_policy_document" "instance_role" {
#   statement {
#     effect  = "Allow"
#     actions = ["sts:AssumeRole"]

#     principals {
#       type        = "Service"
#       identifiers = ["lam"]
#     }
#   }
# }

resource "aws_iam_role" "role" {
  name = "sesRole"

  assume_role_policy = <<POLICY
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
POLICY
}

resource "aws_iam_policy" "policy" {
  name        = "SES"
  # path        = "/"
  description = "SES"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ses:SendEmail",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "iam_role_policy_attachment" {
  role = "${aws_iam_role.role.name}"
  policy_arn = "${aws_iam_policy.policy.arn}"
}

resource "aws_lambda_function" "lambda" {
  filename         = "lambda.zip"
  function_name    = "ses"
  role             = "${aws_iam_role.role.arn}"
  handler          = "lambda.lambda_handler"
  runtime          = "nodejs8.10"
  source_code_hash = "${data.archive_file.file.output_base64sha256}"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda.arn}"
  principal     = "apigateway.amazonaws.com"
}

resource "aws_api_gateway_rest_api" "api_gateway_rest_api" {
  name        = "${var.name}"
  description = "${var.name} description"
}

resource "aws_api_gateway_resource" "api_gateway_resource" {
  rest_api_id = "${aws_api_gateway_rest_api.api_gateway_rest_api.id}"
  parent_id   = "${aws_api_gateway_rest_api.api_gateway_rest_api.root_resource_id}"
  path_part   = "ses"
}

resource "aws_api_gateway_method" "api_gateway_method" {
  rest_api_id        = "${aws_api_gateway_rest_api.api_gateway_rest_api.id}"
  resource_id        = "${aws_api_gateway_resource.api_gateway_resource.id}"
  http_method        = "POST"
  authorization      = "${var.authorization}"
  request_parameters = "${var.request_parameters}"

  request_models = {
    "application/json" = "${var.request_model}"
  }
}

resource "aws_api_gateway_integration" "api_gateway_integration" {
  rest_api_id             = "${aws_api_gateway_rest_api.api_gateway_rest_api.id}"
  resource_id             = "${aws_api_gateway_resource.api_gateway_resource.id}"
  http_method             = "${aws_api_gateway_method.api_gateway_method.http_method}"
  type                    = "AWS_PROXY"
  # uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${aws_lambda_function.lambda.function_name}/invocations"
  uri                     = "${aws_lambda_function.lambda.invoke_arn}"

  integration_http_method = "POST"

  # request_templates = { "application/json" = "${var.integration_request_template}" }
}

# resource "aws_api_gateway_integration_response" "api_gateway_integration_response_200" {
#   rest_api_id = "${aws_api_gateway_rest_api.api_gateway_rest_api.id}"
#   resource_id = "${aws_api_gateway_resource.api_gateway_resource.id}"
#   http_method = "${aws_api_gateway_method.api_gateway_method.http_method}"
#   status_code = "${aws_api_gateway_method_response.ResourceMethod200.status_code}"
#   # status_code = "200"
#   response_parameters = {
#     "method.response.header.Access-Control-Allow-Origin" = "'*'"
#   }
#   response_templates = { "application/json" = "${var.integration_response_template}" }
# }


# resource "aws_api_gateway_integration_response" "aws_api_gateway_integration_response_400" {
#   rest_api_id = "${aws_api_gateway_rest_api.api_gateway_rest_api.id}"
#   resource_id = "${aws_api_gateway_resource.api_gateway_resource.id}"
#   http_method = "${aws_api_gateway_method.api_gateway_method.http_method}"
#   status_code = "${aws_api_gateway_method_response.ResourceMethod400.status_code}"
#   # status_code = "400"
#   # response_templates = {
#   #   "application/json" = "${var.integration_error_template}"
#   # }
#   # response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
# }


# resource "aws_api_gateway_method_response" "ResourceMethod200" {
#   rest_api_id = "${aws_api_gateway_rest_api.api_gateway_rest_api.id}"
#   resource_id = "${aws_api_gateway_resource.api_gateway_resource.id}"
#   http_method = "${aws_api_gateway_method.api_gateway_method.http_method}"
#   status_code = "200"
#   response_models = { "application/json" = "${var.response_model}" }
#   # response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "*" }
# }


# resource "aws_api_gateway_method_response" "ResourceMethod400" {
#   rest_api_id = "${aws_api_gateway_rest_api.api_gateway_rest_api.id}"
#   resource_id = "${aws_api_gateway_resource.api_gateway_resource.id}"
#   http_method = "${aws_api_gateway_method.api_gateway_method.http_method}"
#   status_code = "400"
#   response_models = { "application/json" = "Error" }
#   # response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "*" }
# }

