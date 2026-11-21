#!/usr/bin/env bash
# Prints an xcodebuild -destination for the newest available iPhone simulator,
# so CI doesn't break when Xcode renames devices.
set -euo pipefail
udid=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(x) for x in runtime.split(".iOS-")[-1].split("-"))
    for d in devices:
        if d["name"].startswith("iPhone") and d.get("isAvailable", True):
            key = (version, d["name"])
            if best is None or key > best[0]:
                best = (key, d["udid"])
print(best[1] if best else "")
')
if [[ -z "$udid" ]]; then
  echo "No available iPhone simulator found" >&2
  exit 1
fi
echo "platform=iOS Simulator,id=$udid"
