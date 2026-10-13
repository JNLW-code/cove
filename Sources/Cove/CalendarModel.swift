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
        guard !asked, Permissions.calendar == .notAsked else { return }
        asked = true
        Task { [weak self] in
            guard let self else { return }
            let granted = (try? await self.store.requestFullAccessToEvents()) ?? false
            if granted { self.load() }
        }
    }

    @objc private func storeChanged() { load() }

    func load() {
        guard Permissions.calendar == .granted else { return }
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && ($0.endDate ?? $0.startDate) > start }
            .sorted { $0.startDate < $1.startDate }
        if let event = events.first {
            next = CalendarEvent(title: event.title ?? "Event", when: Self.when(event.startDate),
                                 dayName: Self.dayName(event.startDate), dayNumber: Self.dayNumber(event.startDate))
            scheduleRollover(at: event.endDate ?? event.startDate.addingTimeInterval(3600))
        } else {
            next = nil
            scheduleRollover(at: Calendar.current.date(byAdding: .hour, value: 6, to: start) ?? start.addingTimeInterval(21600))
        }
        onChange?()
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

    static func when(_ date: Date) -> String { whenFormatter.string(from: date) }

    static func dayName(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_AU"); f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    static func dayNumber(_ date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }
}
