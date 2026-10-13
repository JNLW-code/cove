# Cove

A menu-bar app that turns the MacBook notch into a Dynamic Island: Claude Code sessions, Spotify, weather, next calendar event and a focus timer. macOS 26, one Mac, no App Store.

## Build and run

```bash
make check    # build with warnings as errors
make run      # quit the old copy, build, sign and launch build/Cove.app
```

The first build creates a self-signed "Cove Dev" certificate in your login keychain (`scripts/make-cert.sh`). It is the one signing identity the project uses; keeping it means macOS remembers the permissions you grant Cove.

## Install

```bash
make install  # copies to ~/Applications/Cove.app and launches it
```

Launch at login only works from the installed copy (System Settings → General → Login Items shows "Cove").

## Remove

```bash
make uninstall
```

This quits Cove and removes `~/Applications/Cove.app`, the `build/` folder and `~/Library/Application Support/Cove`. The Claude Code hooks (step 5) will add their own lines here.

## Claude Code hooks

```bash
make install-hooks
```

That puts `hook.sh` and the `cove-hook` helper in `~/.claude/island/`. Then add the entries from [hooks/settings-snippet.json](hooks/settings-snippet.json) inside the existing `"hooks"` object of `~/.claude/settings.json` (merge into the `SessionStart` and `PostToolUse` arrays that are already there; add the other events as new keys). Every hook runs the same one-line script; the helper sends a trimmed event to Cove's socket in `~/Library/Application Support/Cove/` and exits. Only `PermissionRequest` waits for an answer, at most 60 s, and gives up silently if Cove isn't running or you're away.

To remove: `make uninstall`, then delete every hook entry whose command contains `.claude/island/hook.sh` from `~/.claude/settings.json`.

To see it without real sessions: `make fake` drives three sessions through every state (needs Cove running).

## Demo and test controls

The menu's **Demo** item cycles through every island state with sample data (pill, peeks, open island, edit mode). From a shell you can drive the same things:

```bash
notifyutil -p com.jameswebster.cove.show.expanded
```

Commands: `theme.dark`, `theme.light`, `theme.system`, `demo.toggle`, `demo.next`, `show.resting`, `show.compact`, `show.peek`, `show.expanded`, `edit.toggle`, `pin.toggle`. They only change what the island shows.

## Layout

- `Sources/Cove/` the app. `Theme.swift` holds every colour and font; `IslandViews.swift` has the one `TileView` every tile uses; `IslandPanel.swift` is the window over the notch.
- `Support/Info.plist` bundle settings (no Dock icon, deployment target 26.0).
- `mockup/` the HTML design mockup. `refs/` the target screenshots. `PLAN.md` the plan, decisions and what's left.
