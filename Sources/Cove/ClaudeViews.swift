import SwiftUI

/// One row per Claude session, in a strip above the tiles.
struct ClaudeStrip: View {
    var island: Island
    let actions: IslandActions

    var body: some View {
        let p = island.palette
        VStack(spacing: 0) {
            ForEach(island.claude.sessions) { session in
                SessionRow(session: session, island: island)
                    .contentShape(Rectangle())
                    .onTapGesture { actions.rowClicked(session) }
                    .overlay(alignment: .bottom) {
                        if session.id != island.claude.sessions.last?.id {
                            Rectangle().fill(p.rim).frame(height: 1)
                        }
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

    var body: some View {
        let p = island.palette
        HStack(spacing: 10) {
            leading(p)
            Text(session.label).font(Theme.font(12, .semibold)).foregroundStyle(p.label)
                .lineLimit(1).truncationMode(.middle).layoutPriority(1)
            HStack(spacing: 5) {
                Image(systemName: stepSymbol).font(.system(size: 11, weight: .medium)).foregroundStyle(stepColor(p))
                Text(stepWord).font(Theme.font(12)).foregroundStyle(p.secondaryLabel)
            }
            .lineLimit(1)
            if !session.agents.isEmpty {
                Text("+\(session.agents.count) agent\(session.agents.count == 1 ? "" : "s")")
                    .font(Theme.font(11)).foregroundStyle(p.tertiaryLabel)
            }
            Spacer(minLength: 8)
            trailing(p)
        }
        .padding(.horizontal, 14)
        .frame(height: Island.rowHeight)
    }

    @ViewBuilder private func leading(_ p: Palette) -> some View {
        switch session.state {
        case .working, .running:
            StatusGrid(size: 16, kind: .working, palette: p, animate: !island.reduceMotion)
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
            let base = session.endsWithQuestion ? "Waiting for you" : "Done · \(durationText(seconds))"
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
        if let card = island.claude.frontCard {
            PermissionCardView(card: card, session: session, island: island, actions: actions)
        } else {
            statusCard
        }
    }

    private var statusCard: some View {
        let p = island.palette
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        return ZStack(alignment: .leading) {
            shape.fill(p.tile).overlay(shape.strokeBorder(edge(p), lineWidth: 1))
            HStack(spacing: 0) {
                grid(p).padding(.leading, 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.font(14, .bold)).foregroundStyle(p.label)
                    Text(subtitle).font(Theme.font(12.5)).foregroundStyle(p.secondaryLabel).lineLimit(1)
                    Text(session.label).font(Theme.font(11)).foregroundStyle(p.tertiaryLabel).lineLimit(1)
                }
                .padding(.leading, 20)
                Spacer(minLength: 12)
                if needsOpen {
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
                }
            }
        }
        .frame(width: Island.expandedWidth - 46, height: Island.cardHeight)
        .contentShape(shape)
        .onTapGesture { if !needsOpen { actions.rowClicked(session) } }
    }

    private var needsOpen: Bool { session.needsYou != nil }

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
        case .done(let seconds, _): session.endsWithQuestion ? "Waiting for you" : "Done in \(durationText(seconds))"
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

    var body: some View {
        let p = island.palette
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        let long = Island.isLong(card.command)
        let allowOn = long ? scrolledToEnd : true
        ZStack(alignment: .leading) {
            shape.fill(p.tile).overlay(shape.strokeBorder(p.needsYou, lineWidth: 1))
            HStack(alignment: long ? .top : .center, spacing: 0) {
                StatusGrid(size: 32, kind: .needsYou, palette: p)
                    .padding(.leading, 20)
                    .padding(.top, long ? 24 : 0)
                VStack(alignment: .leading, spacing: long ? 6 : 4) {
                    HStack(spacing: 8) {
                        Text("Claude needs your OK").font(Theme.font(14, .bold)).foregroundStyle(p.label)
                        if island.claude.cards.count > 1 {
                            Text("1 of \(island.claude.cards.count)").font(Theme.font(11)).foregroundStyle(p.tertiaryLabel)
                        }
                    }
                    if long {
                        ScrollView(.vertical) {
                            Text(card.command).font(Theme.mono(12)).foregroundStyle(p.label)
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
                        Text(scrolledToEnd ? "Full command seen · \(lines) lines" : "Scroll to the end to turn on Allow · \(lines) lines")
                            .font(Theme.font(11)).foregroundStyle(p.tertiaryLabel)
                    } else {
                        Text(card.command).font(Theme.font(12.5)).foregroundStyle(p.secondaryLabel).lineLimit(1).truncationMode(.tail)
                    }
                    Text(session.label).font(Theme.font(11)).foregroundStyle(p.tertiaryLabel).lineLimit(1)
                }
                .padding(.leading, 20)
                .padding(.vertical, long ? 18 : 0)
                Spacer(minLength: 12)
                VStack(spacing: 6) {
                    pill("Allow", island.hotKeyAllow, p.allowBackground, p.allowText, on: allowOn && !island.claude.frontCardGuarded) { actions.answer(card, allow: true) }
                    pill("Deny", island.hotKeyDeny, p.deny, p.label, on: true) { actions.answer(card, allow: false) }
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
            .frame(width: 85, height: 30)
            .background(Capsule().fill(bg))
        }
        .buttonStyle(PressStyle())
        .disabled(!on)
        .opacity(on ? 1 : 0.35)
    }
}
