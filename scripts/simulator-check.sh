#!/bin/bash
# Builds Lumen for the iPhone simulator, checks it against a pretend WiZ light running on this
# machine, and takes screenshots of the main screens in light and dark mode.
set -eo pipefail

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
c=[x for r,l in d.items() if "iOS" in r for x in l if x["name"].startswith("iPhone") and "Pro" in x["name"] and "Max" not in x["name"]]
c.sort(key=lambda x:x["name"])
print(c[-1]["udid"])')
echo "Using simulator $UDID"

xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Debug -sdk iphonesimulator \
  -destination "id=$UDID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build.log | grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)" || true
grep -q "BUILD SUCCEEDED" build.log || { echo "::error::Build failed"; grep -E "error:" build.log | sort -u | head -80; exit 1; }

APP=build/Build/Products/Debug-iphonesimulator/Lumen.app
BID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"
mkdir -p shots

# 1. End-to-end check against a pretend light.
python3 scripts/fake_bulb.py shots/fake_bulb.log &
BULB=$!
trap 'kill $BULB 2>/dev/null || true' EXIT
sleep 1
ifconfig | grep "inet " || true
xcrun simctl launch --terminate-running-process "$UDID" "$BID" -LumenSelfTest
for i in $(seq 1 45); do
  DATA=$(xcrun simctl get_app_container "$UDID" "$BID" data)
  [ -f "$DATA/Documents/selftest.json" ] && break
  sleep 2
done
echo "--- What the pretend light was asked ---"
head -40 shots/fake_bulb.log || true
if [ -f "$DATA/Documents/selftest.json" ]; then
  cp "$DATA/Documents/selftest.json" shots/selftest.json
  python3 -m json.tool shots/selftest.json
  grep -q '"all passed"' shots/selftest.json || { echo "::error::Self-check against the pretend light failed"; exit 1; }
else
  echo "::error::Self-check produced no result"
  exit 1
fi
xcrun simctl terminate "$UDID" "$BID" || true
kill $BULB 2>/dev/null || true

# 2. Screenshots with a pretend home.
shoot() { # name, extra args
  local name=$1; shift
  xcrun simctl launch --terminate-running-process "$UDID" "$BID" "$@"
  sleep 6
  xcrun simctl io "$UDID" screenshot "shots/$name.png"
}
for mode in light dark; do
  xcrun simctl ui "$UDID" appearance $mode
  shoot "home-$mode" -LumenDemo
  shoot "room-$mode" -LumenDemo -LumenDemoRoom
  shoot "colour-$mode" -LumenDemo -LumenDemoColour
  shoot "scenes-$mode" -LumenDemo -LumenDemoScenes
  shoot "mood-$mode" -LumenDemo -LumenDemoMood
  shoot "settings-$mode" -LumenDemo -LumenDemoSettings
  shoot "welcome-$mode" -LumenDemoWelcome
done
ls -la shots
