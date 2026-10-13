import AppKit
import os

enum Log {
    static let app = Logger(subsystem: "com.jameswebster.cove", category: "app")
}

/// Menu-bar app with no Dock icon. Owns the status item; the island panel comes in step 3.
@main
@MainActor
final class CoveApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    static func main() {
        let app = NSApplication.shared
        let delegate = CoveApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusGlyph.image
        item.button?.toolTip = "Cove"
        item.menu = makeMenu()
        statusItem = item
        Log.app.notice("Cove \(Self.version, privacy: .public) launched")
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Cove \(Self.version)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Cove", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }
}

/// The menu-bar glyph: a small island shape, drawn as a template so it follows the menu bar colour.
enum StatusGlyph {
    @MainActor static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 5.5, width: 16, height: 7), xRadius: 3.5, yRadius: 3.5).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
