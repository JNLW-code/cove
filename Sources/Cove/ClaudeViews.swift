import SwiftUI

/// One row per Claude session, in a strip above the tiles.
struct ClaudeStrip: View {
    var island: Island
    let actions: IslandActions

    var body: some View {
        let p = island.palette
        VStack(spacing: 0) {
            ForEach(island.claude.active) { session in
                SessionRow(session: session, island: island, actions: actions)
                    .contentShape(Rectangle())
                    .hoverShade(radius: 8, inset: -6)
                    .onTapGesture { actions.rowClicked(session) }
                    .contextMenu {
                        Button(session.note == nil ? "Add a note…" : "Edit the note…") { actions.editNote(for: session) }
                        if session.note != nil { Button("Clear the note") { actions.setNote(nil, for: session) } }
                    }
                    .overlay(alignment: .bottom) {
                        if session.id != island.claude.active.last?.id || island.replyingTo == session.id || island.notingFor == session.id {
                            Rectangle().fill(p.rim).frame(height: 1)
                        }
                    }
                if island.replyingTo == session.id {
                    ReplyLine(session: session, island: island, actions: actions, autoFocus: true)
                        .padding(.horizontal, 14)
                        .frame(height: Island.replyRow)
                }
                if island.notingFor == session.id {
                    NoteLine(session: session, island: island, actions: actions)
                        .padding(.horizontal, 14)
                        .frame(height: Island.replyRow)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(p.tile))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .frame(width: Island.expandedWidth - 46)
    }
}

struct SessionRow: View {
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions

    var body: some View {
        if ages, !island.reduceMotion {
            TimelineView(.periodic(from: .now, by: 30)) { _ in row }
        } else {
            row
        }
    }

    /// States whose word carries an age ("Waiting · 3m", "Running · 14m") refresh every 30 s while on screen.
    private var ages: Bool {
        switch session.state {
        case .waiting, .running: true
        default: false
        }
    }

    private var row: some View {
        let p = island.palette
        return HStack(spacing: 10) {
            if let n = island.claude.attentionQueue.firstIndex(where: { $0.id == session.id }) {
                Text("\(n + 1)").font(Theme.digits(10, .bold)).foregroundStyle(p.allowText)
                    .frame(width: 16, height: 16).background(Circle().fill(p.needsYou))
            }
            leading(p)
            Text(session.label).font(Theme.font(12, .semibold)).foregroundStyle(p.label)
                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                .frame(maxWidth: 230, alignment: .leading)
                .help(session.labelWithPlace)
            if let note = session.note {
                Text(note).font(Theme.font(11)).italic().foregroundStyle(p.secondaryLabel).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 170, alignment: .leading)
            }
            HStack(spacing: 5) {
                Image(systemName: stepSymbol).font(.system(size: 11, weight: .medium)).foregroundStyle(stepColor(p))
                Text(stepWord).font(Theme.font(12)).foregroundStyle(p.secondaryLabel)
            }
            .lineLimit(1)
            .layoutPriority(1)   // the step word outranks the note and the badges
            if !session.agents.isEmpty {
                Text("+\(session.agents.count) agent\(session.agents.count == 1 ? "" : "s")")
                    .font(Theme.font(11)).foregroundStyle(p.tertiaryLabel)
            }
            if let n = session.dirtyFiles, n > 0 { gitBadge("pencil.line", n, p).help("\(n) file\(n == 1 ? "" : "s") not committed") }
            if let n = session.unpushed, n > 0 { gitBadge("arrow.up", n, p).help("\(n) commit\(n == 1 ? "" : "s") not pushed") }
            Spacer(minLength: 8)
            trailing(p)
            if let stats = statsText {
                Text(stats).font(Theme.digits(11)).foregroundStyle(p.tertiaryLabel).lineLimit(1).fixedSize()
                    .help(session.usage.turns > 0 ? "\(session.usage.turns) turn\(session.usage.turns == 1 ? "" : "s") · \(stats) so far" : stats)
            }
            if let percent = session.contextPercent {
                Text("\(percent)%").font(Theme.digits(11, .medium))
                    .foregroundStyle(percent >= 90 ? p.blocked : percent >= 80 ? p.needsYou : p.tertiaryLabel)
                    .frame(width: 34, alignment: .trailing)
            }
            Button { actions.toggleReply(for: session) } label: {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(island.replyingTo == session.id ? p.label : p.tertiaryLabel)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(island.replyingTo == session.id ? p.quaternaryLabel : .clear))
            }
            .buttonStyle(PressStyle())
            .help("Reply to this session")
        }
        .padding(.horizontal, 14)
        .frame(height: Island.rowHeight)
    }

