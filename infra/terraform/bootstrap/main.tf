# One-time: the S3 bucket that holds every other stack's Terraform state (ADR-0021).
# Run once per AWS account with `make infra-bootstrap`. Its own (tiny) state is kept locally
# and copied into the bucket as a backup; the bucket name is derived from the account ID, so
# a second run can only ever find the same bucket, never create another.

terraform {
  required_version = ">= 1.10" # S3 native state locking (use_lockfile)
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "ap-southeast-2"
  default_tags {
    tags = { Project = "buckleupquiz", ManagedBy = "terraform", Stack = "bootstrap" }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  bucket = "buckleupquiz-tfstate-${data.aws_caller_identity.current.account_id}"
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

# SSE-S3: free, unlike KMS keys ($1/month each).
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

# Old state versions are kept 90 days for recovery, then deleted (keeps storage at cents).
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

# ---------------------------------------------------------------------------------------------
# Least-privilege access (ADR-0021). The account is shared with other projects, so everyday
# Terraform runs use this role, which can only touch BuckleUp Quiz resources. Bootstrap is the
# only stack run with admin rights.
#
#   ~/.aws/config:  [profile buckleupquiz]  role_arn = <deployer_role_arn>  source_profile = <admin>
# ---------------------------------------------------------------------------------------------

variable "admin_principal_arns" {
  description = "Who may assume the deployer role (the admin user or role running bootstrap)."
  type        = list(string)
  default     = []
}

locals {
  account      = data.aws_caller_identity.current.account_id
  domain       = "buckleupquiz.com"
  admin_arns   = length(var.admin_principal_arns) > 0 ? var.admin_principal_arns : [data.aws_caller_identity.current.arn]
  service_path = "/buckleupquiz/"
  boundary_arn = "arn:aws:iam::${local.account}:policy/buckleupquiz/service-boundary"
}

# The most any role the deployer creates can ever do: write its logs, read content.
resource "aws_iam_policy" "service_boundary" {
  name        = "service-boundary"
  path        = local.service_path
  description = "Permissions boundary for BuckleUp Quiz service roles"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "OwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:${local.account}:log-group:/buckleupquiz/*"
      },
      {
        Sid      = "ReadContent"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::buckleupquiz-content-${local.account}/*"
      },
    ]
  })
}

resource "aws_iam_role" "deployer" {
  name                 = "buckleupquiz-deployer"
  description          = "Terraform for BuckleUp Quiz (domain and platform stacks) only"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = local.admin_arns }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "deployer" {
  name = "buckleupquiz-only"
  role = aws_iam_role.deployer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Terraform state
      {
        Sid      = "StateList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid      = "StateObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.state.arn}/domain/*", "${aws_s3_bucket.state.arn}/platform/*"]
      },
      # Content bucket
      {
        Sid      = "ContentBucket"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = ["arn:aws:s3:::buckleupquiz-content-${local.account}", "arn:aws:s3:::buckleupquiz-content-${local.account}/*"]
      },
      # Lambda functions named buckleupquiz-*
      {
        Sid      = "Functions"
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = ["arn:aws:lambda:*:${local.account}:function:buckleupquiz-*", "arn:aws:lambda:*:${local.account}:function:buckleupquiz-*:*"]
      },
      # Log groups under /buckleupquiz/, including reading the error reports
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = "logs:*"
        Resource = ["arn:aws:logs:*:${local.account}:log-group:/buckleupquiz/*", "arn:aws:logs:*:${local.account}:log-group:/buckleupquiz/*:*"]
      },
      {
        Sid      = "LogsDescribe"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups", "logs:GetQueryResults", "logs:StopQuery", "logs:DescribeQueries"]
        Resource = "*"
      },
      # Service roles: only under /buckleupquiz/, only with the boundary, only for Lambda
      {
        Sid       = "ServiceRolesCreate"
        Effect    = "Allow"
        Action    = ["iam:CreateRole", "iam:PutRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:DeleteRolePolicy"]
        Resource  = "arn:aws:iam::${local.account}:role${local.service_path}*"
        Condition = { StringEquals = { "iam:PermissionsBoundary" = local.boundary_arn } }
      },
      {
        Sid    = "ServiceRolesManage"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole",
          "iam:UpdateRoleDescription", "iam:UpdateAssumeRolePolicy", "iam:GetRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
          "iam:ListRoleTags",
        ]
        Resource = "arn:aws:iam::${local.account}:role${local.service_path}*"
      },
      {
        Sid       = "ServiceRolesPass"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = "arn:aws:iam::${local.account}:role${local.service_path}*"
        Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
      },
      {
        Sid      = "NeverRemoveTheBoundary"
        Effect   = "Deny"
        Action   = ["iam:DeleteRolePermissionsBoundary", "iam:PutRolePermissionsBoundary", "iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:SetDefaultPolicyVersion"]
        Resource = "*"
      },
      # CloudFront: read and create anything; change or delete only our tagged distributions
      {
        Sid    = "CloudFrontReadCreate"
        Effect = "Allow"
        Action = [
          "cloudfront:Get*", "cloudfront:List*", "cloudfront:CreateDistribution", "cloudfront:CreateDistributionWithTags",
          "cloudfront:TagResource", "cloudfront:CreateOriginAccessControl", "cloudfront:UpdateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl", "cloudfront:CreateInvalidation",
        ]
        Resource = "*"
      },
      {
        Sid       = "CloudFrontOwnDistributions"
        Effect    = "Allow"
        Action    = ["cloudfront:UpdateDistribution", "cloudfront:DeleteDistribution", "cloudfront:UntagResource"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:ResourceTag/Project" = "buckleupquiz" } }
      },
      # Certificates (us-east-1 for CloudFront)
      {
        Sid      = "Certificates"
        Effect   = "Allow"
        Action   = ["acm:RequestCertificate", "acm:AddTagsToCertificate", "acm:DescribeCertificate", "acm:ListCertificates", "acm:ListTagsForCertificate", "acm:GetCertificate"]
        Resource = "*"
      },
      {
        Sid       = "CertificatesOwnDelete"
        Effect    = "Allow"
        Action    = ["acm:DeleteCertificate", "acm:RemoveTagsFromCertificate"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:ResourceTag/Project" = "buckleupquiz" } }
      },
      # DNS: read everything, change only buckleupquiz.com records
      {
        Sid      = "DnsRead"
        Effect   = "Allow"
        Action   = ["route53:GetHostedZone", "route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:ListResourceRecordSets", "route53:GetChange", "route53:ListTagsForResource", "route53:CreateHostedZone"]
        Resource = "*"
      },
      {
        Sid      = "DnsOwnRecords"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/*"
        Condition = {
          "ForAllValues:StringLike" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = [local.domain, "*.${local.domain}"]
          }
        }
      },
      # Registering and configuring the domain (no transfer, delete or contact changes)
      {
        Sid    = "Domain"
        Effect = "Allow"
        Action = [
          "route53domains:RegisterDomain", "route53domains:GetDomainDetail", "route53domains:GetOperationDetail",
          "route53domains:ListOperations", "route53domains:CheckDomainAvailability", "route53domains:ListPrices",
          "route53domains:ListDomains", "route53domains:UpdateDomainContactPrivacy", "route53domains:EnableDomainAutoRenew",
          "route53domains:EnableDomainTransferLock", "route53domains:ListTagsForDomain", "route53domains:UpdateTagsForDomain",
          "route53domains:GetDomainSuggestions",
        ]
        Resource = "*"
      },
    ]
  })
}

output "deployer_role_arn" {
  value = aws_iam_role.deployer.arn
}

output "service_boundary_arn" {
  value = aws_iam_policy.service_boundary.arn
}
