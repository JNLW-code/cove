import Foundation

/// One line of a session's conversation, read from its transcript: James's prompt, Claude's text, or a tool call.
struct ChatItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case prompt(String)
        case text(String)
        case tool(ToolCall)
    }

    let id: String      // the transcript row's uuid
    var kind: Kind
    let time: Date?
}

/// A tool Claude used: "Edit checkout.ts", "npm test", "Grep hoverShade". Ticked once its result is in.
struct ToolCall: Equatable, Sendable {
    let useID: String
    let name: String
    let detail: String
    var done = false
    var failed = false
    /// For Bash: the first part of what the command printed (stdout then stderr), for the Terminal tab.
    var output: String?

    /// Short plain words for the tool line. The command's first line for Bash, the file name for file tools.
    static func describe(name: String, input: [String: Any]) -> String {
        func file() -> String? { (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } }
        func clip(_ s: String, _ n: Int = 70) -> String {
            let line = s.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? s
            return line.count > n ? String(line.prefix(n - 1)) + "…" : line
        }
        switch name {
        case "Bash":
            // Claude Code sends a plain-words description with most commands ("Run the tests"); the command itself otherwise.
            if let description = input["description"] as? String, !description.isEmpty { return clip(description, 60) }
            return clip((input["command"] as? String) ?? "command", 60)
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit", "NotebookRead":
            return "\(name == "MultiEdit" ? "Edit" : name) \(file() ?? "file")"
        case "Grep", "Glob":
            return "\(name) \(clip((input["pattern"] as? String) ?? "", 40))"
        case "Agent", "Task":
            return "Agent: \(clip((input["description"] as? String) ?? "task", 50))"
        case "WebFetch", "WebSearch":
            let what = (input["url"] as? String).flatMap { URL(string: $0)?.host } ?? (input["query"] as? String) ?? ""
            return "\(name == "WebFetch" ? "Fetch" : "Search") \(clip(what, 40))"
        case "TodoWrite":
            return "Todo list"
        case "AskUserQuestion":
            return "Asked a question"
        case "ExitPlanMode":
            return "Plan ready"
        case "Skill":
            return "Skill \(clip((input["skill"] as? String) ?? "", 30))"
        default:
            if name.hasPrefix("mcp__") {
                let parts = name.split(separator: "_", omittingEmptySubsequences: true).map(String.init)
                let server = parts.count > 1 ? parts[1] : "Tool"
                let tool = parts.count > 2 ? parts[2...].joined(separator: " ").replacingOccurrences(of: "-", with: " ") : ""
                return "\(server.capitalized) \(tool)".trimmingCharacters(in: .whitespaces)
            }
            return name
        }
    }
}

/// One Edit or Write from the transcript, for the Diff tab. Edits carry the exact old and new text Claude sent.
struct FileChange: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let isWrite: Bool
    let oldText: String
    let newText: String
    /// Which prompt of James's this followed (counted from the start of what was read).
    let turn: Int
    let time: Date?

    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var added: Int { newText.isEmpty ? 0 : newText.split(separator: "\n", omittingEmptySubsequences: false).count }
    var removed: Int { oldText.isEmpty ? 0 : oldText.split(separator: "\n", omittingEmptySubsequences: false).count }
}

/// One line of Claude's TodoWrite list: pending, in_progress or completed.
struct TodoItem: Equatable, Sendable {
    let content: String
    let status: String
}

