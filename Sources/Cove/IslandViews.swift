import AppKit
import SwiftUI

/// Actions the views can ask for. The controller fills in the behaviour.
@MainActor
final class IslandActions {
    weak var controller: IslandController?

    func togglePin() { controller?.togglePin() }
    func toggleEdit() { controller?.toggleEdit() }
    func toggleTheme() { controller?.toggleTheme() }
    func openMenu() { controller?.openMenu() }
    func open(_ app: RecentApps.Entry) { controller?.island.recentApps.open(app) }
    func rowClicked(_ session: ClaudeSession) { controller?.rowClicked(session) }
    func reply(_ text: String, to session: ClaudeSession) { controller?.sendReply(text, to: session) }
    func toggleReply(for session: ClaudeSession) { controller?.toggleReply(for: session) }
    func answer(_ card: PermissionCard, allow: Bool) { controller?.answer(card, allow: allow) }
    func spotify(_ command: SpotifyCommand) { controller?.spotify(command) }
}

/// Press feedback on every button: scale 0.97 in 120 ms.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The black shape growing out of the notch: flat top, round bottom corners, small concave "ears"
/// where it meets the screen edge so it reads as part of the notch.
struct BlackShape: Shape {
    var params: BlackParams

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(params.width, params.height), AnimatablePair(params.radius, params.ear)) }
        set { params = BlackParams(width: newValue.first.first, height: newValue.first.second,
                                   radius: newValue.second.first, ear: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        let ear = params.ear
        let radius = min(params.radius, params.height / 2, params.width / 2)
        let x0 = rect.midX - params.width / 2
        let x1 = rect.midX + params.width / 2
        let top = rect.minY
        let bottom = top + params.height
        var path = Path()
        path.move(to: CGPoint(x: x0 - ear, y: top))
        if ear > 0 {
            path.addQuadCurve(to: CGPoint(x: x0, y: top + ear), control: CGPoint(x: x0, y: top))
        }
        path.addLine(to: CGPoint(x: x0, y: bottom - radius))
        path.addArc(tangent1End: CGPoint(x: x0, y: bottom), tangent2End: CGPoint(x: x0 + radius, y: bottom), radius: radius)
        path.addLine(to: CGPoint(x: x1 - radius, y: bottom))
        path.addArc(tangent1End: CGPoint(x: x1, y: bottom), tangent2End: CGPoint(x: x1, y: bottom - radius), radius: radius)
        path.addLine(to: CGPoint(x: x1, y: top + ear))
        if ear > 0 {
            path.addQuadCurve(to: CGPoint(x: x1 + ear, y: top), control: CGPoint(x: x1, y: top))
        }
        path.closeSubpath()
        return path
    }
}

/// Root of the panel. Always draws the black notch shape; the grey island appears for `expanded`.
struct IslandRoot: View {
    var island: Island
    let actions: IslandActions

    var body: some View {
        let params = island.blackParams
        ZStack(alignment: .top) {
            if island.mode == .expanded {
                ExpandedIsland(island: island, actions: actions)
                    .transition(.scale(scale: 0.27, anchor: .top).combined(with: .opacity))
                    .zIndex(1)
            }
            BlackShape(params: params)
                .fill(.black)
                .overlay(alignment: .top) { blackContent }
                .frame(width: params.width + 2 * params.ear, height: params.height)
                .zIndex(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var blackContent: some View {
        switch island.mode {
        case .compact:
            if let content = island.compactContent {
                CompactLobes(content: content, island: island).transition(.opacity)
            }
        case .peek:
            if let content = island.peek {
                PeekBody(content: content, island: island).transition(.opacity)
            }
        default:
            EmptyView()
        }
    }
}

/// Pill A "Wings": state on the left lobe, project and count on the right.
struct CompactLobes: View {
    let content: CompactContent
    var island: Island

    var body: some View {
        let p = island.palette
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                StatusGrid(size: 12, kind: content.kind, palette: p, animate: !island.reduceMotion)
                Text(content.word).font(Theme.font(12, .semibold)).foregroundStyle(p.onBlackLabel)
            }
            .frame(width: Island.lobeWidth)
            Spacer().frame(width: island.notchSize.width)
            HStack(spacing: 6) {
                Text(content.detail).font(Theme.font(12)).foregroundStyle(p.onBlackSecondary)
                if let count = content.count {
                    Text(count).font(Theme.digits(10.5, .bold)).foregroundStyle(p.onBlackLabel)
                        .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(p.onBlackQuaternary))
                }
            }
            .frame(width: Island.lobeWidth)
        }
        .lineLimit(1)
        .frame(height: island.notchSize.height)
        .padding(.horizontal, Island.ear)
    }
}

