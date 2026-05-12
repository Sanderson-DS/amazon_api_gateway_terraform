locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "uploads" {
  bucket_prefix = "${local.name_prefix}-uploads-"
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_dynamodb_table" "photos" {
  name         = "${local.name_prefix}-photos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "N"
  }

  attribute {
    name = "assunto"
    type = "S"
  }

  attribute {
    name = "colecao"
    type = "S"
  }

  attribute {
    name = "descricao"
    type = "S"
  }

  global_secondary_index {
    name            = "assunto-index"
    hash_key        = "assunto"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "assunto-colecao-index"
    hash_key        = "assunto"
    range_key       = "colecao"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "assunto-descricao-index"
    hash_key        = "assunto"
    range_key       = "descricao"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled = true
  }
}

# -----------------------------------------------------------------------------
# Lambda packaging
# -----------------------------------------------------------------------------

data "archive_file" "indexer" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/indexer"
  output_path = "${path.module}/indexer.zip"
}

data "archive_file" "public_api" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/public_api"
  output_path = "${path.module}/public_api.zip"
}

data "archive_file" "admin_api" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/admin_api"
  output_path = "${path.module}/admin_api.zip"
}

# -----------------------------------------------------------------------------
# IAM for Lambda
# -----------------------------------------------------------------------------

resource "aws_iam_role" "indexer_lambda" {
  name = "${local.name_prefix}-indexer-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "public_api_lambda" {
  name = "${local.name_prefix}-public-api-lambda-role"

  assume_role_policy = aws_iam_role.indexer_lambda.assume_role_policy
}

resource "aws_iam_role" "admin_api_lambda" {
  name = "${local.name_prefix}-admin-api-lambda-role"

  assume_role_policy = aws_iam_role.indexer_lambda.assume_role_policy
}

resource "aws_iam_role_policy_attachment" "indexer_basic" {
  role       = aws_iam_role.indexer_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "public_basic" {
  role       = aws_iam_role.public_api_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "admin_basic" {
  role       = aws_iam_role.admin_api_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "indexer_dynamodb" {
  name = "${local.name_prefix}-indexer-dynamodb-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ]
      Resource = aws_dynamodb_table.photos.arn
    }]
  })
}

resource "aws_iam_policy" "public_dynamodb" {
  name = "${local.name_prefix}-public-dynamodb-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:Query"
      ]
      Resource = [
        aws_dynamodb_table.photos.arn,
        "${aws_dynamodb_table.photos.arn}/index/*"
      ]
    }]
  })
}

resource "aws_iam_policy" "admin_s3" {
  name = "${local.name_prefix}-admin-s3-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:DeleteObject"
      ]
      Resource = "${aws_s3_bucket.uploads.arn}/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "indexer_dynamodb" {
  role       = aws_iam_role.indexer_lambda.name
  policy_arn = aws_iam_policy.indexer_dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "public_dynamodb" {
  role       = aws_iam_role.public_api_lambda.name
  policy_arn = aws_iam_policy.public_dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "admin_s3" {
  role       = aws_iam_role.admin_api_lambda.name
  policy_arn = aws_iam_policy.admin_s3.arn
}

# -----------------------------------------------------------------------------
# Lambda functions
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "indexer" {
  name              = "/aws/lambda/${local.name_prefix}-indexer"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "public_api" {
  name              = "/aws/lambda/${local.name_prefix}-public-api"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "admin_api" {
  name              = "/aws/lambda/${local.name_prefix}-admin-api"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "indexer" {
  function_name    = "${local.name_prefix}-indexer"
  filename         = data.archive_file.indexer.output_path
  source_code_hash = data.archive_file.indexer.output_base64sha256
  role             = aws_iam_role.indexer_lambda.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.photos.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.indexer,
    aws_iam_role_policy_attachment.indexer_basic,
    aws_iam_role_policy_attachment.indexer_dynamodb
  ]
}

resource "aws_lambda_function" "public_api" {
  function_name    = "${local.name_prefix}-public-api"
  filename         = data.archive_file.public_api.output_path
  source_code_hash = data.archive_file.public_api.output_base64sha256
  role             = aws_iam_role.public_api_lambda.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.photos.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.public_api,
    aws_iam_role_policy_attachment.public_basic,
    aws_iam_role_policy_attachment.public_dynamodb
  ]
}

resource "aws_lambda_function" "admin_api" {
  function_name    = "${local.name_prefix}-admin-api"
  filename         = data.archive_file.admin_api.output_path
  source_code_hash = data.archive_file.admin_api.output_base64sha256
  role             = aws_iam_role.admin_api_lambda.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.uploads.bucket
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.admin_api,
    aws_iam_role_policy_attachment.admin_basic,
    aws_iam_role_policy_attachment.admin_s3
  ]
}

resource "aws_lambda_permission" "allow_s3_to_indexer" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.indexer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.uploads.arn
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.indexer.arn
    events              = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3_to_indexer]
}

# -----------------------------------------------------------------------------
# Public REST API
# -----------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "public" {
  name        = "${local.name_prefix}-public-api"
  description = "API pública de consulta de fotos"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "public_fotos" {
  rest_api_id = aws_api_gateway_rest_api.public.id
  parent_id   = aws_api_gateway_rest_api.public.root_resource_id
  path_part   = "fotos"
}

