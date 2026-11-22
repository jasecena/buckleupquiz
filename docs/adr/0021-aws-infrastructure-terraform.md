# 0021. AWS infrastructure with Terraform: domain, content CDN and error reports

- **Status:** Accepted
- **Date:** 2026-11-22
- **Relates to:** [ADR-0012](0012-future-backend.md) (backend direction), [ADR-0019](0019-natural-voice-packs.md) (voice packs), [ADR-0020](0020-anonymous-error-telemetry.md) (error reports; replaces its CloudFormation template), [ADR-0005](0005-static-hosting-github-pages.md) (website)

## Context
The app now needs a server for anonymous error reports (ADR-0020). Question packs (ADR-0012) and
natural voice packs (ADR-0019) will follow. Product direction (2026-11-22):
- Use **Terraform** so everything comes up at once.
- One-time things (state bucket, domain) must be created **only once**, with no race conditions.
  Several state files are fine.
- Register **buckleupquiz.com** with AWS.
- Keep the cost **as low as possible**.

## Decision

### One AWS account and region, three Terraform stacks
Region **ap-southeast-2** (Sydney). The ACM certificate for CloudFront lives in us-east-1, set per
resource (AWS provider v6). Code is in `infra/terraform/`, run through `make`:

| Stack | State | What | How often |
|---|---|---|---|
| `bootstrap` | local, copied to S3 | the state bucket `buckleupquiz-tfstate-<account>` | once per account |
| `domain` | `s3://…/domain/terraform.tfstate` | **buckleupquiz.com** registration (auto-renew, WHOIS privacy, transfer lock), its Route 53 zone, a wildcard **ACM certificate**, apex/www → GitHub Pages, SPF/DMARC "we send no email", CAA | once, rarely changed |
| `platform` | `s3://…/platform/terraform.tfstate` | content bucket, **CloudFront** `api.buckleupquiz.com`, error-report **Lambda function URL**, log group | every change |

**Only once, with no races:**
- Each stack has its own state. Splitting them means a mistake in `platform` can never touch the domain.
- State locking uses **S3 native lock files** (`use_lockfile`, Terraform ≥ 1.10), so two applies
  of the same stack can't run at once. There's no DynamoDB table.
- Bucket names are derived from the account ID. Re-running bootstrap finds the same bucket and
  never creates a second one.
- The domain, zone, certificate and buckets have `prevent_destroy`.
- Registering the domain also creates its hosted zone. The stack uses that zone rather than
  making another.
- `platform` finds the zone and certificate by **name**, not through `terraform_remote_state`,
  so it doesn't depend on another stack's state file. With `use_custom_domain = false` it can be
  applied before the domain exists, answering on its `*.cloudfront.net` name.

### Access: least privilege in a shared account
The account (ap-southeast-2) also hosts other projects, so:
- **Bootstrap is the only stack run as admin** (`AWS_PROFILE=<admin> make infra-bootstrap`).
  Along with the state bucket, it creates:
  - **`buckleupquiz-deployer`**, a role only the admin principal can assume. Its policy allows
    only BuckleUp Quiz things: `buckleupquiz-content-*` buckets, `buckleupquiz-*` functions,
    `/buckleupquiz/*` log groups (including reading reports), its own state objects, DNS changes
    limited to `buckleupquiz.com` names
    (`route53:ChangeResourceRecordSetsNormalizedRecordNames`), CloudFront and ACM changes or
    deletes only on resources tagged `Project=buckleupquiz`, and registering (not transferring
    or deleting) the domain.
  - **`buckleupquiz/service-boundary`**, a permissions boundary. The deployer can create roles
    only under `/buckleupquiz/`, only with this boundary attached, and only for Lambda. So even a
    role it creates can do no more than write its own logs and read content. Removing a
    boundary is explicitly denied.
- On this machine, the `buckleupquiz` profile is `role_arn = …:role/buckleupquiz-deployer`
  plus `source_profile = <admin>`. No new long-lived keys. Checked: listing the account's
  buckets, functions or users is denied.
