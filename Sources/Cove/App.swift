import AppKit
import os

enum Log {
    static let app = Logger(subsystem: "com.jameswebster.cove", category: "app")
}

/// Menu-bar app with no Dock icon. Owns the status item, the menu and the island controller.
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

    private func item(_ title: String, _ action: Selector?, _ object: Any? = nil, on: Bool? = nil, enabled: Bool = true) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.representedObject = object
        if let on { entry.state = on ? .on : .off }
        entry.isEnabled = enabled
        return entry
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        return entry
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(item("Cove \(Self.version)", nil, enabled: false))
        menu.addItem(.separator())

        menu.addItem(submenu("Theme", [("Dark", ThemeMode.dark), ("Light", .light), ("Follow macOS", .system)].map {
            item($0.0, #selector(pickTheme(_:)), $0.1.rawValue, on: island.themeMode == $0.1)
        }))

        var tiles = island.order.map { kind in item(kind.title, #selector(toggleTile(_:)), kind.rawValue, on: !island.hidden.contains(kind)) }
        tiles.append(.separator())
        tiles.append(item("Edit Tiles…", #selector(editTiles), on: island.editing))
        menu.addItem(submenu("Tiles", tiles))
        menu.addItem(item("Weather City… (\(island.weatherModel.city))", #selector(changeCity)))

        var peeks = peekAppItems()
        peeks.append(.separator())
        peeks.append(item("Sound", #selector(toggleSound), on: Settings.sound))
        menu.addItem(submenu("Peeks", peeks))

        let combos: [(String, HotKeys.Combo, HotKeys.Combo)] = [
            ("⌃⌥Y / ⌃⌥N", HotKeys.defaultAllow, HotKeys.defaultDeny),
            ("⌃⌘Y / ⌃⌘N", .init(keyCode: 16, modifiers: HotKeys.ctrlCmd), .init(keyCode: 45, modifiers: HotKeys.ctrlCmd)),
            ("⌃⌥A / ⌃⌥D", .init(keyCode: 0, modifiers: HotKeys.ctrlOpt), .init(keyCode: 2, modifiers: HotKeys.ctrlOpt)),
            ("⌃⇧A / ⌃⇧D", .init(keyCode: 0, modifiers: HotKeys.ctrlShift), .init(keyCode: 2, modifiers: HotKeys.ctrlShift)),
        ]
        let current = island.hotKeyAllow + " / " + island.hotKeyDeny
        menu.addItem(submenu("Allow / Deny Shortcuts", combos.map { item($0.0, #selector(pickShortcut(_:)), $0.0, on: $0.0 == current) }))

        menu.addItem(.separator())
        menu.addItem(submenu("Permissions", permissionItems()))
        let login = item("Launch at Login", #selector(toggleLogin), on: LaunchAtLogin.isOn, enabled: LaunchAtLogin.isInstalledCopy)
        if !LaunchAtLogin.isInstalledCopy { login.toolTip = "Run make install first" }
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Demo", #selector(toggleDemo), on: island.demo))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Cove", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// The default five apps plus whatever real apps are running now, each with a tick.
    private func peekAppItems() -> [NSMenuItem] {
        var apps: [(String, String)] = [("Slack", "com.tinyspeck.slackmacgap"), ("WhatsApp", "net.whatsapp.WhatsApp"),
                                        ("Claude", "com.anthropic.claudefordesktop"), ("Google Chrome", "com.google.Chrome"),
                                        ("Xcode", "com.apple.dt.Xcode")]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier, let name = app.localizedName, !apps.contains(where: { $0.1 == id }), id != Bundle.main.bundleIdentifier {
                apps.append((name, id))
            }
        }
        let watched = PeekSources.watchedApps
        return apps.map { item($0.0, #selector(togglePeekApp(_:)), $0.1, on: watched.contains($0.1)) }
    }

    private func permissionItems() -> [NSMenuItem] {
        func line(_ name: String, _ state: Permissions.State, why: String) -> NSMenuItem {
            switch state {
            case .granted: return item("✓ \(name)", nil, enabled: false)
            case .notAsked: return item("\(name): not asked yet. \(why)", nil, enabled: false)
            case .denied: return item("\(name): turned off in System Settings. \(why)", nil, enabled: false)
            case .unavailable: return item("\(name): app not running. \(why)", nil, enabled: false)
            }
        }
        return [
            line("Spotify (Automation)", Permissions.automation(for: SpotifyModel.bundleID), why: "Needed for play, pause, next and artwork."),
            line("Calendar", Permissions.calendar, why: "Needed to show your next event."),
            item("Launch at Login: \(LaunchAtLogin.statusText)", nil, enabled: false),
        ]
    }

    // MARK: Actions

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

    @objc private func changeCity() {
        let alert = NSAlert()
        alert.messageText = "Weather city"
        alert.informativeText = "Type a city name. Open-Meteo looks it up; no account or key is needed."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = island.weatherModel.city
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            island.weatherModel.setCity(field.stringValue)
        }
        giveFocusBack(to: previous)
    }

    /// Cove is a menu-bar app: after one of its alerts, hand the keyboard back to the app that had it.
    private func giveFocusBack(to previous: NSRunningApplication?) {
        guard let previous, previous != NSRunningApplication.current, let url = previous.bundleURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func togglePeekApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var set = PeekSources.watchedApps
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        PeekSources.watchedApps = set
    }

    @objc private func toggleSound() { Settings.sound.toggle() }

    @objc private func pickShortcut(_ sender: NSMenuItem) {
        guard let title = sender.representedObject as? String else { return }
        let presets: [String: (HotKeys.Combo, HotKeys.Combo)] = [
            "⌃⌥Y / ⌃⌥N": (HotKeys.defaultAllow, HotKeys.defaultDeny),
            "⌃⌘Y / ⌃⌘N": (.init(keyCode: 16, modifiers: HotKeys.ctrlCmd), .init(keyCode: 45, modifiers: HotKeys.ctrlCmd)),
            "⌃⌥A / ⌃⌥D": (.init(keyCode: 0, modifiers: HotKeys.ctrlOpt), .init(keyCode: 2, modifiers: HotKeys.ctrlOpt)),
            "⌃⇧A / ⌃⇧D": (.init(keyCode: 0, modifiers: HotKeys.ctrlShift), .init(keyCode: 2, modifiers: HotKeys.ctrlShift)),
        ]
        guard let (allow, deny) = presets[title] else { return }
        HotKeys.save(allow, for: "allowKey")
        HotKeys.save(deny, for: "denyKey")
        controller?.shortcutsChanged()
    }

    @objc private func toggleLogin() {
        if let message = LaunchAtLogin.toggle() {
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = message
            let previous = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
            alert.runModal()
            giveFocusBack(to: previous)
        }
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
        case "open": controller.expand()
        case "close": controller.collapse()
        case "edit.toggle": controller.toggleEdit()
        case "pin.toggle": controller.togglePin()
        case "menu.open": statusItem?.button?.performClick(nil)
        case "calendar.request": island.calendarModel.requestIfNeeded()
        case "test.allow": if let card = island.claude.frontCard { controller.answer(card, allow: true) }
        case "test.deny": if let card = island.claude.frontCard { controller.answer(card, allow: false) }
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
