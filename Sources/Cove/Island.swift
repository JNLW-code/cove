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
    var edge: Tint?
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
    static let pillWidth: CGFloat = 371
    static let peekWidth: CGFloat = 223
    static let ear: CGFloat = 8

    var mode: Mode = .resting
    var pinned = false
    var editing = false
    var demo = false
    private(set) var themeMode: ThemeMode
    /// Bumped when the macOS appearance changes so "follow macOS" re-renders.
    var appearanceTick = 0
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

    init() {
        let defaults = UserDefaults.standard
        themeMode = ThemeMode(rawValue: defaults.string(forKey: "theme") ?? "") ?? .dark
        let saved = (defaults.stringArray(forKey: "tileOrder") ?? []).compactMap(TileKind.init(rawValue:))
        order = saved.count == TileKind.allCases.count ? saved : TileKind.allCases
        hidden = Set((defaults.stringArray(forKey: "hiddenTiles") ?? []).compactMap(TileKind.init(rawValue:)))
    }

    var palette: Palette {
        _ = appearanceTick
        return Theme.palette(themeMode)
    }

    func setTheme(_ mode: ThemeMode) {
        themeMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "theme")
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
    func move(_ kind: TileKind, to target: TileKind) {
        guard kind != target, let from = order.firstIndex(of: kind), let to = order.firstIndex(of: target) else { return }
        order.remove(at: from)
        order.insert(kind, at: to)
        saveTiles()
    }

    private func saveTiles() {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: "tileOrder")
        UserDefaults.standard.set(hidden.map(\.rawValue).sorted(), forKey: "hiddenTiles")
    }

    // MARK: Geometry

    var expandedHeight: CGFloat { notchSize.height + 18 + 94 + 18 }

    var peekHeight: CGFloat { notchSize.height + (peek?.second == nil ? 24 : 40) }

    /// Size of the panel for a mode, including the ears on black shapes.
    func contentSize(for mode: Mode) -> CGSize {
        switch mode {
        case .resting: notchSize
        case .compact: CGSize(width: Self.pillWidth + 2 * Self.ear, height: notchSize.height)
        case .peek: CGSize(width: Self.peekWidth + 2 * Self.ear, height: peekHeight)
        case .expanded: CGSize(width: Self.expandedWidth, height: expandedHeight)
        }
    }

    var blackParams: BlackParams {
        switch mode {
        case .resting, .expanded: BlackParams(width: notchSize.width, height: notchSize.height, radius: 7, ear: 0)
        case .compact: BlackParams(width: Self.pillWidth, height: notchSize.height, radius: notchSize.height / 2, ear: Self.ear)
        case .peek: BlackParams(width: Self.peekWidth, height: peekHeight, radius: 18, ear: Self.ear)
        }
    }
}
