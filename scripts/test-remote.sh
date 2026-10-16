#!/bin/sh
# The SSH path without SSH: a TCP relay on 127.0.0.1:47925 stands in for the tunnel, and the Python helper is driven
# with the same events the real hooks send. Needs Cove launched with COVE_UI_TEST=1 (for test.allow / test.reply).
set -eu
cd "$(dirname "$0")/.."
SOCK="$HOME/Library/Application Support/Cove/cove.sock"
[ -S "$SOCK" ] || { echo "Cove is not running"; exit 1; }
python3 -I - "$SOCK" <<'PY' &
import socket, socketserver, sys, threading
sock = sys.argv[1]
class Relay(socketserver.BaseRequestHandler):
    def handle(self):
        u = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); u.connect(sock)
        def pump(a, b):
            try:
                while True:
                    d = a.recv(4096)
                    if not d: break
                    b.sendall(d)
            except Exception: pass
            try: b.shutdown(socket.SHUT_WR)
            except Exception: pass
        t = threading.Thread(target=pump, args=(self.request, u)); t.start()
        pump(u, self.request); t.join()
socketserver.ThreadingTCPServer.allow_reuse_address = True
socketserver.ThreadingTCPServer(("127.0.0.1", 47925), Relay).serve_forever()
PY
RELAY=$!
trap 'kill $RELAY 2>/dev/null || true' EXIT
sleep 0.5
H=remote/cove-hook.py; S=remote-test; CWD="$PWD"
ev() { printf '%s' "$2" | COVE_TERM=Apple_Terminal python3 $H "$1"; }
echo "== session start, prompt, a Bash tool"
ev SessionStart "{\"session_id\":\"$S\",\"cwd\":\"$CWD\",\"source\":\"startup\"}"
ev UserPromptSubmit "{\"session_id\":\"$S\",\"cwd\":\"$CWD\"}"
ev PreToolUse "{\"session_id\":\"$S\",\"cwd\":\"$CWD\",\"tool_name\":\"Bash\",\"tool_use_id\":\"t1\",\"tool_input\":{\"command\":\"ls\"}}"
sleep 1
ev PostToolUse "{\"session_id\":\"$S\",\"cwd\":\"$CWD\",\"tool_name\":\"Bash\",\"tool_use_id\":\"t1\",\"tool_input\":{\"command\":\"ls\"}}"
echo "== permission request: the island answers Allow after 1.5 s (expect the allow JSON)"
( sleep 1.5; notifyutil -p com.jameswebster.cove.test.allow ) &
OUT=$(printf '%s' "{\"session_id\":\"$S\",\"cwd\":\"$CWD\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"touch x\"}}" | COVE_HOOK_WAIT=10 python3 $H PermissionRequest)
echo "$OUT"; echo "$OUT" | grep -q '"behavior": *"allow"' && echo "allow came back through the relay"
echo "== stop with a question: a reply typed on the island comes back as a block (expect decision block)"
( sleep 2; notifyutil -p com.jameswebster.cove.test.reply ) &
OUT=$(printf '%s' "{\"session_id\":\"$S\",\"cwd\":\"$CWD\",\"last_assistant_message\":\"Which colour do you want?\"}" | COVE_HOOK_WAIT_STOP=10 python3 $H Stop)
echo "$OUT"; echo "$OUT" | grep -q '"decision": "block"' && echo "reply came back through the relay"
echo "== timeout with nobody answering (expect no output, ~2 s)"
printf '%s' "{\"session_id\":\"$S\",\"cwd\":\"$CWD\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}" | COVE_HOOK_WAIT=2 python3 $H PermissionRequest; echo "exit $?"
ev SessionEnd "{\"session_id\":\"$S\",\"cwd\":\"$CWD\",\"reason\":\"other\"}"
echo "remote test done"
