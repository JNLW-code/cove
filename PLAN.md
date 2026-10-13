# Cove — plan

**Status (13 Oct 2026):** waiting for James's OK on the plan and answers to the 5 questions. Nothing built yet.
Done: refs saved, Mac checked, plan written. Left: everything. Blocked: Screen Recording for Claude (James grants).

## What it is
Cove is a menu-bar app (no Dock icon) that draws a black "Dynamic Island" over the MacBook notch.
Hover opens tiles (Claude sessions, Music, Weather, Calendar, Timer). Small black "peeks" grow out of the notch for events.
Claude Code hooks call `~/.claude/island/hook.sh`, which runs a compiled helper that writes one JSON line to a Unix socket
in `~/Library/Application Support/Cove/`. PermissionRequest keeps its connection open and gets Allow/Deny back.

## Facts checked on this Mac (13 Oct 2026)
- macOS 26.6.2 (25G83), Xcode 27.0 (27A266a), Swift 6.4, only the macOS 27.0 SDK → deployment target must be 26.0.
- Notch measured with AppKit: x 646 → 825, width 179 pt, height 32 pt, screen 1470 × 956 @2x. Matches James's numbers.
- Signing identities: 0. → self-signed "Cove Dev" cert in the login keychain (step 2).
- Claude Code: Terminal 2.1.290 (`~/.local/bin/claude`); desktop app bundles 2.1.295 (and 2.1.288) under
  `~/Library/Application Support/Claude/claude-code/`.
- `~/.claude/settings.json` hooks: SessionStart + PostToolUse (GSD node scripts), statusLine GSD. Never edit this file.
- `screencapture -R` from Claude fails ("could not create image from rect") → Claude has no Screen Recording permission.
- No ffmpeg, no xcodegen. brew present.
- Apps present: Claude, Google Chrome, Slack, WhatsApp, Xcode (for the peek list).

## Decisions
### Made by Claude (technical)
- Name **Cove**, bundle id **com.jameswebster.cove**. Data: `~/Library/Application Support/Cove/` (0700), socket `cove.sock` there. Hooks: `~/.claude/island/`.
- Code = one Swift Package: `Cove` (app) + `cove-hook` (helper). `Makefile` builds `Cove.app` (Info.plist, sign) with warnings as errors.
  No .xcodeproj; `open Package.swift` works in Xcode. Reason: every build is one command that can be verified; nothing hidden in Xcode settings.
- Signing: self-signed code-signing certificate "Cove Dev" in the login keychain, same bundle id forever → TCC grants stick.
- MACOSX_DEPLOYMENT_TARGET 26.0. App Sandbox off. Hardened Runtime off (only needed for notarising) → no extra entitlements needed.
- AppKit for the panel, tracking area, hotkeys (Carbon), menu. SwiftUI (NSHostingView) for the views inside, fixed frames.
- Hook timeouts: status hooks `"timeout": 2`; PermissionRequest `"timeout": 75`, helper gives up at 60 s with no output (never allow on timeout).
- Toolbar v1: settings, edit, volume (CoreAudio, public), theme toggle, recent apps (NSWorkspace activation order).
  Out: brightness (no public API on Apple silicon), AirPlay (no public picker API). Later: folder/tray shelf, apps grid, chips row.
### Made by James
- (pending) see Questions below.

## Questions asked 13 Oct 2026 (answers pending)
1. Claude rows: full-width strip above the tiles; Needs-you / Done cards take over the island like refs 2–3. (rec: yes)
2. At rest with only idle sessions: plain notch, no pill. (rec: yes)
3. Long command: Allow turns on once scrolled to the end of the box. (rec: yes)
4. No synced lyrics on LRCLIB: show nothing under the tiles. (rec: yes)
5. Clicking a Claude row: bring Claude forward and close the island. (rec: yes)

## Steps
- [ ] 1. Mockup artifact (all states, both themes, options A/B/C). Done when James has picked.
- [ ] 2. Skeleton: package, Makefile (check/run/install/uninstall), cert, menu-bar icon, no Dock icon. Done when `make check` is clean and `make run` shows the icon at 0% CPU.
- [ ] 3. Island shell: panel, 4 states, hover/reverse, themes, Theme.swift, Tile view, toolbar, edit mode, Demo menu. Done when screenshots in both themes match the picked drawing.
- [ ] 4. Hook probe (throwaway hook in `.claude/settings.local.json`): the 4 questions answered in PLAN.md.
- [ ] 5. Claude status: socket, hook.sh + helper, rows, steps, Working/Done/Waiting/Quiet, agents, process watch, fake-event script, settings.json snippet. Done when fake events drive 3 rows and a real session shows project · branch.
- [ ] 6. Permission card: Allow/Deny, queue, hotkeys, 400 ms guard, long-command box, fail open, 60 s, Allowed/Denied, question/plan, blocked peek. Done when a real request is answered from the island and /security-review is clean.
- [ ] 7. Music tile + LRCLIB lyrics + Automation tick.
- [ ] 8. Weather tile (Open-Meteo), city in menu, one-shot refresh.
- [ ] 9. Calendar tile (EventKit full access) + 25-min timer.
- [ ] 10. Peeks: app open/quit, charger, battery 20/10, DND attempt with findings.
- [ ] 11. Settings menu, permission ticks, `make install`, launch at login.
- [ ] 12. README verified by its own commands, /code-review, final CPU/memory, Later list.

## Later
- Chips row from ref 5: YouTube, Window, Messages, Clipboard, Tray, Recents, Mac.
- Do Not Disturb peek, if v1 can't do it without polling.
- Context %: GSD's claude-ctx file only exists for Terminal sessions; may be estimated from the transcript.
- Folder / tray shelf and the apps grid from the toolbar.
- Brightness and AirPlay (no public API).
