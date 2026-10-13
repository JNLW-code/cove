Build me a native macOS app (Swift 6 + AppKit/SwiftUI) that turns the MacBook notch into a "Dynamic Island", like the iPhone one. It lives in the menu bar, has no Dock icon, and starts at login only if I turn it on. It's only for me on this Mac, so no App Store, no notarising and no other Macs. Pick a short name and bundle id in the plan and use them everywhere.

**My Mac:** MacBook Air M2, 8 GB RAM, macOS 26.6.2, Xcode 27, Swift 6.4. One built-in screen, 1470 × 956 pt. The notch is 179 × 32 pt, from x 646 to 825. Dark mode, Sydney time, en-AU, 12-hour clock. I have no signing certificate or Xcode team yet, because this is my first native app here. I'm not a pro dev, so do the Xcode setup yourself and only hand me the steps that need me.

## How we work

**First message (the only long one):**
* One plain paragraph on what the app does and how it hooks into Claude Code.
* A short numbered plan with a one-line done-line I can check for each step. Claude Code comes straight after the island shell, before music, weather and peeks.
* The permissions it will ask for, including Screen Recording for Claude itself (for the screenshot checks).
* Your questions.

Then wait for my OK.

**My screenshots are the target.** I've attached 6 (ref 1–6, described in "What my screenshots show" below). Match their layout, sizes, spacing, corners and type. Where they and the text disagree, the screenshots win, except colour (see Theme).

**Draw before building UI.** Make an interactive HTML mockup as a Claude artifact link (I check on my phone too) that rebuilds my screenshots at real notch size, in both themes, plus the states they don't show. For the compact pill, the working animation and the colour set, give me 2–3 labelled options (A, B, C) and say which you'd pick. Borrow from the iPhone island and NotchNook / Alcove / boring.notch only where my screenshots don't cover it. Only draw what AppKit can really do. Then build what I pick and match it.

**Then one step at a time:** build it, check it yourself (below), commit, report, and wait for "go". If I say "run it", keep going through any step that doesn't need my eyes. Only stop for a drawing to pick, a permission I have to grant, or a real decision. Leave a done / left / blocked summary at the top of PLAN.md for when I'm back.

**Every step report, nothing more:**
```
Hi James,
Done: <one line>
Checked: <what you ran and saw, e.g. "built, launched, screenshots in both themes match B; 0.0% CPU, 38 MB at rest">
Try it: 1. … 2. … (and what I should see)
Need from you: <or "nothing">
Next: <one step>
```
Details go in PLAN.md, not chat. Use plain words and explain any macOS term in a few words. "simply?" means say it again, shorter.

**Questions:** ask them all at once, numbered, max 5, each with your recommended answer, so I can reply "1 yes 2 b". Check the Decisions list in PLAN.md first, and never re-ask something I've already decided. "go", "begin" and "yes" mean carry on. Read past my typos.

**Decide the technical stuff yourself** and tell me what you picked. Ask me about how it looks and behaves. If my spec is wrong or could be better, say so. Back any "can't be done" with the real macOS or Claude Code limit and offer the closest thing. Never fake it: cut a feature rather than ship a stub.

**Verify, don't claim. Every step:**
* Run `make check` (build with warnings as errors) and `make run` (quit the old copy, build, launch).
* Screenshot the notch area (`screencapture -R`) in both themes. Switch themes with the app's own Theme setting, never the macOS appearance. Compare with the drawing I picked and list the differences.
* Run the fake-event script (section 4).
* After UI steps, measure CPU and memory at rest with `top -l 2 -pid <pid>` and put the numbers in the Checked line.
* Say what you actually tried and what you only compiled.
* Run /code-review and fix what it finds. Run /security-review once the socket and Allow/Deny exist.

I'll send screenshots and screen recordings. Read them before you reply, and pull frames from .mov files (AVFoundation, or ffmpeg if it's installed) when you need to judge motion. When context is getting full, update PLAN.md, tell me in one line, and suggest /wrap.

