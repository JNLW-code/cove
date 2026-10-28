import SwiftUI

/// The side panel: a rail of session initials on the left, the chosen session's conversation on the right.
struct SidePanelRoot: View {
    var island: Island
    let actions: IslandActions

    var body: some View {
        let p = island.palette
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
        HStack(spacing: 0) {
            SessionRail(island: island, actions: actions)
            Rectangle().fill(p.rim).frame(width: 1)
            if let session = island.panelSession {
                SessionPane(session: session, island: island, actions: actions)
            } else {
                Text("No Claude sessions").font(Theme.font(12)).foregroundStyle(p.secondaryLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Surface(shape: shape, color: p.island, palette: p))
        .overlay(shape.strokeBorder(p.rim, lineWidth: 1))
        .clipShape(shape)
        .contentShape(shape)
        .environment(\.hoverShade, p.label)
        .focusEffectDisabled()   // no blue ring on whichever button SwiftUI would focus first
    }
}

/// One square per session, initials inside, a status dot top right. Grouped by project with a thin line between.
struct SessionRail: View {
    var island: Island
    let actions: IslandActions

    var body: some View {
        let p = island.palette
        let groups = Self.groups(island.claude.sessions)
        VStack(spacing: 8) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Rectangle().fill(p.rim).frame(width: 22, height: 1).padding(.vertical, 2) }
                ForEach(group) { session in avatar(session, p) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(width: 44)
    }

    private func avatar(_ session: ClaudeSession, _ p: Palette) -> some View {
        let on = island.panelSession?.id == session.id
        return Button { actions.panelSelect(session) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? p.label.opacity(0.16) : p.tile)
                Text(Self.initials(session.label)).font(Theme.font(11, .bold)).foregroundStyle(on ? p.label : p.secondaryLabel)
            }
            .frame(width: 30, height: 30)
            .overlay(alignment: .topTrailing) {
                if let tint = Self.dot(session) {
                    Circle().fill(p.color(tint)).frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(p.isGlass ? .clear : p.island, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(PressStyle(radius: 9))
        .help(session.labelWithPlace)
    }

    /// Blue while working, green when done and not yet seen, orange when it needs James. Nothing otherwise.
    static func dot(_ session: ClaudeSession) -> Tint? {
        switch session.state {
        case .working, .running: .accent
        case .needsYou: .needsYou
        case .done: session.doneSeen ? nil : .done
        default: nil
        }
    }

    /// "Stream A - V3 Current" → SA, "notch-island" → NI, "Claude" → CL.
    static func initials(_ label: String) -> String {
        let words = label.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.count >= 2, let a = words[0].first, let b = words[1].first { return String([a, b]).uppercased() }
        return String((words.first ?? label).prefix(2)).uppercased()
    }

    /// Sessions in arrival order, grouped by project (or folder), groups in the order their first session arrived.
    static func groups(_ sessions: [ClaudeSession]) -> [[ClaudeSession]] {
        var keys: [String] = []
        var byKey: [String: [ClaudeSession]] = [:]
        for s in sessions {
            let key = s.project ?? s.cwd
            if byKey[key] == nil { keys.append(key) }
            byKey[key, default: []].append(s)
        }
        return keys.compactMap { byKey[$0] }
    }
}

/// Header (name, elapsed, pin, open in the app), the Chat tab, then the conversation.
struct SessionPane: View {
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions

    var body: some View {
        let p = island.palette
        VStack(spacing: 0) {
            header(p)
            Rectangle().fill(p.rim).frame(height: 1)
            HStack {
                Text("Chat").font(Theme.font(11, .semibold)).foregroundStyle(p.label)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.tile))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Rectangle().fill(p.rim).frame(height: 1)
            ChatList(session: session, island: island, actions: actions)
        }
    }

    private func header(_ p: Palette) -> some View {
        HStack(spacing: 6) {
            Text(session.label).font(Theme.font(12, .semibold)).foregroundStyle(p.label)
                .lineLimit(1).truncationMode(.tail)
                .help(session.labelWithPlace)
            if session.isWorking, !island.reduceMotion {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(elapsed).font(Theme.digits(12)).foregroundStyle(p.secondaryLabel).lineLimit(1).fixedSize()
                }
            } else {
                Text(elapsed).font(Theme.digits(12)).foregroundStyle(p.secondaryLabel).lineLimit(1).fixedSize()
            }
            Spacer(minLength: 6)
            Button { actions.panelPin() } label: {
                Image(systemName: island.panelPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(island.panelPinned ? p.label : p.secondaryLabel)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.tile))
            }
            .buttonStyle(PressStyle(radius: 6))
            .help(island.panelPinned ? "Unpin (closes when the mouse leaves)" : "Pin (stays open)")
            Button { actions.panelOpenInApp(session) } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(p.allowText)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.accent))
            }
            .buttonStyle(PressStyle(radius: 6))
            .help("Open this session in the Claude app")
        }
        .padding(.leading, 12).padding(.trailing, 10)
        .frame(height: 38)
    }

    /// "· 2 m 14 s" while working, what the row says otherwise.
    private var elapsed: String {
        switch session.state {
        case .working, .running:
            let seconds = session.turnStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
            return seconds > 0 ? "· \(durationText(seconds))" : ""
        case .done(let seconds, _): return session.endsWithQuestion ? "· Waiting for you" : (seconds > 0 ? "· Done in \(durationText(seconds))" : "· Done")
        case .needsYou: return "· Needs you"
        case .waiting(let since): return "· Waiting \(shortAge(Int(Date().timeIntervalSince(since))))"
        case .quiet: return "· Quiet"
        case .idle: return ""
        }
    }
}

