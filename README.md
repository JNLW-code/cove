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
- The calendar tile opens the event in Google Calendar, in Chrome.
- Toolbar: settings (the menu), ✓ edit tiles (red − removes, grab bar drags), mute, ◐ dark/light, your recent apps.
- Claude rows: the session's name from the Claude app (else project · branch), the current step, agents, a timer. Click a row to bring the Claude app (or Terminal) forward.
- Done cards show Claude's last message and a reply box. Return sends it: through the hook if Claude just asked a question, otherwise Cove opens the session and types it in (needs the Accessibility permission once; desktop sessions only).
- A permission request opens the island by itself: Allow (⌃⌥Y) or Deny (⌃⌥N). Long commands scroll; Allow turns on once you've seen the end.
- **Launchpad**: ⌘4 (changeable in the menu) or the top-left hot corner (off by default) drops a big grid of every app in /Applications, /System/Applications, its Utilities and ~/Applications under the notch. Typing searches (name, word starts, initials), Return opens the first match, Esc clears then closes, ← → or a two-finger swipe turn pages, a click on empty space closes. A widget row sits under the search: Now playing (Spotify, else Apple Music; buttons work only while the player is already running), Weather, quick toggles (Wi-Fi, dark mode, mute) and Control Centre style sliders for Sound, Keyboard and Display brightness (the two brightness tiles use the same private frameworks Control Centre does and hide themselves if macOS removes them). Each can be turned off under Launchpad › Widgets. The grid button top right switches to folders by category (Productivity, Creative, Developer, Music and video, Social, Utilities, Games, Other); click one to open it, ‹ to go back. The app you were using keeps the front and gets the keyboard back on close.
- Themes: Dark, Light, Follow macOS, and Glass (Apple's Liquid Glass, like Control Centre). The ◐ button cycles Dark → Light → Glass.
- Menu: Theme, Tiles, Weather City, Peeks (which apps, sound), Allow / Deny Shortcuts, Launchpad (open, shortcut, hot corner), Permissions (ticks), Launch at Login, Demo, Quit.

## Install from the DMG (no Xcode needed)

Download `Cove.dmg` from the [latest release](https://github.com/JNLW-code/cove/releases/latest) and follow the `Read Me.txt` inside it: drag Cove to Applications, allow it once under System Settings → Privacy & Security ("Open Anyway", because it is signed with a self-signed certificate rather than an Apple Developer ID), then answer the "Welcome to Cove" window. It installs the Claude Code hooks itself (`Setup.swift`: hook files from the app bundle into `~/.claude/island`, Cove's entries merged into `~/.claude/settings.json` with a backup, nothing already there touched) and sets the theme, tiles, hot corner and launch at login. The window is also in the menu as "Set up Cove…". The DMG still carries `Install Hooks.command` for doing the hooks by hand. Needs a MacBook with a notch, Apple silicon, macOS 26 or later and Claude Code 2.1.288 or later.

## Claude Code over SSH

Hooks run where Claude Code runs, so a session on a server cannot reach the notch by itself. One command fixes that for a host from your `~/.ssh/config`:

```bash
make remote HOST=vps      # or: scripts/install-remote.sh vps
```

It copies `remote/cove-hook.py` (a Python 3 version of the hook helper), `remote/hook.sh` and the settings snippet into `~/.claude/island` on the server, merges Cove's hook entries into the server's `~/.claude/settings.json` (backup kept), and adds one line to your `~/.ssh/config`: `RemoteForward 127.0.0.1:47925 "<cove.sock>"`, which makes the server's `localhost:47925` Cove's socket for the life of each SSH connection. Reconnect, start a Claude Code session there, hover the notch. Rows, Allow / Deny, questions, plans and typed replies all work; cost and context figures do not (the transcript is on the server), and clicking a row brings your terminal forward rather than an exact chat. The row shows the server's name after project · branch. The same files are on the DMG under "Claude Code over SSH". `make test-remote` drives the Python helper through a local TCP relay standing in for the tunnel (Cove launched with `COVE_UI_TEST=1`).

## Updates

Cove checks the repo's `appcast.xml` once a day and offers new versions in place (Sparkle). "Check for Updates…" in the menu checks now. `make release` signs the DMG with the EdDSA key that `generate_keys` put in the login keychain (back it up with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x cove-sparkle-key.txt`, kept out of git) and publishes the appcast after the GitHub release. The public half is `SUPublicEDKey` in `Support/Info.plist`; Sparkle also insists the new app carries the same "Cove Dev" signature as the old one. `make test-update` proves the whole path on this Mac without GitHub: it builds a "-test" version, serves it from a local appcast and lets the current build update itself.

## Release

```bash
make dmg        # build/Cove.dmg: the app, an Applications shortcut, Hooks/, Install Hooks.command, Read Me.txt
make test-dmg   # mounts it, runs the install script against a scratch HOME, checks the files and the helper
make release    # tags v<version>, pushes main and the tag, publishes a GitHub release with the dmg, then commits and pushes appcast.xml
```

The version is `CFBundleShortVersionString` in `Support/Info.plist`; `CFBundleVersion` is the commit count. The bundle id (`com.jameswebster.cove`) and the "Cove Dev" certificate never change, so macOS keeps every permission grant across updates: a new version is just the new `Cove.app` dragged over the old one.

## Remove

```bash
make uninstall
```

This quits Cove and removes `~/Applications/Cove.app`, the `build/` folder, `~/Library/Application Support/Cove` and `~/.claude/island`. Then delete every hook entry whose command contains `.claude/island/hook.sh` from `~/.claude/settings.json` (the GSD hooks and statusLine stay). To forget the permission grants too: `tccutil reset All com.jameswebster.cove`.

## Demo and test controls

The menu's **Demo** item cycles through every island state with sample data. `make fake` drives three Claude sessions through every state over the socket (Cove must be running); `scripts/fake-events.sh down` tests the hook helper with Cove quit. From a shell you can also drive the island: `scripts/fake-events.sh question` feeds Claude's multiple-choice question through the real hook helper so you can answer it on the island. `scripts/fake-events.sh plan` does the same with a plan to approve.

```bash
notifyutil -p com.jameswebster.cove.show.expanded
```

Commands: `theme.dark`, `theme.light`, `theme.system`, `demo.toggle`, `demo.next`, `show.resting`, `show.compact`, `show.peek`, `show.expanded`, `open`, `close`, `edit.toggle`, `pin.toggle`, `menu.open`, `launchpad.toggle`, `launchpad.next`, `launchpad.type`, `launchpad.categories`, `launchpad.folder`, `launchpad.demo`. They only change what the island shows; nothing can approve a command from outside the app.

## Layout

- `Sources/Cove/` the app. `Theme.swift` holds every colour and font; `IslandViews.swift` has the one `TileView` every tile uses; `IslandPanel.swift` is the window over the notch; `ClaudeSocket.swift`, `ClaudeModel.swift`, `ClaudeViews.swift` are the Claude side; `Usage.swift` reads cost and turn counts from the session transcripts; `Apps.swift` scans and watches the Applications folders for the Launchpad, `LaunchpadViews.swift` draws it, `Music.swift`, `Toggles.swift` and `Brightness.swift` feed its widgets.
- `Sources/CoveHook/` the hook helper. `hooks/` the shell wrapper and the settings snippet. `scripts/` the certificate and fake-event scripts.
- `Support/Info.plist` bundle settings (no Dock icon, deployment target 26.0, permission texts).
- `mockup/` the HTML design mockup. `refs/` the target screenshots. `PLAN.md` the plan, decisions and what's left.
