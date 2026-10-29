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
            Button { actions.openMenu() } label: {
                Image(systemName: "gearshape").font(.system(size: 13, weight: .medium)).foregroundStyle(p.secondaryLabel)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(PressStyle(radius: 9))
            .help("Cove menu")
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
            HStack(spacing: 2) {
                ForEach(PanelTab.allCases, id: \.self) { tab in tabButton(tab, p) }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Rectangle().fill(p.rim).frame(height: 1)
            switch island.panelTab {
            case .chat: ChatList(session: session, island: island, actions: actions)
            case .plan: PlanTab(session: session, island: island)
            case .diff: DiffTab(session: session, island: island)
            case .files: FilesTab(session: session, island: island, actions: actions)
            case .terminal: TerminalTab(session: session, island: island)
            }
            // The reply box lives under every tab, so a note can go off while reading the diff or the terminal.
            Rectangle().fill(p.rim).frame(height: 1)
            PanelCompose(session: session, island: island, actions: actions)
        }
    }

    /// Files changed this turn, on the Diff tab.
    private var diffCount: Int { Set(session.changes.filter { $0.turn == session.chatTurn }.map(\.path)).count }

    private func tabButton(_ tab: PanelTab, _ p: Palette) -> some View {
        let on = island.panelTab == tab
        return Button { island.panelTab = tab } label: {
            HStack(spacing: 4) {
                Text(tab.title).font(Theme.font(11, on ? .semibold : .regular)).foregroundStyle(on ? p.label : p.secondaryLabel)
                if tab == .diff, diffCount > 0 {
                    Text("\(diffCount)").font(Theme.digits(9.5, .semibold)).foregroundStyle(p.allowText)
                        .padding(.horizontal, 5).frame(height: 14).background(Capsule().fill(p.needsYou))
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? p.tile : .clear))
        }
        .buttonStyle(PressStyle(radius: 7))
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
                    if let question = island.claude.question(for: session) {
                        PanelQuestionCard(card: question, session: session, island: island, actions: actions)
                    } else if let card = island.claude.card(for: session) {
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
            .onChange(of: island.claude.question(for: session)?.id) { proxy.scrollTo("end", anchor: .bottom) }
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
            case .question: return island.claude.question(for: session) != nil ? nil : ("Asking you a question in the app", p.needsYou)
            case .plan: return island.claude.card(for: session) != nil ? nil : ("Plan ready in the app", p.needsYou)
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
                if !card.isPlan, let words = ClaudeModel.alwaysWords(tool: card.tool, command: card.command) {
                    pill("Always", "", p.deny, p.label, on: allowOn) {
                        actions.answer(card, allow: true, seen: scrolledToEnd, always: true)
                    }
                    .help("Allow this now, and every \"\(words)\" request for the rest of this session without asking")
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
                if !key.isEmpty { Text(key).font(Theme.font(9.5)).opacity(0.55) }
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

/// Claude's multiple-choice question inside the chat: options stacked full width, or type an answer. Several
/// questions come one at a time ("1 of 2"). Same answer path as the island's card.
struct PanelQuestionCard: View {
    let card: QuestionCard
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions
    @State private var index = 0
    @State private var answers: [String: String] = [:]
    @State private var picked: [String] = []
    @State private var typed = ""

    var body: some View {
        let p = island.palette
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let q = card.questions[min(index, card.questions.count - 1)]
        let canSend = !picked.isEmpty || !typed.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(q.header.isEmpty ? "Claude has a question" : "Claude asks · \(q.header)")
                    .font(Theme.font(12, .bold)).foregroundStyle(p.label).lineLimit(1)
                Spacer(minLength: 0)
                if card.questions.count > 1 {
                    Text("\(index + 1) of \(card.questions.count)").font(Theme.digits(10.5)).foregroundStyle(p.tertiaryLabel)
                }
            }
            Text(q.text).font(Theme.font(12)).foregroundStyle(p.label).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            ForEach(q.options, id: \.label) { option in optionRow(option, q, p) }
            HStack(spacing: 6) {
                TextField("Or type an answer…", text: $typed)
                    .textFieldStyle(.plain).font(Theme.font(11.5)).foregroundStyle(p.label)
                    .onSubmit { submit(q, typed) }
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.rim, lineWidth: 1))
                if q.multiSelect || !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { submit(q, typed.trimmingCharacters(in: .whitespaces).isEmpty ? picked.joined(separator: ", ") : typed) } label: {
                        Text(q.multiSelect ? "Done" : "Send").font(Theme.font(11.5, .semibold)).foregroundStyle(p.allowText)
                            .padding(.horizontal, 12).frame(height: 26).background(Capsule().fill(p.allowBackground))
                    }
                    .buttonStyle(PressStyle(radius: 13))
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.35)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(p.tile))
        .overlay(shape.strokeBorder(p.needsYou, lineWidth: 1))
        .id(card.id)
    }

    private func optionRow(_ option: ClaudeQuestion.Option, _ q: ClaudeQuestion, _ p: Palette) -> some View {
        let on = picked.contains(option.label)
        return Button {
            if q.multiSelect {
                if on { picked.removeAll { $0 == option.label } } else { picked.append(option.label) }
            } else {
                submit(q, option.label)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if q.multiSelect {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 12))
                        .foregroundStyle(on ? p.accent : p.tertiaryLabel).padding(.top, 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(Theme.font(12, .semibold)).foregroundStyle(p.label)
                    if !option.description.isEmpty {
                        Text(option.description).font(Theme.font(11)).foregroundStyle(p.secondaryLabel).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? p.accent : p.rim, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressStyle(radius: 8))
    }

    /// One question answered: on to the next, or send the lot.
    private func submit(_ q: ClaudeQuestion, _ answer: String) {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        answers[q.text] = text
        picked = []
        typed = ""
        if index + 1 < card.questions.count { index += 1 } else { actions.answerQuestion(card, answers: answers) }
    }
}

/// The reply box at the bottom of the panel (mockup: a text area with an accent edge, ↑ to send). Return sends,
/// Shift-Return makes a new line (handled by the panel's key monitor). The reply goes down the waiting Stop hook when Claude stopped on a question
/// less than 45 s ago, otherwise Cove types it into the Claude app (`IslandController.sendReply`, as on the island).
struct PanelCompose: View {
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let p = island.palette
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 6) {
            TextField("Reply to \(session.label)…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(Theme.font(12.5))
                .foregroundStyle(p.label)
                .focused($focused)
                .onSubmit(send)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(minHeight: 44, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.island))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? p.accent.opacity(0.6) : p.rim, lineWidth: 1))
            HStack(spacing: 8) {
                Text(island.replyStatus ?? (session.replyRequestID != nil ? "Claude is waiting for your answer" : "Return sends · ⇧Return new line · /commands go to the app"))
                    .font(Theme.font(10.5)).foregroundStyle(p.tertiaryLabel).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundStyle(p.allowText)
                        .frame(width: 22, height: 22).background(Circle().fill(p.allowBackground))
                }
                .buttonStyle(PressStyle(radius: 11))
                .disabled(empty)
                .opacity(empty ? 0.35 : 1)
                .help("Send to Claude")
            }
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 12)
    }

    private func send() {
        let reply = text
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        text = ""
        actions.reply(reply, to: session)
    }
}