## What my screenshots show

Ref 1 is a 1286 × 426 px image. Its notch is 334 × 58 px and my real notch is 179 pt wide, so 1 pt ≈ 1.87 px. Rough pt values below; re-measure from the images.

* **Ref 1, expanded (dark):**
  * Island about 662 × 197 pt, centred on the notch, corner radius about 34 pt, with a 1 pt lighter rim. The notch sits flush in the top edge with about 7 pt bottom corners. Empty band about 18 pt between the notch and the tiles.
  * One row of 4 tiles, about 94 pt tall, 8 pt gaps, 23 pt side insets, radius about 15 pt. Widths: music, weather and calendar about 170 pt each, timer about 81 pt.
  * Music: square art (about 57 pt, rounded) on the left, bold title, dim artist, then prev / pause / next along the bottom.
  * Weather: big light-weight "18°", city under it, colour rain icon top right (the only colour in the view), "H 20° L 14°" along the bottom.
  * Calendar: small "SUN" over a big light "11" on the left, bold event title and dim time on the right.
  * Timer: "25:00" over a round play button.
  * Lyrics sit under the tiles, not inside the music tile: two centred lines, the current one bright and semibold, the next one smaller and dim. About 16 pt bottom padding.
* **Toolbar row (refs 2, 3, 5, 6):** icons on both sides of the notch, level with it. Left: settings, apps grid, edit (✓), volume, brightness, theme toggle (◐). Right: icons of my recent apps, then AirPlay, folder, and window/tray.
* **Ref 2, permission card:** a 5 × 5 square grid on the left with a few cells lit amber, then "Claude needs your OK" (bold), the command (dim), and the project (dimmer). On the right, stacked: Allow as a white pill with dark text and "⌃⌥Y", and Deny as a dark grey pill with "⌃⌥N".
* **Ref 3, Done card:** the same grid lit green in a ring pattern, then "Done in 10 s", "2 files changed", and the project.
* **Ref 4, Do Not Disturb peek:** the notch itself grows downward into a wider black shape, with a lilac moon and "Do Not Disturb". Peeks are black and grow out of the notch; they aren't separate coloured bubbles.
* **Ref 5, edit mode:** every tile gets a red "−" badge at its top-left to remove it and a grab bar on its right edge to drag it. A row of pill chips sits under the tiles (YouTube, Window, Messages, Clipboard, Tray, Recents, Mac). Only one lyric line shows here.
* **Ref 6, Light theme:** same layout on a light island. Tiles are a little darker than the island, never lighter. Dark text, dark app icons.

Scope for v1: build the toolbar's settings, edit, volume, theme toggle and recent-app icons. Brightness, AirPlay, folder and tray are only in if macOS gives a public API; if not, say so and leave them out. The chips row goes in PLAN.md's Later list, not v1.

## 1. The island

* A borderless, non-activating panel that sits exactly over the notch, above every app, in full screen and on every desktop. It never steals focus.
* States:
  * resting: just the black notch
  * compact: a black pill that grows out of the sides of the notch
  * peek: the black notch grows downward for 2–4 s with an icon and a word (ref 4)
  * expanded: opens 0.25 s after the mouse rests on the notch and closes when it leaves; a click keeps it open
* Feel: calm and clean like the iPhone island, never flashy. Bright and crisp, never faded grey text. Apple-grade polish, not the default SwiftUI look. One main action per state, nothing to learn.
* Rounded corners that blend into the notch with no seam. Hairline edges and only a subtle shadow.
* Motion: 120 / 220 / 360 ms, with a slight spring overshoot on open. It can be interrupted: if the mouse leaves halfway, it reverses instead of restarting. Press scale 0.97 on every button. A light trackpad haptic on expand, pin and Allow/Deny. Respect Reduce Motion.
* Flat and matte: no glass, no blur, no gradients.
* Colour: clean and native, like macOS itself. Use macOS's own system colours, not custom hex, so it looks like part of the Mac:
  * text: labelColor, secondaryLabelColor, tertiaryLabelColor
  * island and tile fills: macOS's own solid window and control background colours (no glass, no blur)
  * edges: separatorColor as a hairline
  * accent: controlAccentColor, so it follows the accent I pick in System Settings
  * status: systemOrange = needs you, systemGreen = done, systemRed = blocked or denied
  * Allow: a white pill with dark text, like ref 2