/// The conversation: prompts as bubbles on the right, Claude's text on the left, tool calls as one grey line.
struct ChatList: View {
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions

    private enum Row: Identifiable {
        case prompt(String, String)
        case text(String, String)
        case tools(String, [ToolCall])

        var id: String {
            switch self {
            case .prompt(let id, _), .text(let id, _), .tools(let id, _): id
            }
        }
    }

    var body: some View {
        let p = island.palette
        let rows = Self.rows(session.chat)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if rows.isEmpty {
                        Text(session.transcriptPath == nil ? "No transcript yet. It appears with this session's next event." : (session.chatLoaded ? "Nothing in this conversation yet." : "Reading…"))
                            .font(Theme.font(12)).foregroundStyle(p.secondaryLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    ForEach(rows) { row in
                        switch row {
                        case .prompt(_, let text): promptBubble(text, p)
                        case .text(_, let text): MarkdownText(text: text, palette: p).frame(maxWidth: .infinity, alignment: .leading)
                        case .tools(_, let calls): toolLine(calls, p)
                        }
                    }
                    if let card = island.claude.card(for: session) {
                        PanelPermissionCard(card: card, session: session, island: island, actions: actions)
                    } else if let word = session.lastAnswerWord {
                        answerLine(word, p)
                    }
                    if let line = statusLine {
                        Text(line.0).font(Theme.font(12)).foregroundStyle(line.1)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: session.chat.count) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: island.claude.card(for: session)?.id) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: session.id) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    /// "✓ Allowed" after a card was answered, until the next prompt or card.
    private func answerLine(_ word: String, _ p: Palette) -> some View {
        let denied = word == "Denied" || word == "Keep planning"
        return Text("\(Image(systemName: denied ? "xmark" : "checkmark")) \(word)")
            .font(Theme.font(11, .medium)).foregroundStyle(denied ? p.blocked : p.done)
    }

    /// What Claude is doing right now, under the last message.
    private var statusLine: (String, Color)? {
        let p = island.palette
        switch session.state {
        case .working(let step), .running(_, let step): return ("\(step.word)…", p.secondaryLabel)
        case .needsYou(let kind):
            switch kind {
            case .permission: return island.claude.card(for: session) != nil ? nil : ("Waiting for your OK in the app", p.needsYou)
            case .question: return ("Asking you a question on the island", p.needsYou)
            case .plan: return ("Plan ready on the island", p.needsYou)
            case .askingInApp: return ("Asking in the app", p.needsYou)
            }
        default: return nil
        }
    }

    private func promptBubble(_ text: String, _ p: Palette) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(text).font(Theme.font(12)).foregroundStyle(p.label).lineSpacing(2)
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 3, topTrailingRadius: 12, style: .continuous)
                    .fill(p.accent.opacity(0.18)))
        }
    }

    /// "✓ Read checkout.ts · ✓ Edit checkout.ts · … npm test": one line for a run of tool calls.
    private func toolLine(_ calls: [ToolCall], _ p: Palette) -> some View {
        var text = Text(verbatim: "")
        for (index, call) in calls.enumerated() {
            let mark: Text = call.failed ? Text("\(Image(systemName: "xmark"))").foregroundStyle(p.blocked)
                : Text("\(Image(systemName: call.done ? "checkmark" : "ellipsis"))")
            let piece = Text("\(mark) \(call.detail)")
            text = index == 0 ? piece : Text("\(text)  ·  \(piece)")
        }
        return text.font(Theme.font(11)).foregroundStyle(p.secondaryLabel).lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Consecutive tool calls fold into one row.
    private static func rows(_ items: [ChatItem]) -> [Row] {
        var rows: [Row] = []
        for item in items {
            switch item.kind {
            case .prompt(let text): rows.append(.prompt(item.id, text))
            case .text(let text): rows.append(.text(item.id, text))
            case .tool(let call):
                if case .tools(let id, var calls) = rows.last {
                    calls.append(call)
                    rows[rows.count - 1] = .tools(id, calls)
                } else {
                    rows.append(.tools(item.id, [call]))
                }
            }
        }
        return rows
    }
}

