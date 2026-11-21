// BuckleUp Quiz anonymous error reports (ADR-0020). Validates a batch from the app and logs
// each event as structured JSON. Never logs the request's IP address or headers.
const MAX_BODY = 1000000;
const NAME = /^[A-Za-z0-9._-]{1,64}$/;
const str = (v, n) => (typeof v === "string" ? v.slice(0, n) : undefined);

exports.handler = async (event) => {
  if (event.requestContext?.http?.method !== "POST") return { statusCode: 405 };
  let body = event.body || "";
  if (event.isBase64Encoded) body = Buffer.from(body, "base64").toString("utf8");
  if (body.length > MAX_BODY) return { statusCode: 413 };
  let p;
  try { p = JSON.parse(body); } catch { return { statusCode: 400 }; }
  if (p?.schema !== 1 || !Array.isArray(p.events) || p.events.length > 50) {
    return { statusCode: 400 };
  }
  const context = {
    app: str(p.app, 16), build: str(p.build, 16), os: str(p.os, 32),
    device: str(p.device, 32), launch: str(p.launch, 40),
  };
  for (const e of p.events) {
    if (!e || !NAME.test(e.name || "")) continue;
    const fields = {};
    for (const [k, v] of Object.entries(e.fields || {}).slice(0, 20)) {
      if (NAME.test(k) && typeof v === "string") fields[k] = v.slice(0, 60000);
    }
    console.info({ kind: "telemetry", ...context, name: e.name, at: str(e.at, 32), fields });
  }
  return { statusCode: 204 };
};