* Two themes, Dark (default) and Light, plus "follow macOS". Resolve the system colours through the chosen NSAppearance so the toggle works whatever macOS is set to. All colour lookups live in one Theme.swift.
* The black band of the real notch always stays black, and peeks are black (ref 4). Anything drawn on black uses the dark-appearance colours in both themes.
* State shows as an icon plus a plain word, with a coloured edge. Never a lone colour dot. Working = accent.
* SF Pro, with monospaced digits for times, durations and temperatures. Fixed sizes, so buttons never move when text changes. Long text truncates or scrolls. Hide any count when it's 0.

## 2. Tiles in the expanded island

* I remove and reorder tiles right in the island, in edit mode (ref 5), and show them again from the menu.
* Claude sessions (section 4).
* Music: Apple Music only (no Spotify). Cover, title, artist, play/pause/next and a progress bar. Lyrics are synced from LRCLIB (free, no key) with a local cache, and laid out like ref 1: current line plus the next one under the tiles.
* Weather from Open-Meteo (free, no key): temperature, icon, high and low. Sydney and °C by default; I can change the city.
* Next calendar event from EventKit, shown like "Wed 14 Oct · 9:30 am".
* A 25-minute focus timer with start and reset.
* If I haven't granted the permission a tile needs, the tile is hidden, not greyed out.

## 3. Peeks (small bubbles that appear and go away)

* An app opens or quits, with its icon. Real apps only, not helpers or Chrome web-app shims. I tick which apps in settings. Start with Slack, WhatsApp, Claude, Chrome and Xcode.
* Charger connected, and battery at 20% and 10%.
* Do Not Disturb on or off (ref 4). There's no clean public API: try INFocusStatusCenter first. If it needs an Intents extension or a paid team, tell me the real options (for example watching the Focus assertions file, which needs Full Disk Access) and let me pick. Never poll.
* One peek at a time, and the same event twice counts as one peek. No peeks per Claude tool call. No sound unless I turn it on.

## 4. Claude Code, live in the notch

**How I use it, so build for this:**
* I run Claude Code in the Claude desktop app, sometimes `claude` in Terminal.
* Usually 1–2 sessions are working at once, sometimes 3 or more, with others left open. Mostly quoteflow-v3, in the main repo and in git worktrees (sibling folders like qf-wt-rec, or `.claude/worktrees/<name>`), with lots of subagents. Some sessions have no repo, like my home folder or the desktop app's scratch folders.
* I'm almost always in auto mode, overnight runs included. Real permission prompts are rare, and "auto mode blocked it" happens more often. I also answer from my phone with Remote Control.
* Turns run from seconds to over an hour. I walk away and come back minutes later. I interrupt often and use /clear, /compact and /resume a lot.

**What I want:**
* One row per session, keyed by session_id. Label it project · branch, worked out from git so subfolders and worktrees still show the right project. With no repo, use the session title, or else the folder name. Compact shows the most urgent session plus a count.
* The current step as an icon plus a word: Thinking (from my prompt until the first tool), Reading, Editing, Searching, Testing, Checking, Building, Git, Waiting on CI, Browsing.
  * Most of my tool calls are Bash, so work the step out from the command: git/gh, test/playwright, tsc/npm run check/xcodebuild, grep/rg, sleep/gh pr checks.
  * Turn mcp__server__tool names into plain words.
  * Smooth it out so it doesn't flicker (I can hit about 100 events a minute).
