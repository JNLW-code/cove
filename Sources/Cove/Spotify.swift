import AppKit
import Foundation

/// Spotify for the music tile. Track and play state come from Spotify's own distributed notification
/// (no permission needed). AppleScript is used only for controls, artwork and position, only while the
/// island is open, and only if Spotify is already running (otherwise AppleScript would launch it).
@MainActor
@Observable
final class SpotifyModel: NSObject {
    static let bundleID = "com.spotify.client"
    private static let artDirectory = ClaudeSocket.directory.appendingPathComponent("art", isDirectory: true)

    private(set) var track: SpotifyTrack?
    private var trackID: String?
    private var durationSeconds: Double = 0
    private var positionAtUpdate: Double = 0
    private var updatedAt = Date()
    private var artworkTask: Task<Void, Never>?
    /// Called whenever `track` changes so the island can refresh.
    var onChange: (() -> Void)?

    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(playbackChanged(_:)),
                                                            name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appTerminated(_:)),
                                                          name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: Notification path (free, no permission)

    @objc private func playbackChanged(_ note: Notification) {
        guard let info = note.userInfo else { return }
        let state = info["Player State"] as? String ?? ""
        guard state == "Playing" || state == "Paused" else { clear(); return }
        let id = info["Track ID"] as? String ?? ""
        let name = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        if let ms = info["Duration"] as? Double { durationSeconds = ms / 1000 }
        if let pos = info["Playback Position"] as? Double { positionAtUpdate = pos }
        updatedAt = Date()
        let changed = id != trackID
        trackID = id
        var current = track ?? SpotifyTrack(title: name, artist: artist, artwork: nil, progress: 0, playing: false)
        current.title = name
        current.artist = artist
        current.playing = state == "Playing"
        track = current            // progress reads the playing flag, so store it first
        current.progress = progress
        if changed { current.artwork = cachedArtwork(for: id) }
        track = current
        onChange?()
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.bundleID else { return }
        clear()
    }

    private func clear() {
        artworkTask?.cancel()
        track = nil
        trackID = nil
        onChange?()
    }

    /// Position worked out from the last notification plus the clock, so no polling is needed.
    var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        let elapsed = (track?.playing ?? false) ? Date().timeIntervalSince(updatedAt) : 0
        return min(1, max(0, (positionAtUpdate + elapsed) / durationSeconds))
    }

    /// Refreshes the shown progress (the tile calls this once a second while open and playing).
    func tick() {
        guard var current = track else { return }
        current.progress = progress
        track = current
    }

    // MARK: AppleScript path (Automation permission; only while the island is open)

    /// When the island opens: after the open animation, if Spotify runs but we have no track yet, ask it once; then fetch artwork.
    func islandOpened() {
        guard Self.isRunning else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.askSpotify()
        }
    }

    /// AppleScript is synchronous, so this runs only once the island has finished opening.
    private func askSpotify() {
        if track == nil, let info = run("""
            tell application "Spotify"
                if player state is stopped then return ""
                set t to current track
                return (id of t) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (duration of t) & linefeed & (player position) & linefeed & (player state as text)
            end tell
            """), !info.isEmpty {
            let parts = info.components(separatedBy: "\n")
            if parts.count >= 6 {
                trackID = parts[0]
                durationSeconds = (Double(parts[3]) ?? 0) / 1000
                positionAtUpdate = Double(parts[4]) ?? 0
                updatedAt = Date()
                track = SpotifyTrack(title: parts[1], artist: parts[2], artwork: cachedArtwork(for: parts[0]),
                                     progress: progress, playing: parts[5] == "playing")
                onChange?()
            }
        }
        fetchArtworkIfNeeded()
    }

    func send(_ command: SpotifyCommand) {
        guard Self.isRunning else { return }
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        _ = run("tell application \"Spotify\" to \(verb)")
    }

    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error { Log.app.error("Spotify AppleScript failed: \(String(describing: error[NSAppleScript.errorBriefMessage] ?? ""), privacy: .public)"); return nil }
        return result.stringValue ?? ""
    }

    // MARK: Artwork (Spotify's own CDN, cached on disk by track id)

    private func cachedArtwork(for id: String) -> NSImage? {
        guard !id.isEmpty else { return nil }
        return NSImage(contentsOf: Self.artDirectory.appendingPathComponent(Self.fileName(id)))
    }

    private static func fileName(_ id: String) -> String {
        id.replacingOccurrences(of: ":", with: "_").filter { $0.isLetter || $0.isNumber || $0 == "_" } + ".jpg"
    }

    private func fetchArtworkIfNeeded() {
        guard let id = trackID, track?.artwork == nil, artworkTask == nil else { return }
        guard let urlText = run("tell application \"Spotify\" to return artwork url of current track"),
              let url = URL(string: urlText), url.scheme == "https", url.host?.hasSuffix("scdn.co") == true else { return }
        let file = Self.artDirectory.appendingPathComponent(Self.fileName(id))
        artworkTask = Task { [weak self] in
            defer { self?.artworkTask = nil }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 3_000_000,
                  let image = NSImage(data: data), let self, self.trackID == id else { return }
            try? FileManager.default.createDirectory(at: Self.artDirectory, withIntermediateDirectories: true)
            try? data.write(to: file)
            if var current = self.track { current.artwork = image; self.track = current; self.onChange?() }
        }
    }
}
