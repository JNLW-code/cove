---
description: Session-close handoff for Cove — reconcile git, update PLAN.md's top status block with the single NEXT action, save durable decisions to memory, release if a step was confirmed, and print the line to start the next chat with. Run BEFORE /clear when context is getting long.
---

You are closing this session so a **fresh chat with zero context can pick up exactly where we left off**. In this repo the state lives in **PLAN.md's top status block + the memory files**, not in this chat. Make them current NOW, while you still have the context to be accurate. Do not skip a step. Reply in James's format: "Hi James," then dot points.

**Optional focus / note for the handoff:** $ARGUMENTS

## Do this, in order

1. **Reconcile git.** Report: branch · commits ahead of `origin/main` · pushed? · uncommitted changes. Flag any drift between what was claimed done and what is actually committed. Everything in this repo is committed per verified step, so uncommitted work at wrap time is a miss to surface.

2. **Release check (James's standing rule: "live is when I finish").** If a step was confirmed by James this session and not yet released: bump `CFBundleShortVersionString` in `Support/Info.plist`, write `release/notes.md`, run `make release`, then `make install`. If `make release` is blocked by the session's permissions, say so plainly and give James the one-line `make release` to run himself. Never leave a confirmed step unreleased without saying it.

3. **Update PLAN.md's top `**Status (…)**` block** (replace it, do not append): date and time · what is released and installed (version on James's Mac, version on the feed) · what is built but not released · what James confirmed this session · what is still untried by him · **`Next:` the single next action**, specific (a file, a feature, the mockup state to build from), not "continue the work". Add a short dated section further down for anything built this session, in the style of the existing ones (what, where in the code, how it was verified, numbers). Keep "Known quirks" and "How to work on it" current.

4. **Save durable decisions to memory** (`~/.claude/projects/-Users-jameswebster-Desktop-notch-island/memory/`): James's rulings and preferences → a `feedback-*` file; project state a fresh session needs that the repo does not record → `project-cove-state.md`; new pitfalls that cost time → the same file. Update `MEMORY.md`'s index line if the description changed. Never store what PLAN.md or the code already says. List what you saved.

5. **Commit the wrap's own output without asking** (`PLAN.md`, `README.md` if touched) with a message like `PLAN: wrap-up for a fresh session; next is <X>`, then `git push origin main`. This exemption covers the handoff files only; product code still goes through the normal step-and-verify flow.

6. **Honest status + the resume line.** Print: Done / Not done / Released / Need from you, as dot points, then the **exact first message for the next chat** — normally `/resume`, or `/resume <steer>` if James named a different next step.

Then tell James he can `/clear` and start with that line. If context is still healthy and he would rather keep going, suggest `/compact` instead.