/// A file Claude read or changed this session, with how often.
struct FileTouch: Identifiable, Equatable, Sendable {
    var id: String { path }
    let path: String
    var reads = 0
    var edits = 0
    var last: Date?
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

/// Everything the panel shows for a session, read from its transcript.
struct ChatSnapshot: Equatable, Sendable {
    var items: [ChatItem] = []
    var changes: [FileChange] = []
    var todos: [TodoItem] = []
    var plan: String?
    var files: [FileTouch] = []
    /// The number of prompts seen so far; the current turn's changes carry this number.
    var turn = 0
}

/// Reads a session's main transcript (`~/.claude/projects/…/<session>.jsonl`) into chat items, a bit at a time:
/// the first read takes only the last 1.5 MB of a long file, every later one only the bytes written since.
/// Subagent files are not read (their work shows as one "Agent" line). Nothing here is ever logged.
actor ChatReader {
    private struct State {
        var offset: UInt64 = 0
        var remainder = Data()
        var skipPartialLine = false
        var snapshot = ChatSnapshot()
        var items: [ChatItem] {
            get { snapshot.items }
            set { snapshot.items = newValue }
        }
    }

    private var states: [String: State] = [:]
    static let tailBytes: UInt64 = 1_500_000
    static let chunk = 1024 * 1024
    static let maxItems = 300
    static let maxChanges = 150
    static let maxFiles = 200
    static let maxOutput = 1500
    static let maxChangeText = 8000

    /// The snapshot for a session, up to date with its transcript file.
    func load(session: String, transcript: String) -> ChatSnapshot {
        var state = states[session] ?? State()
        read(transcript, into: &state)
        states[session] = state
        return state.snapshot
    }

    func forget(session: String) { states[session] = nil }

    private func read(_ path: String, into state: inout State) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < state.offset { state = State() }   // rewritten from the start: read it again
        if state.offset == 0, state.items.isEmpty, size > Self.tailBytes {
            state.offset = size - Self.tailBytes
            state.skipPartialLine = true
        }
        guard size > state.offset, (try? handle.seek(toOffset: state.offset)) != nil else { return }
        while let data = try? handle.read(upToCount: Self.chunk), !data.isEmpty {
            state.offset += UInt64(data.count)
            state.remainder.append(data)
            var start = state.remainder.startIndex
            while let newline = state.remainder[start...].firstIndex(of: 0x0A) {
                if state.skipPartialLine { state.skipPartialLine = false } else { process(state.remainder[start..<newline], into: &state) }
                start = newline + 1
            }
            state.remainder = Data(state.remainder[start...])
        }
        if state.items.count > Self.maxItems { state.items.removeFirst(state.items.count - Self.maxItems) }
        if state.snapshot.changes.count > Self.maxChanges { state.snapshot.changes.removeFirst(state.snapshot.changes.count - Self.maxChanges) }
        if state.snapshot.files.count > Self.maxFiles {
            state.snapshot.files.sort { ($0.last ?? .distantPast) > ($1.last ?? .distantPast) }
            state.snapshot.files.removeLast(state.snapshot.files.count - Self.maxFiles)
        }
    }

