# Cove

A menu-bar app that turns the MacBook notch into a Dynamic Island: Claude Code sessions live in the notch (with Allow / Deny for permission requests), plus Spotify, weather, your next calendar event and a focus timer. macOS 26, one Mac, no App Store, no analytics. Nothing leaves the Mac except Open-Meteo (weather) and Spotify's own image server (artwork).

## Build and run

```bash
make check    # build with warnings as errors
make run      # quit the old copy, build, sign and launch build/Cove.app
```

The first build creates a self-signed "Cove Dev" certificate in your login keychain (`scripts/make-cert.sh`). It is the one signing identity the project uses; keeping it means macOS remembers the permissions you grant Cove.

## Install

```bash
make install        # copies to ~/Applications/Cove.app and launches it
make install-hooks  # puts hook.sh and the cove-hook helper in ~/.claude/island/
```

Launch at Login (in Cove's menu) only works from the installed copy. If macOS asks, approve Cove under System Settings → General → Login Items.

Then add the entries from [hooks/settings-snippet.json](hooks/settings-snippet.json) inside the existing `"hooks"` object of `~/.claude/settings.json`: merge the `SessionStart` and `PostToolUse` objects into the arrays that are already there, and add the other events as new keys. Hooks only run in folders you have trusted. Every hook runs the same one-line script; the helper sends a trimmed event to Cove's socket in `~/Library/Application Support/Cove/` and exits in a few milliseconds. Only `PermissionRequest` waits for an answer, at most 60 s, and gives up silently (Claude asks as usual) if Cove isn't running, you're away, or anything goes wrong.

## Use

- Rest the mouse on the notch: the island opens. Move away: it closes. Click the background to keep it open.
- Toolbar: settings (the menu), ✓ edit tiles (red − removes, grab bar drags), mute, ◐ dark/light, your recent apps.
- Claude rows: project · branch, the current step, agents, a timer. Click a row to bring the Claude app (or Terminal) forward.
- Done cards show Claude's last message and a reply box. Return sends it: through the hook if Claude just asked a question, otherwise Cove opens the session and types it in (needs the Accessibility permission once; desktop sessions only).
- A permission request opens the island by itself: Allow (⌃⌥Y) or Deny (⌃⌥N). Long commands scroll; Allow turns on once you've seen the end.
- Menu: Theme, Tiles, Weather City, Peeks (which apps, sound), Allow / Deny Shortcuts, Permissions (ticks), Launch at Login, Demo, Quit.

## Remove

```bash
make uninstall
```

This quits Cove and removes `~/Applications/Cove.app`, the `build/` folder, `~/Library/Application Support/Cove` and `~/.claude/island`. Then delete every hook entry whose command contains `.claude/island/hook.sh` from `~/.claude/settings.json` (the GSD hooks and statusLine stay). To forget the permission grants too: `tccutil reset All com.jameswebster.cove`.

## Demo and test controls

The menu's **Demo** item cycles through every island state with sample data. `make fake` drives three Claude sessions through every state over the socket (Cove must be running); `scripts/fake-events.sh down` tests the hook helper with Cove quit. From a shell you can also drive the island:

```bash
notifyutil -p com.jameswebster.cove.show.expanded
```

Commands: `theme.dark`, `theme.light`, `theme.system`, `demo.toggle`, `demo.next`, `show.resting`, `show.compact`, `show.peek`, `show.expanded`, `open`, `close`, `edit.toggle`, `pin.toggle`, `menu.open`. They only change what the island shows; nothing can approve a command from outside the app.

## Layout

- `Sources/Cove/` the app. `Theme.swift` holds every colour and font; `IslandViews.swift` has the one `TileView` every tile uses; `IslandPanel.swift` is the window over the notch; `ClaudeSocket.swift`, `ClaudeModel.swift`, `ClaudeViews.swift` are the Claude side; `Usage.swift` reads cost and turn counts from the session transcripts.
- `Sources/CoveHook/` the hook helper. `hooks/` the shell wrapper and the settings snippet. `scripts/` the certificate and fake-event scripts.
- `Support/Info.plist` bundle settings (no Dock icon, deployment target 26.0, permission texts).
- `mockup/` the HTML design mockup. `refs/` the target screenshots. `PLAN.md` the plan, decisions and what's left.
