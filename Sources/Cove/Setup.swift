import AppKit
import SwiftUI

/// Installs Cove's Claude Code hooks from the files inside the app bundle: the two hook files into ~/.claude/island
/// and the hook entries into ~/.claude/settings.json (backup first, nothing already there is touched, invalid JSON
/// is left alone and reported). Everything is keyed off the home folder, never a fixed path.
@MainActor
enum ClaudeHooks {
    enum Outcome { case installed(added: Int, backup: String?), alreadySetUp, noClaude, failed(String) }

    /// The real home folder; test builds (COVE_UI_TEST=1) may point it at a scratch folder through $HOME,
    /// which NSHomeDirectory ignores.
    static var home: String {
        let env = ProcessInfo.processInfo.environment
        if env["COVE_UI_TEST"] == "1", let h = env["HOME"], !h.isEmpty { return h }
        return NSHomeDirectory()
    }
    static var claudeFolder: String { home + "/.claude" }
    static var settingsPath: String { claudeFolder + "/settings.json" }
    static var islandFolder: String { claudeFolder + "/island" }
    static let marker = ".claude/island/hook.sh"

    static var claudeCodeFound: Bool { FileManager.default.fileExists(atPath: claudeFolder) }

    /// True when settings.json already calls Cove's hook script.
    static var isSetUp: Bool {
        guard let data = FileManager.default.contents(atPath: settingsPath), let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(marker) && FileManager.default.fileExists(atPath: islandFolder + "/cove-hook")
    }

    static func install() -> Outcome {
        guard claudeCodeFound else { return .noClaude }
        let fm = FileManager.default
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("island"),
              let snippetURL = Bundle.main.url(forResource: "settings-snippet", withExtension: "json", subdirectory: "island") else {
            return .failed("The hook files are missing from this copy of Cove.")
        }
        do {
            try fm.createDirectory(atPath: islandFolder, withIntermediateDirectories: true)
            for name in ["hook.sh", "cove-hook"] {
                let dest = islandFolder + "/" + name
                if fm.fileExists(atPath: dest) { try fm.removeItem(atPath: dest) }
                try fm.copyItem(at: bundled.appendingPathComponent(name), to: URL(fileURLWithPath: dest))
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest)
                removeQuarantine(dest)
            }
        } catch {
            return .failed("Could not copy the hook files: \(error.localizedDescription)")
        }
        // settings.json: read what is there (or start empty), add only the events that do not call Cove yet.
        var settings: [String: Any] = [:]
        let hadFile = fm.fileExists(atPath: settingsPath)
        if let data = fm.contents(atPath: settingsPath) {
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return .failed("\(settingsPath) is not valid JSON, so it was left alone. Fix it, then run Set up Cove again.")
            }
            settings = json
        }
        guard let snippetData = fm.contents(atPath: snippetURL.path),
              let snippet = (try? JSONSerialization.jsonObject(with: snippetData)) as? [String: Any] else {
            return .failed("The bundled hook snippet could not be read.")
        }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var added = 0
        for (event, entries) in snippet {
            guard let newEntries = entries as? [[String: Any]] else { continue }
            var existing = hooks[event] as? [[String: Any]] ?? []
            let present = existing.contains { entry in
                ((entry["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
            }
            if present { continue }
            existing.append(contentsOf: newEntries)
            hooks[event] = existing
            added += 1
        }
        if added == 0 { return .alreadySetUp }
        // Only now, with something to write, keep a copy of the file as it was.
        var backup: String?
        if hadFile {
            backup = settingsPath + ".cove-backup"
            try? fm.removeItem(atPath: backup!)
            do { try fm.copyItem(atPath: settingsPath, toPath: backup!) } catch { return .failed("Could not write the backup: \(error.localizedDescription)") }
        }
        settings["hooks"] = hooks
        do {
            let out = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try out.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        } catch {
            return .failed("Could not write settings.json: \(error.localizedDescription)")
        }
        return .installed(added: added, backup: backup)
    }

    private static func removeQuarantine(_ path: String) {
        removexattr(path, "com.apple.quarantine", 0)
    }
}

/// What the welcome window lets you pick. Applied in one go by `SetupController.apply`.
@MainActor
struct SetupChoices {
    var claudeHooks = ClaudeHooks.claudeCodeFound
    var theme: ThemeMode = .glass
    var weather = true
    var city = "Sydney"
    var calendar = true
    var music = true
    var timer = true
    var hotCorner = false
    var launchAtLogin = LaunchAtLogin.isInstalledCopy
}

/// The welcome window: shown on the first launch, and from the menu ("Set up Cove…") any time after.
@MainActor
final class SetupController {
    static let doneKey = "setupDone"
    static var isDone: Bool {
        get { UserDefaults.standard.bool(forKey: doneKey) }
        set { UserDefaults.standard.set(newValue, forKey: doneKey) }
    }

    private var window: NSWindow?
    private let island: Island
    private weak var controller: IslandController?

    init(island: Island, controller: IslandController?) {
        self.island = island
        self.controller = controller
    }

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let view = SetupView(initial: SetupChoices(), onFinish: { [weak self] choices in self?.apply(choices) ?? [] },
                             onClose: { [weak self] in self?.close() })
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Set up Cove"
        w.contentView = NSHostingView(rootView: view)
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.orderOut(nil)
        Self.isDone = true
    }

    /// Applies the choices; returns one line per thing done, shown in the window.
    func apply(_ c: SetupChoices) -> [String] {
        var lines: [String] = []
        island.setTheme(c.theme)
        lines.append("Theme: \(c.theme == .glass ? "Glass" : c.theme == .dark ? "Dark" : c.theme == .light ? "Light" : "Follow macOS")")
        for (kind, on) in [(TileKind.weather, c.weather), (.calendar, c.calendar), (.spotify, c.music), (.timer, c.timer)] {
            if on { island.show(kind) } else { island.hide(kind) }
        }
        island.setWidget(.nowPlaying, shown: c.music)
        island.setWidget(.weather, shown: c.weather)
        lines.append("Tiles: " + [c.weather ? "Weather" : nil, c.calendar ? "Calendar" : nil, c.music ? "Music" : nil, c.timer ? "Timer" : nil].compactMap { $0 }.joined(separator: ", "))
        if c.weather { island.weatherModel.setCity(c.city); lines.append("Weather city: \(island.weatherModel.city)") }
        Settings.hotCorner = c.hotCorner
        controller?.setHotCorner(c.hotCorner)
        lines.append("Launchpad: ⌘4" + (c.hotCorner ? " and the top-left hot corner" : ""))
        if c.launchAtLogin, !LaunchAtLogin.isOn {
            lines.append(LaunchAtLogin.toggle().map { "Launch at login: \($0)" } ?? "Launch at login: on")
        } else if c.launchAtLogin {
            lines.append("Launch at login: on")
        }
        if c.claudeHooks {
            switch ClaudeHooks.install() {
            case .installed(let added, let backup):
                lines.append("Claude Code: hooks installed, \(added) entr\(added == 1 ? "y" : "ies") added to settings.json"
                             + (backup.map { " (backup: \($0))" } ?? ""))
                Log.app.notice("Setup: Claude hooks installed, \(added) entries added")
            case .alreadySetUp: lines.append("Claude Code: already set up")
            case .noClaude: lines.append("Claude Code: not found on this Mac. Install it, run it once, then Set up Cove again")
            case .failed(let why): lines.append("Claude Code: \(why)"); Log.app.error("Setup: \(why, privacy: .public)")
            }
        }
        Self.isDone = true
        return lines
    }
}

