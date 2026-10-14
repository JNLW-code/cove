import AppKit

/// One app in the Launchpad grid.
struct AppEntry: Identifiable, Hashable, Sendable {
    /// The bundle's path (symlinks resolved).
    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    /// LSApplicationCategoryType from Info.plist, when the app declares one.
    let category: String?
    /// Lower-cased words of the name, for search ("visual studio code" → ["visual", "studio", "code"]).
    let words: [String]

    var lowercasedName: String { words.joined(separator: " ") }
    /// First letter of each word, so "vsc" finds Visual Studio Code.
    var initials: String { words.compactMap(\.first).map(String.init).joined() }
}

/// The eight Launchpad folders. Apps land in one by their LSApplicationCategoryType; none → Other.
enum AppCategory: String, CaseIterable, Sendable {
    case productivity, creative, developer, music, social, utilities, games, other

    var title: String {
        switch self {
        case .productivity: "Productivity"
        case .creative: "Creative"
        case .developer: "Developer"
        case .music: "Music and video"
        case .social: "Social"
        case .utilities: "Utilities"
        case .games: "Games"
        case .other: "Other"
        }
    }

    static func of(_ type: String?) -> AppCategory {
        guard let type, type.hasPrefix("public.app-category.") else { return .other }
        let kind = String(type.dropFirst("public.app-category.".count))
        if kind.hasSuffix("games") { return .games }
        switch kind {
        case "productivity", "business", "finance", "education", "reference": return .productivity
        case "graphics-design", "photography", "video": return .creative
        case "developer-tools": return .developer
        case "music", "entertainment": return .music
        case "social-networking": return .social
        case "utilities": return .utilities
        default: return .other
        }
    }
}

/// Every app in the four Applications folders, alphabetical, with icons rendered once at grid size.
/// The folders are watched, so installing or removing an app updates the grid without a restart.
@MainActor
@Observable
final class AppCatalog {
    nonisolated static let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                                      NSHomeDirectory() + "/Applications"]
    nonisolated static let iconPoints: CGFloat = 48

    private(set) var apps: [AppEntry] = []
    private(set) var scanned = false
    private var icons: [String: NSImage] = [:]
    private var loading: Set<String> = []
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var rescanTask: Task<Void, Never>?

    init() {
        rescan()
        watch()
    }

    // MARK: Scanning

    func rescan() {
        rescanTask?.cancel()
        rescanTask = Task.detached(priority: .utility) { [weak self] in
            let found = AppCatalog.scan()
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.apply(found) }
        }
    }

    private func apply(_ found: [AppEntry]) {
        apps = found
        scanned = true
        let keep = Set(found.map(\.id))
        icons = icons.filter { keep.contains($0.key) }
        Log.app.notice("App catalog: \(found.count) apps")
    }

    /// Reads the four folders on a background thread. Follows symlinks, skips bundles inside bundles
    /// (only the top level of each folder is read), background-only processes and helper apps.
    nonisolated static func scan() -> [AppEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [AppEntry] = []
        for folder in folders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                let raw = URL(fileURLWithPath: folder).appendingPathComponent(name)
                let url = raw.resolvingSymlinksInPath()
                guard let bundle = Bundle(url: url), let info = bundle.infoDictionary, !info.isEmpty else { continue }
                if (info["LSBackgroundOnly"] as? Bool) == true || (info["LSBackgroundOnly"] as? String) == "1" { continue }
                let display = fm.displayName(atPath: raw.path).replacingOccurrences(of: ".app", with: "")
                if isHelper(display) { continue }
                let bundleID = bundle.bundleIdentifier
                let key = bundleID ?? display.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let words = display.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" }).map(String.init)
                out.append(AppEntry(id: url.path, name: display, url: url, bundleID: bundleID,
                                    category: info["LSApplicationCategoryType"] as? String, words: words))
            }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func isHelper(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["helper", "handler", "agent", "daemon", "uninstaller"].contains { lower.hasSuffix(" " + $0) || lower.hasSuffix($0 + ".app") }
    }

    /// One vnode watch per folder; a change rescans after 1.5 s of quiet (installs write many files).
    private func watch() {
        for folder in Self.folders {
            let fd = Darwin.open(folder, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.changed() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
    }

    private func changed() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    // MARK: Icons

    /// The icon at grid size, or nil while it renders (the cell asks again when `icons` changes).
    func icon(for app: AppEntry) -> NSImage? {
        if let image = icons[app.id] { return image }
        guard !loading.contains(app.id) else { return nil }
        loading.insert(app.id)
        let path = app.id
        Task.detached(priority: .userInitiated) { [weak self] in
            let box = AppCatalog.renderIcon(path: path)
            await MainActor.run {
                guard let self else { return }
                self.loading.remove(path)
                if let box { self.icons[path] = box.image }
            }
        }
        return nil
    }

    private struct IconBox: @unchecked Sendable { let image: NSImage }

    /// Draws the Finder icon once into a bitmap of the size the grid uses (2× for Retina), so the hundreds
    /// of cells never resample a 1024-point icon while scrolling.
    private nonisolated static func renderIcon(path: String) -> IconBox? {
        let source = NSWorkspace.shared.icon(forFile: path)
        let pixels = Int(iconPoints * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: iconPoints, height: iconPoints))
        image.addRepresentation(rep)
        return IconBox(image: image)
    }

    /// Drops every cached icon so they render again (used after the icon style changes).
    func dropIcons() { icons = [:] }

    // MARK: Search

    /// Apps matching `query`: name prefix first, then a word prefix, then the initials, then anywhere in the name.
    func search(_ query: String) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return apps }
        func rank(_ app: AppEntry) -> Int? {
            if app.lowercasedName.hasPrefix(q) { return 0 }
            if app.words.contains(where: { $0.hasPrefix(q) }) { return 1 }
            if app.initials.hasPrefix(q) { return 2 }
            if app.lowercasedName.contains(q) { return 3 }
            return nil
        }
        var ranked: [(Int, AppEntry)] = []
        for app in apps { if let r = rank(app) { ranked.append((r, app)) } }
        ranked.sort { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            return a.1.name.localizedStandardCompare(b.1.name) == .orderedAscending
        }
        return ranked.map(\.1)
    }

    func apps(in category: AppCategory) -> [AppEntry] {
        apps.filter { AppCategory.of($0.category) == category }
    }

    /// Folders that have at least one app, in the fixed order.
    var categories: [AppCategory] { AppCategory.allCases.filter { !apps(in: $0).isEmpty } }

    func open(_ app: AppEntry) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }
}
