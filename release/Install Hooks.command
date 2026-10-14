#!/bin/sh
# Puts Cove's hook script and helper where Claude Code can call them, then opens the settings snippet to paste.
# Double-click this file. If macOS says it cannot be opened, right-click it and choose Open.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/island"
if [ ! -d "$HOME/.claude" ]; then
  echo "No ~/.claude folder: install and run Claude Code once first, then run this again."
  exit 1
fi
mkdir -p "$DEST"
cp "$HERE/Hooks/hook.sh" "$HERE/Hooks/cove-hook" "$DEST/"
chmod 755 "$DEST/hook.sh" "$DEST/cove-hook"
# Files copied off a downloaded disk image carry the quarantine flag; the helper must run without a prompt.
xattr -d com.apple.quarantine "$DEST/hook.sh" "$DEST/cove-hook" 2>/dev/null || true
echo "Installed hook.sh and cove-hook in $DEST"
echo
echo "Last step: paste the hooks into $HOME/.claude/settings.json."
echo "The snippet is opening in TextEdit. Put its entries inside the \"hooks\" object of settings.json"
echo "(create \"hooks\": { } if there is none). Claude Code picks the change up on its own."
if [ -z "${COVE_NO_OPEN:-}" ]; then
  open -a TextEdit "$HERE/Hooks/settings-snippet.json" 2>/dev/null || open "$HERE/Hooks/settings-snippet.json"
fi
