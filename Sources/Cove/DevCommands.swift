import Foundation
import notify

/// Tiny control channel for testing, driven by `notifyutil -p com.jameswebster.cove.<command>`.
/// Nothing here approves anything; it only changes what the island shows.
@MainActor
final class DevCommands {
    static let names = ["theme.dark", "theme.light", "theme.system", "theme.glass", "demo.toggle", "demo.next",
                        "show.resting", "show.compact", "show.peek", "show.expanded", "open", "close", "edit.toggle", "pin.toggle", "menu.open", "calendar.request",
                        "launchpad.toggle", "launchpad.next", "launchpad.type", "launchpad.categories", "launchpad.folder", "launchpad.demo", "update.check", "setup.open",
                        "panel.toggle", "panel.next", "panel.demo"]
    private var tokens: [Int32] = []

    /// Only when launched with COVE_UI_TEST=1 (never by `make run` or the installed app): answer the front card.
    static let testOnly = ["test.allow", "test.deny", "test.reply", "test.answerq", "test.seen", "test.note", "test.record", "test.update", "test.setup"]

    init(handler: @escaping @MainActor @Sendable (String) -> Void) {
        let names = ProcessInfo.processInfo.environment["COVE_UI_TEST"] == "1" ? Self.names + Self.testOnly : Self.names
        for name in names {
            var token: Int32 = 0
            notify_register_dispatch("com.jameswebster.cove.\(name)", &token, DispatchQueue.main) { _ in
                MainActor.assumeIsolated { handler(name) }
            }
            tokens.append(token)
        }
    }
}