    /// Small git counts: a pencil with files not committed, an arrow with commits not pushed. Hidden at 0.
    private func gitBadge(_ symbol: String, _ n: Int, _ p: Palette) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
            Text("\(n)").font(Theme.digits(11))
        }
        .foregroundStyle(p.tertiaryLabel)
        .fixedSize()
    }

    /// "$87" from the transcript (the turn count is in the tooltip, to keep the row short); hidden at 0.
    private var statsText: String? { session.usage.costUSD >= 0.005 ? costText(session.usage.costUSD) : nil }

    @ViewBuilder private func leading(_ p: Palette) -> some View {
        switch session.state {
        case .working, .running:
            StatusGrid(size: 16, kind: .working, palette: p, animate: !island.reduceMotion, trigger: stepWord.hashValue)
        case .needsYou:
            StatusGrid(size: 16, kind: .needsYou, palette: p)
        case .done:
            StatusGrid(size: 16, kind: .done, palette: p)
        default:
            Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(p.tertiaryLabel).frame(width: 16, height: 16)
        }
    }

    private var stepSymbol: String {
        switch session.state {
        case .idle: "circle"
        case .working(let step), .running(_, let step): step.symbol
        case .needsYou(let kind):
            switch kind {
            case .permission: "hand.raised"
            case .askingInApp: "bubble.left"
            case .question: "questionmark.circle"
            case .plan: "list.bullet.clipboard"
            }
        case .done: session.endsWithQuestion ? "questionmark.circle" : "checkmark"
        case .waiting: "clock"
        case .quiet: "zzz"
        }
    }

    private var stepWord: String {
        switch session.state {
        case .idle: return "Idle"
        case .working(let step): return step.word
        case .running(let since, _): return "Running · \(shortAge(Int(Date().timeIntervalSince(since))))"
        case .needsYou(let kind):
            switch kind {
            case .permission: return "Needs your OK"
            case .askingInApp: return "Asking in the app"
            case .question: return "Has a question"
            case .plan: return "Plan ready"
            }
        case .done(let seconds, let files):
            let base = session.endsWithQuestion ? "Waiting for you" : (seconds > 0 ? "Done · \(durationText(seconds))" : "Done")
            return files > 0 ? "\(base) · \(files) file\(files == 1 ? "" : "s")" : base
        case .waiting(let since): return "Waiting · \(shortAge(Int(Date().timeIntervalSince(since))))"
        case .quiet: return "Quiet"
        }
    }

    private func stepColor(_ p: Palette) -> Color {
        switch session.state {
        case .needsYou: p.needsYou
        case .done: session.endsWithQuestion ? p.needsYou : p.done
        case .working, .running: p.accent
        default: p.tertiaryLabel
        }
    }

    @ViewBuilder private func trailing(_ p: Palette) -> some View {
        if session.isWorking, let start = session.turnStart, !island.reduceMotion {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(clock(Int(context.date.timeIntervalSince(start))))
                    .font(Theme.digits(12)).foregroundStyle(p.secondaryLabel)
            }
        } else if session.isWorking, let start = session.turnStart {
            Text(clock(Int(Date().timeIntervalSince(start)))).font(Theme.digits(12)).foregroundStyle(p.secondaryLabel)
        }
    }

    private func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The card that takes over the island: Done (ref 3), a question or plan, or Claude asking in the app.
