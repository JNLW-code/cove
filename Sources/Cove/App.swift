import AppKit
import os

enum Log {
    static let app = Logger(subsystem: "com.jameswebster.cove", category: "app")
}

/// Menu-bar app with no Dock icon. Owns the status item and the island controller.
@main
@MainActor
final class CoveApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let island = Island()
    private var controller: IslandController?
    private var devCommands: DevCommands?

    static func main() {
        let app = NSApplication.shared
        let delegate = CoveApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = IslandController(island: island)
        self.controller = controller
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusGlyph.image
        item.button?.toolTip = "Cove"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        controller.onOpenMenu = { [weak self] in self?.statusItem?.button?.performClick(nil) }
        devCommands = DevCommands { [weak self] command in self?.handle(command) }
        Log.app.notice("Cove \(Self.version, privacy: .public) launched")
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    // MARK: Menu (rebuilt each time it opens so ticks are current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "Cove \(Self.version)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let theme = NSMenu()
        for (title, mode) in [("Dark", ThemeMode.dark), ("Light", .light), ("Follow macOS", .system)] {
            let entry = NSMenuItem(title: title, action: #selector(pickTheme(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.rawValue
            entry.state = island.themeMode == mode ? .on : .off
            theme.addItem(entry)
        }
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = theme
        menu.addItem(themeItem)

        let tiles = NSMenu()
        for kind in island.order {
            let entry = NSMenuItem(title: kind.title, action: #selector(toggleTile(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = kind.rawValue
            entry.state = island.hidden.contains(kind) ? .off : .on
            tiles.addItem(entry)
        }
        tiles.addItem(.separator())
        let edit = NSMenuItem(title: "Edit Tiles", action: #selector(editTiles), keyEquivalent: "")
        edit.target = self
        edit.state = island.editing ? .on : .off
        tiles.addItem(edit)
        let tilesItem = NSMenuItem(title: "Tiles", action: nil, keyEquivalent: "")
        tilesItem.submenu = tiles
        menu.addItem(tilesItem)

        menu.addItem(.separator())
        let demo = NSMenuItem(title: "Demo", action: #selector(toggleDemo), keyEquivalent: "")
        demo.target = self
        demo.state = island.demo ? .on : .off
        menu.addItem(demo)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Cove", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ThemeMode(rawValue: raw) else { return }
        island.setTheme(mode)
    }

    @objc private func toggleTile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = TileKind(rawValue: raw) else { return }
        if island.hidden.contains(kind) { island.show(kind) } else { island.hide(kind) }
    }

    @objc private func editTiles() {
        guard let controller else { return }
        if island.mode != .expanded {
            controller.show(.expanded, animation: IslandController.openAnimation, settle: 0.55)
        }
        controller.toggleEdit()
    }

    @objc private func toggleDemo() {
        controller?.toggleDemo()
    }

    // MARK: Dev commands (notifyutil -p com.jameswebster.cove.<name>)

    private func handle(_ command: String) {
        guard let controller else { return }
        switch command {
        case "theme.dark": island.setTheme(.dark)
        case "theme.light": island.setTheme(.light)
        case "theme.system": island.setTheme(.system)
        case "demo.toggle": controller.toggleDemo()
        case "demo.next": controller.nextDemoStep()
        // show.* put the island in a held demo state (sample data, hover off); show.resting ends it.
        case "show.resting": controller.stopDemo()
        case "show.compact": controller.holdDemo(); controller.closeIfExpanded(); controller.setCompact(Demo.working)
        case "show.peek": controller.holdDemo(); controller.closeIfExpanded(); controller.showPeek(Demo.dnd)
        case "show.expanded": controller.holdDemo(); Demo.fill(island); controller.show(.expanded, animation: IslandController.openAnimation, settle: 0.55)
        case "edit.toggle": controller.toggleEdit()
        case "pin.toggle": controller.togglePin()
        default: break
        }
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
