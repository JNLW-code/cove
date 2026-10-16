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
    private var updater: Updater?
    private var setup: SetupController?

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
        updater = Updater()
        setup = SetupController(island: island, controller: controller)
        Log.app.notice("Cove \(Self.version, privacy: .public) launched")
        // First launch: the welcome window, a moment after the island has settled. Never again once closed.
        if !SetupController.isDone {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.setup?.show()
            }
        }
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
        controller?.startFocusIfPossible()
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(item("Cove \(Self.version)", nil, enabled: false))
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates), enabled: updater?.canCheck ?? false))
        menu.addItem(item("Set up Cove…", #selector(openSetup)))
        menu.addItem(.separator())

        menu.addItem(submenu("Theme", [("Dark", ThemeMode.dark), ("Light", .light), ("Follow macOS", .system), ("Glass", .glass)].map {
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
        var shortcutItems = combos.map { item($0.0, #selector(pickShortcut(_:)), $0.0, on: $0.0 == current) }
        let custom = !combos.contains { $0.0 == current }
        shortcutItems.append(.separator())
        shortcutItems.append(item(custom ? "Your own: \(current)" : "Record your own…", #selector(recordShortcuts), on: custom))
        menu.addItem(submenu("Allow / Deny Shortcuts", shortcutItems))

        let launchpad = item("Open  (\(island.hotKeyLaunchpad))", #selector(toggleLaunchpad), on: island.mode == .launchpad)
        let widgets = LaunchpadWidget.allCases.map { item($0.title, #selector(toggleWidget(_:)), $0.rawValue, on: !island.hiddenWidgets.contains($0)) }
        menu.addItem(submenu("Launchpad", [
            launchpad,
            item("Change Shortcut…", #selector(recordLaunchpadShortcut)),
            item("Hot Corner (top-left)", #selector(toggleHotCorner), on: Settings.hotCorner),
            .separator(),
            submenu("Widgets", widgets),
        ]))

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
            line("Apple Music (Automation)", Permissions.automation(for: MusicModel.bundleID), why: "Needed for play, pause, next and artwork in the Launchpad."),
            line("System Events (Automation)", Permissions.automation(for: "com.apple.systemevents"), why: "Needed for the dark mode toggle in the Launchpad."),
            line("Calendar", Permissions.calendar, why: "Needed to show your next event."),
            line("Accessibility", Typist.isTrusted ? .granted : .notAsked, why: "Needed to type a reply into the Claude app after its hook has moved on."),
            FocusWatcher.access == .granted
                ? line("Full Disk Access (Do Not Disturb peek)", .granted, why: "")
                : item("Full Disk Access: not granted. Only for the Do Not Disturb peek — click to open System Settings", #selector(openFullDiskAccess)),
            item("Launch at Login: \(LaunchAtLogin.statusText)", nil, enabled: false),
            item("Claude Code hooks: \(ClaudeHooks.isSetUp ? "set up" : (ClaudeHooks.claudeCodeFound ? "not set up (Set up Cove…)" : "Claude Code not found"))", nil, enabled: false),
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
        IslandController.handBack(to: previous)
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

    /// Two boxes that record whatever keys are pressed in them, saved as the Allow / Deny shortcuts.
    @objc private func recordShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Allow / Deny shortcuts"
        alert.informativeText = "Click a box and press the keys you want. Use Control or Command in the combo; Option-only shortcuts may not register."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let allowBox = KeyCaptureView(combo: HotKeys.load("allowKey", default: HotKeys.defaultAllow))
        let denyBox = KeyCaptureView(combo: HotKeys.load("denyKey", default: HotKeys.defaultDeny))
        let grid = NSGridView(views: [[NSTextField(labelWithString: "Allow"), allowBox], [NSTextField(labelWithString: "Deny"), denyBox]])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = allowBox
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, let allow = allowBox.combo, let deny = denyBox.combo {
            if allow == deny {
                let same = NSAlert()
                same.messageText = "Allow and Deny need different keys"
                same.runModal()
            } else {
                HotKeys.save(allow, for: "allowKey")
                HotKeys.save(deny, for: "denyKey")
                controller?.shortcutsChanged()
            }
        }
        giveFocusBack(to: previous)
    }

    @objc private func checkForUpdates() { updater?.checkForUpdates() }

    @objc private func openSetup() { setup?.show() }

    @objc private func toggleLaunchpad() { controller?.toggleLaunchpad() }

    @objc private func toggleWidget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let widget = LaunchpadWidget(rawValue: raw) else { return }
        controller?.toggleWidget(widget)
    }

    @objc private func toggleHotCorner() {
        Settings.hotCorner.toggle()
        controller?.setHotCorner(Settings.hotCorner)
    }

    /// One box that records the keys for the Launchpad (default ⌘4).
    @objc private func recordLaunchpadShortcut() {
        let alert = NSAlert()
        alert.messageText = "Launchpad shortcut"
        alert.informativeText = "Click the box and press the keys you want. It works in every app, so pick one nothing else needs."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let box = KeyCaptureView(combo: HotKeys.load("launchpadKey", default: HotKeys.defaultLaunchpad))
        alert.accessoryView = box
        alert.window.initialFirstResponder = box
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, let combo = box.combo {
            HotKeys.save(combo, for: "launchpadKey")
            controller?.shortcutsChanged()
        }
        giveFocusBack(to: previous)
    }

    /// System Settings → Privacy & Security → Full Disk Access. macOS has no prompt for this one; James adds Cove there.
    @objc private func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
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
        case "theme.glass": island.setTheme(.glass)
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
        case "launchpad.toggle": controller.toggleLaunchpad()
        case "launchpad.next": controller.launchpadStep(1)
        case "launchpad.type": island.launchpadQuery = "ca"; island.launchpadPage = 0   // as if "ca" had been typed
        case "launchpad.categories": controller.toggleCategories()
        case "launchpad.folder": controller.openFolder(island.apps.categories.first)
        case "launchpad.demo": island.music = Demo.track; island.weather = Demo.weather   // sample widgets without Spotify or Music
        case "update.check": updater?.checkForUpdates()
        case "setup.open": setup?.show()
        case "test.setup":   // applies the default choices without the window (hooks install into $HOME, so only in a scratch home)
            if let lines = setup?.apply(SetupChoices()) { for line in lines { Log.app.notice("Setup result: \(line, privacy: .public)") } }
        case "test.update": updater?.checkInBackground()   // silent check against COVE_FEED, installs and relaunches
        case "test.allow": if let card = island.claude.frontCard { controller.answer(card, allow: true) }
        case "test.deny": if let card = island.claude.frontCard { controller.answer(card, allow: false) }
        case "test.reply": if let s = island.cardSession { controller.sendReply("test reply from the island", to: s) }
        case "test.seen": island.claude.frontCardFullySeen = true   // as if the long box had been scrolled to the end
        case "test.note":   // first call opens the note line on the first row, second call keeps a sample note
            if let s = island.claude.sessions.first {
                if island.notingFor == nil { controller.editNote(for: s) } else { controller.setNote("waiting on Dave's PR", for: s) }
            }
        case "test.record":   // opens the shortcut recorder and closes it by itself after 3 s (a timer in common modes runs inside the modal loop)
            let timer = Timer(timeInterval: 3, repeats: false) { _ in MainActor.assumeIsolated { NSApp.abortModal() } }
            RunLoop.main.add(timer, forMode: .common)
            recordShortcuts()
        case "test.answerq":   // first option of every question
            if let q = island.claude.frontQuestion {
                controller.answerQuestion(q, answers: Dictionary(q.questions.map { ($0.text, $0.options[0].label) }, uniquingKeysWith: { a, _ in a }))
            }
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