/// The permission card with Allow / Deny is built in step 6.
struct ClaudeCard: View {
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let card = island.displayedCard {
                PermissionCardView(card: card, session: session, island: island, actions: actions)
            } else if let question = island.displayedQuestion {
                QuestionCardView(card: question, session: session, island: island, actions: actions)
            } else {
                statusCard
            }
            HStack(spacing: 6) {
                if island.claude.attentionQueue.count > 1 {
                    let p = island.palette
                    Text("\(min(island.cardIndex, island.claude.attentionQueue.count - 1) + 1) of \(island.claude.attentionQueue.count)")
                        .font(Theme.digits(11)).foregroundStyle(p.tertiaryLabel)
                    smallButton("chevron.left") { actions.stepCard(-1) }
                    smallButton("chevron.right") { actions.stepCard(1) }
                }
                if island.displayedCard == nil {
                    smallButton("xmark") { actions.dismissCard(session) }
                }
            }
            .padding(.top, 10).padding(.trailing, 12)
        }
    }

    private func smallButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        let p = island.palette
        return Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(p.secondaryLabel)
                .frame(width: 20, height: 20).background(Circle().fill(p.quaternaryLabel))
        }
        .buttonStyle(PressStyle())
    }

    private var statusCard: some View {
        let p = island.palette
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        let message = messageToShow
        return ZStack(alignment: .leading) {
            shape.fill(p.tile).overlay(shape.strokeBorder(edge(p), lineWidth: 1))
            HStack(alignment: message == nil ? .center : .top, spacing: 0) {
                grid(p).padding(.leading, 20).padding(.top, message == nil ? 0 : 24)
                VStack(alignment: .leading, spacing: message == nil ? 4 : 6) {
                    Text(title).font(Theme.font(14, .bold)).foregroundStyle(p.label)
                    if let message {
                        ScrollView(.vertical) {
                            Text(message).font(Theme.font(12.5)).foregroundStyle(p.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .textSelection(.enabled)
                        }
                        .frame(height: Island.longCommandBox - 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.rim, lineWidth: 1))
                    }
                    Text(subtitle).font(Theme.font(12.5)).foregroundStyle(p.secondaryLabel).lineLimit(1)
                    Text(session.labelWithPlace).font(Theme.font(11)).foregroundStyle(p.tertiaryLabel).lineLimit(1)
                    if isDone { ReplyLine(session: session, island: island, actions: actions, autoFocus: false).frame(height: Island.replyRow - 8).padding(.top, 2) }
                }
                .padding(.leading, 20)
                .padding(.vertical, (message == nil && !isDone) ? 0 : 18)
                Spacer(minLength: 12)
                if needsOpen || message != nil {
                    Button { actions.rowClicked(session) } label: {
                        HStack(spacing: 5) {
                            Text("Open").font(Theme.font(13, .semibold))
                            Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).opacity(0.55)
                        }
                        .foregroundStyle(p.allowText)
                        .frame(width: 85, height: 30)
                        .background(Capsule().fill(p.allowBackground))
                    }
                    .buttonStyle(PressStyle())
                    .padding(.trailing, 20)
                    .padding(.top, message == nil ? 0 : 24)
                }
            }
        }
        .frame(width: Island.expandedWidth - 46, height: island.cardHeight)
        .contentShape(shape)
        .onTapGesture { if !needsOpen { actions.rowClicked(session) } }
    }

    private var needsOpen: Bool { session.needsYou != nil }

    private var isDone: Bool {
        if case .done = session.state { return true }
        return false
    }


    /// Claude's last words, shown on the Done card so you can read the reply without opening the app.
    private var messageToShow: String? {
        if case .done = session.state { return session.lastMessage }
        return nil
    }

    @ViewBuilder private func grid(_ p: Palette) -> some View {
        switch session.state {
        case .done: StatusGrid(size: 32, kind: session.endsWithQuestion ? .needsYou : .done, palette: p)
        default: StatusGrid(size: 32, kind: .needsYou, palette: p)
        }
    }

    private func edge(_ p: Palette) -> Color {
        switch session.state {
        case .done: session.endsWithQuestion ? p.needsYou : p.done
        default: p.needsYou
        }
    }

    private var title: String {
        switch session.state {
        case .done(let seconds, _): session.endsWithQuestion ? "Waiting for you" : (seconds > 0 ? "Done in \(durationText(seconds))" : "Done")
        case .needsYou(.question): "Claude has a question"
        case .needsYou(.plan): "Claude's plan is ready"
        case .needsYou(.askingInApp): "Claude is asking in the app"
        default: "Claude needs your OK"
        }
    }

    private var subtitle: String {
        switch session.state {
        case .done(_, let files):
            var parts: [String] = []
            if files > 0 { parts.append("\(files) file\(files == 1 ? "" : "s") changed") }
            if !session.agents.isEmpty { parts.append("\(session.agents.count) agent\(session.agents.count == 1 ? "" : "s") running") }
            if let n = session.dirtyFiles, n > 0 { parts.append("\(n) not committed") }
            if let n = session.unpushed, n > 0 { parts.append("\(n) commit\(n == 1 ? "" : "s") to push") }
            if let cost = session.turnCost, cost >= 0.005 { parts.append("\(costText(cost)) this turn") }
            return parts.isEmpty ? "Nothing changed" : parts.joined(separator: " · ")
        case .needsYou(.question), .needsYou(.plan): return "Answer it in the app"
        case .needsYou(.askingInApp): return "The island could not take this one"
        default: return ""
        }
    }
}

