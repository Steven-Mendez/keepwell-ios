#!/bin/bash
# Prints an xcodebuild destination for an available iPhone simulator.
# Prefers $SIMULATOR_NAME (default "iPhone 17e", available locally and on the CI runner).
set -euo pipefail

PREFERRED="${SIMULATOR_NAME:-iPhone 17e}"
DEVICES="$(xcrun simctl list devices available -j)"

udid="$(/usr/bin/python3 -c '
import json, sys
preferred = sys.argv[1]
data = json.loads(sys.stdin.read())["devices"]
ios = [(rt, d) for rt, ds in data.items() if "iOS" in rt for d in ds if d.get("isAvailable")]
ios.sort(key=lambda p: [int(x) for x in p[0].rsplit("iOS-", 1)[-1].split("-")[:2] if x.isdigit()], reverse=True)
match = next((d for _, d in ios if d["name"] == preferred), None) \
    or next((d for _, d in ios if d["name"].startswith("iPhone")), None)
print(match["udid"] if match else "")
' "$PREFERRED" <<<"$DEVICES")"

if [ -z "$udid" ]; then
  echo "No iPhone simulator available. Create one, e.g.:" >&2
  echo "  xcrun simctl create \"$PREFERRED\" com.apple.CoreSimulator.SimDeviceType.${PREFERRED// /-} <iOS runtime id>" >&2
  echo "(list runtimes with: xcrun simctl list runtimes)" >&2
  exit 1
fi
echo "platform=iOS Simulator,id=$udid"