* A small animated grid only while a session is working, with a live timer. Subagents show as "+3 agents" on their session and never replace the main step.
* **Needs you** is the loudest state, and it stays until I hover or click:
  * Permission: open the island like ref 2: amber grid, "Claude needs your OK", the command, then project · branch. A short command shows as in the screenshot. A long one opens into a scrollable monospace box, never cut off, because some of my commands are hundreds of lines.
    * Allow stays off until the full command has been on screen.
    * Ignore clicks and shortcuts for about 400 ms after a card appears or moves to the next request.
    * Allow and Deny look like ref 2 and are equally easy to hit. Shortcuts default to ⌃⌥Y and ⌃⌥N, and I can change them.
    * Several requests at once queue up ("1 of 3"), and each answer goes to the right request.
    * Show "Allowed" or "Denied" afterwards.
  * Question or plan ready (AskUserQuestion, ExitPlanMode): say so, with a button to jump to it. Never show an Allow card for these.
  * Blocked by auto mode (PermissionDenied): a small peek with the project and what it tried.
* **Done** looks like ref 3: green grid, "Done in 10 s" ("Done in 4 m 12 s", "Done in 1 h 05 m"), how many files changed (unique Edit/Write paths this turn, hidden at 0), and project · branch. It's timed from my prompt to the end.
  * It stays as a badge until I hover, and only peeks for turns over about 30 s.
  * If Claude's last message ends with a question, show "Waiting for you" instead.
  * If agents are still running, add "2 agents running".
* Done can flip back. quoteflow-v3's Stop hooks (type check, ship gate) send Claude back to work. After a Stop, only UserPromptSubmit, PreToolUse or SubagentStart mean Working again.
* The idle notification (about 60 s after Claude stops) only updates the row ("Waiting · 3m"). No new alert.
* Nothing gets stuck:
  * An interrupted turn sends no Stop, so reset on my next prompt.
  * After about 10 min with no events, show "Quiet", but only if nothing is in flight: no PreToolUse without its PostToolUse, and no pending agents. If a tool is still running, show "Running · 14m".
  * SessionEnd (for any reason, including /clear) removes that row, and SessionStart adds one. Never match rows by folder, because several sessions share one.
  * The app watches Claude's process for exit, so rows vanish if Claude quits or crashes.
* Clicking a row brings the Claude app (or Terminal) to the front. That's enough; it doesn't need to open the exact session.
* Claude already notifies me when things finish, so this app posts no macOS notifications.

**How it hooks in:**
* Every hook calls one tiny script in ~/.claude/island/: shell plus a small compiled helper. No Node or Python per call, because GSD already runs Node on every tool call.
* The helper forwards only what the app needs:
  * event, session_id, agent_id/agent_type, tool_name, cwd and session_title
  * the first ~200 characters of a Bash command
  * the file_path of Edit/Write calls, but never their content (for "files changed")
  * project and branch, worked out by the hook with /usr/bin/git on SessionStart and UserPromptSubmit (project = parent folder of `git rev-parse --path-format=absolute --git-common-dir`)
  * whether Claude's last message ends with "?"
  * Claude's PID and $TERM_PROGRAM

  Never forward tool_response. Only PermissionRequest forwards the full tool_input. The app itself never reads repo folders: they're on ~/Desktop, which would trigger a privacy prompt.
* Status hooks (SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, SubagentStart, SubagentStop, Stop, PermissionDenied, Notification) run synchronously with `"timeout": 2`. The helper connects without blocking, writes one line, doesn't wait for a reply, and exits 0 within a few ms. This keeps events in order; async hooks can arrive out of order.
* Only PermissionRequest blocks. It keeps its socket connection open, gets the answer back on it, and prints exactly:
  * allow: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
  * deny: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from the island"}}}`
* For AskUserQuestion and ExitPlanMode, the permission script exits 0 with no output.
* Fail open:
  * Exit 0 straight away with no output if the app isn't running, if I'm away (screen locked or no input for about 60 s), or if anything goes wrong. Claude's own prompt (and my phone) then take over, and overnight runs never hang.
  * Wait at most about 60 s, and exit on your own before Claude's timeout.
  * Never allow on timeout.
