import AppKit

/// The last few real apps you used, newest first. Updated from NSWorkspace activation events, never polled.
@MainActor
@Observable
final class RecentApps: NSObject {
    struct Entry: Identifiable, Equatable {
        let id: pid_t
        let name: String
        let url: URL
        let icon: NSImage
    }

    static let limit = 5
    private(set) var apps: [Entry] = []

    override init() {
        super.init()
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != NSRunningApplication.current }
        apps = running.prefix(Self.limit).compactMap(Entry.init)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(activated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(terminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    @objc private func activated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular, app != NSRunningApplication.current,
              let entry = Entry(app) else { return }
        apps.removeAll { $0.id == entry.id }
        apps.insert(entry, at: 0)
        if apps.count > Self.limit { apps.removeLast(apps.count - Self.limit) }
    }

    @objc private func terminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        apps.removeAll { $0.id == app.processIdentifier }
    }

    func open(_ entry: Entry) {
        NSWorkspace.shared.openApplication(at: entry.url, configuration: NSWorkspace.OpenConfiguration())
    }
}

extension RecentApps.Entry {
    init?(_ app: NSRunningApplication) {
        guard let url = app.bundleURL, let name = app.localizedName, let icon = app.icon else { return nil }
        self.init(id: app.processIdentifier, name: name, url: url, icon: icon)
    }
}
