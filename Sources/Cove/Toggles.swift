import AppKit
import CoreWLAN
import Foundation

/// The Launchpad's quick toggles: Wi-Fi (CoreWLAN, public), dark mode (System Events through AppleScript,
/// Automation permission on first use), mute and volume (CoreAudio through `VolumeControl`).
/// Bluetooth and brightness have no public API on Apple silicon and are left out on purpose.
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

    /// Keyboard backlight up or down. There is no public API for the level, so this presses the keyboard's own
    /// illumination keys (a system-defined event), which needs the Accessibility permission Cove already uses for replies.
    func keyboardBrightness(up: Bool) {
        guard Typist.isTrusted else { Log.app.error("Keyboard brightness needs Accessibility"); return }
        let key = up ? 0x15 : 0x16   // NX_KEYTYPE_ILLUMINATION_UP / DOWN
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let flags = NSEvent.ModifierFlags(rawValue: UInt(state << 8))
            let data1 = (key << 16) | (state << 8)
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                                 windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Flips macOS between light and dark. System Events does the switch, so macOS asks once to let Cove control it.
    func toggleDarkMode() {
        var error: NSDictionary?
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.app.error("Dark mode toggle failed: \(String(describing: error[NSAppleScript.errorBriefMessage] ?? ""), privacy: .public)")
        }
        darkMode.toggle()
    }
}
