import AppKit
import Foundation

/// What Claude is doing right now, as an icon and a plain word.
struct ClaudeStep: Equatable, Sendable {
    let symbol: String
    let word: String

    static let thinking = ClaudeStep(symbol: "sparkles", word: "Thinking")
    static let reading = ClaudeStep(symbol: "doc.text", word: "Reading")
    static let editing = ClaudeStep(symbol: "pencil", word: "Editing")
    static let searching = ClaudeStep(symbol: "magnifyingglass", word: "Searching")
    static let testing = ClaudeStep(symbol: "flask", word: "Testing")
    static let checking = ClaudeStep(symbol: "checkmark.circle", word: "Checking")
    static let building = ClaudeStep(symbol: "hammer", word: "Building")
    static let git = ClaudeStep(symbol: "arrow.triangle.branch", word: "Git")
    static let waitingCI = ClaudeStep(symbol: "clock", word: "Waiting on CI")
    static let browsing = ClaudeStep(symbol: "globe", word: "Browsing")
    static let running = ClaudeStep(symbol: "terminal", word: "Running")
    static let delegating = ClaudeStep(symbol: "person.2", word: "Delegating")

    /// Works the step out from the tool, and for Bash from the command itself.
    static func from(tool: String, command: String?) -> ClaudeStep {
        switch tool {
        case "Read", "NotebookRead": return .reading
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return .editing
        case "Grep", "Glob", "LS": return .searching
        case "WebFetch", "WebSearch": return .browsing
        case "Task", "Agent": return .delegating
        case "Bash": return fromCommand(command ?? "")
        default: break
        }
        if tool.hasPrefix("mcp__") {
            let parts = tool.split(separator: "_", omittingEmptySubsequences: true).map(String.init)
            // mcp__Server__tool → "Server · tool", browsers become Browsing
            let server = parts.count > 1 ? parts[1] : "Tool"
            if server.lowercased().contains("browser") || server.lowercased().contains("chrome") { return .browsing }
            let toolPart = parts.count > 2 ? parts[2...].joined(separator: " ") : ""
            return ClaudeStep(symbol: "puzzlepiece", word: humanize(server) + (toolPart.isEmpty ? "" : " · " + humanize(toolPart)))
        }
        return .running
    }

    static func fromCommand(_ command: String) -> ClaudeStep {
        let c = command.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { c.contains($0) } }
        if has("gh pr checks", "gh run watch", "gh run view") || c.hasPrefix("sleep ") { return .waitingCI }
        if has("git ", "gh ") { return .git }
        if has("playwright", "vitest", "jest", "pytest", "npm test", "npm run test", "swift test", "xcodebuild test") { return .testing }
        if has("tsc", "npm run check", "eslint", "npm run lint", "swiftlint", "make check", "codesign") { return .checking }
        if has("xcodebuild", "swift build", "npm run build", "next build", "make ", "cargo build") { return .building }
        if has("rg ", "grep ", "find ", "fd ") { return .searching }
        if has("curl ", "wget ") { return .browsing }
        if has("cat ", "head ", "tail ", "sed -n", "less ") { return .reading }
        return .running
    }

    static func humanize(_ s: String) -> String {
        let spaced = s.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}

/// A permission request waiting for an answer from the island.
struct PermissionCard: Identifiable, Equatable {
    let id: String          // request_id, one per request
    let sessionID: String
    let agentID: String?
    let tool: String
    let inputKey: String?
    let command: String     // what Claude wants to run, shown in full
    let received: Date
}

/// One Claude Code session, keyed by session_id.
@MainActor
@Observable
final class ClaudeSession: Identifiable {
    enum State: Equatable {
        case idle
        case working(ClaudeStep)
        case needsYou(NeedsYou)
        case done(seconds: Int, files: Int)
        case waiting(since: Date)
        case quiet
        case running(since: Date, ClaudeStep)
    }

    enum NeedsYou: Equatable {
        case permission     // card with Allow / Deny
        case askingInApp    // Claude's own prompt is up (the hook gave up or was away)
        case question       // AskUserQuestion
        case plan           // ExitPlanMode
    }

