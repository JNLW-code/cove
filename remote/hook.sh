#!/bin/sh
# Cove hook for a machine reached over SSH. Hands the event to the Python helper; if anything is missing, exit 0
# with no output so Claude carries on as normal. COVE_TERM names the Mac terminal the SSH session lives in.
export COVE_TERM="${COVE_TERM:-__COVE_TERM__}"
exec python3 "$HOME/.claude/island/cove-hook.py" "$1" 2>/dev/null || exit 0
