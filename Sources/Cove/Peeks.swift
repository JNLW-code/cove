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
    /// Top-left hot corner opens the Launchpad.
    static var hotCorner: Bool {
        get { UserDefaults.standard.bool(forKey: "launchpadHotCorner") }
        set { UserDefaults.standard.set(newValue, forKey: "launchpadHotCorner") }
    }
}

/// Do Not Disturb and other Focus modes, read from macOS's own Focus database. There is no public API for this
/// without a paid team (INFocusStatusCenter needs an entitlement), so Cove watches the folder, which needs Full Disk Access.
/// Event-driven: a file-system watch, no polling. Without the permission the watcher simply stays off.
@MainActor
final class FocusWatcher {
    private static let realDB = NSHomeDirectory() + "/Library/DoNotDisturb/DB"
    /// Test builds (COVE_UI_TEST=1) may point at a scratch folder holding fake files.
    static var db: String {
        let env = ProcessInfo.processInfo.environment
        if env["COVE_UI_TEST"] == "1", let dir = env["COVE_FOCUS_DB"], !dir.isEmpty { return dir }
        return realDB
    }
    private static let fallbackNames = [
        "com.apple.donotdisturb.mode.default": "Do Not Disturb", "com.apple.sleep.sleep-mode": "Sleep",
        "com.apple.focus.work": "Work", "com.apple.focus.personal": "Personal", "com.apple.focus.driving": "Driving",
        "com.apple.focus.fitness": "Fitness", "com.apple.focus.gaming": "Gaming", "com.apple.focus.mindfulness": "Mindfulness",
        "com.apple.focus.reading": "Reading",
    ]

    /// Full Disk Access as seen from here: can the Assertions file be opened?
    static var access: Permissions.State {
        let fd = open(db + "/Assertions.json", O_RDONLY)
        if fd >= 0 { close(fd); return .granted }
        return errno == ENOENT ? .unavailable : .denied
    }

    private let emit: (PeekContent, String) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var settle: Task<Void, Never>?
    private var hasRead = false
    private var lastMode: String?
    private(set) var running = false

    init(emit: @escaping (PeekContent, String) -> Void) { self.emit = emit }

    /// Starts watching if Full Disk Access allows it. Safe to call again, e.g. after James grants it in System Settings.
    func startIfPossible() {
        guard !running else { return }
        guard Self.access == .granted else {
            if !hasRead { Log.app.notice("Focus watch off: no Full Disk Access"); hasRead = true }
            return
        }
        let fd = open(Self.db, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .attrib], queue: .main)
        s.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
        running = true
        lastMode = Self.activeMode()
        hasRead = true
        Log.app.notice("Focus watch on")
    }

    /// macOS rewrites the files in a burst; read once they settle.
    private func changed() {
        settle?.cancel()
        settle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            let now = Self.activeMode()
            let before = self.lastMode
            guard before != now else { return }
            self.lastMode = now
            if let now {
                self.emit(PeekContent(symbol: "moon.fill", icon: nil, tint: .focus, word: Self.name(of: now), second: nil), "focus.on")
            } else if let before {
                self.emit(PeekContent(symbol: "moon", icon: nil, tint: .focus, word: "\(Self.name(of: before)) off", second: nil), "focus.off")
            }
        }
    }

    /// The mode identifier of the first active assertion, or nil when no Focus is on.
    private static func activeMode() -> String? {
        guard let data = FileManager.default.contents(atPath: db + "/Assertions.json"),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let records = (json["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]] else { return nil }
        for record in records {
            if let details = record["assertionDetails"] as? [String: Any],
               let mode = details["assertionDetailsModeIdentifier"] as? String, !mode.isEmpty { return mode }
        }
        return nil
    }

    /// The mode's name as James named it in System Settings, else a sensible default.
    private static func name(of mode: String) -> String {
        if let data = FileManager.default.contents(atPath: db + "/ModeConfigurations.json"),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let configs = (json["data"] as? [[String: Any]])?.first?["modeConfigurations"] as? [String: Any],
           let entry = configs[mode] as? [String: Any], let m = entry["mode"] as? [String: Any],
           let n = m["name"] as? String, !n.isEmpty { return n }
        return fallbackNames[mode] ?? "Focus"
    }
}
