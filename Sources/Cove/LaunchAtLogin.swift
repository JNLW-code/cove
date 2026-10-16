import AppKit
import ServiceManagement

/// Launch at login through SMAppService. Only meaningful for the copy in ~/Applications (`make install`).
@MainActor
enum LaunchAtLogin {
    /// Either Applications folder counts; build/ and the DMG do not (macOS would register a path that goes away).
    static var isInstalledCopy: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix(NSHomeDirectory() + "/Applications/") || path.hasPrefix("/Applications/")
    }

    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: "On"
        case .requiresApproval: "Waiting for your approval in Login Items"
        case .notFound: "Off"
        case .notRegistered: "Off"
        @unknown default: "Off"
        }
    }

    /// Returns a one-line message when something needs you.
    static func toggle() -> String? {
        guard isInstalledCopy else { return "Move Cove to your Applications folder first; launch at login only works from there." }
        do {
            if isOn {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    return "macOS wants you to approve Cove in Login Items."
                }
            }
        } catch {
            return "Could not change launch at login: \(error.localizedDescription)"
        }
        return nil
    }
}
