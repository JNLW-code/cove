import AppKit
import EventKit

/// Permission state for the Settings menu: a tick when granted, one line on why when not. Never prompts here.
@MainActor
enum Permissions {
    enum State { case granted, notAsked, denied, unavailable }

    /// Automation (Apple Events) for Spotify, checked without prompting.
    static func automation(for bundleID: String) -> State {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return .unavailable }
        var target = AEAddressDesc()
        var pid = app.processIdentifier
        guard AECreateDesc(typeKernelProcessID, &pid, MemoryLayout<pid_t>.size, &target) == noErr else { return .unavailable }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unavailable
        }
    }

    static var calendar: State {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .unavailable
        }
    }
}
