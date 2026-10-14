#!/bin/sh
# End-to-end Sparkle test on this Mac: builds the current version, makes a "-test" build with a higher build number,
# serves it from a local appcast, launches the current build in test mode and lets it update itself. No GitHub involved.
set -eu
cd "$(dirname "$0")/.."
make build >/dev/null
V="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Cove.app/Contents/Info.plist)"
T="$(mktemp -d)"; trap 'kill $SERVER 2>/dev/null || true; rm -rf "$T"' EXIT
mkdir -p "$T/next" "$T/serve"
cp -R build/Cove.app "$T/next/Cove.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V-test" -c "Set :CFBundleVersion 99999" "$T/next/Cove.app/Contents/Info.plist"
codesign --force --sign "Cove Dev" --identifier com.jameswebster.cove "$T/next/Cove.app"
hdiutil create -volname "Cove test" -srcfolder "$T/next" -ov -format UDZO -quiet "$T/serve/Cove.dmg"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --download-url-prefix "http://127.0.0.1:8765/" -o "$T/serve/appcast.xml" "$T/serve" >/dev/null
grep -o 'sparkle:version="[^"]*"\|sparkle:shortVersionString="[^"]*"' "$T/serve/appcast.xml" | tr '\n' ' '; echo
( cd "$T/serve" && python3 -I -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 ) & SERVER=$!
sleep 1
pkill -x Cove 2>/dev/null || true; sleep 0.5
COVE_UI_TEST=1 COVE_FEED=http://127.0.0.1:8765/appcast.xml build/Cove.app/Contents/MacOS/Cove >/dev/null 2>&1 &
sleep 3
notifyutil -p com.jameswebster.cove.test.update
echo "waiting for Cove $V-test to launch itself..."
for i in $(seq 1 60); do
  sleep 1
  if /usr/bin/log show --predicate 'subsystem == "com.jameswebster.cove"' --last 2m --style compact 2>/dev/null | grep -q "Cove $V-test launched"; then
    echo "updated and relaunched after ${i}s"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Cove.app/Contents/Info.plist
    /usr/bin/log show --predicate 'subsystem == "com.jameswebster.cove"' --last 2m --style compact 2>/dev/null | grep -i "update" | tail -4
    pkill -x Cove 2>/dev/null || true
    echo "update test passed (build/Cove.app is now the test build; make build puts the real one back)"
    exit 0
  fi
done
echo "update did not happen; log:"
/usr/bin/log show --predicate 'subsystem == "com.jameswebster.cove"' --last 2m --style compact 2>/dev/null | grep -i "update\|launched" | tail -8
exit 1
