#!/bin/bash
# Drives every Claude state through Cove's socket: three sessions, a 500-line command, a blocked Stop,
# subagents and an interrupt. Then feeds real PermissionRequest JSON to the hook helper with the app up,
# with it down (pass "down" after quitting Cove) and on timeout. Usage: scripts/fake-events.sh [up|down|keep|rows|question]
# "question" feeds a two-part AskUserQuestion to the helper and prints what the helper answers with.
set -u
SOCK="$HOME/Library/Application Support/Cove/cove.sock"
HELPER="${COVE_HOOK:-$(dirname "$0")/../.build/release/cove-hook}"
MODE="${1:-up}"
export COVE_HOOK_AWAY=${COVE_HOOK_AWAY:-999999}   # tests ignore the away check
send() { printf '%s\n' "$1" | nc -U "$SOCK" 2>/dev/null; }
ev()   { send "{\"v\":1,\"event\":\"$1\",\"session_id\":\"$2\",$3}"; sleep "${4:-0.4}"; }
A=fake-quoteflow; B=fake-worktree; C=fake-home
TRANSCRIPT="$(cd "$(dirname "$0")" && pwd)/fake-transcript.jsonl"   # 3 prompts, two Fable messages ≈ $0.93 (one of them written as two rows)
QF='"cwd":"/Users/jameswebster/Desktop/quoteflow-v3","project":"quoteflow-v3","branch":"feat/notch","term":"claude-desktop","pid":1,"transcript_path":"'"$TRANSCRIPT"'"'
WT='"cwd":"/Users/jameswebster/Desktop/qf-wt-rec","project":"quoteflow-v3","branch":"rec-fix","term":"Apple_Terminal","pid":1'
HM='"cwd":"/Users/jameswebster","term":"claude-desktop","pid":1'

if [ "$MODE" = down ]; then
  echo "== helper with the app down (expect: no output, exit 0, instant)"
  printf '{"session_id":"x","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"ls"}}' | /usr/bin/time -p "$HELPER" PermissionRequest; echo "exit $?"
  exit 0
fi
[ -S "$SOCK" ] || { echo "Cove is not running (no socket at $SOCK)"; exit 1; }
if [ "$MODE" = plan ]; then
  echo "== ExitPlanMode through the real helper (Approve / Keep planning on the island, or test.allow / test.deny with COVE_UI_TEST=1)"
  python3 -c 'import json,sys; plan="# Add git badges to rows\n\n" + "\n".join(f"{i}. Step {i}: do the thing, check it, commit." for i in range(1,31)); print(json.dumps({"session_id":sys.argv[1],"cwd":"/Users/jameswebster/Desktop/quoteflow-v3","permission_mode":"plan","hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode","tool_input":{"plan":plan,"planFilePath":"/tmp/plan.md"}}))' "$A" \
    | COVE_HOOK_WAIT=${COVE_HOOK_WAIT:-40} /usr/bin/time -p "$HELPER" PermissionRequest; echo "exit $?"
  exit 0
fi
if [ "$MODE" = question ]; then
  echo "== AskUserQuestion through the real helper (answer it on the island, or notifyutil -p com.jameswebster.cove.test.answerq with COVE_UI_TEST=1)"
  printf '{"session_id":"%s","cwd":"/Users/jameswebster/Desktop/quoteflow-v3","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which layout should the settings page use?","header":"Layout","options":[{"label":"Tabs","description":"One tab per section, like System Settings"},{"label":"One page","description":"Everything on one scrolling page"},{"label":"Sidebar","description":"Sections down the left, content on the right"}],"multiSelect":false},{"question":"Which of these should it remember between launches?","header":"Memory","options":[{"label":"Window size","description":""},{"label":"Last tab","description":""},{"label":"Search text","description":""}],"multiSelect":true}]}}' "$A" \
    | COVE_HOOK_WAIT=${COVE_HOOK_WAIT:-40} /usr/bin/time -p "$HELPER" PermissionRequest; echo "exit $?"
  exit 0
fi