/// Plan tab: Claude's current step list (TodoWrite) and the last plan it wrote (ExitPlanMode).
struct PlanTab: View {
    var session: ClaudeSession
    var island: Island

    var body: some View {
        let p = island.palette
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                if session.todos.isEmpty, session.plan == nil {
                    Text(session.chatLoaded ? "No steps or plan in this session yet. Steps appear when Claude keeps a todo list; the plan when it finishes planning." : "Reading…")
                        .font(Theme.font(12)).foregroundStyle(p.secondaryLabel)
                }
                if !session.todos.isEmpty {
                    Text("Steps").font(Theme.font(11, .semibold)).foregroundStyle(p.secondaryLabel)
                    ForEach(Array(session.todos.enumerated()), id: \.offset) { _, todo in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: todo.status == "completed" ? "checkmark.circle.fill" : todo.status == "in_progress" ? "circle.dotted.circle" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(todo.status == "completed" ? p.done : todo.status == "in_progress" ? p.accent : p.tertiaryLabel)
                                .padding(.top, 2)
                            Text(todo.content).font(Theme.font(12)).foregroundStyle(todo.status == "completed" ? p.secondaryLabel : p.label)
                                .strikethrough(todo.status == "completed", color: p.tertiaryLabel)
                                .textSelection(.enabled)
                        }
                    }
                }
                if let plan = session.plan {
                    Text("Plan").font(Theme.font(11, .semibold)).foregroundStyle(p.secondaryLabel).padding(.top, session.todos.isEmpty ? 0 : 6)
                    MarkdownText(text: plan, palette: p)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }
}

