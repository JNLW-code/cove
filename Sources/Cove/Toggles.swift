import AppKit
import CoreWLAN
import Foundation

/// The Launchpad's quick toggles: Wi-Fi (CoreWLAN, public), dark mode (System Events through AppleScript,
/// Automation permission on first use), mute and volume (CoreAudio through `VolumeControl`).
/// Bluetooth has no public API and is left out; brightness lives in `Brightness.swift`.
@MainActor
@Observable
final class QuickToggles {
    private(set) var wifiOn = false
    private(set) var wifiAvailable = false
    private(set) var darkMode = false

    /// Read the current states (called when the Launchpad opens; nothing is polled).
    func refresh() {
        if let interface = CWWiFiClient.shared().interface() {
            wifiAvailable = true
            wifiOn = interface.powerOn()
        } else {
            wifiAvailable = false
        }
        let style = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String
        darkMode = style?.lowercased() == "dark"
    }

    func toggleWifi() {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        do {
            try interface.setPower(!wifiOn)
            wifiOn = interface.powerOn()
        } catch {
            Log.app.error("Wi-Fi toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Flips macOS between light and dark. System Events does the switch, so macOS asks once to let Cove control it.
    func toggleDarkMode() {
        var error: NSDictionary?
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.app.error("Dark mode toggle failed: \(String(describing: error[NSAppleScript.errorBriefMessage] ?? ""), privacy: .public)")
            return   // nothing changed, so the button keeps its state
        }
        darkMode.toggle()
    }
}
