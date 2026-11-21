# infra/

AWS infrastructure in Terraform ([ADR-0021](../docs/adr/0021-aws-infrastructure-terraform.md)).
Three stacks, each with its own state, so one-time things are created once and never touched
by everyday changes:

| Stack | What | Run |
|---|---|---|
| [`terraform/bootstrap`](terraform/bootstrap/main.tf) | Terraform state bucket | once per account: `make infra-bootstrap` |
| [`terraform/domain`](terraform/domain/main.tf) | buckleupquiz.com, DNS zone, certificate, website records | once: `make infra-domain` |
| [`terraform/platform`](terraform/platform/main.tf) | `api.buckleupquiz.com`: content bucket + CloudFront, error reports (Lambda) | `make infra-platform` |

```sh
AWS_PROFILE=<admin> make infra-bootstrap   # once: state bucket + least-privilege deployer role
export AWS_PROFILE=buckleupquiz            # role_arn = buckleupquiz-deployer, source_profile = <admin>
make infra-check        # account, domain availability and price
cp infra/terraform/domain/contact.auto.tfvars.example infra/terraform/domain/contact.auto.tfvars  # fill in
make infra-domain
make infra-platform     # NO_DOMAIN=1 before the certificate is issued
make infra-plan         # later: see what would change
```

`site/` is still hosted on GitHub Pages ([ADR-0005](../docs/adr/0005-static-hosting-github-pages.md));
the domain stack points buckleupquiz.com at it.
