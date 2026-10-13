import AppKit
import ApplicationServices

/// Delivers a reply when Claude's hook is no longer waiting: opens the exact session in the Claude app,
/// then pastes the text into its box and presses Return. Needs the Accessibility permission (asked on first use).
@MainActor
enum Typist {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Returns nil on success, else a one-line reason.
    static func deliver(_ text: String, to session: ClaudeSession) async -> String? {
        guard let host = session.hostID, let url = URL(string: "claude://claude.ai/epitaxy/\(host)") else {
            return "Only desktop-app sessions can take typed replies. Use the app for this one."
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return "Allow Cove under System Settings → Privacy & Security → Accessibility, then send again."
        }
        NSWorkspace.shared.open(url)
        try? await Task.sleep(for: .milliseconds(900))
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.anthropic.claudefordesktop" else {
            return "The Claude app did not come forward; the reply was not typed."
        }
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        press(keyCode: 9, flags: .maskCommand)   // ⌘V
        try? await Task.sleep(for: .milliseconds(250))
        press(keyCode: 36, flags: [])            // Return
        try? await Task.sleep(for: .milliseconds(300))
        pasteboard.clearContents()
        if let saved { pasteboard.setString(saved, forType: .string) }
        return nil
    }

    private static func press(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