    let id: String
    var cwd = ""
    var project: String?
    var branch: String?
    var title: String?
    var pid: Int32?
    var term = ""
    /// The desktop app's own id for this session (opens the exact session); nil for terminal sessions.
    var hostID: String?
    /// What Claude last said (kept in memory only, cleared on the next prompt).
    var lastMessage: String?
    /// While Claude's Stop hook is waiting, a reply typed in the island goes straight back through it.
    var replyRequestID: String?
    var state: State = .idle
    var turnStart: Date?
    var lastEvent = Date()
    var filesChanged: Set<String> = []
    var agents: Set<String> = []
    var inFlight: [String: (step: ClaudeStep, start: Date)] = [:]
    var endsWithQuestion = false
    var doneSeen = false
    var lastAnswered = Date.distantPast
    var pendingStep: ClaudeStep?
    var lastStepApplied = Date.distantPast

    init(id: String) { self.id = id }

    /// "project · branch", else the session title, else the folder name.
    var label: String {
        if let project { return branch.map { "\(project) · \($0)" } ?? project }
        if let title, !title.isEmpty { return title }
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        return folder.isEmpty ? "Claude" : folder
    }

    var isWorking: Bool {
        if case .working = state { return true }
        if case .running = state { return true }
        return false
    }

    var needsYou: NeedsYou? {
        if case .needsYou(let kind) = state { return kind }
        return nil
    }

    var unseenDone: Bool {
        if case .done = state { return !doneSeen }
        return false
    }

    /// How urgent this session is for the compact pill. Higher wins.
    var urgency: Int {
        switch state {
        case .needsYou: 3
        case .done: doneSeen ? 0 : 2
        case .working, .running: 1
        default: 0
        }
    }
}

/// Formats "10 s", "4 m 12 s", "1 h 05 m".
func durationText(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds) s" }
    if seconds < 3600 { return "\(seconds / 60) m \(String(format: "%02d", seconds % 60)) s" }
    return "\(seconds / 3600) h \(String(format: "%02d", (seconds % 3600) / 60)) m"
}

/// Short "3m" / "1h" for the row.
func shortAge(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    return "\(seconds / 3600)h"
}

/// All sessions and the hook events that drive them. Views read `sessions`; the controller asks for peeks and cards.
@MainActor
@Observable
final class ClaudeModel {
    static let quietAfter: TimeInterval = 600
    static let stepHold: TimeInterval = 0.7

    private(set) var sessions: [ClaudeSession] = []
    private(set) var cards: [PermissionCard] = []
    /// Peek requests the controller shows (set by `handle`, consumed by the controller).
    var onPeek: ((PeekContent, Double) -> Void)?
    var onCardSettled: ((PermissionCard) -> Void)?
    /// Called after every change so the controller can refresh the pill.
    var onChanged: (() -> Void)?
    /// Called when a new card arrives or the front card changes.
    var onCardsChanged: (() -> Void)?
    /// The 400 ms after a card appears or moves on, during which clicks and shortcuts are ignored.
    static let guardSeconds: TimeInterval = 0.4
    var frontCardShownAt = Date.distantPast
    /// True once the whole command of the front card has been on screen (short ones at once, long ones when scrolled to the end).
    var frontCardFullySeen = false
    /// Allow is only possible when the full command has been seen; Deny always is.
    var frontCardAllowReady: Bool {
        guard let card = frontCard else { return false }
        return !Island.isLong(card.command) || frontCardFullySeen
    }
    var frontCard: PermissionCard? { cards.first }
    var frontCardGuarded: Bool { Date().timeIntervalSince(frontCardShownAt) < Self.guardSeconds }
    var socket: ClaudeSocket?

    private var quietTasks: [String: Task<Void, Never>] = [:]
    private var stepTasks: [String: Task<Void, Never>] = [:]
    private var processWatchers: [String: DispatchSourceProcess] = [:]

    var active: [ClaudeSession] { sessions.sorted { $0.urgency > $1.urgency } }
    var mostUrgent: ClaudeSession? { active.first { $0.urgency > 0 } }

    func session(_ id: String) -> ClaudeSession? { sessions.first { $0.id == id } }