- **The app has no AWS credentials.** It only calls public HTTPS URLs. Keys in an app binary
  can be extracted by anyone.

### What the app uses
| URL | Method | Behind it |
|---|---|---|
| `https://api.buckleupquiz.com/v1/reports` | POST | Lambda function URL → CloudWatch Logs `/buckleupquiz/telemetry` (90 days) |
| `https://api.buckleupquiz.com/content/v1/…` | GET | S3 (private, CloudFront OAC only): signed question sets (ADR-0031), written by the `buckleupquiz-content-publisher` role from GitHub Actions |
| `https://api.buckleupquiz.com/voices/…` | GET | S3: natural voice packs (ADR-0019), later |
| `https://buckleupquiz.com` | GET | GitHub Pages: privacy policy and support (free) |

### Cost choices
- **Lambda function URL** instead of API Gateway: no per-request API Gateway charge. arm64,
  128 MB, 5 s timeout. Within the free tier (1 M requests a month).
- **One CloudFront distribution** for content and reports. Always-free tier: 1 TB and 10 M
  requests a month. `PriceClass_All` because the families are in Australia; it's free at this
  volume anyway. No access logs.
- **SSE-S3** encryption (free), not KMS ($1 a month per key). Old object versions expire after
  30 days (content) or 90 days (state).
- **S3 lock files**, not a DynamoDB lock table.
- The website stays on **GitHub Pages** (free). DNS just points the apex there.
- Expected bill: about **US$0.50 a month** (Route 53 hosted zone) plus the **.com registration
  (US$16 a year, checked 2026-11-22)**, plus cents for logs and storage. That's roughly
  **US$22 a year**.

### Family data
Not here. Players, progress and scores keep syncing through the family's own iCloud
(CloudKit, ADR-0012) unless a separate ADR decides we need our own database.

## Running it
```sh
AWS_PROFILE=<admin> make infra-bootstrap   # once per account: state bucket, deployer role
aws configure set role_arn arn:aws:iam::<account>:role/buckleupquiz-deployer --profile buckleupquiz
aws configure set source_profile <admin> --profile buckleupquiz
export AWS_PROFILE=buckleupquiz      # everything below runs least-privilege
make infra-check                     # who am I, is the domain available, its price
cp infra/terraform/domain/contact.auto.tfvars.example infra/terraform/domain/contact.auto.tfvars
make infra-domain                    # registers the domain (charged once a year)
make infra-platform                  # NO_DOMAIN=1 to deploy before the certificate exists
```
Then put `reports_url` from the platform outputs into `project.yml` as `TELEMETRY_URL`.

## Alternatives considered
- **CloudFormation or CDK** (ADR-0012 suggested CDK): the product owner asked for Terraform.
  It's also one tool for AWS and GitHub, if needed later.
- **One state for everything**: simpler, but a platform mistake could plan a domain or bucket
  change, and every apply would lock the domain too.
- **API Gateway HTTP API**: request validation and throttling, but costs per request after its
  free year. The function URL plus CloudFront is enough at this size.
- **Cloudflare (registrar at cost, R2 with no egress fees)**: cheaper at large scale, but a
  second provider. Kept as the exit route for voice-pack egress (ADR-0019).

## Consequences
- The app has a stable domain for every future network feature. Changing what's behind a path
  doesn't need an app update.
- Registration details for the domain are kept in `contact.auto.tfvars`, which git ignores,
  never in the repo.
- Any CI that applies Terraform needs AWS credentials. Today applies are run by hand.
- **Deployed 2026-11-22:** bootstrap, domain (buckleupquiz.com registered, wildcard certificate
  issued) and platform on **api.buckleupquiz.com**. buckleupquiz.com serves the GitHub Pages
  site (custom domain set on the repo's Pages). Builds v0.3.3–v0.3.4 send reports to
  `d3fmbcooclif09.cloudfront.net`, which stays valid; v0.3.5 onwards use api.buckleupquiz.com.