/// Diff tab: every Edit and Write, grouped by turn, latest first; click a file to see the old and new text.
struct DiffTab: View {
    var session: ClaudeSession
    var island: Island
    @State private var opened: Set<String> = []
    @State private var closed: Set<String> = []

    var body: some View {
        let p = island.palette
        let turns = Dictionary(grouping: session.changes, by: \.turn).keys.sorted(by: >)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                if session.changes.isEmpty {
                    Text(session.chatLoaded ? "No edits in this session yet." : "Reading…").font(Theme.font(12)).foregroundStyle(p.secondaryLabel)
                }
                ForEach(turns, id: \.self) { turn in
                    Text(turn == session.chatTurn ? "This turn" : "Turn \(turn)").font(Theme.font(11, .semibold)).foregroundStyle(p.secondaryLabel)
                        .padding(.top, turn == turns.first ? 0 : 6)
                    ForEach(session.changes.filter { $0.turn == turn }.reversed()) { change in changeView(change, p) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    private func changeView(_ change: FileChange, _ p: Palette) -> some View {
        // The latest change of this turn starts open; everything else starts closed.
        let latest = change.turn == session.chatTurn && session.changes.last?.id == change.id
        let shown = opened.contains(change.id) || (latest && !closed.contains(change.id))
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if shown { opened.remove(change.id); closed.insert(change.id) } else { opened.insert(change.id); closed.remove(change.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: shown ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(p.tertiaryLabel).frame(width: 10)
                    Text(change.name).font(Theme.font(11.5, .semibold)).foregroundStyle(p.label).lineLimit(1)
                    if change.isWrite { Text("new").font(Theme.font(10)).foregroundStyle(p.tertiaryLabel) }
                    Spacer(minLength: 4)
                    Text("+\(change.added)").font(Theme.digits(10.5)).foregroundStyle(p.done)
                    Text("−\(change.removed)").font(Theme.digits(10.5)).foregroundStyle(p.blocked)
                }
                .padding(.horizontal, 9).frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(radius: 9))
            .help(change.path)
            if shown { diffLines(change, p) }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.tile))
    }

    private func diffLines(_ change: FileChange, _ p: Palette) -> some View {
        let removed = change.oldText.isEmpty ? [] : change.oldText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let added = change.newText.isEmpty ? [] : change.newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let cap = 120
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(removed.prefix(cap).enumerated()), id: \.offset) { _, line in diffLine("−", line, p.blocked, p) }
            if removed.count > cap { Text("… \(removed.count - cap) more lines").font(Theme.font(10)).foregroundStyle(p.tertiaryLabel).padding(.horizontal, 9) }
            ForEach(Array(added.prefix(cap).enumerated()), id: \.offset) { _, line in diffLine("+", line, p.done, p) }
            if added.count > cap { Text("… \(added.count - cap) more lines").font(Theme.font(10)).foregroundStyle(p.tertiaryLabel).padding(.horizontal, 9) }
        }
        .padding(.bottom, 6)
        .textSelection(.enabled)
    }

    private func diffLine(_ sign: String, _ line: String, _ tint: Color, _ p: Palette) -> some View {
        Text("\(sign) \(line)").font(Theme.mono(10)).foregroundStyle(p.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.vertical, 1)
            .background(tint.opacity(0.16))
    }
}