* Clear a card only when its request is settled: a PostToolUse or PermissionDenied with the same agent, tool and input, or a Stop or SessionEnd for that session. Other agents in the session share its session_id, so their events must not clear it. Clearing a card closes its connection, so the hook exits 0 with no output.
* Commands can contain keys. Keep them in memory only, never log or save them, and clear them when the session ends.
* Give me the exact entries to add inside the existing "hooks" object in ~/.claude/settings.json. It already has GSD SessionStart and PostToolUse hooks and a GSD statusLine. Keep them all, don't add a second "hooks" key, and don't touch statusLine. Open the file for me, I'll paste, then you check it works.
* Write a fake-event script that:
  * fires every state at the socket: 3 sessions, a 500-line command, a blocked Stop, subagents and an interrupt
  * feeds real PermissionRequest JSON to the permission script on stdin, with the app up, with it down, and on timeout

  Also add a Demo item in the menu that cycles through every state.

## 5. Settings

* A small menu-bar menu: show, hide and reorder tiles, weather city, theme (Dark, Light, or follow macOS), which apps peek, the shortcuts, sound on/off, launch at login, quit. Use submenus to keep it short.
* Show a tick next to each permission I've granted, and one line on why for any I haven't.

## Things that will trip you up (handle them from the start)

* **Xcode project:**
  * Set MACOSX_DEPLOYMENT_TARGET = 26.0. Xcode 27 only ships the macOS 27 SDK and its template defaults to 27.0, so the app wouldn't launch on 26.6.2.
  * Turn App Sandbox off. It moves Application Support into a container and blocks Music.
  * If Hardened Runtime stays on, add the apple-events and calendars entitlements. Check with `codesign -d --entitlements - <App>.app`.
* **Signing:** ad-hoc signing changes every build, so macOS forgets Calendar and Automation grants each time. Set up one stable signing identity (a self-signed certificate or a free Apple ID team; your call, tell me which) and keep the same bundle id. Check with `codesign -d -r-`, and clear stale grants with `tccutil reset <service> <bundle-id>`.
* **Notch:** use the screen whose safeAreaInsets.top > 0, not NSScreen.main. The notch runs from auxiliaryTopLeftArea.maxX to auxiliaryTopRightArea.minX, with height safeAreaInsets.top. Check it against my numbers above, and work it out again on didChangeScreenParametersNotification, because display scaling changes it. If no screen has a notch, draw a fake one at the top centre.
* **Window:** a level above .mainMenu, an NSPanel with .nonactivatingPanel set at init, and hidesOnDeactivate = false (or it vanishes after the menu opens). collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]. Keep the frame tight, because a panel over the menu bar eats clicks meant for the menu items beside it.
* **Hover:** at rest, the panel is exactly the notch rect (macOS never puts menu items under the notch). It takes mouse events and uses an NSTrackingArea (.mouseEnteredAndExited, .activeAlways). No polling.
* **Liquid Glass:** macOS 26 adds glass to standard controls on its own. Keep our views flat: no NSGlassEffectView, .glassEffect or NSVisualEffectView. The system menu will still be glass, and that's fine.
* **Launch at login:** SMAppService.mainApp.register(), only from the copy installed in ~/Applications by `make install`. If it returns requiresApproval, open Login Items for me.
* **Music:**
  * Add NSAppleEventsUsageDescription.
  * Get track and play state from the DistributedNotificationCenter "com.apple.Music.playerInfo" notification.
  * Use AppleScript only for artwork, controls and position while the tile is open, and only if Music is already running (otherwise AppleScript opens it).
  * Show the Automation tick with AEDeterminePermissionToAutomateTarget, without prompting.