/// Ref 2: amber grid, "Claude needs your OK", the command, project and branch, Allow and Deny stacked on the right.
/// Long commands open in a scrolling monospace box; Allow turns on once you have scrolled to the end.
struct PermissionCardView: View {
    let card: PermissionCard
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions
    @State private var scrolledToEnd = false
    @State private var feedback = ""

    var body: some View {
        let p = island.palette
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        let long = card.isPlan || Island.isLong(card.command)
        // A long command must be read to the end before Allow turns on; a plan can be approved at once.
        let allowOn = long && !card.isPlan ? scrolledToEnd : true
        ZStack(alignment: .leading) {
            shape.fill(p.tile).overlay(shape.strokeBorder(p.needsYou, lineWidth: 1))
            HStack(alignment: long ? .top : .center, spacing: 0) {
                StatusGrid(size: 32, kind: .needsYou, palette: p)
                    .padding(.leading, 20)
                    .padding(.top, long ? 24 : 0)
                VStack(alignment: .leading, spacing: long ? 6 : 4) {
                    HStack(spacing: 8) {
                        Text(card.isPlan ? "Claude's plan is ready" : "Claude needs your OK").font(Theme.font(14, .bold)).foregroundStyle(p.label)
                    }
                    if long {
                        ScrollView(.vertical) {
                            Text(card.command).font(card.isPlan ? Theme.font(12) : Theme.mono(12)).foregroundStyle(p.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .textSelection(.enabled)
                        }
                        .frame(height: Island.longCommandBox - 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.rim, lineWidth: 1))
                        .onScrollGeometryChange(for: Bool.self) { geometry in
                            geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 2
                        } action: { _, atEnd in
                            if atEnd { scrolledToEnd = true; island.claude.frontCardFullySeen = true }
                        }
                        if card.isPlan {
                            TextField("Why not? Goes to Claude with Keep planning (optional)", text: $feedback)
                                .textFieldStyle(.plain).font(Theme.font(12)).foregroundStyle(p.label)
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.rim, lineWidth: 1))
                        }
                        Text(card.isPlan ? "\(lines) lines · scroll to read it all, or Approve now"
                             : scrolledToEnd ? "Full command seen · \(lines) lines" : "Scroll to the end to turn on Allow · \(lines) lines")
                            .font(Theme.font(11)).foregroundStyle(p.tertiaryLabel)
                    } else {
                        Text(card.command).font(Theme.font(12.5)).foregroundStyle(p.secondaryLabel).lineLimit(1).truncationMode(.tail)
                    }
                    Text(session.labelWithPlace).font(Theme.font(11)).foregroundStyle(p.tertiaryLabel).lineLimit(1)
                }
                .padding(.leading, 20)
                .padding(.vertical, long ? 18 : 0)
                Spacer(minLength: 12)
                VStack(spacing: 6) {
                    pill(card.isPlan ? "Approve" : "Allow", island.hotKeyAllow, p.allowBackground, p.allowText, on: allowOn && !island.claude.frontCardGuarded) { actions.answer(card, allow: true) }
                    pill(card.isPlan ? "Keep planning" : "Deny", island.hotKeyDeny, p.deny, p.label, on: true) { actions.answer(card, allow: false, message: feedback) }
                }
                .padding(.trailing, 20)
                .padding(.top, long ? 24 : 0)
            }
        }
        .frame(width: Island.expandedWidth - 46, height: island.cardHeight)
        .id(card.id)
    }

    private var lines: Int { card.command.filter { $0 == "\n" }.count + 1 }

    private func pill(_ title: String, _ key: String, _ bg: Color, _ fg: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(Theme.font(13, .semibold))
                Text(key).font(Theme.font(10.5)).opacity(0.55)
            }
            .foregroundStyle(fg)
            .frame(width: card.isPlan ? 140 : 85, height: 30)
            .background(Capsule().fill(bg))
        }
        .buttonStyle(PressStyle())
        .disabled(!on)
        .opacity(on ? 1 : 0.35)
    }
}

