import CoreGraphics
import Darwin
import Foundation

// cove-hook <event>
// Reads the hook JSON on stdin, sends one trimmed JSON line to Cove's socket, exits 0.
// Status events never wait. PermissionRequest keeps the connection open for the answer (at most 60 s).
// Anything wrong → exit 0 with no output, so Claude's own prompt takes over.

let socketPath = NSHomeDirectory() + "/Library/Application Support/Cove/cove.sock"
let waitSeconds: TimeInterval = ProcessInfo.processInfo.environment["COVE_HOOK_WAIT"].flatMap(Double.init) ?? 60
/// How long a Stop hook waits for a reply typed in the island when Claude's message ends with a question.
let replySeconds: TimeInterval = ProcessInfo.processInfo.environment["COVE_HOOK_WAIT_STOP"].flatMap(Double.init) ?? 45
let awaySeconds: Double = ProcessInfo.processInfo.environment["COVE_HOOK_AWAY"].flatMap(Double.init) ?? 60
let commandLimit = 200

func finish() -> Never { exit(0) }

guard CommandLine.arguments.count >= 2 else { finish() }
let event = CommandLine.arguments[1]
let raw = FileHandle.standardInput.readDataToEndOfFile()
guard raw.count < 4_000_000,
      let any = try? JSONSerialization.jsonObject(with: raw), let input = any as? [String: Any] else { finish() }

func str(_ key: String) -> String? { input[key] as? String }

var message: [String: Any] = ["v": 1, "event": event]
for key in ["session_id", "agent_id", "agent_type", "tool_name", "tool_use_id", "cwd", "session_title",
            "source", "reason", "notification_type", "permission_mode", "stop_hook_active"] {
    if let value = input[key] { message[key] = value }
}
if let pid = ProcessInfo.processInfo.environment["CLAUDE_PID"].flatMap(Int32.init) { message["pid"] = pid }
message["term"] = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? ""
// The desktop app's own session id, so a click on the row can open that exact session.
if let host = ProcessInfo.processInfo.environment["CLAUDE_CODE_HOST_SESSION_ID"], !host.isEmpty { message["host_session_id"] = host }

let toolInput = input["tool_input"] as? [String: Any]
let toolName = str("tool_name") ?? ""

/// A stable key for "the same request": tool name + the whole tool input, so PostToolUse can settle a card.
@MainActor func inputKey() -> String? {
    guard let toolInput, let data = try? JSONSerialization.data(withJSONObject: toolInput, options: [.sortedKeys]) else { return nil }
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in [UInt8](data) { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
    return toolName + ":" + String(hash, radix: 16)
}

switch event {
case "PreToolUse", "PostToolUse", "PermissionDenied":
    if let key = inputKey() { message["input_key"] = key }
    if toolName == "Bash", let command = toolInput?["command"] as? String {
        message["command"] = String(command.prefix(commandLimit))
    }
    if ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(toolName) {
        if let path = (toolInput?["file_path"] ?? toolInput?["notebook_path"]) as? String { message["file_path"] = path }
    }
case "Stop", "SubagentStop":
    if let last = str("last_assistant_message") {
        let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines)
        message["ends_with_question"] = trimmed.hasSuffix("?")
        if event == "Stop" {
            message["last_message"] = String(trimmed.prefix(1500))
            if trimmed.hasSuffix("?") { message["request_id"] = UUID().uuidString }
        }
    }
case "PermissionRequest":
    if let key = inputKey() { message["input_key"] = key }
    if let toolInput { message["tool_input"] = toolInput }
    message["request_id"] = UUID().uuidString
default:
    break
}

/// project = parent folder of the git common dir (so worktrees and subfolders show the main repo), branch = current branch.
@MainActor func git(_ args: [String], in cwd: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", cwd] + args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    // The whole hook has 2 s; give git 1 s and move on without project/branch if it is slower.
    let deadline = Date().addingTimeInterval(1)
    while process.isRunning && Date() < deadline { usleep(5000) }
    if process.isRunning { process.terminate(); return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0, let out = String(data: data, encoding: .utf8) else { return nil }
    let line = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return line.isEmpty ? nil : line
}

if event == "SessionStart" || event == "UserPromptSubmit", let cwd = str("cwd") {
    if let common = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: cwd) {
        message["project"] = URL(fileURLWithPath: common).deletingLastPathComponent().lastPathComponent
        if let branch = git(["rev-parse", "--abbrev-ref", "HEAD"], in: cwd) { message["branch"] = branch }
    }
}

// MARK: Send

guard let payload = try? JSONSerialization.data(withJSONObject: message), payload.count < 2_000_000 else { finish() }

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { finish() }
var one: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { finish() }
withUnsafeMutableBytes(of: &address.sun_path) { buffer in
    for (i, byte) in pathBytes.enumerated() { buffer[i] = byte }
    buffer[pathBytes.count] = 0
}
let connected = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard connected == 0 else { finish() }

var line = payload
line.append(0x0A)
let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
guard written == line.count else { finish() }

let waitsForReply = event == "Stop" && message["request_id"] != nil
guard event == "PermissionRequest" || waitsForReply else { finish() }

// AskUserQuestion and ExitPlanMode are never answered from the island; the app was told, Claude asks as usual.
if toolName == "AskUserQuestion" || toolName == "ExitPlanMode" { finish() }

// Away (screen locked, or no input for a minute) → let Claude's own prompt and the phone handle it.
if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
   (session["CGSSessionScreenIsLocked"] as? Bool) == true { finish() }
let inputTypes: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel, .flagsChanged,
                                 .leftMouseDragged, .otherMouseDown, .tabletPointer]
let idle = inputTypes.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
if idle > awaySeconds { finish() }

// Wait for one reply line, at most waitSeconds (replySeconds for a Stop). Closed connection or timeout → no output.
let maxWait = waitsForReply ? replySeconds : waitSeconds
var timeout = timeval(tv_sec: Int(maxWait), tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
var reply = Data()
var buffer = [UInt8](repeating: 0, count: 4096)
let deadline = Date().addingTimeInterval(maxWait)
while Date() < deadline {
    let n = read(fd, &buffer, buffer.count)
    if n <= 0 { break }
    reply.append(buffer, count: n)
    if reply.contains(0x0A) { break }
}
close(fd)
guard let replyAny = try? JSONSerialization.jsonObject(with: reply.prefix(while: { $0 != 0x0A })),
      let replyObject = replyAny as? [String: Any],
      replyObject["request_id"] as? String == message["request_id"] as? String else { finish() }

// A Stop reply: James typed an answer in the island; Claude carries on with it.
if waitsForReply {
    if let text = replyObject["reply"] as? String, !text.isEmpty,
       let out = try? JSONSerialization.data(withJSONObject: ["decision": "block", "reason": text]),
       let line = String(data: out, encoding: .utf8) { print(line) }
    finish()
}
guard let decision = replyObject["decision"] as? String else { finish() }

switch decision {
case "allow":
    print(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
case "deny":
    print(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from the island"}}}"#)
default:
    break
}
finish()
