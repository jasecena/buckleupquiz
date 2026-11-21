# The domain, its DNS zone and the TLS certificate (ADR-0021). Things that must exist exactly
# once and outlive everything else, so they have their own state and `prevent_destroy`.
#
#   make infra-domain       (needs contact.auto.tfvars; see contact.auto.tfvars.example)
#
# Registering buckleupquiz.com through Route 53 also creates its hosted zone. Every record
# below goes into that zone. buckleupquiz.com itself points at the GitHub Pages site (privacy
# policy and support pages, ADR-0005), so the website costs nothing extra.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  # bucket is passed at init: -backend-config=bucket=buckleupquiz-tfstate-<account id>
  backend "s3" {
    key          = "domain/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-southeast-2"
  default_tags {
    tags = { Project = "buckleupquiz", ManagedBy = "terraform", Stack = "domain" }
  }
}

variable "domain_name" {
  type    = string
  default = "buckleupquiz.com"
}

# The registrant's details (ICANN requires them). WHOIS privacy hides them publicly.
# Kept in contact.auto.tfvars, which git ignores.
variable "contact" {
  type = object({
    first_name     = string
    last_name      = string
    email          = string
    phone_number   = string # "+61.412345678"
    address_line_1 = string
    city           = string
    state          = string
    zip_code       = string
    country_code   = string # "AU"
  })
  sensitive = true
}

variable "github_pages_host" {
  type    = string
  default = "jasecena.github.io"
}

resource "aws_route53domains_domain" "main" {
  domain_name        = var.domain_name
  duration_in_years  = 1
  auto_renew         = true
  transfer_lock      = true
  admin_privacy      = true
  registrant_privacy = true
  tech_privacy       = true
  billing_privacy    = true

  dynamic "registrant_contact" {
    for_each = [var.contact]
    content {
      contact_type   = "PERSON"
      first_name     = registrant_contact.value.first_name
      last_name      = registrant_contact.value.last_name
      email          = registrant_contact.value.email
      phone_number   = registrant_contact.value.phone_number
      address_line_1 = registrant_contact.value.address_line_1
      city           = registrant_contact.value.city
      state          = registrant_contact.value.state
      zip_code       = registrant_contact.value.zip_code
      country_code   = registrant_contact.value.country_code
    }
  }
  dynamic "admin_contact" {
    for_each = [var.contact]
    content {
      contact_type   = "PERSON"
      first_name     = admin_contact.value.first_name
      last_name      = admin_contact.value.last_name
      email          = admin_contact.value.email
      phone_number   = admin_contact.value.phone_number
      address_line_1 = admin_contact.value.address_line_1
      city           = admin_contact.value.city
      state          = admin_contact.value.state
      zip_code       = admin_contact.value.zip_code
      country_code   = admin_contact.value.country_code
    }
  }
  dynamic "tech_contact" {
    for_each = [var.contact]
    content {
      contact_type   = "PERSON"
      first_name     = tech_contact.value.first_name
      last_name      = tech_contact.value.last_name
      email          = tech_contact.value.email
      phone_number   = tech_contact.value.phone_number
      address_line_1 = tech_contact.value.address_line_1
      city           = tech_contact.value.city
      state          = tech_contact.value.state
      zip_code       = tech_contact.value.zip_code
      country_code   = tech_contact.value.country_code
    }
  }

  timeouts {
    create = "60m"
  }

  lifecycle {
    prevent_destroy = true
    # Contact edits are rare and slow (registrar verification); change them deliberately.
    ignore_changes = [registrant_contact, admin_contact, tech_contact]
  }
}

locals {
  zone_id = aws_route53domains_domain.main.hosted_zone_id
}

# --- Certificate for CloudFront (must be in us-east-1). Free with ACM; renews itself. ---

resource "aws_acm_certificate" "main" {
  region                    = "us-east-1"
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
  lifecycle {
    prevent_destroy       = true
    create_before_destroy = true
  }
}

locals {
  validation = { for o in aws_acm_certificate.main.domain_validation_options : o.domain_name => o }
}

resource "aws_route53_record" "certificate_validation" {
  # The apex and the wildcard share one validation record, so one record keyed by the (known)
  # domain name covers both and Terraform can plan it before the certificate exists.
  for_each        = toset([var.domain_name])
  zone_id         = local.zone_id
  name            = local.validation[each.key].resource_record_name
  type            = local.validation[each.key].resource_record_type
  records         = [local.validation[each.key].resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  region                  = "us-east-1"
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for r in aws_route53_record.certificate_validation : r.fqdn]
}

# --- buckleupquiz.com → GitHub Pages (free hosting for the privacy and support pages) ---

resource "aws_route53_record" "apex_a" {
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 3600
  records = ["185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"]
}

resource "aws_route53_record" "apex_aaaa" {
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "AAAA"
  ttl     = 3600
  records = ["2606:50c0:8000::153", "2606:50c0:8001::153", "2606:50c0:8002::153", "2606:50c0:8003::153"]
}

resource "aws_route53_record" "www" {
  zone_id = local.zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 3600
  records = [var.github_pages_host]
}

# --- No email is sent from this domain: tell receivers to reject anything claiming to be us ---

# All TXT values for the apex live in one record set (Route 53 allows one per name).
resource "aws_route53_record" "spf" {
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 3600
  records = [
    "v=spf1 -all",
    # Apple domain verification (requested by the account holder, 2026-11-22).
    "apple-domain-verification=C9EMenBswkzDSsuD",
  ]
}

resource "aws_route53_record" "dmarc" {
  zone_id = local.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 3600
  records = ["v=DMARC1; p=reject;"]
}

# Only Amazon may issue certificates for the domain.
resource "aws_route53_record" "caa" {
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "CAA"
  ttl     = 3600
  records = ["0 issue \"amazon.com\"", "0 issuewild \"amazon.com\"", "0 issue \"letsencrypt.org\""]
}

output "domain_name" {
  value = var.domain_name
}

output "zone_id" {
  value = local.zone_id
}

output "certificate_arn" {
  value = aws_acm_certificate_validation.main.certificate_arn
}
