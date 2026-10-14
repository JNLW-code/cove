import AppKit
import ApplicationServices

/// Delivers a reply when Claude's hook is no longer waiting: opens the exact session in the Claude app,
/// finds its message box through Accessibility, puts the text in and presses Return.
/// Needs the Accessibility permission (asked on first use).
@MainActor
enum Typist {
    static let claudeBundle = "com.anthropic.claudefordesktop"
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
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundle).first,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundle else {
            return "The Claude app did not come forward; the reply was not typed."
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Electron apps only expose their page to Accessibility once asked to.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        try? await Task.sleep(for: .milliseconds(300))
        guard let composer = findComposer(in: appElement) else {
            return "Could not find the message box in the Claude app."
        }
        AXUIElementSetAttributeValue(composer, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(for: .milliseconds(150))
        // Prefer setting the value straight in; fall back to pasting if the box refuses.
        var typed = AXUIElementSetAttributeValue(composer, kAXValueAttribute as CFString, text as CFTypeRef) == .success
        if typed {
            try? await Task.sleep(for: .milliseconds(150))
            var value: AnyObject?
            AXUIElementCopyAttributeValue(composer, kAXValueAttribute as CFString, &value)
            typed = (value as? String)?.contains(text.prefix(20)) == true
        }
        if !typed {
            let pasteboard = NSPasteboard.general
            let saved = pasteboard.string(forType: .string)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            press(keyCode: 9, flags: .maskCommand)   // ⌘V
            try? await Task.sleep(for: .milliseconds(300))
            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
        }
        press(keyCode: 36, flags: [])                // Return sends
        Log.app.notice("Typist: composer \(describe(composer), privacy: .public), via \(typed ? "AXValue" : "paste", privacy: .public)")
        return nil
    }

    /// The message box: the lowest text area or text field in the app's front window.
    private static func findComposer(in app: AXUIElement) -> AXUIElement? {
        var windowValue: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue)
        var windows: [AXUIElement] = []
        if let w = windowValue { windows.append(w as! AXUIElement) }
        var all: AnyObject?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &all) == .success, let list = all as? [AXUIElement] {
            windows.append(contentsOf: list.filter { !windows.contains($0) })
        }
        var best: (AXUIElement, CGFloat)?
        for window in windows.prefix(3) {
            walk(window, depth: 0) { element, role in
                guard role == "AXTextArea" || role == "AXTextField" || role == "AXComboBox" else { return }
                guard let frame = frame(of: element), frame.width > 100 else { return }
                if best == nil || frame.minY > best!.1 { best = (element, frame.minY) }
            }
            if best != nil { break }
        }
        return best?.0
    }

    private static func walk(_ element: AXUIElement, depth: Int, visit: (AXUIElement, String) -> Void) {
        guard depth < 30 else { return }
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        visit(element, roleValue as? String ?? "")
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let kids = children as? [AXUIElement], kids.count < 400 else { return }
        for kid in kids { walk(kid, depth: depth + 1, visit: visit) }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?, sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private static func describe(_ element: AXUIElement) -> String {
        var role: AnyObject?, placeholder: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, "AXPlaceholderValue" as CFString, &placeholder)
        return "\(role as? String ?? "?") '\(placeholder as? String ?? "")'"
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
