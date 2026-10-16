#!/bin/sh
# Sets up Cove for Claude Code sessions on a machine you reach over SSH.
#   scripts/install-remote.sh <ssh host> [port]
# On the server: ~/.claude/island/{cove-hook.py, hook.sh, settings-snippet.json} and Cove's entries in settings.json.
# On this Mac: a RemoteForward line in ~/.ssh/config so the server's localhost:<port> is Cove's socket.
# Then reconnect (ssh <host>) and start a Claude Code session there.
set -eu
HOST="${1:?usage: install-remote.sh <ssh host> [port]}"
PORT="${2:-47925}"
# Works from the repo (scripts/), from the DMG folder (everything next to this file), or on its own: then the
# files come from GitHub, so `curl -fsSL https://raw.githubusercontent.com/JNLW-code/cove/main/scripts/install-remote.sh | sh -s vps` is enough.
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"
if [ -f "$HERE/cove-hook.py" ]; then R="$HERE"; SNIP="$HERE/settings-snippet.json"
elif [ -f "$HERE/../remote/cove-hook.py" ]; then R="$HERE/../remote"; SNIP="$HERE/../hooks/settings-snippet.json"
else
  R="$(mktemp -d)"; SNIP="$R/settings-snippet.json"
  BASE="https://raw.githubusercontent.com/JNLW-code/cove/main"
  echo "== fetching the server files from GitHub"
  for f in remote/cove-hook.py remote/hook.sh remote/merge-settings.py hooks/settings-snippet.json; do
    curl -fsSL "$BASE/$f" -o "$R/$(basename "$f")" || { echo "Could not download $f"; exit 1; }
  done
fi
SOCK="$HOME/Library/Application Support/Cove/cove.sock"
TERM_NAME="${TERM_PROGRAM:-Apple_Terminal}"
echo "== $HOST: hook files"
ssh "$HOST" 'mkdir -p ~/.claude/island && test -d ~/.claude' || { echo "No ~/.claude on $HOST: run Claude Code there once first."; exit 1; }
sed "s/__COVE_TERM__/$TERM_NAME/" "$R/hook.sh" > "/tmp/cove-hook.sh.$$"
scp -q "$R/cove-hook.py" "$R/merge-settings.py" "$SNIP" "$HOST:~/.claude/island/"
scp -q "/tmp/cove-hook.sh.$$" "$HOST:~/.claude/island/hook.sh"; rm -f "/tmp/cove-hook.sh.$$"
ssh "$HOST" 'chmod 755 ~/.claude/island/hook.sh ~/.claude/island/cove-hook.py && python3 --version && python3 ~/.claude/island/merge-settings.py'
echo "== this Mac: ~/.ssh/config"
mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
if grep -q "Cove: $HOST" "$HOME/.ssh/config"; then
  echo "RemoteForward for $HOST already there."
else
  printf '\n# Cove: %s (the notch for Claude Code sessions on this host)\nHost %s\n  RemoteForward 127.0.0.1:%s "%s"\n' "$HOST" "$HOST" "$PORT" "$SOCK" >> "$HOME/.ssh/config"
  echo "Added RemoteForward 127.0.0.1:$PORT -> Cove's socket for Host $HOST."
fi
ssh -G "$HOST" | grep -i "^remoteforward" || { echo "ssh does not see the forward; check ~/.ssh/config"; exit 1; }
echo "Done. Reconnect with: ssh $HOST   then start a Claude Code session there and hover the notch."
