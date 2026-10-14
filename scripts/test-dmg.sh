#!/bin/sh
# Mounts build/Cove.dmg, runs its install script against a scratch HOME and checks what it left behind.
set -eu
DMG="${1:-build/Cove.dmg}"
MNT="$(mktemp -d)/mnt"
SCRATCH="$(mktemp -d)"
mkdir -p "$MNT" "$SCRATCH/.claude"
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" >/dev/null
trap 'hdiutil detach "$MNT" -quiet || true; rm -rf "$SCRATCH"' EXIT
echo "== contents"; ls -1 "$MNT"
echo "== app signature"; codesign --verify --verbose=1 "$MNT/Cove.app" 2>&1
echo "== install script against a scratch home"
HOME="$SCRATCH" COVE_NO_OPEN=1 sh "$MNT/Install Hooks.command"
test -x "$SCRATCH/.claude/island/hook.sh" && test -x "$SCRATCH/.claude/island/cove-hook" && echo "hook files installed and executable"
grep -q 'exec "$HOME/.claude/island/cove-hook"' "$SCRATCH/.claude/island/hook.sh" && echo "hook.sh uses \$HOME, not a fixed path"
echo "== helper runs with no Cove socket (expect: no output, exit 0)"
printf '{"session_id":"x","cwd":"/tmp"}' | HOME="$SCRATCH" "$SCRATCH/.claude/island/cove-hook" SessionStart; echo "exit $?"
echo "== snippet is valid JSON"; python3 -I -c 'import json,sys; json.load(open(sys.argv[1])); print("ok")' "$MNT/Hooks/settings-snippet.json"
echo "DMG test passed"
