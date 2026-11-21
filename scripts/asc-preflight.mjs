#!/usr/bin/env node
// App Store Connect preflight for the release workflow.
//
// Fails in seconds, before a 20-minute archive, when the account is not ready:
//   1. The bundle id is registered as an App ID. If it isn't, this registers it
//      (needs an API key allowed to manage identifiers; otherwise Xcode's
//      -allowProvisioningUpdates registers it during the archive).
//   2. An App Store Connect *app record* exists for the bundle id. The API cannot
//      create one, so this explains how to make it in the web UI.
//
// No dependencies, same JWT approach as asc-certificates.mjs.
//
// Usage: node scripts/asc-preflight.mjs <bundle-id> [app-name]
// Env:   ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH or ASC_PRIVATE_KEY

import { sign } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';

const API = 'https://api.appstoreconnect.apple.com/v1';

const die = (message) => {
  console.error(`::error::asc-preflight: ${message}`);
  process.exit(1);
};
const env = (name) => process.env[name] || die(`${name} is not set.`);

function privateKey() {
  if (process.env.ASC_PRIVATE_KEY) return process.env.ASC_PRIVATE_KEY;
  const path = env('ASC_KEY_PATH');
  if (!existsSync(path)) die(`ASC_KEY_PATH points at ${path}, which does not exist.`);
  return readFileSync(path, 'utf8');
}

const base64url = (value) => Buffer.from(value).toString('base64url');

function token() {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: env('ASC_KEY_ID'), typ: 'JWT' }));
  const payload = base64url(JSON.stringify({ iss: env('ASC_ISSUER_ID'), iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }));
  // Apple wants the raw r‖s signature, not Node's default DER.
  const signature = sign('sha256', Buffer.from(`${header}.${payload}`), { key: privateKey(), dsaEncoding: 'ieee-p1363' });
  return `${header}.${payload}.${base64url(signature)}`;
}

async function call(jwt, path, { method = 'GET', body } = {}) {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  return { ok: response.ok, status: response.status, json: text ? JSON.parse(text) : null };
}

async function main() {
  const [bundleId, appName = 'BuckleUp Quiz'] = process.argv.slice(2);
  if (!bundleId) die('usage: asc-preflight.mjs <bundle-id> [app-name]');
  const jwt = token();

  // 1. App ID.
  const ids = await call(jwt, `/bundleIds?filter[identifier]=${encodeURIComponent(bundleId)}&limit=200`);
  if (ids.status === 401) die('App Store Connect rejected the API key (401). Check the Key ID / Issuer ID pair and the .p8.');
  if (!ids.ok) die(`listing bundle ids failed: ${ids.status} ${JSON.stringify(ids.json)}`);
  const exact = ids.json.data.find((d) => d.attributes.identifier === bundleId);
  if (exact) {
    console.log(`App ID ${bundleId} is registered.`);
  } else {
    const created = await call(jwt, '/bundleIds', {
      method: 'POST',
      body: { data: { type: 'bundleIds', attributes: { identifier: bundleId, name: appName, platform: 'IOS' } } },
    });
    if (created.ok) console.log(`Registered App ID ${bundleId}.`);
    else console.log(`::warning::Could not register App ID ${bundleId} (${created.status}); Xcode will try during the archive.`);
  }

  // 2. App record.
  const apps = await call(jwt, `/apps?filter[bundleId]=${encodeURIComponent(bundleId)}`);
  if (!apps.ok) die(`listing apps failed: ${apps.status} ${JSON.stringify(apps.json)}`);
  const app = apps.json.data.find((d) => d.attributes.bundleId === bundleId);
  if (!app) {
    die(
      `No App Store Connect app record for ${bundleId}. Create it once in the web UI ` +
        `(App Store Connect → Apps → + → New App: platform iOS, name "${appName}", bundle id ${bundleId}, ` +
        `SKU buckleupquiz), then re-run this workflow. The API cannot create app records.`,
    );
  }
  console.log(`App record found: "${app.attributes.name}" (Apple ID ${app.id}).`);
}

await main();