/// Files tab: everything Claude read or changed this session, latest first. Click opens the file; right-click reveals it.
struct FilesTab: View {
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions

    var body: some View {
        let p = island.palette
        let files = session.files.sorted { ($0.last ?? .distantPast) > ($1.last ?? .distantPast) }
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
                if files.isEmpty {
                    Text(session.chatLoaded ? "No files read or changed yet." : "Reading…").font(Theme.font(12)).foregroundStyle(p.secondaryLabel)
                }
                ForEach(files) { file in
                    Button { actions.openFile(file.path) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: file.edits > 0 ? "pencil" : "doc.text").font(.system(size: 11)).foregroundStyle(file.edits > 0 ? p.accent : p.tertiaryLabel).frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).font(Theme.font(11.5, .semibold)).foregroundStyle(p.label).lineLimit(1)
                                Text(file.folder).font(Theme.font(10)).foregroundStyle(p.tertiaryLabel).lineLimit(1).truncationMode(.head)
                            }
                            Spacer(minLength: 4)
                            Text(counts(file)).font(Theme.digits(10.5)).foregroundStyle(p.secondaryLabel).lineLimit(1).fixedSize()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(radius: 8))
                    .help(file.path)
                    .contextMenu {
                        Button("Reveal in Finder") { actions.revealFile(file.path) }
                        Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.path, forType: .string) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6).padding(.vertical, 8)
        }
    }

    private func counts(_ file: FileTouch) -> String {
        var parts: [String] = []
        if file.reads > 0 { parts.append("\(file.reads) read\(file.reads == 1 ? "" : "s")") }
        if file.edits > 0 { parts.append("\(file.edits) edit\(file.edits == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

/// Terminal tab: every command Claude ran, with what it printed (the first part), latest at the bottom.
struct TerminalTab: View {
    var session: ClaudeSession
    var island: Island
    @State private var expanded: Set<String> = []

    var body: some View {
        let p = island.palette
        let calls = session.chat.compactMap { item -> ToolCall? in
            if case .tool(let call) = item.kind, call.name == "Bash" { return call }
            return nil
        }.suffix(100)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    if calls.isEmpty {
                        Text(session.chatLoaded ? "No commands run yet." : "Reading…").font(Theme.font(12)).foregroundStyle(p.secondaryLabel)
                    }
                    ForEach(Array(calls), id: \.useID) { call in commandView(call, p) }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: calls.last?.useID) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    private func commandView(_ call: ToolCall, _ p: Palette) -> some View {
        let lines = (call.output ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let short = 8
        let showAll = expanded.contains(call.useID)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: call.failed ? "xmark" : call.done ? "checkmark" : "ellipsis").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(call.failed ? p.blocked : call.done ? p.done : p.tertiaryLabel).frame(width: 12).padding(.top, 2)
                Text(call.detail).font(Theme.font(11.5, .semibold)).foregroundStyle(p.label).textSelection(.enabled)
            }
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((showAll ? lines : Array(lines.prefix(short))).enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line).font(Theme.mono(10)).foregroundStyle(p.secondaryLabel).lineLimit(showAll ? nil : 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if lines.count > short {
                        Button(showAll ? "Less" : "\(lines.count - short) more lines") {
                            if showAll { expanded.remove(call.useID) } else { expanded.insert(call.useID) }
                        }
                        .buttonStyle(.plain).font(Theme.font(10, .medium)).foregroundStyle(p.accent).padding(.top, 3)
                    }
                }
                .padding(8)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.tile))
            }
        }
    }
}