    // MARK: Events

    func handle(_ m: HookMessage) {
        guard let id = m.string("session_id"), !id.isEmpty else { return }
        if m.event == "SessionEnd" { end(id); return }
        if m.event == "SubagentStop" {
            // The desktop app's own title agent stops without ever starting; ignore agents we never saw.
            guard let known = session(id), let agent = m.string("agent_id"), known.agents.contains(agent) else { return }
        }
        let s = session(id) ?? add(id)
        s.lastEvent = Date()
        if let cwd = m.string("cwd"), !cwd.isEmpty { s.cwd = cwd }
        if let project = m.string("project") { s.project = project; s.branch = m.string("branch") }
        if let title = m.string("session_title") { s.title = title }
        if let pid = m.int("pid").map(Int32.init), s.pid != pid { s.pid = pid; watch(s) }
        if let term = m.string("term") { s.term = term }
        if let host = m.string("host_session_id"), !host.isEmpty { s.hostID = host }
        let agent = m.string("agent_id")

        switch m.event {
        case "SessionStart":
            if s.state == .quiet { s.state = .idle }
        case "UserPromptSubmit":
            s.turnStart = Date()
            s.filesChanged = []
            s.inFlight = [:]
            s.endsWithQuestion = false
            s.lastMessage = nil
            closeReply(s)
            s.doneSeen = false
            s.agents = []
            settleCards(for: s.id)
            setStep(s, .thinking, now: true)
        case "SubagentStart":
            if let agent { s.agents.insert(agent) }
            if !s.isWorking { setStep(s, .delegating, now: true) }
        case "SubagentStop":
            if let agent { s.agents.remove(agent) }
        case "PreToolUse":
            let step = ClaudeStep.from(tool: m.string("tool_name") ?? "", command: m.string("command"))
            if let agent {
                s.agents.insert(agent)
                if !s.isWorking { setStep(s, .delegating, now: true) }
            } else {
                if let use = m.string("tool_use_id") { s.inFlight[use] = (step, Date()) }
                setStep(s, step, now: false)
            }
        case "PostToolUse":
            if let use = m.string("tool_use_id") { s.inFlight[use] = nil }
            if let path = m.string("file_path") { s.filesChanged.insert(path) }
            if let key = m.string("input_key") { settleCards(for: s.id, agent: agent, inputKey: key) }
            if case .running(_, let step) = s.state { s.state = .working(step) }
        case "PermissionDenied":
            if let key = m.string("input_key") { settleCards(for: s.id, agent: agent, inputKey: key) }
            let what = m.string("command") ?? m.string("file_path") ?? (m.string("tool_name") ?? "a tool")
            onPeek?(PeekContent(symbol: "exclamationmark.triangle", icon: nil, tint: .blocked,
                                word: "Blocked · \(s.label)", second: String(what.prefix(60))), 4)
        case "Stop":
            if agent == nil {
                let seconds = Int(Date().timeIntervalSince(s.turnStart ?? Date()))
                s.endsWithQuestion = m.bool("ends_with_question") ?? false
                if let text = m.string("last_message"), !text.isEmpty { s.lastMessage = text }
                closeReply(s)
                s.replyRequestID = m.string("request_id")
                s.inFlight = [:]
                s.pendingStep = nil
                stepTasks[s.id]?.cancel()
                s.doneSeen = false
                s.state = .done(seconds: seconds, files: s.filesChanged.count)
                settleCards(for: s.id)
                if seconds >= 30 {
                    let word = s.endsWithQuestion ? "Waiting for you" : "Done in \(durationText(seconds))"
                    onPeek?(PeekContent(symbol: s.endsWithQuestion ? "questionmark.circle" : "checkmark",
                                        icon: nil, tint: s.endsWithQuestion ? .needsYou : .done, word: word, second: s.label), 3)
                }
            }
        case "Notification":
            switch m.string("notification_type") {
            case "idle_prompt":
                if case .done = s.state { s.state = .waiting(since: Date()) }
            case "permission_prompt":
                // Claude Code sends this ~6 s after the request even when the island already answered it.
                let justAnswered = Date().timeIntervalSince(s.lastAnswered) < 10
                if s.needsYou == nil, !justAnswered, !cards.contains(where: { $0.sessionID == s.id }) { s.state = .needsYou(.askingInApp) }
            default: break
            }
        case "PermissionRequest":
            guard let requestID = m.string("request_id") else { break }
            let tool = m.string("tool_name") ?? ""
            if tool == "AskUserQuestion" { s.state = .needsYou(.question); break }
            if tool == "ExitPlanMode" { s.state = .needsYou(.plan); break }
            let command = Self.describe(tool: tool, inputJSON: m.string("tool_input"))
            cards.append(PermissionCard(id: requestID, sessionID: s.id, agentID: agent, tool: tool,
                                        inputKey: m.string("input_key"), command: command, received: Date()))
            s.state = .needsYou(.permission)
            if cards.count == 1 { frontCardShownAt = Date(); frontCardFullySeen = false }
            onCardsChanged?()
        default:
            break
        }
        scheduleQuiet(s)
        onChanged?()
    }

