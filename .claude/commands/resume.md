---
description: Session-start re-hydration for Cove — read PLAN.md's status block and the memory notes, reconcile against git and the installed app, and propose the single NEXT action. Use this to pick up cleanly in a fresh chat.
---

You are picking up Cove (the macOS notch app in this folder) in a **fresh chat with no prior context**. Re-hydrate from the repo before doing anything. Do not assume you know where things are. Reply in James's format: "Hi James," then dot points, ≤5 numbered questions with recommended answers.

**Optional steer (overrides NEXT if given):** $ARGUMENTS

## Run the session-start protocol

1. **Read `PLAN.md`**: the top `**Status (…)**` block (what is released, what is built but not released, what James confirmed, `Next:`), then "Known quirks" and "How to work on it". Read `PROMPT.md` for James's working rules (report format, "simply?", never edit `~/.claude/settings.json`, only touch the listed folders, never fake a feature, verify with `make check` / `make run` / screenshots / `top`). Read `CLAUDE.md` if present.
2. **Read the memory notes** that were recalled for you (feedback files and `project-cove-state.md`): James's rulings, the release-after-confirmation rule, testing pitfalls (the `log` builtin, synthetic mouse moves, idle-gated screenshots).
3. **Reconcile against reality.** Report: branch · ahead of `origin/main` · pushed? · uncommitted changes · the installed version (`/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ~/Applications/Cove.app/Contents/Info.plist`) · the version in `Support/Info.plist` · the latest release on the feed (`curl -sL https://raw.githubusercontent.com/JNLW-code/cove/main/appcast.xml | grep -o '<sparkle:shortVersionString>[^<]*' | head -1`) · is Cove running (`pgrep -x Cove`). **Report any drift** between PLAN.md and reality before taking the task. A built-but-unreleased version is a standing item: say so and offer the `make release` line.
4. **If NEXT is a UI step, open the mockup it points at** (`docs/mockups/full.html`, in Chrome, the named state) and say in one line what you are building from.
5. **Check the log for errors since last launch**: `/usr/bin/log show --predicate 'subsystem == "com.jameswebster.cove"' --last 30m --style compact | grep -E " E | F "`. Mention anything found.

## Then
Give a **tight re-hydration report**:
- Where we are (version released / installed / built, branch, pushed).
- Anything owed (an unreleased build, something James has not tried yet).
- **NEXT**: the single next action as a clear recommendation, not a menu. If `$ARGUMENTS` steered elsewhere, go with that and say so.

Then **wait for "go"** before building. For a trivially small, low-risk NEXT you may proceed and report. Every verified step gets committed, and once James confirms it, released (`feedback-release-after-confirmation`).
