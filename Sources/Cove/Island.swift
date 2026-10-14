import AppKit
import SwiftUI

enum TileKind: String, CaseIterable, Sendable {
    case spotify, weather, calendar, timer

    var width: CGFloat { self == .timer ? 81 : 170 }
    var title: String {
        switch self {
        case .spotify: "Spotify"
        case .weather: "Weather"
        case .calendar: "Calendar"
        case .timer: "Timer"
        }
    }
}

struct SpotifyTrack: Equatable {
    var title: String
    var artist: String
    var artwork: NSImage?
    var progress: Double
    var playing: Bool
}

enum SpotifyCommand: Sendable { case previous, playPause, next }

struct WeatherNow: Equatable {
    var temperature: Int
    var high: Int
    var low: Int
    var symbol: String
    var city: String
}

struct CalendarEvent: Equatable {
    var title: String
    var when: String
    var dayName: String
    var dayNumber: String
}

/// What the compact pill shows: the most urgent session plus a count.
struct CompactContent: Equatable {
    enum Kind: Sendable { case working, needsYou, done }
    var kind: Kind
    var word: String
    var detail: String
    var count: String?

    var tint: Tint {
        switch kind {
        case .working: .accent
        case .needsYou: .needsYou
        case .done: .done
        }
    }
}

/// A short black bubble growing out of the notch.
struct PeekContent: Equatable {
    var symbol: String?
    var icon: NSImage?
    var tint: Tint?
    var word: String
    var second: String?
}

/// The black shape that grows out of the notch, in points.
struct BlackParams: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var ear: CGFloat
}

/// Everything the island shows. Views read it; the controller and data sources write it.
@MainActor
@Observable
final class Island {
    enum Mode: Equatable { case resting, compact, peek, expanded }

    static let expandedWidth: CGFloat = 662
    static let lobeWidth: CGFloat = 112
    static let ear: CGFloat = 8

    var mode: Mode = .resting
    var pinned = false
    var editing = false
    var demo = false
    private(set) var themeMode: ThemeMode
    /// Every colour the views use, resolved once per theme change (not per view body).
    private(set) var palette: Palette
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var notchSize = CGSize(width: 179, height: 32)

    private(set) var order: [TileKind]
    private(set) var hidden: Set<TileKind>

    var compact: CompactContent?
    var peek: PeekContent?
    var spotify: SpotifyTrack?
    var weather: WeatherNow?
    var nextEvent: CalendarEvent?

    let timer = FocusTimer()
    let recentApps = RecentApps()
    let volume = VolumeControl()
    let claude = ClaudeModel()
    let spotifyModel = SpotifyModel()
    let weatherModel = WeatherModel()
    let calendarModel = CalendarModel()
    /// Feedback under the reply box ("Sent", or why it could not be delivered).
    var replyStatus: String?
    /// The session whose row has its reply line open.
    var replyingTo: String?
    var hotKeyAllow = HotKeys.defaultAllow.display
    var hotKeyDeny = HotKeys.defaultDeny.display

    init() {
        let defaults = UserDefaults.standard
        let mode = ThemeMode(rawValue: defaults.string(forKey: "theme") ?? "") ?? .dark
        themeMode = mode
        palette = Theme.palette(mode)
        let saved = (defaults.stringArray(forKey: "tileOrder") ?? []).compactMap(TileKind.init(rawValue:))
        order = saved.count == TileKind.allCases.count ? saved : TileKind.allCases
        hidden = Set((defaults.stringArray(forKey: "hiddenTiles") ?? []).compactMap(TileKind.init(rawValue:)))
    }

    func setTheme(_ mode: ThemeMode) {
        themeMode = mode
        palette = Theme.palette(mode)
        UserDefaults.standard.set(mode.rawValue, forKey: "theme")
    }

    /// Call when the macOS appearance changes so "follow macOS" re-resolves.
    func appearanceDidChange() {
        palette = Theme.palette(themeMode)
    }

    // MARK: Tiles

    func hasData(_ kind: TileKind) -> Bool {
        switch kind {
        case .spotify: spotify != nil
        case .weather: weather != nil
        case .calendar: nextEvent != nil
        case .timer: true
        }
    }

    /// Tiles in order, minus hidden ones and ones without data (a tile without its permission is hidden, not greyed).
    var visibleTiles: [TileKind] { order.filter { !hidden.contains($0) && hasData($0) } }

    func hide(_ kind: TileKind) { hidden.insert(kind); saveTiles() }
    func show(_ kind: TileKind) { hidden.remove(kind); saveTiles() }