/// The lower band of a peek: icon + word, optional second line in monospace.
struct PeekBody: View {
    let content: PeekContent
    var island: Island

    var body: some View {
        let p = island.palette
        VStack(spacing: 2) {
            HStack(spacing: 7) {
                if let icon = content.icon {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                } else if let symbol = content.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(content.tint.map(p.color) ?? p.onBlackLabel)
                }
                Text(content.word).font(Theme.font(13, .semibold)).foregroundStyle(p.onBlackLabel)
            }
            .frame(height: 24)
            if let second = content.second {
                Text(second).font(Theme.mono(11)).foregroundStyle(p.onBlackSecondary).frame(height: 14)
            }
        }
        .lineLimit(1)
        .frame(width: island.notchSize.width - 16)
        .padding(.top, island.notchSize.height)
    }
}

/// The 5 × 5 status grid. Working walks three accent cells; needs-you lights a few amber; done is a green ring.
struct StatusGrid: View {
    let size: CGFloat
    let kind: CompactContent.Kind
    let palette: Palette
    var animate = true

    static let amber: Set<Int> = [3, 4, 7]
    static let ring: Set<Int> = [0, 1, 2, 3, 4, 5, 9, 10, 12, 14, 15, 19, 20, 21, 22, 23, 24]
    var body: some View {
        switch kind {
        case .working where animate:
            TimelineView(.periodic(from: .now, by: 0.3)) { context in
                cells(lit: Walk.cells(at: Int(context.date.timeIntervalSinceReferenceDate / 0.3)), color: palette.accent)
            }
        case .working:
            cells(lit: Set(Walk.start), color: palette.accent)
        case .needsYou:
            cells(lit: Self.amber, color: palette.needsYou)
        case .done:
            cells(lit: Self.ring, color: palette.done)
        }
    }

    private func cells(lit: Set<Int>, color: Color) -> some View {
        let gap = size / 32 * 1.75
        let cell = (size - 4 * gap) / 5
        return VStack(spacing: gap) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<5, id: \.self) { col in
                        RoundedRectangle(cornerRadius: max(0.5, cell / 5))
                            .fill(lit.contains(row * 5 + col) ? color : palette.onBlackQuaternary)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// A deterministic random walk so the grid needs no stored state: step n always gives the same cells.
enum Walk {
    static let start = [6, 7, 12]

    static func cells(at step: Int) -> Set<Int> {
        var lit = start
        var seed = UInt64(truncatingIfNeeded: step / 240) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        for _ in 0..<(step % 240) {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let which = Int(seed >> 33) % lit.count
            let cell = lit[which]
            let row = cell / 5, col = cell % 5
            let moves = [(1, 0), (-1, 0), (0, 1), (0, -1)].compactMap { (dr, dc) -> Int? in
                let r = row + dr, c = col + dc
                guard r >= 0, r < 5, c >= 0, c < 5 else { return nil }
                let next = r * 5 + c
                return lit.contains(next) ? nil : next
            }
            if !moves.isEmpty { lit[which] = moves[Int((seed >> 17) % UInt64(moves.count))] }
        }
        return Set(lit)
    }
}

// MARK: - Expanded island

struct ExpandedIsland: View {
    var island: Island
    let actions: IslandActions

    var body: some View {
        let p = island.palette
        let shape = RoundedRectangle(cornerRadius: 35, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(p.island)
                .overlay(shape.strokeBorder(p.rim, lineWidth: 1))
                .contentShape(shape)
                .onTapGesture { actions.togglePin() }
            ToolbarRow(island: island, actions: actions)
            if let session = island.cardSession {
                ClaudeCard(session: session, island: island, actions: actions)
                    .padding(.top, island.notchSize.height + 18)
            } else {
                VStack(spacing: 8) {
                    if !island.claude.sessions.isEmpty {
                        ClaudeStrip(island: island, actions: actions)
                    }
                    if !island.visibleTiles.isEmpty {
                        TilesRow(island: island, actions: actions)
                    }
                }
                .padding(.top, island.notchSize.height + 18)
            }
        }
        .frame(width: Island.expandedWidth, height: island.expandedHeight)
    }
}

struct ToolbarRow: View {
    var island: Island
    let actions: IslandActions

    var body: some View {
        let p = island.palette
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ToolButton(symbol: "gearshape", palette: p) { actions.openMenu() }
                ToolButton(symbol: "checkmark.circle", on: island.editing, palette: p) { actions.toggleEdit() }
                if island.volume.available {
                    ToolButton(symbol: island.volume.muted ? "speaker.slash" : "speaker.wave.2", palette: p) { island.volume.toggleMute() }
                }
                ToolButton(symbol: "circle.lefthalf.filled", palette: p) { actions.toggleTheme() }
            }
            .padding(.leading, 24)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(island.recentApps.apps) { app in
                    Button { actions.open(app) } label: {
                        Image(nsImage: app.icon).resizable().frame(width: 16, height: 16).frame(width: 22, height: 22)
                    }
                    .buttonStyle(PressStyle())
                    .help(app.name)
                }
            }
            .padding(.trailing, 24)
        }
        .frame(width: Island.expandedWidth, height: island.notchSize.height)
    }
}

