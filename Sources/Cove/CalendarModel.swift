import AppKit
import EventKit
import Foundation

/// Next calendar event from EventKit. Asks for full access the first time the tile is used; hidden until granted.
@MainActor
@Observable
final class CalendarModel: NSObject {
    private let store = EKEventStore()
    private(set) var next: CalendarEvent?
    private var rolloverTask: Task<Void, Never>?
    private var asked = false
    var onChange: (() -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .EKEventStoreChanged, object: store)
        if Permissions.calendar == .granted { load() }
    }

    /// First real use of the tile: ask once, explain why in the system prompt text (Info.plist).
    func requestIfNeeded() {
        let state = Permissions.calendar
        Log.app.notice("Calendar access: \(String(describing: state), privacy: .public), asked before: \(self.asked)")
        guard !asked, state == .notAsked else { return }
        asked = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let granted = try await self.store.requestFullAccessToEvents()
                Log.app.notice("Calendar access answered: \(granted)")
                if granted { self.load() }
            } catch {
                Log.app.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @objc private func storeChanged() { load() }

    func load() {
        guard Permissions.calendar == .granted else { return }
        store.refreshSourcesIfNecessary()
        let names = store.calendars(for: .event).map { "\($0.source?.title ?? "?")/\($0.title)" }
        Log.app.notice("Calendar sources: \(names.joined(separator: ", "), privacy: .public)")
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { ($0.endDate ?? $0.startDate) > start }
            .sorted { $0.startDate < $1.startDate }
        Log.app.notice("Calendar: \(events.count) upcoming events in 7 days")
        if let event = events.first {
            let when = event.isAllDay ? Self.dayFormatter.string(from: event.startDate) + " · All day" : Self.when(event.startDate)
            next = CalendarEvent(title: event.title ?? "Event", when: when,
                                 dayName: Self.dayName(event.startDate), dayNumber: Self.dayNumber(event.startDate),
                                 openURL: Self.openURL(for: event))
            Log.app.notice("Calendar: next event link \(self.next?.openURL?.absoluteString ?? "none", privacy: .public)")
            scheduleRollover(at: event.endDate ?? event.startDate.addingTimeInterval(3600))
        } else {
            next = nil
            scheduleRollover(at: Calendar.current.date(byAdding: .hour, value: 6, to: start) ?? start.addingTimeInterval(21600))
        }
        onChange?()
    }

    /// Google Calendar in the browser (James's choice, 16 Oct). The exact event when it lives in a Google calendar:
    /// Google's event id is base64("<uid without @google.com> <calendar address>"), the address being the Google
    /// calendar's title in macOS ("james@…" for the main one). Otherwise the day view for that date.
    private static func openURL(for event: EKEvent) -> URL? {
        if let uid = event.calendarItemExternalIdentifier, uid.hasSuffix("@google.com"),
           event.calendar.source.title.lowercased().contains("google"), event.calendar.title.contains("@") {
            var id = String(uid.dropLast("@google.com".count))
            if event.hasRecurrenceRules {   // one occurrence: id_<start in UTC>
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
                f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                id += "_" + f.string(from: event.startDate)
            }
            let eid = Data("\(id) \(event.calendar.title)".utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
            return URL(string: "https://calendar.google.com/calendar/event?eid=\(eid)")
        }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: event.startDate)
        return URL(string: "https://calendar.google.com/calendar/r/day/\(parts.year ?? 2026)/\(parts.month ?? 1)/\(parts.day ?? 1)")
    }

    /// Click on the tile: the event (or its day) in Google Calendar, in Google Chrome (James's browser for it);
    /// the default browser only when Chrome is not installed.
    func openNext() {
        guard let url = next?.openURL ?? URL(string: "https://calendar.google.com/") else { return }
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func scheduleRollover(at date: Date) {
        rolloverTask?.cancel()
        let seconds = max(5, date.timeIntervalSinceNow + 1)
        rolloverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds), tolerance: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            self.load()
        }
    }

    private static let whenFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "EEE d MMM · h:mm a"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    static func when(_ date: Date) -> String { whenFormatter.string(from: date) }

    static func dayName(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_AU"); f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    static func dayNumber(_ date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }
}
