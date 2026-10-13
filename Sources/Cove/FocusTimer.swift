import Foundation

/// A 25-minute focus timer. Ticks once a second only while running.
@MainActor
@Observable
final class FocusTimer {
    static let length = 25 * 60

    private(set) var remaining = FocusTimer.length
    private(set) var running = false
    private var ticker: Task<Void, Never>?

    var text: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }
    var isAtStart: Bool { remaining == Self.length && !running }

    func toggle() { running ? pause() : start() }

    func start() {
        guard remaining > 0, !running else { return }
        running = true
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                self.remaining -= 1
                if self.remaining <= 0 {
                    self.remaining = 0
                    self.pause()
                }
            }
        }
    }

    func pause() {
        running = false
        ticker?.cancel()
        ticker = nil
    }

    func reset() {
        pause()
        remaining = Self.length
    }
}