struct ToolButton: View {
    let symbol: String
    var on = false
    let palette: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? palette.label : palette.secondaryLabel)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? palette.quaternaryLabel : .clear))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Tiles

struct TilesRow: View {
    var island: Island
    let actions: IslandActions
    @State private var drag: Drag?

    private struct Drag {
        var kind: TileKind
        var offset: CGFloat = 0
        /// How far the tile's resting spot has already moved because of swaps during this drag.
        var consumed: CGFloat = 0
    }

    var body: some View {
        let tiles = island.visibleTiles
        HStack(alignment: .top, spacing: 8) {
            ForEach(tiles, id: \.self) { kind in
                TileView(kind: kind, island: island, actions: actions,
                         dragOffset: drag?.kind == kind ? (drag?.offset ?? 0) : 0,
                         onDrag: { dragChanged(kind, translation: $0) },
                         onDragEnd: { island.commitOrder(); withAnimation(.easeInOut(duration: 0.12)) { drag = nil } })
                    .zIndex(drag?.kind == kind ? 1 : 0)
            }
        }
        .frame(width: Island.expandedWidth, alignment: .center)
    }

    private func dragChanged(_ kind: TileKind, translation: CGFloat) {
        var d = drag ?? Drag(kind: kind)
        d.offset = translation - d.consumed
        let tiles = island.visibleTiles
        guard let index = tiles.firstIndex(of: kind) else { return }
        let centers = tiles.reduce(into: [CGFloat]()) { acc, t in
            let x = (acc.last.map { $0 + tiles[acc.count - 1].width / 2 + 8 } ?? 0) + t.width / 2
            acc.append(x)
        }
        let draggedCenter = centers[index] + d.offset
        if index + 1 < tiles.count, draggedCenter > centers[index + 1] {
            let shift = tiles[index + 1].width + 8
            d.consumed += shift
            d.offset -= shift
            withAnimation(.easeInOut(duration: 0.12)) { island.move(kind, to: tiles[index + 1]) }
        } else if index > 0, draggedCenter < centers[index - 1] {
            let shift = tiles[index - 1].width + 8
            d.consumed -= shift
            d.offset += shift
            withAnimation(.easeInOut(duration: 0.12)) { island.move(kind, to: tiles[index - 1]) }
        }
        drag = d
    }
}

/// The one tile view every tile uses: fill, radius, fixed size, edit badges and drag handle.
struct TileView: View {
    let kind: TileKind
    var island: Island
    let actions: IslandActions
    var dragOffset: CGFloat = 0
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnd: () -> Void = {}

    var body: some View {
        let p = island.palette
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(p.tile)
            content
                .frame(width: kind.width, height: 94, alignment: .topLeading)
                .clipShape(shape)
            if island.editing {
                Button { withAnimation(.easeInOut(duration: 0.22)) { island.hide(kind) } } label: {
                    ZStack {
                        Circle().fill(p.blocked)
                        Image(systemName: "minus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(width: 16, height: 16)
                }
                .buttonStyle(PressStyle())
                .offset(x: -5, y: -5)
                RoundedRectangle(cornerRadius: 1.5).fill(p.tertiaryLabel)
                    .frame(width: 3, height: 24)
                    .frame(width: 16, height: 40)
                    .contentShape(Rectangle())
                    .offset(x: kind.width - 17, y: 27)
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { onDrag($0.translation.width) }
                        .onEnded { _ in onDragEnd() })
            }
        }
        .frame(width: kind.width, height: 94)
        .offset(x: dragOffset)
    }

