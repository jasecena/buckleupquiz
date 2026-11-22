"""Unit tests for scripts/publish_content.py (ADR-0031)."""
import base64
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publish_content as pc  # noqa: E402

REPO_CONTENT = Path(__file__).resolve().parents[2] / "Content"


class PublishContentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)

    def test_copies_every_file_byte_for_byte_with_hashes(self):
        manifest = pc.build(REPO_CONTENT, self.tmp, 1790000000, "0.4.0")
        self.assertEqual(manifest["format"], 1)
        self.assertEqual(manifest["files"][0]["path"], "topics.json")
        expected = 1 + len(list((REPO_CONTENT / "questions").glob("*.json")))
        self.assertEqual(len(manifest["files"]), expected)
        for f in manifest["files"]:
            data = (self.tmp / "content/v1/sets/1790000000" / f["path"]).read_bytes()
            self.assertEqual(data, (REPO_CONTENT / f["path"]).read_bytes())
            self.assertEqual(f["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual(f["size"], len(data))

    def test_refuses_names_the_app_would_refuse(self):
        content = self.tmp / "c"
        (content / "questions").mkdir(parents=True)
        (content / "topics.json").write_text("[]")
        (content / "questions" / "Bad Name.json").write_text("[]")
        with self.assertRaises(ValueError):
            pc.build(content, self.tmp / "out", 1, "0.4.0")

    def test_refuses_bad_versions(self):
        with self.assertRaises(ValueError):
            pc.build(REPO_CONTENT, self.tmp, 0, "0.4.0")
        with self.assertRaises(ValueError):
            pc.build(REPO_CONTENT, self.tmp, 1, "latest")

    @unittest.skipUnless(shutil.which("openssl"), "needs openssl")
    def test_signature_verifies_with_the_public_key(self):
        key = self.tmp / "key.pem"
        pub = self.tmp / "pub.pem"
        subprocess.run(["openssl", "genpkey", "-algorithm", "ed25519", "-out", str(key)], check=True)
        subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(pub)], check=True)
        manifest = pc.build(REPO_CONTENT, self.tmp, 1790000000, "0.4.0")
        path = pc.write_current(self.tmp, manifest, key)
        self.assertEqual(pc.read_current(path.read_bytes()), manifest)
        envelope = json.loads(path.read_text())
        signed = self.tmp / "manifest.bin"
        signed.write_bytes(base64.b64decode(envelope["manifest"]))
        sig = self.tmp / "sig.bin"
        sig.write_bytes(base64.b64decode(envelope["signature"]))
        result = subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-inkey", str(pub),
                                 "-in", str(signed), "-sigfile", str(sig)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