echo "== three sessions start"
ev SessionStart $A "$QF,\"source\":\"startup\""
ev SessionStart $B "$WT,\"source\":\"startup\""
ev SessionStart $C "$HM,\"source\":\"startup\""
echo "== A works: thinking → checking → editing, 3 agents"
ev UserPromptSubmit $A "$QF" 1.5
ev PreToolUse $A "\"tool_name\":\"Bash\",\"tool_use_id\":\"t1\",\"command\":\"npm run check\",\"input_key\":\"k1\"" 1.5
ev PostToolUse $A "\"tool_name\":\"Bash\",\"tool_use_id\":\"t1\",\"input_key\":\"k1\""
ev PreToolUse $A "\"tool_name\":\"Edit\",\"tool_use_id\":\"t2\",\"file_path\":\"/x/a.ts\",\"input_key\":\"k2\"" 1
ev PostToolUse $A "\"tool_name\":\"Edit\",\"tool_use_id\":\"t2\",\"file_path\":\"/x/a.ts\",\"input_key\":\"k2\""
ev SubagentStart $A "\"agent_id\":\"ag1\",\"agent_type\":\"Explore\""
ev SubagentStart $A "\"agent_id\":\"ag2\",\"agent_type\":\"Explore\""
ev SubagentStart $A "\"agent_id\":\"ag3\",\"agent_type\":\"Plan\""
ev PreToolUse $A "\"agent_id\":\"ag1\",\"tool_name\":\"Grep\",\"tool_use_id\":\"t3\",\"input_key\":\"k3\"" 1.5
echo "== B: git, then an interrupt (new prompt, no Stop)"
ev UserPromptSubmit $B "$WT" 1
ev PreToolUse $B "\"tool_name\":\"Bash\",\"tool_use_id\":\"t4\",\"command\":\"git status\",\"input_key\":\"k4\"" 1.5
ev UserPromptSubmit $B "$WT" 1
ev PreToolUse $B "\"tool_name\":\"Read\",\"tool_use_id\":\"t5\",\"input_key\":\"k5\"" 1
ev PostToolUse $B "\"tool_name\":\"Read\",\"tool_use_id\":\"t5\",\"input_key\":\"k5\""
echo "== C: no repo, read, stop, idle"
ev UserPromptSubmit $C "$HM" 1
ev PreToolUse $C "\"tool_name\":\"Read\",\"tool_use_id\":\"t6\",\"input_key\":\"k6\"" 1
ev PostToolUse $C "\"tool_name\":\"Read\",\"tool_use_id\":\"t6\",\"input_key\":\"k6\""
ev Stop $C "\"ends_with_question\":true" 1
ev Notification $C "\"notification_type\":\"idle_prompt\"" 1
echo "== A: blocked by auto mode (peek), then a Stop that gets sent back to work, then real Stop"
ev PermissionDenied $A "\"tool_name\":\"Bash\",\"command\":\"rm -rf .next\",\"input_key\":\"k7\",\"reason\":\"[Irreversible Local Destruction]\"" 3
ev SubagentStop $A "\"agent_id\":\"ag1\""
ev Stop $A "\"ends_with_question\":false" 2
ev PreToolUse $A "\"tool_name\":\"Bash\",\"tool_use_id\":\"t8\",\"command\":\"npm run check\",\"input_key\":\"k8\"" 2
ev PostToolUse $A "\"tool_name\":\"Bash\",\"tool_use_id\":\"t8\",\"input_key\":\"k8\""
ev Stop $A "\"ends_with_question\":false,\"project\":\"quoteflow-v3\",\"branch\":\"feat/notch\",\"dirty\":3,\"ahead\":2" 2
if [ "$MODE" = rows ]; then echo "rows only, keeping the sessions"; exit 0; fi
echo "== A: a 500-line command through the real helper (app up: card until settled by Stop)"
python3 -c 'import json,sys; cmd="\n".join(f"line {i}: psql \"$DATABASE_URL\" -c \"ALTER TABLE quotes ADD COLUMN IF NOT EXISTS note_{i} text;\"" for i in range(1,501)); print(json.dumps({"session_id":sys.argv[1],"cwd":"/Users/jameswebster/Desktop/quoteflow-v3","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":cmd}}))' "$A" > /tmp/cove-perm.json
( COVE_HOOK_WAIT=20 "$HELPER" PermissionRequest < /tmp/cove-perm.json > /tmp/cove-perm.out; echo "helper (app up, settled by Stop) exit $? output: $(cat /tmp/cove-perm.out)" ) &
sleep 4
ev Stop $A "\"ends_with_question\":false" 2
wait
echo "== helper timeout: app up, nobody answers for 3 s (expect: no output, exit 0 after ~3 s)"
printf '{"session_id":"%s","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"touch x"}}' "$A" | COVE_HOOK_WAIT=3 /usr/bin/time -p "$HELPER" PermissionRequest; echo "exit $?"
rm -f /tmp/cove-perm.json /tmp/cove-perm.out
if [ "$MODE" = keep ]; then echo "keeping the three sessions"; exit 0; fi
sleep 2
echo "== sessions end"
ev SessionEnd $A "\"reason\":\"other\"" 0.2
ev SessionEnd $B "\"reason\":\"clear\"" 0.2
ev SessionEnd $C "\"reason\":\"other\"" 0.2
echo "done"
