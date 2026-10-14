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
        var composer: AXUIElement?
        for _ in 0..<3 {                      // the page tree can take a moment to appear
            try? await Task.sleep(for: .milliseconds(400))
            composer = findComposer(in: appElement) ?? composerAtBottom(of: appElement)
            if composer != nil { break }
        }
        var typed = false
        if let composer {
            AXUIElementSetAttributeValue(composer, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            try? await Task.sleep(for: .milliseconds(150))
            // Prefer setting the value straight in; fall back to pasting if the box refuses.
            typed = AXUIElementSetAttributeValue(composer, kAXValueAttribute as CFString, text as CFTypeRef) == .success
            if typed {
                try? await Task.sleep(for: .milliseconds(150))
                var value: AnyObject?
                AXUIElementCopyAttributeValue(composer, kAXValueAttribute as CFString, &value)
                typed = (value as? String)?.contains(text.prefix(20)) == true
            }
        } else {
            // No text box exposed: click where the message box sits (bottom centre of the window) to focus it.
            guard let window = focusedWindowFrame(of: appElement) else {
                Log.app.error("Typist: no window; roles seen: \(roleSummary(in: appElement), privacy: .public)")
                return "Could not find the Claude window."
            }
            let point = CGPoint(x: window.midX, y: window.maxY - 70)
            click(at: point)
            try? await Task.sleep(for: .milliseconds(250))
            Log.app.notice("Typist: clicked the message box area; roles seen: \(roleSummary(in: appElement), privacy: .public)")
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
        Log.app.notice("Typist: composer \(composer.map(describe) ?? "clicked", privacy: .public), via \(typed ? "AXValue" : "paste", privacy: .public)")
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
                guard role == "AXTextArea" || role == "AXTextField" || role == "AXComboBox" || role == "AXWebArea" && false else { return }
                guard let frame = frame(of: element), frame.width > 100 else { return }
                if best == nil || frame.minY > best!.1 { best = (element, frame.minY) }
            }
            if best != nil { break }
        }
        return best?.0
    }

    /// The element under the bottom-centre of the window, climbed up to a text box if there is one.
    private static func composerAtBottom(of app: AXUIElement) -> AXUIElement? {
        guard let window = focusedWindowFrame(of: app) else { return nil }
        var hit: AXUIElement?
        let point = CGPoint(x: window.midX, y: window.maxY - 70)
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, var element = hit else { return nil }
        for _ in 0..<8 {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? ""
            if role == "AXTextArea" || role == "AXTextField" || role == "AXComboBox" { return element }
            var parent: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success, let p = parent else { break }
            element = p as! AXUIElement
        }
        return nil
    }

    private static func focusedWindowFrame(of app: AXUIElement) -> CGRect? {
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let window = windowValue else { return nil }
        return frame(of: window as! AXUIElement)
    }

    private static func click(at point: CGPoint) {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// For the log when the box is not found: which roles the app exposes (never any text).
    private static func roleSummary(in app: AXUIElement) -> String {
        var counts: [String: Int] = [:]
        var windowValue: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue)
        guard let window = windowValue else { return "no focused window" }
        walk(window as! AXUIElement, depth: 0) { _, role in counts[role, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(14).map { "\($0.key)×\($0.value)" }.joined(separator: " ")
    }

    private static func walk(_ element: AXUIElement, depth: Int, visit: (AXUIElement, String) -> Void) {
        guard depth < 60 else { return }
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        visit(element, roleValue as? String ?? "")
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let kids = children as? [AXUIElement] else { return }
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
