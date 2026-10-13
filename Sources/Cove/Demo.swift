import AppKit

/// Sample content for the Demo menu item. Only ever shown while Demo is on.
@MainActor
enum Demo {
    static let track = SpotifyTrack(title: "Low Tide", artist: "Nova Lane", artwork: nil, progress: 0.38, playing: true)
    static let weather = WeatherNow(temperature: 19, high: 22, low: 14, symbol: "cloud.rain.fill", city: "Sydney")
    static let event = CalendarEvent(title: "Design review", when: "Wed 14 Oct · 9:30 am", dayName: "TUE", dayNumber: "13")

    static let working = CompactContent(kind: .working, word: "Editing", detail: "quoteflow-v3", count: "2")
    static let needsYou = CompactContent(kind: .needsYou, word: "Needs you", detail: "quoteflow-v3", count: "1 of 3")
    static let done = CompactContent(kind: .done, word: "Done · 10 s", detail: "2 files", count: "2")

    static func appIcon(_ name: String) -> NSImage? {
        let path = "/Applications/\(name).app"
        return FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
    }

    static let dnd = PeekContent(symbol: "moon.fill", icon: nil, tint: .focus, word: "Do Not Disturb", second: nil, edge: nil)
    static var slack: PeekContent {
        PeekContent(symbol: "app.fill", icon: appIcon("Slack"), tint: nil, word: "Slack opened", second: nil, edge: nil)
    }
    static let charging = PeekContent(symbol: "bolt.fill", icon: nil, tint: .done, word: "Charging", second: nil, edge: .done)
    static let blocked = PeekContent(symbol: "exclamationmark.triangle", icon: nil, tint: .blocked,
                                     word: "Blocked · quoteflow-v3", second: "rm -rf .next", edge: .blocked)

    static func fill(_ island: Island) {
        island.spotify = track
        island.weather = weather
        island.nextEvent = event
    }

    static func clear(_ island: Island) {
        island.spotify = nil
        island.weather = nil
        island.nextEvent = nil
    }

    /// One step every 2.6 s: compact states, peeks, then the open island and edit mode.
    static let steps: [(IslandController) -> Void] = [
        { c in c.island.editing = false; c.island.peek = nil; c.setCompact(working) },
        { c in c.setCompact(needsYou) },
        { c in c.setCompact(done) },
        { c in c.setCompact(nil); c.showPeek(dnd, seconds: 2.4) },
        { c in c.showPeek(slack, seconds: 2.4) },
        { c in c.showPeek(charging, seconds: 2.4) },
        { c in c.showPeek(blocked, seconds: 2.4) },
        { c in fill(c.island); c.show(.expanded, animation: IslandController.openAnimation, settle: 0.55) },
        { c in c.island.editing = true },
        { c in c.island.editing = false; c.show(.resting, animation: IslandController.closeAnimation) },
    ]
}
