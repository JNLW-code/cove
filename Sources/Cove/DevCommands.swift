import Foundation
import notify

/// Tiny control channel for testing, driven by `notifyutil -p com.jameswebster.cove.<command>`.
/// Nothing here approves anything; it only changes what the island shows.
@MainActor
final class DevCommands {
    static let names = ["theme.dark", "theme.light", "theme.system", "demo.toggle", "demo.next",
                        "show.resting", "show.compact", "show.peek", "show.expanded", "edit.toggle", "pin.toggle"]
    private var tokens: [Int32] = []

    init(handler: @escaping @MainActor @Sendable (String) -> Void) {
        for name in Self.names {
            var token: Int32 = 0
            notify_register_dispatch("com.jameswebster.cove.\(name)", &token, DispatchQueue.main) { _ in
                MainActor.assumeIsolated { handler(name) }
            }
            tokens.append(token)
        }
    }
}