    @ViewBuilder private var content: some View {
        let p = island.palette
        switch kind {
        case .spotify:
            if let track = island.spotify {
                SpotifyTileContent(track: track, palette: p, actions: actions, live: !island.demo && !island.reduceMotion,
                                   progress: { [spotifyModel = island.spotifyModel] in spotifyModel.progress })
            }
        case .weather:
            if let weather = island.weather { WeatherTileContent(weather: weather, palette: p) }
        case .calendar:
            if let event = island.nextEvent { CalendarTileContent(event: event, palette: p) }
        case .timer:
            TimerTileContent(timer: island.timer, palette: p)
        }
    }
}

struct SpotifyTileContent: View {
    let track: SpotifyTrack
    let palette: Palette
    let actions: IslandActions
    /// Live progress from the Spotify model (false in Demo, where the sample value is shown).
    var live = false
    var progress: () -> Double = { 0 }

    private func progressBar(_ value: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(palette.quaternaryLabel)
            Capsule().fill(palette.secondaryLabel).frame(width: max(0, min(1, value)) * 81)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let art = track.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        palette.quaternaryLabel
                        Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(palette.secondaryLabel)
                    }
                }
            }
            .frame(width: 57, height: 57)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .offset(x: 10, y: 15)
            Text(track.title).font(Theme.font(13, .bold)).foregroundStyle(palette.label)
                .lineLimit(1).frame(width: 85, alignment: .leading).offset(x: 77, y: 15)
            Text(track.artist).font(Theme.font(12)).foregroundStyle(palette.secondaryLabel)
                .lineLimit(1).frame(width: 85, alignment: .leading).offset(x: 77, y: 32)
            Group {
                if track.playing && live {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in progressBar(progress()) }
                } else {
                    progressBar(track.progress)
                }
            }
            .frame(width: 81, height: 2).offset(x: 77, y: 53)
            HStack(spacing: 16) {
                control("backward.fill", .previous)
                control(track.playing ? "pause.fill" : "play.fill", .playPause)
                control("forward.fill", .next)
            }
            .offset(x: 84, y: 64)
        }
    }

    private func control(_ symbol: String, _ command: SpotifyCommand) -> some View {
        Button { actions.spotify(command) } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.label)
                .frame(width: 18, height: 16)
        }
        .buttonStyle(PressStyle())
    }
}

struct WeatherTileContent: View {
    let weather: WeatherNow
    let palette: Palette

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("\(weather.temperature)°").font(Theme.digits(28, .light)).foregroundStyle(palette.label)
                .offset(x: 14, y: 10)
            Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 22))
                .frame(width: 26, height: 26).offset(x: 170 - 14 - 26, y: 12)
            Text(weather.city).font(Theme.font(12)).foregroundStyle(palette.secondaryLabel)
                .lineLimit(1).frame(width: 120, alignment: .leading).offset(x: 14, y: 50)
            Text("H \(weather.high)°  L \(weather.low)°").font(Theme.digits(11)).foregroundStyle(palette.tertiaryLabel)
                .offset(x: 14, y: 73)
        }
    }
}

struct CalendarTileContent: View {
    let event: CalendarEvent
    let palette: Palette

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(event.dayName).font(Theme.font(10, .bold)).kerning(0.6).foregroundStyle(palette.tertiaryLabel)
                .offset(x: 14, y: 14)
            Text(event.dayNumber).font(Theme.digits(28, .light)).foregroundStyle(palette.label)
                .offset(x: 14, y: 28)
            Text(event.title).font(Theme.font(13, .bold)).foregroundStyle(palette.label)
                .lineLimit(1).frame(width: 110, alignment: .leading).offset(x: 54, y: 15)
            Text(event.when).font(Theme.digits(10)).foregroundStyle(palette.secondaryLabel)
                .lineLimit(1).frame(width: 110, alignment: .leading).offset(x: 54, y: 34)
        }
    }
}

struct TimerTileContent: View {
    var timer: FocusTimer
    let palette: Palette

    var body: some View {
        ZStack(alignment: .top) {
            Text(timer.text).font(Theme.digits(20, .light)).foregroundStyle(palette.label)
                .frame(width: 81).offset(y: 16)
            Button { timer.toggle() } label: {
                ZStack {
                    Circle().fill(palette.quaternaryLabel)
                    Image(systemName: timer.running ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.label)
                        .offset(x: timer.running ? 0 : 1)
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(PressStyle())
            .offset(y: 46)
            Button { timer.reset() } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.secondaryLabel).frame(width: 18, height: 18)
            }
            .buttonStyle(PressStyle())
            .opacity(timer.isAtStart ? 0 : 1)
            .offset(x: 26, y: 51)
        }
    }
}
