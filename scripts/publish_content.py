#!/usr/bin/env python3
"""Build a signed question set for download (ADR-0031). Standard library plus the openssl CLI.

    python3 scripts/publish_content.py --out build/publish --version 1790000000 \
        --min-app-version 0.4.0 --key signing.pem

Writes, ready to upload to the content bucket under `content/v1/`:
    <out>/content/v1/sets/<version>/topics.json
    <out>/content/v1/sets/<version>/questions/<topic>.json
    <out>/content/v1/current.json    (upload last) {"manifest": <base64 of the manifest's JSON>,
                                      "signature": <base64 Ed25519 signature of those bytes>}

One file for the manifest and its signature, so a phone can never get one without the other.

The files are copied byte for byte from Content/, so the app's SHA-256 checks match them.
"""
import argparse
import base64
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

FORMAT = 1
SAFE_QUESTION_FILE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}\.json$")
MAX_FILE_SIZE = 2_000_000  # matches ContentManifest.maxFileSize in the app


def build(content: Path, out: Path, version: int, min_app_version: str) -> dict:
    """Copies the set and returns the manifest (not yet written)."""
    if version <= 0:
        raise ValueError("version must be positive")
    if not re.fullmatch(r"\d+(\.\d+)*", min_app_version):
        raise ValueError(f"bad minAppVersion {min_app_version!r}")
    base = out / "content" / "v1"
    set_dir = base / "sets" / str(version)
    if set_dir.exists():
        shutil.rmtree(set_dir)
    (set_dir / "questions").mkdir(parents=True)

    sources = [("topics.json", content / "topics.json")]
    for path in sorted((content / "questions").glob("*.json")):
        if not SAFE_QUESTION_FILE.match(path.name):
            raise ValueError(f"file name the app would refuse: {path.name}")
        sources.append((f"questions/{path.name}", path))

    files = []
    for rel, src in sources:
        data = src.read_bytes()
        json.loads(data)  # must be JSON; make validate checks the rest
        if not 0 < len(data) <= MAX_FILE_SIZE:
            raise ValueError(f"{rel} is {len(data)} bytes")
        (set_dir / rel).write_bytes(data)
        files.append({"path": rel, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
    return {"format": FORMAT, "version": version, "minAppVersion": min_app_version, "files": files}


def write_current(out: Path, manifest: dict, key: Path) -> Path:
    """The signed manifest, as the app reads it."""
    data = json.dumps(manifest, indent=1, sort_keys=True).encode() + b"\n"
    envelope = {"manifest": base64.b64encode(data).decode(), "signature": base64.b64encode(sign(data, key)).decode()}
    path = out / "content" / "v1" / "current.json"
    path.write_text(json.dumps(envelope, indent=1) + "\n")
    return path


def read_current(data: bytes) -> dict:
    """The manifest inside a current.json (not checking the signature)."""
    return json.loads(base64.b64decode(json.loads(data)["manifest"]))


def sign(data: bytes, key: Path) -> bytes:
    """Ed25519 needs the whole message (-rawin); OpenSSL 3 or later."""
    with tempfile.NamedTemporaryFile() as msg:
        msg.write(data)
        msg.flush()
        result = subprocess.run(["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(key), "-in", msg.name],
                                check=True, capture_output=True)
    if len(result.stdout) != 64:
        raise ValueError("not an Ed25519 signature: is the key Ed25519?")
    return result.stdout


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--content", type=Path, default=Path(__file__).resolve().parents[1] / "Content")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--version", type=int, required=True, help="the commit time (git log -1 --format=%%ct)")
    parser.add_argument("--min-app-version", required=True)
    parser.add_argument("--key", type=Path, required=True, help="Ed25519 private key (PEM)")
    args = parser.parse_args(argv)
    manifest = build(args.content, args.out, args.version, args.min_app_version)
    path = write_current(args.out, manifest, args.key)
    print(f"{len(manifest['files'])} files, version {args.version} -> {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
