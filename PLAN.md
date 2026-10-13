# Cove — plan

**Status (14 Oct 2026):** steps 1–3 done and seen in screenshots (both themes). Next: step 4, the hook probe.
Done: refs, Mac facts, measurements, mockup v1 at https://claude.ai/artifact/CQbY8iEvUZZ6R55xrWAwyr (source: mockup/cove-mockup.html).
Left: steps 2–12. Blocked: Screen Recording for Claude (James grants); picks for step 1.

## What it is
Cove is a menu-bar app (no Dock icon) that draws a black "Dynamic Island" over the MacBook notch.
Hover opens tiles (Claude sessions, Spotify, Weather, Calendar, Timer). No lyrics. Small black "peeks" grow out of the notch for events.
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
### Made by James (13 Oct 2026)
- Claude rows are a full-width strip above the tiles; Needs-you and Done cards take over the whole island (refs 2–3).
- At rest with only idle sessions: plain notch, no pill. The pill appears only for Working, Needs you, Done.
- Long command: Allow turns on once the box has been scrolled to the end.
- **No lyrics at all.** LRCLIB is dropped. The island is shorter (no lyric lines under the tiles).
- **Music tile = Spotify, not Apple Music.** Track and play state from Spotify's distributed notification
  `com.spotify.client.PlaybackStateChanged`; controls/artwork/position via AppleScript only while open and only if Spotify runs.
  Artwork comes from Spotify's own CDN (`artwork url`), cached locally. That is one more outbound request (to Spotify) — flagged to James.
- Clicking a Claude row brings Claude forward and closes the island.
- Peeks are exactly the notch's width (James, 13 Oct), growing 24 pt down (40 for two lines), bottom radius 14. Long words truncate.
- No coloured edge on the black shapes (James, 13 Oct): pill and peeks are pure black like the notch; status colour lives only in the icon/grid. No window shadow on them either, only on the open island.
- Mockup picks (13 Oct): **Colours B Lifted** (dark: island underPageBackground #282828, tiles secondarySystemFill → #383838; light: island windowBackground #FFFFFF, tiles → #EBEBEB; Deny = unemphasizedSelectedContentBackground). **Pill A Wings** (two lobes level with the menu bar, 371 × 32). **Working animation A Walk** (3 accent cells wander on the 5×5 grid, one move per 300 ms, only while working and visible).

## Measurements from the refs (pt, notch = 179 pt wide)
- Ref 1 scale 1.866 px/pt. Island 662 × 197 (197 included ~54 pt of lyrics; without lyrics ≈ 162), radius ≈ 35, rim 1 pt lighter.
  Notch band 32, gap 18, tiles 94 tall, side insets 23, gaps 8, tile radius 15. Widths 170 / 170 / 170 / 81.
  Art 57 pt, 10 pt from tile left, 15 pt from tile top. Titles 13 pt bold, secondary 11–12 pt. Big numbers (18°, 11) ≈ 28 pt light, 25:00 ≈ 20 pt light, play circle ≈ 28 pt.
- Ref 2 scale 2.2 px/pt. Card ≈ 111 pt tall; grid 32 pt (5×5); title 14 pt bold; command 12.5 pt secondary; project 11 pt tertiary.
  Allow/Deny pills ≈ 85 × 30, 6 pt apart; Allow white with dark text; Deny = tile fill. Toolbar icons ≈ 12 pt glyphs at 30 pt pitch, centred in the notch band.
- Ref 4: peek = notch grows down ≈ 24 pt (total 56) and ≈ 22 pt wider each side; icon 13 pt + 13 pt semibold word, centred in the lower band.
- Ref 6 light: island ≈ #F5F4F8, tiles ≈ #E2E2E8 (darker than island), dark text.
- Real macOS 26 colours (sRGB): dark window/control bg #1E1E1E, underPage #282828, fills = white at 10/8/5/3/1 %, label white 85/55/25 %,
  separator white 10 %, accent #007AFF, orange #FF9230, green #30D158, red #FF4245. Light: window #FFFFFF, fills black at 10/8/5/3/1 %, label black 85/50/26 %.

## Steps
- [x] 1. Mockup artifact (all states, both themes, options A/B/C). Published; James picked B / A / A.
  Options offered: Colours A Quiet / B Lifted (rec) / C Crisp. Pill A Wings (rec) / B Chin / C Lobe. Working anim A Walk (rec) / B Wave / C Ring.
- [x] 2. Skeleton: package, Makefile (check/run/install/uninstall), cert, menu-bar icon, no Dock icon. `make check` clean, `make run` launches; 0.0 % CPU, 10 MB.
  Cert: `scripts/make-cert.sh` makes "Cove Dev" (self-signed, legacy PKCS12, imported with -T codesign). It shows as CSSMERR_TP_NOT_TRUSTED in
  `security find-identity -v` but codesign signs with it without any prompt and the designated requirement is stable:
  `identifier "com.jameswebster.cove" and certificate leaf = H"c51892c9…"`. No trust-settings change was needed. Entitlements: none (Hardened Runtime off).
  Screenshots from Claude still come out black: Screen Recording not granted yet.
- [x] 3. Island shell: panel, 4 states, hover/reverse, themes, Theme.swift, Tile view, toolbar, edit mode, Demo menu. Screenshots 14 Oct in both themes match the mockup (island, tiles, toolbar, edit badges, pill, peek). Fixed after seeing pixels: tile content was clipped to its own size, calendar date line, pill lobes widened to 112 (pill 403 wide).
  Checked 13 Oct: panel frames per mode (resting 179×32 at x 646, compact 387×32, peek 239×56, expanded 662×162), 0.0 % CPU at rest (6 samples),
  26 MB, 1–2 % while the pill animates, demo ran 28 s and returned to rest. Not yet seen: the actual pixels (Screen Recording), hover with a real mouse.
  How it works: `IslandController` owns an `IslandPanel` (NSPanel, nonactivating, level mainMenu+1, canJoinAllSpaces/fullScreenAuxiliary/stationary).
  For a mode change it grows the panel to the union of old and new frames, animates the SwiftUI content (`island.mode`), then tightens the frame
  after the animation settles. Hover: NSTrackingArea on the content view, 250 ms one-shot Task → expand; exit → collapse (SwiftUI retargets mid-animation).
  Click on the island background pins it; a global mouse-down monitor (only while pinned) unpins on a click outside. Edit mode pins automatically.
  /code-review (8 findings) fixed 13 Oct: pin leak, sample data leaking out of Demo, palette cached per theme, shadow timing, peeks queued while open, edit-mode unpin, drag persists once.
  Dev control channel for testing: `notifyutil -p com.jameswebster.cove.<cmd>` with cmd in theme.dark|theme.light|theme.system|demo.toggle|demo.next|
  show.resting|show.compact|show.peek|show.expanded|edit.toggle|pin.toggle (Darwin notify, public API; it only changes what is shown).
- [ ] 4. Hook probe (throwaway hook in `.claude/settings.local.json`): the 4 questions answered in PLAN.md.
- [ ] 5. Claude status: socket, hook.sh + helper, rows, steps, Working/Done/Waiting/Quiet, agents, process watch, fake-event script, settings.json snippet. Done when fake events drive 3 rows and a real session shows project · branch.
- [ ] 6. Permission card: Allow/Deny, queue, hotkeys, 400 ms guard, long-command box, fail open, 60 s, Allowed/Denied, question/plan, blocked peek. Done when a real request is answered from the island and /security-review is clean.
- [ ] 7. Spotify tile (art, title, artist, prev/play/next, progress) + Automation tick.
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
