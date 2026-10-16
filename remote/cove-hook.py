#!/usr/bin/env python3
"""Cove's hook helper for a machine you reach over SSH (Linux or macOS, Python 3.6+).

Claude Code runs its hooks where it runs. On a server that is the server, so this file does what the Mac helper
does, and sends the event down the SSH tunnel to Cove: `RemoteForward 127.0.0.1:47925 <cove.sock>` in the Mac's
~/.ssh/config turns the server's localhost:47925 into Cove's socket.

Usage (from hook.sh): cove-hook.py <event>, hook JSON on stdin. Status events never wait. PermissionRequest,
and a Stop whose message ends with a question, keep the connection open for the island's answer (60 s / 45 s).
Anything wrong -> exit 0 with no output, so Claude's own prompt takes over. Never prints anything else.
"""
import json
import os
import re
import socket
import subprocess
import sys
import time
import uuid

PORT = int(os.environ.get("COVE_PORT", "47925"))
SOCK = os.environ.get("COVE_SOCK")            # a Unix socket path instead of the TCP port (used by the tests)
WAIT = float(os.environ.get("COVE_HOOK_WAIT", "60"))
WAIT_STOP = float(os.environ.get("COVE_HOOK_WAIT_STOP", "45"))
TERM = os.environ.get("COVE_TERM") or "ssh"   # the Mac terminal the SSH session lives in, set by hook.sh
COMMAND_LIMIT = 200
START = time.time()


def finish():
    sys.exit(0)


