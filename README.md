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