resource "aws_api_gateway_resource" "public_proxy" {
  rest_api_id = aws_api_gateway_rest_api.public.id
  parent_id   = aws_api_gateway_resource.public_fotos.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "public_fotos_get" {
  rest_api_id   = aws_api_gateway_rest_api.public.id
  resource_id   = aws_api_gateway_resource.public_fotos.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "public_proxy_get" {
  rest_api_id   = aws_api_gateway_rest_api.public.id
  resource_id   = aws_api_gateway_resource.public_proxy.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "public_fotos_get" {
  rest_api_id             = aws_api_gateway_rest_api.public.id
  resource_id             = aws_api_gateway_resource.public_fotos.id
  http_method             = aws_api_gateway_method.public_fotos_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.public_api.invoke_arn
}

resource "aws_api_gateway_integration" "public_proxy_get" {
  rest_api_id             = aws_api_gateway_rest_api.public.id
  resource_id             = aws_api_gateway_resource.public_proxy.id
  http_method             = aws_api_gateway_method.public_proxy_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.public_api.invoke_arn
}

resource "aws_lambda_permission" "allow_public_apigw" {
  statement_id  = "AllowExecutionFromPublicAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.public_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.public.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "public" {
  rest_api_id = aws_api_gateway_rest_api.public.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.public_fotos.id,
      aws_api_gateway_resource.public_proxy.id,
      aws_api_gateway_method.public_fotos_get.id,
      aws_api_gateway_method.public_proxy_get.id,
      aws_api_gateway_integration.public_fotos_get.id,
      aws_api_gateway_integration.public_proxy_get.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.public_fotos_get,
    aws_api_gateway_integration.public_proxy_get
  ]
}

resource "aws_api_gateway_stage" "public" {
  rest_api_id          = aws_api_gateway_rest_api.public.id
  deployment_id        = aws_api_gateway_deployment.public.id
  stage_name           = var.environment
  xray_tracing_enabled = true
}

# -----------------------------------------------------------------------------
# Admin REST API
# -----------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "admin" {
  name        = "${local.name_prefix}-admin-api"
  description = "API administrativa para upload e remoção de fotos"

  binary_media_types = [
    "image/jpeg",
    "application/octet-stream"
  ]

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "admin_bucket" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  parent_id   = aws_api_gateway_rest_api.admin.root_resource_id
  path_part   = "bucket"
}

resource "aws_api_gateway_resource" "admin_item" {
  rest_api_id = aws_api_gateway_rest_api.admin.id
  parent_id   = aws_api_gateway_resource.admin_bucket.id
  path_part   = "{item}"
}

resource "aws_api_gateway_method" "admin_post" {
  rest_api_id      = aws_api_gateway_rest_api.admin.id
  resource_id      = aws_api_gateway_resource.admin_item.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "admin_delete" {
  rest_api_id      = aws_api_gateway_rest_api.admin.id
  resource_id      = aws_api_gateway_resource.admin_item.id
  http_method      = "DELETE"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "admin_post" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.admin_item.id
  http_method             = aws_api_gateway_method.admin_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.admin_api.invoke_arn
}

resource "aws_api_gateway_integration" "admin_delete" {
  rest_api_id             = aws_api_gateway_rest_api.admin.id
  resource_id             = aws_api_gateway_resource.admin_item.id
  http_method             = aws_api_gateway_method.admin_delete.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.admin_api.invoke_arn
}

resource "aws_lambda_permission" "allow_admin_apigw" {
  statement_id  = "AllowExecutionFromAdminAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.admin_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.admin.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "admin" {
  rest_api_id = aws_api_gateway_rest_api.admin.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.admin_bucket.id,
      aws_api_gateway_resource.admin_item.id,
      aws_api_gateway_method.admin_post.id,
      aws_api_gateway_method.admin_delete.id,
      aws_api_gateway_integration.admin_post.id,
      aws_api_gateway_integration.admin_delete.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.admin_post,
    aws_api_gateway_integration.admin_delete
  ]
}

resource "aws_api_gateway_stage" "admin" {
  rest_api_id          = aws_api_gateway_rest_api.admin.id
  deployment_id        = aws_api_gateway_deployment.admin.id
  stage_name           = var.environment
  xray_tracing_enabled = true
}

resource "aws_api_gateway_api_key" "admin" {
  name    = "${local.name_prefix}-admin-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "admin" {
  name        = "${local.name_prefix}-admin-usage-plan"
  description = "Usage plan da API administrativa"

  api_stages {
    api_id = aws_api_gateway_rest_api.admin.id
    stage  = aws_api_gateway_stage.admin.stage_name
  }

  throttle_settings {
    burst_limit = var.admin_api_burst_limit
    rate_limit  = var.admin_api_rate_limit
  }
}

resource "aws_api_gateway_usage_plan_key" "admin" {
  key_id        = aws_api_gateway_api_key.admin.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.admin.id
}

# -----------------------------------------------------------------------------
# Optional WAF
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "api" {
  count = var.enable_waf ? 1 : 0

  name  = "${local.name_prefix}-api-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimit"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-api-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "public_api" {
  count = var.enable_waf ? 1 : 0

  resource_arn = "arn:aws:apigateway:${var.aws_region}::/restapis/${aws_api_gateway_rest_api.public.id}/stages/${aws_api_gateway_stage.public.stage_name}"
  web_acl_arn  = aws_wafv2_web_acl.api[0].arn
}

resource "aws_wafv2_web_acl_association" "admin_api" {
  count = var.enable_waf ? 1 : 0

  resource_arn = "arn:aws:apigateway:${var.aws_region}::/restapis/${aws_api_gateway_rest_api.admin.id}/stages/${aws_api_gateway_stage.admin.stage_name}"
  web_acl_arn  = aws_wafv2_web_acl.api[0].arn
}