struct SetupView: View {
    @State var choices: SetupChoices
    @State private var result: [String]?
    let onFinish: (SetupChoices) -> [String]
    let onClose: () -> Void

    init(initial: SetupChoices, onFinish: @escaping (SetupChoices) -> [String], onClose: @escaping () -> Void) {
        _choices = State(initialValue: initial)
        self.onFinish = onFinish
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let result {
                done(result)
            } else {
                form
            }
        }
        .frame(width: 460)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Cove").font(.title2.bold())
                Text("Pick what you want on the notch. Everything can be changed later from Cove's menu.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            GroupBox("Claude Code") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show my Claude Code sessions on the notch", isOn: $choices.claudeHooks)
                        .disabled(!ClaudeHooks.claudeCodeFound)
                    Text(ClaudeHooks.claudeCodeFound
                         ? (ClaudeHooks.isSetUp ? "Already set up." : "Installs two small hook files in ~/.claude/island and adds Cove's hooks to ~/.claude/settings.json (a backup is kept).")
                         : "Claude Code was not found. Install it and run it once, then open Set up Cove… from the menu.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Look") {
                Picker("Theme", selection: $choices.theme) {
                    Text("Glass").tag(ThemeMode.glass)
                    Text("Dark").tag(ThemeMode.dark)
                    Text("Light").tag(ThemeMode.light)
                    Text("Follow macOS").tag(ThemeMode.system)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }

            GroupBox("Tiles") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle("Weather", isOn: $choices.weather)
                        TextField("City", text: $choices.city).textFieldStyle(.roundedBorder).frame(width: 160).disabled(!choices.weather)
                    }
                    Toggle("Next calendar event (asks for Calendar access once)", isOn: $choices.calendar)
                    Toggle("Music: Spotify or Apple Music, when one is playing", isOn: $choices.music)
                    Toggle("Focus timer", isOn: $choices.timer)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Launchpad and startup") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("⌘4 opens the Launchpad (change it in the menu).").font(.caption).foregroundStyle(.secondary)
                    Toggle("Also open it from the top-left hot corner", isOn: $choices.hotCorner)
                    Toggle("Start Cove at login", isOn: $choices.launchAtLogin).disabled(!LaunchAtLogin.isInstalledCopy)
                    if !LaunchAtLogin.isInstalledCopy {
                        Text("Launch at login works once Cove is in your Applications folder.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Later") { onClose() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Finish") { result = onFinish(choices) }.keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
    }

    private func done(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All set").font(.title2.bold())
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: line.contains("not found") || line.contains("Could not") || line.contains("not valid") ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(line).font(.callout).textSelection(.enabled)
                }
            }
            Text("Rest the mouse on the notch to open Cove. The menu bar icon has everything else.")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 4)
            HStack { Spacer(); Button("Close") { onClose() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
    }
}
