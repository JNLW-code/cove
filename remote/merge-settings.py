#!/usr/bin/env python3
"""Adds Cove's hook entries to ~/.claude/settings.json on this machine. Keeps everything already there, adds only
the events that do not call Cove yet, writes settings.json.cove-backup first. Invalid JSON is left alone."""
import json
import os
import shutil
import sys

home = os.path.expanduser("~")
settings_path = os.path.join(home, ".claude", "settings.json")
snippet_path = os.path.join(home, ".claude", "island", "settings-snippet.json")
marker = ".claude/island/hook.sh"

if not os.path.isdir(os.path.join(home, ".claude")):
    print("No ~/.claude folder here: run Claude Code once on this machine first.")
    sys.exit(1)
with open(snippet_path, "r", encoding="utf-8") as f:
    snippet = json.load(f)
settings = {}
had_file = os.path.exists(settings_path)
if had_file:
    try:
        with open(settings_path, "r", encoding="utf-8") as f:
            settings = json.load(f)
    except Exception as e:
        print("%s is not valid JSON (%s); left alone. Fix it and run this again." % (settings_path, e))
        sys.exit(1)
hooks = settings.get("hooks") if isinstance(settings.get("hooks"), dict) else {}
added = 0
for event, entries in snippet.items():
    existing = hooks.get(event) if isinstance(hooks.get(event), list) else []
    present = any(marker in (h.get("command") or "") for e in existing if isinstance(e, dict)
                  for h in (e.get("hooks") or []) if isinstance(h, dict))
    if present:
        continue
    hooks[event] = existing + entries
    added += 1
if added == 0:
    print("Cove's hooks were already in %s." % settings_path)
    sys.exit(0)
if had_file:
    shutil.copyfile(settings_path, settings_path + ".cove-backup")
settings["hooks"] = hooks
with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, sort_keys=True)
    f.write("\n")
print("Added %d hook event(s) to %s%s." % (added, settings_path, " (backup: settings.json.cove-backup)" if had_file else ""))