/// Claude's multiple-choice question: tap an option, or type an answer. Several questions come one at a time.
/// The answers go back down the waiting hook; × or Open hands the question to the app instead.
struct QuestionCardView: View {
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
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        let q = card.questions[min(index, card.questions.count - 1)]
        ZStack(alignment: .leading) {
            shape.fill(p.tile).overlay(shape.strokeBorder(p.needsYou, lineWidth: 1))
            HStack(alignment: .top, spacing: 0) {
                StatusGrid(size: 32, kind: .needsYou, palette: p).padding(.leading, 20).padding(.top, 24)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(q.header.isEmpty ? "Claude has a question" : "Claude asks · \(q.header)")
                            .font(Theme.font(14, .bold)).foregroundStyle(p.label).lineLimit(1)
                        if card.questions.count > 1 {
                            Text("\(index + 1) of \(card.questions.count)").font(Theme.digits(11)).foregroundStyle(p.tertiaryLabel)
                        }
                    }
                    .padding(.trailing, 110)   // room for × and ‹ › in the corner
                    Text(q.text).font(Theme.font(12.5)).foregroundStyle(p.label).lineLimit(2)
                        .frame(height: 32, alignment: .topLeading)
                    ForEach(q.options, id: \.label) { option in optionRow(option, q, p) }
                    HStack(spacing: 8) {
                        TextField("Or type an answer…", text: $typed)
                            .textFieldStyle(.plain)
                            .font(Theme.font(12.5))
                            .foregroundStyle(p.label)
                            .onSubmit { submit(q, typed) }
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(p.rim, lineWidth: 1))
                        if q.multiSelect || !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button { submit(q, typed.trimmingCharacters(in: .whitespaces).isEmpty ? picked.joined(separator: ", ") : typed) } label: {
                                Text(q.multiSelect ? "Done" : "Send").font(Theme.font(13, .semibold)).foregroundStyle(p.allowText)
                                    .frame(width: 70, height: 28).background(Capsule().fill(p.allowBackground))
                            }
                            .buttonStyle(PressStyle())
                            .disabled(picked.isEmpty && typed.trimmingCharacters(in: .whitespaces).isEmpty)
                            .opacity(picked.isEmpty && typed.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
                        }
                    }
                    Text(session.labelWithPlace).font(Theme.font(11)).foregroundStyle(p.tertiaryLabel).lineLimit(1)
                }
                .padding(.leading, 20).padding(.trailing, 20).padding(.vertical, 18)
            }
        }
        .frame(width: Island.expandedWidth - 46, height: island.cardHeight)
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
            HStack(spacing: 8) {
                if q.multiSelect {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 12))
                        .foregroundStyle(on ? p.accent : p.tertiaryLabel)
                }
                Text(option.label).font(Theme.font(12.5, .semibold)).foregroundStyle(p.label).lineLimit(1)
                if !option.description.isEmpty {
                    Text(option.description).font(Theme.font(11)).foregroundStyle(p.secondaryLabel).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: Island.questionOption - 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? p.accent : p.rim, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressStyle())
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

/// One line to type a note for the row; Return keeps it, Escape or an empty line clears it.
struct NoteLine: View {
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let p = island.palette
        HStack(spacing: 8) {
            Image(systemName: "note.text").font(.system(size: 11, weight: .medium)).foregroundStyle(p.tertiaryLabel)
            TextField("Note for this row, e.g. waiting on Dave's PR", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.font(12.5))
                .foregroundStyle(p.label)
                .focused($focused)
                .onSubmit { actions.setNote(text, for: session) }
                .onExitCommand { actions.setNote(session.note, for: session) }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(focused ? p.accent : p.rim, lineWidth: 1))
            Button { actions.setNote(text, for: session) } label: {
                Text("Keep").font(Theme.font(12, .semibold)).foregroundStyle(p.allowText)
                    .frame(width: 56, height: 28).background(Capsule().fill(p.allowBackground))
            }
            .buttonStyle(PressStyle())
        }
        .onAppear { text = session.note ?? ""; focused = true }
    }
}

/// One line to type a reply; Return or the arrow sends it. Claude gets it as its next instruction.
struct ReplyLine: View {
    var session: ClaudeSession
    var island: Island
    let actions: IslandActions
    var autoFocus: Bool
    @State private var reply = ""
    @FocusState private var focused: Bool

    var body: some View {
        let p = island.palette
        HStack(spacing: 8) {
            TextField("Reply to Claude…", text: $reply)
                .textFieldStyle(.plain)
                .font(Theme.font(12.5))
                .foregroundStyle(p.label)
                .focused($focused)
                .onSubmit(send)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.island))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(focused ? p.accent : p.rim, lineWidth: 1))
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(p.allowText)
                    .frame(width: 28, height: 28).background(Circle().fill(p.allowBackground))
            }
            .buttonStyle(PressStyle())
            .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(reply.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
            if let status = island.replyStatus {
                Text(status).font(Theme.font(11)).foregroundStyle(p.tertiaryLabel).lineLimit(1)
            }
        }
        .onAppear { if autoFocus { focused = true } }
    }

    private func send() {
        let text = reply
        reply = ""
        actions.reply(text, to: session)
    }
}