    private func process(_ line: Data, into state: inout State) {
        guard line.range(of: Data("\"type\":\"user\"".utf8)) != nil || line.range(of: Data("\"type\":\"assistant\"".utf8)) != nil,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = object["type"] as? String, type == "user" || type == "assistant",
              object["isSidechain"] as? Bool != true,          // subagent rows live in their own files anyway
              object["isMeta"] as? Bool != true,               // injected context, not something James typed
              let message = object["message"] as? [String: Any] else { return }
        let uuid = (object["uuid"] as? String) ?? UUID().uuidString
        let time = (object["timestamp"] as? String).flatMap { ISO8601DateFormatter.shared.date(from: $0) }
        if type == "user" {
            if let text = message["content"] as? String {
                if let shown = Self.promptText(text) {
                    state.items.append(ChatItem(id: uuid, kind: .prompt(shown), time: time))
                    state.snapshot.turn += 1
                }
                return
            }
            guard let blocks = message["content"] as? [[String: Any]] else { return }
            var texts: [String] = []
            for block in blocks {
                switch block["type"] as? String {
                case "tool_result":
                    guard let useID = block["tool_use_id"] as? String else { continue }
                    let failed = block["is_error"] as? Bool ?? false
                    // Results follow their call closely, so a scan back from the end finds it at once.
                    for index in stride(from: state.items.count - 1, through: max(0, state.items.count - 60), by: -1) {
                        if case .tool(var call) = state.items[index].kind, call.useID == useID {
                            call.done = true; call.failed = failed
                            if call.name == "Bash" { call.output = Self.output(of: object, block: block) }
                            state.items[index].kind = .tool(call)
                            break
                        }
                    }
                case "text":
                    if let text = block["text"] as? String, let shown = Self.promptText(text) { texts.append(shown) }
                default: break
                }
            }
            if !texts.isEmpty {
                state.items.append(ChatItem(id: uuid, kind: .prompt(texts.joined(separator: "\n\n")), time: time))
                state.snapshot.turn += 1
            }
        } else {
            guard let blocks = message["content"] as? [[String: Any]] else { return }
            for (index, block) in blocks.enumerated() {
                let id = blocks.count == 1 ? uuid : "\(uuid)-\(index)"
                switch block["type"] as? String {
                case "text":
                    let text = ((block["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { state.items.append(ChatItem(id: id, kind: .text(text), time: time)) }
                case "tool_use":
                    let name = (block["name"] as? String) ?? "Tool"
                    let input = (block["input"] as? [String: Any]) ?? [:]
                    let call = ToolCall(useID: (block["id"] as? String) ?? id, name: name, detail: ToolCall.describe(name: name, input: input))
                    state.items.append(ChatItem(id: id, kind: .tool(call), time: time))
                    collect(name: name, input: input, id: call.useID, time: time, into: &state.snapshot)
                default: break   // thinking, and anything newer Claude Code adds
                }
            }
        }
    }

    /// Edits, writes, reads, the todo list and the plan, for the other tabs.
    private func collect(name: String, input: [String: Any], id: String, time: Date?, into snapshot: inout ChatSnapshot) {
        func clipText(_ text: String) -> String { text.count > Self.maxChangeText ? String(text.prefix(Self.maxChangeText)) + "\n…" : text }
        func touch(_ path: String, read: Bool) {
            if let index = snapshot.files.firstIndex(where: { $0.path == path }) {
                if read { snapshot.files[index].reads += 1 } else { snapshot.files[index].edits += 1 }
                snapshot.files[index].last = time
            } else {
                snapshot.files.append(FileTouch(path: path, reads: read ? 1 : 0, edits: read ? 0 : 1, last: time))
            }
        }
        let path = input["file_path"] as? String
        switch name {
        case "Read", "NotebookRead":
            if let path { touch(path, read: true) }
        case "Edit":
            guard let path else { return }
            touch(path, read: false)
            snapshot.changes.append(FileChange(id: id, path: path, isWrite: false, oldText: clipText((input["old_string"] as? String) ?? ""),
                                               newText: clipText((input["new_string"] as? String) ?? ""), turn: snapshot.turn, time: time))
        case "MultiEdit":
            guard let path else { return }
            touch(path, read: false)
            for (n, edit) in ((input["edits"] as? [[String: Any]]) ?? []).enumerated() {
                snapshot.changes.append(FileChange(id: "\(id)-\(n)", path: path, isWrite: false, oldText: clipText((edit["old_string"] as? String) ?? ""),
                                                   newText: clipText((edit["new_string"] as? String) ?? ""), turn: snapshot.turn, time: time))
            }
        case "Write":
            guard let path else { return }
            touch(path, read: false)
            snapshot.changes.append(FileChange(id: id, path: path, isWrite: true, oldText: "", newText: clipText((input["content"] as? String) ?? ""),
                                               turn: snapshot.turn, time: time))
        case "NotebookEdit":
            if let path { touch(path, read: false) }
        case "TodoWrite":
            let todos = ((input["todos"] as? [[String: Any]]) ?? []).compactMap { t -> TodoItem? in
                guard let content = t["content"] as? String, !content.isEmpty else { return nil }
                return TodoItem(content: content, status: (t["status"] as? String) ?? "pending")
            }
            if !todos.isEmpty { snapshot.todos = todos }
        case "ExitPlanMode":
            if let plan = input["plan"] as? String, !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { snapshot.plan = plan }
        default:
            break
        }
    }

    /// What a Bash command printed: Claude Code keeps stdout and stderr beside the result; older rows only have the text.
    private static func output(of row: [String: Any], block: [String: Any]) -> String? {
        var text = ""
        if let result = row["toolUseResult"] as? [String: Any] {
            text = ((result["stdout"] as? String) ?? "")
            if let err = result["stderr"] as? String, !err.isEmpty { text += (text.isEmpty ? "" : "\n") + err }
        } else if let content = block["content"] as? String {
            text = content
        } else if let parts = block["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        return text.count > maxOutput ? String(text.prefix(maxOutput)) + "\n…" : text
    }

    /// What James typed, with the tags Claude Code wraps around it removed. nil for rows that are not his words
    /// (command output, attachments, reminders). A slash command shows as "/name".
    static func promptText(_ raw: String) -> String? {
        var text = raw
        if let name = tagged(text, "command-name") { return name.hasPrefix("/") ? name : "/" + name }
        if text.contains("<local-command-stdout>") || text.contains("<local-command-caveat>") { return nil }
        for tag in ["system-reminder", "ide_opened_file", "ide_selection"] { text = stripping(text, tag) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func tagged(_ text: String, _ tag: String) -> String? {
        guard let open = text.range(of: "<\(tag)>"), let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex) else { return nil }
        return String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripping(_ text: String, _ tag: String) -> String {
        var out = text
        while let open = out.range(of: "<\(tag)"), let close = out.range(of: "</\(tag)>", range: open.upperBound..<out.endIndex) {
            out.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return out
    }
}

extension ISO8601DateFormatter {
    /// Transcript timestamps look like 2026-10-28T10:50:58.220Z.
    nonisolated(unsafe) static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
