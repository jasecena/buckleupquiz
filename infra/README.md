# infra/

Infrastructure as code. See [ADR-0012](../docs/adr/0012-future-backend.md) for the backend
direction. `site/` is hosted on GitHub Pages ([ADR-0005](../docs/adr/0005-static-hosting-github-pages.md))
and needs nothing here.

| Folder | What | ADR |
|---|---|---|
| [`telemetry/`](telemetry/template.yaml) | Anonymous error reports endpoint (Lambda function URL + CloudWatch Logs, ap-southeast-2) | [0020](../docs/adr/0020-anonymous-error-telemetry.md) |

## Deploying the telemetry endpoint
```sh
aws cloudformation deploy --region ap-southeast-2 --stack-name buckleupquiz-telemetry \
  --template-file infra/telemetry/template.yaml --capabilities CAPABILITY_IAM
aws cloudformation describe-stacks --region ap-southeast-2 --stack-name buckleupquiz-telemetry \
  --query "Stacks[0].Outputs[?OutputKey=='Endpoint'].OutputValue" --output text
```
Put the endpoint URL in `project.yml` as `TELEMETRY_URL` and release a new build.