    /// Plain text of what a tool wants to do: the full command for Bash, the path for file tools, else the input.
    static func describe(tool: String, inputJSON: String?) -> String {
        guard let inputJSON, let data = inputJSON.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return tool }
        if tool == "Bash", let command = object["command"] as? String { return command }
        if let path = object["file_path"] as? String { return "\(tool) \(path)" }
        if let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) { return "\(tool)\n\(text)" }
        return tool
    }

    private func add(_ id: String) -> ClaudeSession {
        let s = ClaudeSession(id: id)
        sessions.append(s)
        return s
    }

    /// Lets a waiting Stop hook go (Claude stops normally).
    func closeReply(_ s: ClaudeSession) {
        if let id = s.replyRequestID { socket?.close(request: id); s.replyRequestID = nil }
    }

    /// Sends a typed reply through the waiting Stop hook. Returns false when that hook is gone.
    func replyThroughHook(_ s: ClaudeSession, text: String) -> Bool {
        guard let id = s.replyRequestID, socket?.isPending(id) == true else { s.replyRequestID = nil; return false }
        socket?.reply(to: id, text: text)
        s.replyRequestID = nil
        s.turnStart = Date()
        s.lastMessage = nil
        s.doneSeen = true
        s.state = .working(.thinking)
        onChanged?()
        return true
    }

    private func end(_ id: String) {
        if let s = session(id) { closeReply(s) }
        settleCards(for: id)
        sessions.removeAll { $0.id == id }
        quietTasks[id]?.cancel(); quietTasks[id] = nil
        stepTasks[id]?.cancel(); stepTasks[id] = nil
        processWatchers[id]?.cancel(); processWatchers[id] = nil
        onChanged?()
    }

    /// Steps change at most every 0.7 s so 100 events a minute don't flicker.
    private func setStep(_ s: ClaudeSession, _ step: ClaudeStep, now: Bool) {
        let since = Date().timeIntervalSince(s.lastStepApplied)
        if now || since >= Self.stepHold {
            apply(s, step)
        } else {
            s.pendingStep = step
            if stepTasks[s.id] == nil {
                let wait = Self.stepHold - since
                stepTasks[s.id] = Task { [weak self, weak s] in
                    try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
                    guard let self, let s, !Task.isCancelled else { return }
                    self.stepTasks[s.id] = nil
                    if let pending = s.pendingStep { self.apply(s, pending); s.pendingStep = nil }
                }
            }
        }
    }

    private func apply(_ s: ClaudeSession, _ step: ClaudeStep) {
        s.lastStepApplied = Date()
        if s.needsYou != nil { return }   // a pending card or question stays the loudest state
        if case .running(let since, _) = s.state { s.state = .running(since: since, step) } else { s.state = .working(step) }
    }

    // MARK: Cards

    /// A card is settled when its own request finished (same agent, tool and input) or its session stopped or ended.
    private func settleCards(for sessionID: String, agent: String? = nil, inputKey: String? = nil) {
        let settled = cards.filter { card in
            guard card.sessionID == sessionID else { return false }
            guard let inputKey else { return true }
            return card.agentID == agent && card.inputKey == inputKey
        }
        guard !settled.isEmpty else { return }
        let front = cards.first?.id
        cards.removeAll { c in settled.contains { $0.id == c.id } }
        for card in settled {
            socket?.close(request: card.id)
            onCardSettled?(card)
        }
        if cards.first?.id != front { frontCardShownAt = Date(); frontCardFullySeen = false; onCardsChanged?() }
        if let s = session(sessionID), !cards.contains(where: { $0.sessionID == sessionID }), s.needsYou == .permission {
            s.state = s.inFlight.isEmpty ? .idle : .working(s.inFlight.values.first?.step ?? .running)
        }
    }

    func answer(_ card: PermissionCard, allow: Bool) {
        socket?.reply(to: card.id, decision: allow ? "allow" : "deny")
        cards.removeAll { $0.id == card.id }
        if let s = session(card.sessionID) {
            s.lastAnswered = Date()
            if !cards.contains(where: { $0.sessionID == s.id }) { s.state = allow ? .working(.running) : .idle }
        }
        frontCardShownAt = Date()
        frontCardFullySeen = false
        onCardsChanged?()
        onChanged?()
    }

    /// The hook gave up (timed out, or Claude went on without us): drop the card, Claude is asking in the app now.
    func requestClosed(_ requestID: String) {
        if let s = sessions.first(where: { $0.replyRequestID == requestID }) { s.replyRequestID = nil; return }
        guard let card = cards.first(where: { $0.id == requestID }) else { return }
        cards.removeAll { $0.id == requestID }
        if let s = session(card.sessionID), !cards.contains(where: { $0.sessionID == s.id }) { s.state = .needsYou(.askingInApp) }
        frontCardShownAt = Date()
        frontCardFullySeen = false
        onCardsChanged?()
        onChanged?()
    }

    func markDoneSeen() {
        for s in sessions where s.unseenDone { s.doneSeen = true }
        onChanged?()
    }

    /// Demo only: replaces the sessions with sample rows.
    func setDemoSessions(_ demo: [ClaudeSession]) {
        sessions = demo
        onChanged?()
    }

    // MARK: Quiet and process exit

    private func scheduleQuiet(_ s: ClaudeSession) {
        quietTasks[s.id]?.cancel()
        quietTasks[s.id] = Task { [weak self, weak s] in
            try? await Task.sleep(for: .seconds(Self.quietAfter), tolerance: .seconds(30))
            guard let self, let s, !Task.isCancelled else { return }
            if let (step, start) = s.inFlight.values.min(by: { $0.start < $1.start }) {
                s.state = .running(since: start, step)
                self.scheduleQuiet(s)
            } else if s.agents.isEmpty, s.needsYou == nil {
                s.state = .quiet
            }
            self.onChanged?()
        }
    }

    private func watch(_ s: ClaudeSession) {
        processWatchers[s.id]?.cancel()
        guard let pid = s.pid, pid > 0 else { return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        let id = s.id
        let transfer = ModelTransfer(value: self)
        source.setEventHandler { MainActor.assumeIsolated { transfer.value.end(id) } }
        source.resume()
        processWatchers[s.id] = source
    }

    /// Brings the session forward: the exact session in the Claude app when its id is known, else the app itself
    /// (the Claude app, or the terminal it was started from).
    func bringForward(_ s: ClaudeSession) {
        if let host = s.hostID, s.term != "Apple_Terminal", s.term != "iTerm.app",
           let url = URL(string: "claude://claude.ai/epitaxy/\(host)") {
            NSWorkspace.shared.open(url)
            return
        }
        let name: String
        switch s.term {
        case "Apple_Terminal": name = "Terminal"
        case "iTerm.app": name = "iTerm"
        case "WarpTerminal": name = "Warp"
        case "ghostty": name = "Ghostty"
        default: name = "Claude"
        }
        let candidates = ["/Applications/\(name).app", NSHomeDirectory() + "/Applications/\(name).app", "/System/Applications/Utilities/\(name).app"]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
    }
}

private struct ModelTransfer: @unchecked Sendable { let value: ClaudeModel }
