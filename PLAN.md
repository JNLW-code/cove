# Cove — plan

**Status (14 Oct 2026, overnight run):** steps 1–6 done. Working through 7–12 without James. Blocked on James: 5b (paste hooks/settings-snippet.json into ~/.claude/settings.json), Spotify Automation and Calendar permission prompts when those tiles first load.
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

## Step 4 findings — hooks (docs checked 14 Oct 2026, code.claude.com/docs/en/hooks; empirical bits marked)
- PermissionRequest fires only when Claude is about to ask (or would auto-deny in a session that can't prompt). Not for auto-mode classifier blocks: those are **PermissionDenied** (auto mode only; fields tool_name, tool_input, tool_use_id, reason).
- **Exit 2 is ignored for PermissionRequest** ("permission flow proceeds unchanged", stderr discarded) → deny only with the JSON decision. Allow/deny JSON shapes as in PROMPT.md; deny may add `"interrupt": true`.
- Default hook timeout 600 s; per-hook `"timeout"` in seconds. Ours: PermissionRequest 75, helper gives up at 60. `onFailure` needs 2.1.295, so not relied on.
- Desktop app / Remote Control (canUseTool host): docs say the host's prompt and the hooks "run alongside… whichever decides first applies" → the app shows its own prompt at the same time; first answer wins. (James's live test confirms what the losing hook sees.)
- PreToolUse `permissionDecision: "allow"` skips the prompt (except never-auto-approved actions, network paths, AskUserQuestion/ExitPlanMode). PreToolUse stays status-only for us.
- Stop input has `last_assistant_message` (and `stop_hook_active`) → "ends with ?" needs no transcript reading. SubagentStart/Stop carry `agent_id`, `agent_type`.
- SessionStart `source`: startup | resume | clear | compact | fork; `session_title` only when set (--name, /rename), else absent → fall back to folder name. SessionEnd `reason`: clear | resume | logout | prompt_input_exit | other; **/clear sends SessionEnd** then SessionStart(clear). SessionEnd hook budget 1.5 s by default (our 2 s timeout is fine).
- Notification `notification_type`: permission_prompt (~6 s after the prompt), idle_prompt (~60 s after Claude stops), agent_needs_input, agent_completed, …
- Env in hooks: CLAUDE_PID, CLAUDE_CODE_SESSION_ID, CLAUDE_PROJECT_DIR, CLAUDE_CODE_CHILD_SESSION; TERM_PROGRAM is inherited (empty in the desktop app, "Apple_Terminal"/"iTerm.app" in a terminal). Seen empirically: common fields session_id, transcript_path, cwd, scratchpad_dir, prompt_id, permission_mode ("auto"/"default"), effort, hook_event_name; PreToolUse/PostToolUse add tool_name, tool_input, tool_use_id, and agent_id/agent_type when inside a subagent.
- Hooks are held back until the folder is trusted; `claude -p` treats folders as trusted. Settings edits are picked up live by a file watcher (seen: this session ran the probe hook seconds after settings.local.json was written) — no restart needed.
- Print mode: PermissionRequest hooks run; with no decision the tool is denied. `--permission-prompts none` exists (2.1.259+). Permission modes: default, acceptEdits, plan, auto, dontAsk, bypassPermissions.
- Both CLI copies (Terminal 2.1.290, bundled 2.1.295) were logged out on 14 Oct; James logged in Terminal for the scripted tests.
- **Scripted (Terminal 2.1.290, `claude -p --permission-mode default`, command `touch build/x`):**
  - no decision from the hook → PermissionRequest fires, tool denied in print mode (Claude asks for approval in text).
  - PreToolUse `permissionDecision: allow` → **no PermissionRequest at all**, tool runs. (Q1: yes, it skips the prompt.)
  - PermissionRequest exit 2 with stderr → treated as no decision; tool "blocked pending approval". (Q2: exit 2 never denies; deny only with JSON.)
  - PermissionRequest deny JSON → denied with our message; allow JSON → PostToolUse 200 ms later, file created.
- **Desktop app 2.1.295, Manual mode, hook waits 25 s then allows:** PermissionRequest fired 0.3 s after PreToolUse; a `Notification permission_prompt` fired 6 s later, but James saw **no prompt in the app** during the wait; the hook's allow ran the tool. (Q3: the app shows nothing while a PermissionRequest hook is pending, at least on 2.1.295.)
- `echo hello` never prompts even in Manual: it is on Claude Code's built-in safe list. Tests must use a write such as `touch`.
- **Desktop app, hook returns no decision:** the app's own prompt ("Do you want to proceed? 1. Yes…") appears within a second; James's Yes ran the tool (PostToolUse). So the app only prompts once the hook has finished without a decision.
- **Phone (Remote Control) while the hook waits:** not tested. Docs: host prompt and hooks run alongside each other, first decision wins. Design for it anyway: a PostToolUse (or PermissionDenied) for the same tool_use clears the card and the hook exits 0 with no output.
- `TERM_PROGRAM` is `claude-desktop` in desktop-app sessions (empty on the very first events of a session), `Apple_Terminal` in Terminal.
- Desktop sessions emit a `SubagentStop` with no `SubagentStart` after every turn (the app's own title/summary agent) → treat SubagentStop for an unknown agent_id as nothing.

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
- [x] 4. Hook probe done 14 Oct (throwaway hook removed). Answers: (1) PreToolUse allow skips the prompt entirely. (2) Exit 2 in PermissionRequest does nothing; deny only by JSON. (3) The desktop app shows no prompt while a PermissionRequest hook is pending; it prompts only after the hook returns without a decision. (4) Answering first in the app can't happen while our hook waits; the phone case is untested, handled by clearing the card on PostToolUse.
- [x] 5. Claude status (14 Oct): socket (`ClaudeSocket.swift`, 0700 dir, peer uid checked), `cove-hook` helper + `hooks/hook.sh`, `hooks/settings-snippet.json`, rows/steps/Done/Waiting/Quiet/agents/process watch (`ClaudeModel.swift`), strip + cards (`ClaudeViews.swift`), `scripts/fake-events.sh` (`make fake`). Fake events drive 3 rows, the Done card and the pill; screenshots match the mockup. Real session check: see step 5b.
- [ ] 5b. James pastes `hooks/settings-snippet.json` into ~/.claude/settings.json, then a real session shows project · branch.
- [x] 6. Permission card (14 Oct): `PermissionCardView` (ref 2), Allow/Deny pills, Carbon hot keys ⌃⌥Y/⌃⌥N registered only while a card shows (`HotKeys.swift`), queue with "1 of N", 400 ms guard, long commands in a 128 pt monospace scroll box with Allow off until scrolled to the end (shortcut path refuses too), Allowed/Denied peeks, question/plan card with Open, blocked peek. The island opens itself on a request and stays open until answered.
  Verified with the real helper: allow → helper prints the allow JSON; deny → deny JSON; settled by Stop → no output; 3 s timeout → no output; app down → instant exit 0. Real end-to-end answer needs step 5b (James's settings.json paste).
  /code-review (6 findings) fixed. /security-review: no high or medium findings. Notes: any same-user process can connect to the socket or post the notify dev commands, but neither path can approve anything (approval is only the app's own buttons/hot keys, replies go only down the requesting hook's own connection, the helper prints fixed JSON). `test.allow/deny` exist only when launched with COVE_UI_TEST=1, which `make run`/`install` never set. Commands are held in memory only and never logged.
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
