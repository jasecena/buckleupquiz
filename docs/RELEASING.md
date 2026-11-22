# Releasing to TestFlight

Releases are built, signed and uploaded by GitHub Actions
([`ios-release.yml`](../.github/workflows/ios-release.yml)). No Mac is needed. This is the same
pipeline as the activity-tracker app ([ADR-0014](adr/0014-testflight-release-pipeline.md)).

## One-time setup

1. **App Store Connect app record** (the API can't create it):
   App Store Connect → **Apps → + → New App**
   - Platform: iOS · Name: **BuckleUp Quiz** · Primary language: English (Australia)
   - Bundle ID: **`com.jcena.buckleupquiz`** (if it's not in the list yet, run the release
     workflow once; its preflight registers it. Or add it under Certificates, Identifiers &
     Profiles → Identifiers.)
   - SKU: `buckleupquiz` · User access: Full Access
2. **Repository configuration** (variables are already set):

   | Kind | Name | Value |
   |---|---|---|
   | variable | `IOS_BUNDLE_IDENTIFIER` | `com.jcena.buckleupquiz` |
   | variable | `APPLE_TEAM_ID` | your 10-character team id |
   | secret | `APP_STORE_CONNECT_KEY_ID` | 10-character key id (the `AuthKey_<id>.p8` filename) |
   | secret | `APP_STORE_CONNECT_ISSUER_ID` | UUID shown above the key list in App Store Connect → Users and Access → Integrations |
   | secret | `APP_STORE_CONNECT_PRIVATE_KEY` | the whole `.p8` file |

   ```sh
   R=jasecena/buckleupquiz
   gh secret set APP_STORE_CONNECT_KEY_ID      -R $R --body "<KEY_ID>"
   gh secret set APP_STORE_CONNECT_ISSUER_ID   -R $R          # paste the UUID when prompted
   gh secret set APP_STORE_CONNECT_PRIVATE_KEY -R $R < ~/Downloads/AuthKey_<KEY_ID>.p8
   ```
   The key needs the **App Manager** (or Admin) role. The activity-tracker key works.

## Ship a build

1. **Rehearse** (recommended the first time): Actions → *iOS Release* → *Run workflow*. Untick
   "Upload" for a signed build that isn't uploaded.
2. **Release:** bump nothing by hand. The tag is the version, and the build number is the run
   number:
   ```sh
   git tag v0.1.0 && git push origin v0.1.0
   ```
3. After 5–30 minutes the build appears in App Store Connect → TestFlight.
   - **Internal testers** in the **Family** group (gets every build automatically; add
     people under TestFlight → Internal Testing → Family) can install straight away from the
     TestFlight app, using the same Apple ID they were invited with.
   - **External testers** need a short Beta App Review, plus a test description and contact
     details.

## Publishing questions (ADR-0031)

New and fixed questions reach phones without an app update. Apps from 0.4.0 check at most every
12 hours and use the new questions from the next game.

### One-time setup
1. **Signing key:** `make content-signing-key`. It saves the private key only as the GitHub
   secret `CONTENT_SIGNING_KEY`, and writes the public key into `project.yml`
   (`CONTENT_PUBLIC_KEY`). Commit and push that, then release an app build. Builds without the
   public key never download.
2. **AWS publisher role:** `make infra-bootstrap`, with your admin sign-in. It adds GitHub's
   OIDC sign-in and the `buckleupquiz-content-publisher` role, which can only write under
   `content/` in the content bucket, and only from `main`. If the account already has a GitHub
   OIDC provider (another project), pass it:
   `terraform -chdir=infra/terraform/bootstrap apply -var github_oidc_provider_arn=<arn>`.
3. **GitHub variable:** the bootstrap output `content_publisher_role_arn`:
   ```sh
   gh variable set CONTENT_PUBLISH_ROLE_ARN --body "$(terraform -chdir=infra/terraform/bootstrap output -raw content_publisher_role_arn)"
   ```

### Each time
1. Merge the content pull request and wait for CI on `main` to pass.
2. Actions → **Publish questions** → *Run workflow*. Keep the app version at `0.4.0` unless the
   questions use something only a newer app can read.
3. To check: `curl -s https://api.buckleupquiz.com/content/v1/current.json` shows the signed
   manifest. On a phone, questions arrive the next time the app is opened (12 hours at most).

To undo a bad question, revert the commit and publish again. A set that fails any check on the
phone is thrown away, and the app keeps the questions it had (it reports `content.updateRefused`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Missing required configuration` | Set the variable or secret it names (table above) |
| Preflight: `No App Store Connect app record` | Do one-time setup step 1, then re-run |
| 401 from App Store Connect | Key ID and Issuer ID swapped, or the wrong `.p8` |
| "maximum number of certificates" | Actions → *Certificates* → `list`, then `revoke-all` (type `revoke`) |
| "team has no devices" | Register any iPhone under Certificates, Identifiers & Profiles → Devices |
| Upload: build number already used | Re-run the workflow (new run number) rather than re-running the failed job |

## Reading error reports (ADR-0020)
Reports land in CloudWatch Logs (`/buckleupquiz/telemetry`, ap-southeast-2). In the console,
open **CloudWatch → Logs Insights**, pick that log group, and run, for example:

```
# What's failing, by iPhone and iOS
fields message.name as name, message.device as device, message.os as os, message.fields.error as error
| filter message.kind = "telemetry" and name like /Failed|noPermission|noOnDevice/
| stats count() as n by name, device, os, error
| sort n desc

# How well voice answers are heard in real games
fields message.fields.right as right, message.fields.wrong as wrong, message.fields.unclear as unclear,
       message.fields.silent as silent, message.fields.input as input
| filter message.name = "game.finished" and message.fields.mode = "voice"
| stats count() as games, sum(right) as r, sum(wrong) as w, sum(unclear) as u, sum(silent) as s by input
```

Before the first **public** release, update the App Store privacy label to
"Data Not Linked to You → Diagnostics (Crash Data, Performance Data, Other Diagnostic Data)".