    /// Moves `kind` to sit where `target` is now (before it when moving left, after it when moving right).
    /// Not persisted until `commitOrder()`, so a drag does not write defaults on every swap.
    func move(_ kind: TileKind, to target: TileKind) {
        guard kind != target, let from = order.firstIndex(of: kind), let to = order.firstIndex(of: target) else { return }
        order.remove(at: from)
        order.insert(kind, at: to)
    }

    func commitOrder() { saveTiles() }

    private func saveTiles() {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: "tileOrder")
        UserDefaults.standard.set(hidden.map(\.rawValue).sorted(), forKey: "hiddenTiles")
    }

    // MARK: Geometry

    var pillWidth: CGFloat { notchSize.width + 2 * Self.lobeWidth }

    static let rowHeight: CGFloat = 28
    static let cardHeight: CGFloat = 111

    /// The session whose card takes over the island: needs you, or a Done not yet seen.
    var cardSession: ClaudeSession? {
        if let card = claude.frontCard, let s = claude.session(card.sessionID) { return s }
        guard let s = claude.mostUrgent else { return nil }
        return s.needsYou != nil || s.unseenDone ? s : nil
    }

    static let longCommandBox: CGFloat = 128
    static let replyRow: CGFloat = 40

    /// A command that needs the scrolling box: more than 2 lines or longer than one line of the card.
    static func isLong(_ command: String) -> Bool {
        command.filter { $0 == "\n" }.count >= 2 || command.count > 110
    }

    var cardHeight: CGFloat {
        if let card = claude.frontCard, Self.isLong(card.command) { return Self.cardHeight + Self.longCommandBox }
        if claude.frontCard == nil, let s = cardSession, case .done = s.state { return Self.cardHeight + (s.lastMessage != nil ? Self.longCommandBox : 0) + Self.replyRow }
        return Self.cardHeight
    }

    var expandedHeight: CGFloat {
        if cardSession != nil { return notchSize.height + 18 + cardHeight + 18 }
        let rows = claude.sessions.count
        let replyLine: CGFloat = replyingTo != nil && claude.sessions.contains(where: { $0.id == replyingTo }) ? Self.replyRow : 0
        let strip: CGFloat = rows > 0 ? CGFloat(rows) * Self.rowHeight + replyLine + 8 : 0
        let tiles: CGFloat = visibleTiles.isEmpty ? 0 : 94 + 18
        return notchSize.height + 18 + strip + tiles + (visibleTiles.isEmpty ? 10 : 0)
    }

    /// What the pill shows: the demo's content, else the most urgent Claude session plus a count of the others.
    var compactContent: CompactContent? {
        if let compact { return compact }
        guard let s = claude.mostUrgent else { return nil }
        let others = claude.sessions.filter { $0.id != s.id && $0.urgency > 0 }.count
        let count = others > 0 ? "\(others)" : nil
        switch s.state {
        case .needsYou: return CompactContent(kind: .needsYou, word: "Needs you", detail: s.label, count: count)
        case .done(let seconds, let files):
            let detail = files > 0 ? "\(files) file\(files == 1 ? "" : "s")" : s.label
            return CompactContent(kind: .done, word: s.endsWithQuestion ? "Waiting for you" : "Done · \(durationText(seconds))", detail: detail, count: count)
        case .working(let step), .running(_, let step):
            return CompactContent(kind: .working, word: step.word, detail: s.label, count: count)
        default: return nil
        }
    }

    var peekHeight: CGFloat { notchSize.height + (peek?.second == nil ? 24 : 40) }

    /// Size of the panel for a mode, including the ears on black shapes.
    func contentSize(for mode: Mode) -> CGSize {
        switch mode {
        case .resting: notchSize
        case .compact: CGSize(width: pillWidth + 2 * Self.ear, height: notchSize.height)
        case .peek: CGSize(width: notchSize.width, height: peekHeight)
        case .expanded: CGSize(width: Self.expandedWidth, height: expandedHeight)
        }
    }

    var blackParams: BlackParams {
        switch mode {
        case .resting, .expanded: BlackParams(width: notchSize.width, height: notchSize.height, radius: 7, ear: 0)
        case .compact: BlackParams(width: pillWidth, height: notchSize.height, radius: notchSize.height / 2, ear: Self.ear)
        case .peek: BlackParams(width: notchSize.width, height: peekHeight, radius: 14, ear: 0)
        }
    }
}
