import AppKit
import IOKit.ps

/// Event sources for peeks: app open/quit (ticked apps only), charger connected, battery at 20 % and 10 %.
/// All event-driven; nothing polls.
@MainActor
final class PeekSources: NSObject {
    static let defaultApps = ["com.tinyspeck.slackmacgap", "net.whatsapp.WhatsApp", "com.anthropic.claudefordesktop",
                              "com.google.Chrome", "com.apple.dt.Xcode"]
    private var powerSource: CFRunLoopSource?
    private var lastOnAC: Bool?
    private var lastPercent: Int?
    private let emit: (PeekContent, String) -> Void
    nonisolated(unsafe) private static weak var shared: PeekSources?

    /// `emit(content, key)`: the key makes the same event twice count as one peek.
    init(emit: @escaping (PeekContent, String) -> Void) {
        self.emit = emit
        super.init()
        Self.shared = self
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appQuit(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        readPower(initial: true)
        let source = IOPSNotificationCreateRunLoopSource({ _ in
            Task { @MainActor in PeekSources.shared?.readPower(initial: false) }
        }, nil)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
    }

    static var watchedApps: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "peekApps") ?? defaultApps) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "peekApps") }
    }

    private func app(from note: Notification) -> NSRunningApplication? {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular, let id = app.bundleIdentifier, Self.watchedApps.contains(id) else { return nil }
        return app
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = app(from: note) else { return }
        emit(PeekContent(symbol: nil, icon: app.icon, tint: nil, word: "\(app.localizedName ?? "App") opened", second: nil), "open-\(app.bundleIdentifier ?? "")")
    }

    @objc private func appQuit(_ note: Notification) {
        guard let app = app(from: note) else { return }
        emit(PeekContent(symbol: nil, icon: app.icon, tint: nil, word: "\(app.localizedName ?? "App") quit", second: nil), "quit-\(app.bundleIdentifier ?? "")")
    }

    private func readPower(initial: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let desc = IOPSGetPowerSourceDescription(info, first)?.takeUnretainedValue() as? [String: Any] else { return }
        let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let percent = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
        defer { lastOnAC = onAC; lastPercent = percent }
        guard !initial else { return }
        if onAC, lastOnAC == false {
            emit(PeekContent(symbol: "bolt.fill", icon: nil, tint: .done, word: "Charging", second: nil), "charging")
        }
        if !onAC, let last = lastPercent {
            for level in [20, 10] where percent <= level && last > level {
                emit(PeekContent(symbol: level == 10 ? "battery.0percent" : "battery.25percent", icon: nil,
                                 tint: level == 10 ? .blocked : .needsYou, word: "Battery \(percent)%", second: nil), "battery-\(level)")
            }
        }
    }
}

/// Settings that are just switches.
enum Settings {
    static var sound: Bool {
        get { UserDefaults.standard.bool(forKey: "peekSound") }
        set { UserDefaults.standard.set(newValue, forKey: "peekSound") }
    }
}