* **Calendar, power and app launches** (all event-driven):
  * Calendar: requestFullAccessToEvents with NSCalendarsFullAccessUsageDescription. Write-only access can't read events.
  * Charger connected: watch for the switch from battery to AC in IOPSNotificationCreateRunLoopSource.
  * App launches: NSWorkspace.shared.notificationCenter (not NotificationCenter.default), .regular apps only.
* **Bringing apps forward:** our app is never active, so use NSWorkspace.shared.openApplication(at:configuration:) with activates = true, and use $TERM_PROGRAM to pick the right app. activate(ignoringOtherApps:) is deprecated, so it fails the warnings-as-errors build.
* **Shortcuts:**
  * Use Carbon RegisterEventHotKey, so no Accessibility permission is needed.
  * Register Allow/Deny only while a card is showing, and unregister when it closes.
  * Include Cmd or Ctrl. Option-only hotkeys may not register on macOS 15 and later.
  * Already taken by Wispr Flow: Fn, Fn+Space, Ctrl+Fn, Cmd+Ctrl+V, Cmd+Ctrl+C, Opt+1, Opt+2, Opt+O, Opt+M, Esc.
  * Already taken by my Clips app: Cmd+Shift+L.
  * Defaults are ⌃⌥Y / ⌃⌥N from ref 2 (not taken by anything above). Check them and let me change them.
* **Approvals:** use PermissionRequest, because it only fires when Claude would really ask. PreToolUse is for status only. Deny with JSON, never an exit code. Before building the card, test with a throwaway hook in this app folder's .claude/settings.local.json on this Claude Code version, then tell me what you found:
  * Does a PreToolUse allow skip Claude's prompt?
  * What does exit 2 do in PermissionRequest?
  * Does the desktop app show its own prompt while the hook waits?
  * What happens if I answer in the app or on my phone first?
* **Claude Code versions:** hooks only run after a folder is trusted, and every new worktree is a new folder. The desktop app runs its own Claude Code (2.1.295 now; Terminal has 2.1.290), so check before relying on newer fields. Claude Code updates every few days: ignore unknown fields and events, and never crash on them.
* **Socket:** a Unix socket in ~/Library/Application Support/<app>/ (folder 0700). Check the caller is me, and use one id per request. Never use a URL scheme for anything that approves, because any app or web page can open a URL. Keep the socket and hook scripts off ~/Desktop, because macOS blocks background access there.

## Rules

* Go easy on my Mac: it has 8 GB, usually with several Claude sessions and builds going. About 0% CPU at rest, no web views, small memory. No repeating timers or animation while idle; one-shot timers with tolerance are fine for the weather refresh, the Quiet timeout and calendar rollover. Stop anything you started when testing is done.
* Only touch:
  * this app's folder, ~/.claude/island/ and ~/Library/Application Support/<app>/
  * the installed app in ~/Applications and its login item
  * one signing identity in my login keychain
  * `tccutil reset` for this bundle id only

  Ask first before anything else. Never edit ~/.claude/settings.json or any other project.
* Privacy first: nothing leaves the Mac except the LRCLIB and Open-Meteo requests. No analytics, no accounts, and nothing paid or needing a key without asking me.
* Ask for each permission only when its feature is first used (Automation for Music, Calendar), and explain why in one line.
* Keep it to a few clear files, with one Theme.swift and one Tile view that every tile uses. Write a README that says how to build, run, install and remove the app, including which settings.json lines to take out. Verify with the README's own commands so it can't go stale.
* Keep PLAN.md current: the steps with their done-lines (ticked when done), the decisions I've made, and a Later list. Start the Later list with:
  * The chips row from ref 5: YouTube, Window, Messages, Clipboard, Tray, Recents, Mac.
  * The Do Not Disturb peek, if v1 couldn't do it without polling.
  * Context %. GSD's claude-ctx file only exists for Terminal sessions, so it might be estimated from the transcript instead.

  A fresh session should be able to pick up from PLAN.md.
* Commit each verified step with a short message that says why. Don't push.

