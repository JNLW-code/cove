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

/// The Launchpad's widget row, each one switchable in the menu.
enum LaunchpadWidget: String, CaseIterable, Sendable {
    case nowPlaying, weather, toggles, sound, keyboard, display

    var title: String {
        switch self {
        case .nowPlaying: "Now playing"
        case .weather: "Weather"
        case .toggles: "Quick toggles"
        case .sound: "Sound"
        case .keyboard: "Keyboard brightness"
        case .display: "Display brightness"
        }
    }

    var width: CGFloat {
        switch self {
        case .nowPlaying: 262
        case .weather: 172
        case .toggles: 190
        case .sound, .keyboard, .display: 160
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
    enum Mode: Equatable { case resting, compact, peek, expanded, launchpad }

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
    /// Width of the screen the notch is on; the Launchpad takes 85 % of it, at most 1230.
    var screenWidth: CGFloat = 1470

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
    let apps = AppCatalog()
    let musicModel = MusicModel()
    let toggles = QuickToggles()
    let brightness = Brightness()
    var music: SpotifyTrack?
    private(set) var hiddenWidgets: Set<LaunchpadWidget>
    /// What is typed in the Launchpad's search field, and which page of the grid is showing.
    var launchpadQuery = ""
    var launchpadPage = 0
    /// "By category": the grid shows folders; `launchpadFolder` is the one opened.
    var launchpadCategories = UserDefaults.standard.bool(forKey: "launchpadCategories") {
        didSet { UserDefaults.standard.set(launchpadCategories, forKey: "launchpadCategories") }
    }
    var launchpadFolder: AppCategory?
    /// Feedback under the reply box ("Sent", or why it could not be delivered).
    var replyStatus: String?
    /// The session whose row has its reply line open.
    var replyingTo: String?
    /// The session whose note line is open under its row.
    var notingFor: String?
    var hotKeyAllow = HotKeys.defaultAllow.display
    var hotKeyDeny = HotKeys.defaultDeny.display
    var hotKeyLaunchpad = HotKeys.defaultLaunchpad.display

    init() {
        let defaults = UserDefaults.standard
        let mode = ThemeMode(rawValue: defaults.string(forKey: "theme") ?? "") ?? .dark
        themeMode = mode
        palette = Theme.palette(mode)
        let saved = (defaults.stringArray(forKey: "tileOrder") ?? []).compactMap(TileKind.init(rawValue:))
        order = saved.count == TileKind.allCases.count ? saved : TileKind.allCases
        hidden = Set((defaults.stringArray(forKey: "hiddenTiles") ?? []).compactMap(TileKind.init(rawValue:)))
        hiddenWidgets = Set((defaults.stringArray(forKey: "launchpadHiddenWidgets") ?? []).compactMap(LaunchpadWidget.init(rawValue:)))
    }

    func setWidget(_ widget: LaunchpadWidget, shown: Bool) {
        if shown { hiddenWidgets.remove(widget) } else { hiddenWidgets.insert(widget) }
        UserDefaults.standard.set(hiddenWidgets.map(\.rawValue).sorted(), forKey: "launchpadHiddenWidgets")
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

    /// Which of the sessions needing you the card shows (‹ › move it).
    var cardIndex = 0

    /// The session whose card sits at the top: the chosen one of those needing you.
    var cardSession: ClaudeSession? {
        let queue = claude.attentionQueue
        guard !queue.isEmpty else { return nil }
        return queue[min(cardIndex, queue.count - 1)]
    }

    /// The permission card on screen, if the shown session has one. Allow/Deny and the shortcuts act on this one.
    var displayedCard: PermissionCard? {
        guard let s = cardSession else { return nil }
        return claude.card(for: s)
    }

    /// The question card on screen, if the shown session has one.
    var displayedQuestion: QuestionCard? {
        guard let s = cardSession else { return nil }
        return claude.question(for: s)
    }

    static let questionOption: CGFloat = 32
    /// Title, the question (2 lines), one row per option, a line to type an answer, project · branch.
    static func questionCardHeight(_ card: QuestionCard) -> CGFloat {
        158 + CGFloat(card.questions.map(\.options.count).max() ?? 0) * questionOption
    }

    static let longCommandBox: CGFloat = 128
    /// The "why not?" line under a plan.
    static let feedbackLine: CGFloat = 34
    static let replyRow: CGFloat = 40

    /// A command that needs the scrolling box: more than 2 lines or longer than one line of the card.
    static func isLong(_ command: String) -> Bool {
        command.filter { $0 == "\n" }.count >= 2 || command.count > 110
    }

    var cardHeight: CGFloat {
        if let card = displayedCard {
            return Self.cardHeight + (card.isPlan || Self.isLong(card.command) ? Self.longCommandBox : 0) + (card.isPlan ? Self.feedbackLine : 0)
        }
        if let question = displayedQuestion { return Self.questionCardHeight(question) }
        if let s = cardSession, case .done = s.state { return Self.cardHeight + (s.lastMessage != nil ? Self.longCommandBox : 0) + Self.replyRow }
        return Self.cardHeight
    }

    /// Card on top (when something needs you) and the rows under it; tiles only when nothing needs you.
    var expandedHeight: CGFloat {
        let rows = claude.sessions.count
        let replyLine: CGFloat = replyingTo != nil && claude.sessions.contains(where: { $0.id == replyingTo }) ? Self.replyRow : 0
        let noteLine: CGFloat = notingFor != nil && claude.sessions.contains(where: { $0.id == notingFor }) ? Self.replyRow : 0
        let strip: CGFloat = rows > 0 ? CGFloat(rows) * Self.rowHeight + replyLine + noteLine + 8 : 0
        if cardSession != nil { return notchSize.height + 18 + cardHeight + 8 + strip + 10 }
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
            return CompactContent(kind: .done, word: s.endsWithQuestion ? "Waiting for you" : (seconds > 0 ? "Done · \(durationText(seconds))" : "Done"), detail: detail, count: count)
        case .working(let step), .running(_, let step):
            return CompactContent(kind: .working, word: step.word, detail: s.label, count: count)
        default: return nil
        }
    }

    var peekHeight: CGFloat { notchSize.height + (peek?.second == nil ? 24 : 40) }

    // MARK: Launchpad

    static let launchpadMaxWidth: CGFloat = 1230
    static let launchpadColumns = 8
    static let launchpadRows = 4
    static let launchpadPageSize = launchpadColumns * launchpadRows
    static let launchpadInset: CGFloat = 60
    static let launchpadCell: CGFloat = 84
    static let launchpadSearchHeight: CGFloat = 32
    static let launchpadRadius: CGFloat = 44
    static let widgetHeight: CGFloat = 96
    static let widgetGap: CGFloat = 12

    /// Spotify first, else Apple Music.
    var nowPlaying: SpotifyTrack? { spotify ?? music }
    var nowPlayingIsSpotify: Bool { spotify != nil }

    /// Widgets in the row: not hidden, and with something to show.
    var visibleWidgets: [LaunchpadWidget] {
        LaunchpadWidget.allCases.filter { widget in
            guard !hiddenWidgets.contains(widget) else { return false }
            switch widget {
            case .nowPlaying: return nowPlaying != nil
            case .weather: return weather != nil
            case .toggles: return true
            case .sound: return volume.hasLevel
            case .keyboard: return brightness.keyboardAvailable
            case .display: return brightness.displayAvailable
            }
        }
    }

    /// The row never gets cut at the sides: it scales down when the widgets are wider than the card.
    var widgetScale: CGFloat {
        let widgets = visibleWidgets
        guard !widgets.isEmpty else { return 1 }
        let total = widgets.map(\.width).reduce(0, +) + CGFloat(widgets.count - 1) * Self.widgetGap
        return min(1, (launchpadWidth - 2 * Self.launchpadInset) / total)
    }

    var widgetRowHeight: CGFloat { visibleWidgets.isEmpty ? 0 : (Self.widgetHeight * widgetScale).rounded() + 18 }

    var launchpadWidth: CGFloat { min(Self.launchpadMaxWidth, (screenWidth * 0.85).rounded()) }
    /// Notch band, 12 gap, search, 22 gap, the widget row (if any), four rows, dots, bottom inset.
    var launchpadHeight: CGFloat {
        notchSize.height + 12 + Self.launchpadSearchHeight + 22 + widgetRowHeight
            + CGFloat(Self.launchpadRows) * Self.launchpadCell + 10 + 16 + 18
    }

    /// Folders show when "By category" is on, nothing is typed and no folder is open.
    var launchpadShowsFolders: Bool { launchpadCategories && launchpadQuery.isEmpty && launchpadFolder == nil }

    /// The apps the grid shows: the search matches, the open folder, or all of them.
    var launchpadApps: [AppEntry] {
        if !launchpadQuery.isEmpty { return apps.search(launchpadQuery) }
        if launchpadCategories, let folder = launchpadFolder { return apps.apps(in: folder) }
        return apps.apps
    }
    var launchpadPageCount: Int {
        launchpadShowsFolders ? 1 : max(1, Int((Double(launchpadApps.count) / Double(Self.launchpadPageSize)).rounded(.up)))
    }
    var launchpadPageApps: [AppEntry] {
        let all = launchpadApps
        let start = min(launchpadPage, launchpadPageCount - 1) * Self.launchpadPageSize
        return Array(all[min(start, all.count)..<min(start + Self.launchpadPageSize, all.count)])
    }

    /// Size of the panel for a mode, including the ears on black shapes.
    func contentSize(for mode: Mode) -> CGSize {
        switch mode {
        case .resting: notchSize
        case .compact: CGSize(width: pillWidth + 2 * Self.ear, height: notchSize.height)
        case .peek: CGSize(width: notchSize.width, height: peekHeight)
        case .expanded: CGSize(width: Self.expandedWidth, height: expandedHeight)
        case .launchpad: CGSize(width: launchpadWidth, height: launchpadHeight)
        }
    }

    var blackParams: BlackParams {
        switch mode {
        case .resting, .expanded, .launchpad: BlackParams(width: notchSize.width, height: notchSize.height, radius: 7, ear: 0)
        case .compact: BlackParams(width: pillWidth, height: notchSize.height, radius: notchSize.height / 2, ear: Self.ear)
        case .peek: BlackParams(width: notchSize.width, height: peekHeight, radius: 14, ear: 0)
        }
    }
}
