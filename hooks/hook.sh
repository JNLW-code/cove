#!/bin/sh
# Called by every Claude Code hook with the event name. Hands the event to the compiled helper.
# If the helper is missing or fails, exit 0 with no output so Claude carries on as normal.
exec "$HOME/.claude/island/cove-hook" "$1" 2>/dev/null || exit 0