/// Claude's message: inline Markdown (bold, italic, code, links) for prose, a grey box for fenced code.
/// Headings become bold lines; lists keep their dashes. No tables or images.
struct MarkdownText: View {
    let text: String
    let palette: Palette

    private enum Segment { case prose(String), code(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.segments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .code(let code):
                    Text(code).font(Theme.mono(10.5)).foregroundStyle(palette.label).lineSpacing(2)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.tile))
                case .prose(let prose):
                    Text(Self.attributed(prose)).font(Theme.font(12)).foregroundStyle(palette.label).lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static func segments(_ text: String) -> [Segment] {
        var out: [Segment] = []
        var prose: [String] = []
        var code: [String] = []
        var inCode = false
        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(.prose(joined)) }
            prose = []
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode { out.append(.code(code.joined(separator: "\n"))); code = [] } else { flushProse() }
                inCode.toggle()
            } else if inCode {
                code.append(line)
            } else {
                prose.append(line)
            }
        }
        if inCode { out.append(.code(code.joined(separator: "\n"))) } else { flushProse() }
        return out
    }

    private static func attributed(_ prose: String) -> AttributedString {
        let lines = prose.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = String(line)
            if l.hasPrefix("#") {
                let heading = l.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { l = "**\(heading)**" }
            }
            return l
        }
        let joined = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: joined, options: options)) ?? AttributedString(joined)
    }
}

/// The permission card inside the chat (mockup: orange edge, "Claude wants to run", the command, Allow / Deny).
/// A long command opens in a scrollable box and Allow turns on once it has been scrolled to the end; a plan shows
/// Approve / Keep planning with a line for why not. Same answer path and 400 ms guard as the island's card.
struct PanelPermissionCard: View {
    let card: PermissionCard
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions
    @State private var scrolledToEnd = false
    @State private var feedback = ""

    var body: some View {
        let p = island.palette
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let long = card.isPlan || Island.isLong(card.command)
        let allowOn = long && !card.isPlan ? scrolledToEnd : true
        VStack(alignment: .leading, spacing: 6) {
            Text(card.isPlan ? "Claude's plan is ready" : "Claude wants to run").font(Theme.font(12, .bold)).foregroundStyle(p.label)
            if long {
                ScrollView(.vertical) {
                    Text(card.command).font(card.isPlan ? Theme.font(11.5) : Theme.mono(10.5)).foregroundStyle(p.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .textSelection(.enabled)
                }
                .frame(height: Island.longCommandBox)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.rim, lineWidth: 1))
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 2
                } action: { _, atEnd in
                    if atEnd { scrolledToEnd = true }
                }
                if card.isPlan {
                    TextField("Why not? Goes to Claude with Keep planning (optional)", text: $feedback)
                        .textFieldStyle(.plain).font(Theme.font(11.5)).foregroundStyle(p.label)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.rim, lineWidth: 1))
                }
                Text(card.isPlan ? "\(lines) lines · scroll to read it all, or Approve now"
                     : scrolledToEnd ? "Full command seen · \(lines) lines" : "Scroll to the end to turn on Allow · \(lines) lines")
                    .font(Theme.font(10.5)).foregroundStyle(p.tertiaryLabel)
            } else {
                Text(card.command).font(Theme.mono(11)).foregroundStyle(p.label).lineLimit(2).truncationMode(.tail)
                    .textSelection(.enabled)
            }
            HStack(spacing: 6) {
                pill(card.isPlan ? "Approve" : "Allow", island.hotKeyAllow, p.allowBackground, p.allowText, on: allowOn) {
                    actions.answer(card, allow: true, seen: scrolledToEnd)
                }
                pill(card.isPlan ? "Keep planning" : "Deny", island.hotKeyDeny, p.deny, p.label, on: true) {
                    actions.answer(card, allow: false, message: feedback, seen: scrolledToEnd)
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(p.tile))
        .overlay(shape.strokeBorder(p.needsYou, lineWidth: 1))
        .id(card.id)
    }

    private var lines: Int { card.command.filter { $0 == "\n" }.count + 1 }

    private func pill(_ title: String, _ key: String, _ bg: Color, _ fg: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(Theme.font(11.5, .semibold))
                Text(key).font(Theme.font(9.5)).opacity(0.55)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(bg))
        }
        .buttonStyle(PressStyle(radius: 12))
        .disabled(!on)
        .opacity(on ? 1 : 0.35)
    }
}
