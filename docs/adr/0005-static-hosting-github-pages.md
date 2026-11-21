# 0005. Host static pages on GitHub Pages, not AWS

- **Status:** Accepted
- **Date:** 2026-11-22

## Context
v1 has no backend. The only hosted things are the **privacy policy** and **support page**,
which App Store Connect requires. The default hosting choice for this project is AWS, unless a
cheaper option made for this job exists.

## Decision
Serve `site/` with **GitHub Pages**, deployed by `.github/workflows/pages.yml` on every push
to `main` that touches `site/`. Before launch, add a custom domain (`buckleupquiz.app`, once
registered) via a `CNAME` file and DNS.

| Option | Monthly cost | Notes |
|---|---|---|
| **GitHub Pages** | **$0** | HTTPS, CDN, custom domain, deploys from the repo |
| AWS S3 + CloudFront | ~$0–1 + $0.50 Route 53 zone | More moving parts (bucket policy, OAC, certificate) |
| AWS Amplify Hosting | ~$0–1 | Fine, but overkill for two static pages |

## Consequences
- Zero cost and zero infrastructure to maintain.
- Needs the repository to stay public (Pages on private repos needs a paid plan).
- If the backend lands on AWS (ADR-0012), the pages can move to CloudFront then. It's a
  DNS change.