def main():
    if len(sys.argv) < 2:
        finish()
    event = sys.argv[1]
    raw = sys.stdin.buffer.read(4_000_000)
    try:
        data = json.loads(raw.decode("utf-8"))
    except Exception:
        finish()
    if not isinstance(data, dict):
        finish()

    message = {"v": 1, "event": event}
    for key in ("session_id", "agent_id", "agent_type", "tool_name", "tool_use_id", "cwd", "session_title",
                "source", "reason", "notification_type", "permission_mode", "stop_hook_active"):
        if key in data:
            message[key] = data[key]
    # transcript_path is not sent: it is a path on this machine, which Cove cannot read.
    transcript = data.get("transcript_path")
    if "session_title" not in message and isinstance(transcript, str) and transcript.endswith(".jsonl"):
        try:
            with open(transcript[:-6] + "/custom-title.json", "r", encoding="utf-8") as f:
                title = json.load(f).get("customTitle")
            if isinstance(title, str) and title:
                message["session_title"] = title
        except Exception:
            pass
    message["term"] = TERM
    message["host"] = socket.gethostname().split(".")[0]

    tool_input = data.get("tool_input") if isinstance(data.get("tool_input"), dict) else None
    tool_name = data.get("tool_name") if isinstance(data.get("tool_name"), str) else ""

    def input_key():
        if tool_input is None:
            return None
        blob = json.dumps(tool_input, sort_keys=True, separators=(",", ":")).encode("utf-8")
        h = 1469598103934665603
        for b in blob:
            h = ((h ^ b) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
        return "%s:%x" % (tool_name, h)

    if event in ("PreToolUse", "PostToolUse", "PermissionDenied"):
        key = input_key()
        if key:
            message["input_key"] = key
        if tool_name == "Bash" and tool_input and isinstance(tool_input.get("command"), str):
            message["command"] = tool_input["command"][:COMMAND_LIMIT]
        if tool_name in ("Edit", "Write", "MultiEdit", "NotebookEdit") and tool_input:
            path = tool_input.get("file_path") or tool_input.get("notebook_path")
            if isinstance(path, str):
                message["file_path"] = path
    elif event in ("Stop", "SubagentStop"):
        last = data.get("last_assistant_message")
        if isinstance(last, str):
            trimmed = last.strip()
            message["ends_with_question"] = trimmed.endswith("?")
            if event == "Stop":
                message["last_message"] = trimmed[:1500]
                if trimmed.endswith("?"):
                    message["request_id"] = str(uuid.uuid4()).upper()
    elif event == "PermissionRequest":
        key = input_key()
        if key:
            message["input_key"] = key
        if tool_input is not None:
            message["tool_input"] = tool_input
        message["request_id"] = str(uuid.uuid4()).upper()

    if event in ("Stop", "UserPromptSubmit"):
        tokens = context_tokens(transcript)
        if tokens:
            message["context_tokens"] = tokens

    cwd = data.get("cwd")
    if event in ("SessionStart", "UserPromptSubmit", "Stop") and isinstance(cwd, str):
        common = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], cwd)
        if common:
            message["project"] = os.path.basename(os.path.dirname(common.rstrip("/")))
            branch = git(["rev-parse", "--abbrev-ref", "HEAD"], cwd)
            if branch:
                message["branch"] = branch
            status = git(["status", "--porcelain", "--untracked-files=normal"], cwd, allow_empty=True)
            if status is not None:
                message["dirty"] = 0 if status == "" else len(status.split("\n"))
            ahead = git(["rev-list", "--count", "@{upstream}..HEAD"], cwd)
            if ahead and ahead.isdigit():
                message["ahead"] = int(ahead)

    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    if len(payload) >= 2_000_000:
        finish()

    try:
        if SOCK:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(1)
            s.connect(SOCK)
        else:
            s = socket.create_connection(("127.0.0.1", PORT), timeout=1)
        s.sendall(payload + b"\n")
    except Exception:
        finish()

    waits_for_reply = event == "Stop" and "request_id" in message
    if event != "PermissionRequest" and not waits_for_reply:
        finish()

    max_wait = WAIT_STOP if waits_for_reply else WAIT
    reply = b""
    deadline = time.time() + max_wait
    try:
        while time.time() < deadline:
            s.settimeout(max(0.1, deadline - time.time()))
            chunk = s.recv(4096)
            if not chunk:
                break
            reply += chunk
            if b"\n" in reply:
                break
    except Exception:
        pass
    finally:
        try:
            s.close()
        except Exception:
            pass
    try:
        obj = json.loads(reply.split(b"\n", 1)[0].decode("utf-8"))
    except Exception:
        finish()
    if not isinstance(obj, dict) or obj.get("request_id") != message.get("request_id"):
        finish()

    if waits_for_reply:
        text = obj.get("reply")
        if isinstance(text, str) and text:
            print(json.dumps({"decision": "block", "reason": text}))
        finish()
    if tool_name == "AskUserQuestion":
        answers = obj.get("answers")
        if not isinstance(answers, dict) or not answers or tool_input is None:
            finish()
        updated = dict(tool_input)
        updated["answers"] = answers
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                                                 "decision": {"behavior": "allow", "updatedInput": updated}}}))
        finish()
    decision = obj.get("decision")
    if decision == "allow":
        if tool_name == "ExitPlanMode" and tool_input is not None:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                                                     "decision": {"behavior": "allow", "updatedInput": tool_input}}}))
        else:
            print('{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}')
    elif decision == "deny":
        why = obj.get("message")
        if not isinstance(why, str) or not why:
            why = "Denied from the island"
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                                                 "decision": {"behavior": "deny", "message": why}}}))
    finish()


def git(args, cwd, allow_empty=False):
    """One git call with a 1 s cap, and 1.6 s for all of them together; nothing when git is slow or absent."""
    budget = min(1.0, 1.6 - (time.time() - START))
    if budget <= 0:
        return None
    try:
        out = subprocess.run(["git", "-C", cwd] + args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             timeout=budget)
    except Exception:
        return None
    if out.returncode != 0:
        return None
    line = out.stdout.decode("utf-8", "replace").strip()
    if line == "" and not allow_empty:
        return None
    return line


def context_tokens(transcript):
    """The last usage block in the transcript's tail: input + cache tokens, for the context %."""
    if not isinstance(transcript, str):
        return None
    try:
        with open(transcript, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 262144))
            tail = f.read().decode("utf-8", "replace")
    except Exception:
        return None
    blocks = re.findall(r'"usage":\{[^}]*\}', tail)
    if not blocks:
        return None
    block = blocks[-1]

    def number(key):
        m = re.search(r'"%s":(\d+)' % key, block)
        return int(m.group(1)) if m else 0

    total = number("input_tokens") + number("cache_creation_input_tokens") + number("cache_read_input_tokens")
    return total if total > 0 else None


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)
