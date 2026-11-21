# Everything the app talks to, behind one CloudFront distribution (ADR-0021):
#
#   https://api.buckleupquiz.com/v1/reports   POST  anonymous error reports → Lambda → logs (ADR-0020)
#   https://api.buckleupquiz.com/content/...  GET   question packs (ADR-0012, not used by the app yet)
#   https://api.buckleupquiz.com/voices/...   GET   natural voice packs (ADR-0019, later)
#
#   make infra-platform
#
# Can be applied before the domain exists (use_custom_domain = false): it then answers on the
# *.cloudfront.net name, and switches to api.buckleupquiz.com on the next apply.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.7" }
  }
  backend "s3" {
    key          = "platform/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-southeast-2"
  default_tags {
    tags = { Project = "buckleupquiz", ManagedBy = "terraform", Stack = "platform" }
  }
}

variable "domain_name" {
  type    = string
  default = "buckleupquiz.com"
}

variable "use_custom_domain" {
  description = "Serve on api.<domain_name>. Needs the domain stack applied and its certificate issued."
  type        = bool
  default     = true
}

variable "reports_retention_days" {
  type    = number
  default = 90
}

variable "reports_max_concurrency" {
  description = "Reserved concurrency to cap cost if the endpoint is abused. -1 = no reservation."
  type        = number
  default     = -1
}

data "aws_caller_identity" "current" {}

locals {
  api_host = "api.${var.domain_name}"
}

data "aws_route53_zone" "main" {
  count = var.use_custom_domain ? 1 : 0
  name  = var.domain_name
}

data "aws_acm_certificate" "main" {
  count    = var.use_custom_domain ? 1 : 0
  region   = "us-east-1"
  domain   = var.domain_name
  statuses = ["ISSUED"]
}

# ---------------------------------------------------------------------------------------------
# Content bucket (question packs, voice packs). Private: only CloudFront can read it.
# ---------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "content" {
  bucket = "buckleupquiz-content-${data.aws_caller_identity.current.account_id}"
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_public_access_block" "content" {
  bucket                  = aws_s3_bucket.content.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "content" {
  bucket = aws_s3_bucket.content.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  bucket = aws_s3_bucket.content.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# Versioning guards against an accidental overwrite; old versions go after 30 days.
resource "aws_s3_bucket_versioning" "content" {
  bucket = aws_s3_bucket.content.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "content" {
  bucket = aws_s3_bucket.content.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_cloudfront_origin_access_control" "content" {
  name                              = "buckleupquiz-content"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "content" {
  bucket = aws_s3_bucket.content.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudFrontReadsContent"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.content.arn}/*"
        Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.api.arn } }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.content.arn, "${aws_s3_bucket.content.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.content]
}

# ---------------------------------------------------------------------------------------------
# Error reports: Lambda function URL (no API Gateway: cheaper, nothing to configure)
# ---------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "reports" {
  name              = "/buckleupquiz/telemetry"
  retention_in_days = var.reports_retention_days
}

# Service roles live under /buckleupquiz/ and carry the boundary from the bootstrap stack, the
# only kind of role the deployer may create (ADR-0021).
resource "aws_iam_role" "reports" {
  name                 = "buckleupquiz-reports"
  path                 = "/buckleupquiz/"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/buckleupquiz/service-boundary"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "reports_logs" {
  name = "write-report-logs"
  role = aws_iam_role.reports.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.reports.arn}:*"
    }]
  })
}

data "archive_file" "reports" {
  type        = "zip"
  source_file = "${path.module}/reports/index.js"
  output_path = "${path.module}/.terraform/reports.zip"
}

resource "aws_lambda_function" "reports" {
  function_name                  = "buckleupquiz-reports"
  description                    = "BuckleUp Quiz anonymous error reports (ADR-0020)"
  role                           = aws_iam_role.reports.arn
  runtime                        = "nodejs22.x"
  architectures                  = ["arm64"] # cheaper per GB-second than x86
  handler                        = "index.handler"
  memory_size                    = 128
  timeout                        = 5
  filename                       = data.archive_file.reports.output_path
  source_code_hash               = data.archive_file.reports.output_base64sha256
  reserved_concurrent_executions = var.reports_max_concurrency

  logging_config {
    log_format            = "JSON"
    log_group             = aws_cloudwatch_log_group.reports.name
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  depends_on = [aws_iam_role_policy.reports_logs]
}

resource "aws_lambda_function_url" "reports" {
  function_name      = aws_lambda_function.reports.function_name
  authorization_type = "NONE"
}

# A public function URL needs both permissions (the second since October 2025).
resource "aws_lambda_permission" "reports_url" {
  statement_id           = "PublicFunctionUrl"
  function_name          = aws_lambda_function.reports.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "reports_invoke" {
  statement_id             = "PublicInvokeViaFunctionUrl"
  function_name            = aws_lambda_function.reports.function_name
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  invoked_via_function_url = true
}

# ---------------------------------------------------------------------------------------------
# CloudFront: one distribution for content and reports. Always-free tier: 1 TB and
# 10 million requests a month. No access logs (they'd cost money and hold IPs).
# ---------------------------------------------------------------------------------------------

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

locals {
  reports_origin_host = trimsuffix(trimprefix(aws_lambda_function_url.reports.function_url, "https://"), "/")
}

resource "aws_cloudfront_distribution" "api" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  comment         = "BuckleUp Quiz: content packs and anonymous error reports"
  # Families are mostly in Australia, which only PriceClass_All covers. Traffic is within the
  # always-free tier either way.
  price_class = "PriceClass_All"
  aliases     = var.use_custom_domain ? [local.api_host] : []

  origin {
    origin_id                = "content"
    domain_name              = aws_s3_bucket.content.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.content.id
  }

  origin {
    origin_id   = "reports"
    domain_name = local.reports_origin_host
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "content"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true
  }

  ordered_cache_behavior {
    path_pattern             = "/v1/reports"
    target_origin_id         = "reports"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    compress                 = false
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = !var.use_custom_domain
    acm_certificate_arn            = var.use_custom_domain ? data.aws_acm_certificate.main[0].arn : null
    ssl_support_method             = var.use_custom_domain ? "sni-only" : null
    minimum_protocol_version       = var.use_custom_domain ? "TLSv1.2_2021" : "TLSv1"
  }
}

resource "aws_route53_record" "api" {
  for_each = var.use_custom_domain ? toset(["A", "AAAA"]) : toset([])
  zone_id  = data.aws_route53_zone.main[0].zone_id
  name     = local.api_host
  type     = each.key
  alias {
    name                   = aws_cloudfront_distribution.api.domain_name
    zone_id                = aws_cloudfront_distribution.api.hosted_zone_id
    evaluate_target_health = false
  }
}

# ---------------------------------------------------------------------------------------------

locals {
  base_url = var.use_custom_domain ? "https://${local.api_host}" : "https://${aws_cloudfront_distribution.api.domain_name}"
}

output "reports_url" {
  description = "Put this in project.yml as TELEMETRY_URL."
  value       = "${local.base_url}/v1/reports"
}

output "content_base_url" {
  value = "${local.base_url}/content/"
}

output "content_bucket" {
  value = aws_s3_bucket.content.bucket
}

output "distribution_id" {
  value = aws_cloudfront_distribution.api.id
}
