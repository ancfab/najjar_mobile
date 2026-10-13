#!/usr/bin/env bash
# Captures one App Store screenshot set by running the Maestro login flow
# against a simulator, for the Codemagic "iOS Screenshots" workflow.
#
# Usage: capture_app_store_screenshots.sh <slot> "<device>,<fallback>,..."
#
#   slot    Output folder under screenshots/, named after the App Store size
#           the set is uploaded to (e.g. iphone-6.9, ipad-13).
#   devices Comma-separated simulator names, tried in order — which device
#           types exist depends on the Xcode version on the build machine.
#
# Every screenshot comes from a real iOS simulator, so the status bar is
# iOS's own: App Store screenshots must never show another platform's
# status bar (App Review guideline 2.3.10).
set -u

SLOT="${1:?usage: capture_app_store_screenshots.sh <slot> <device names>}"
DEVICES="${2:?usage: capture_app_store_screenshots.sh <slot> <device names>}"

BUILD_DIR="${CM_BUILD_DIR:-$(pwd)}"
APP_PATH="$BUILD_DIR/build/ios/iphonesimulator/Runner.app"
FLOW="$BUILD_DIR/maestro/login_flow.yaml"
OUT="$BUILD_DIR/screenshots/$SLOT"

latest_runtime () {
  xcrun simctl list runtimes -j | python3 -c "
import json, sys
runtimes = [r for r in json.load(sys.stdin)['runtimes']
            if r.get('isAvailable') and r['name'].split()[0] in ('iOS', 'iPadOS')]
print(sorted(runtimes, key=lambda r: [int(p) for p in r['version'].split('.')])[-1]['identifier']
      if runtimes else '')
"
}

udid_for () {
  WANTED="$1" xcrun simctl list devices available -j | python3 -c "
import json, os, sys
wanted = os.environ['WANTED']
devices = json.load(sys.stdin)['devices']
print(next((d['udid'] for group in devices.values() for d in group
            if d['name'] == wanted), ''))
"
}

devicetype_for () {
  WANTED="$1" xcrun simctl list devicetypes -j | python3 -c "
import json, os, sys
wanted = os.environ['WANTED']
print(next((t['identifier'] for t in json.load(sys.stdin)['devicetypes']
            if t['name'] == wanted), ''))
"
}

DEVICE_NAME=""
UDID=""
RUNTIME="$(latest_runtime)"

IFS=','
for CANDIDATE in $DEVICES; do
  unset IFS
  [ -z "$CANDIDATE" ] && continue
  FOUND="$(udid_for "$CANDIDATE")"
  if [ -z "$FOUND" ] && [ -n "$RUNTIME" ]; then
    TYPE="$(devicetype_for "$CANDIDATE")"
    if [ -n "$TYPE" ]; then
      FOUND="$(xcrun simctl create "$CANDIDATE" "$TYPE" "$RUNTIME" 2>/dev/null || true)"
    fi
  fi
  if [ -n "$FOUND" ]; then
    DEVICE_NAME="$CANDIDATE"
    UDID="$FOUND"
    break
  fi
  IFS=','
done
unset IFS

if [ -z "$UDID" ]; then
  echo "WARNING: no simulator available for any of: $DEVICES"
  echo "         (skipping the $SLOT set rather than failing the build)"
  exit 0
fi

echo "Capturing '$SLOT' on $DEVICE_NAME ($UDID)"
mkdir -p "$OUT"

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

# The fixed status bar Apple itself uses for store imagery: 9:41, full
# signal, full battery, no carrier name.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --cellularMode active \
  --cellularBars 4 \
  --wifiMode active \
  --wifiBars 3 \
  --batteryState charged \
  --batteryLevel 100 || true

xcrun simctl install "$UDID" "$APP_PATH"

# Maestro writes each screenshot into its working directory.
cd "$OUT"
maestro --device "$UDID" test \
  -e TEST_MOBILE="${TEST_MOBILE:-}" \
  -e TEST_CLIENT="${TEST_CLIENT:-}" \
  -e TEST_PASSWORD="${TEST_PASSWORD:-}" \
  "$FLOW" || echo "WARNING: the Maestro flow reported a failure; keeping whatever it captured"
cd "$BUILD_DIR"

# Some Maestro versions write to ~/.maestro instead; collect those too.
find "$HOME" -name 'screen-*.png' -newer "$APP_PATH" 2>/dev/null | while read -r shot; do
  cp "$shot" "$OUT/" 2>/dev/null || true
done

xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true

echo "'$SLOT' contains:"
ls -la "$OUT"
