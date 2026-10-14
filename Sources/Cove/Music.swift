import AppKit
import Foundation

/// Apple Music for the Now playing widget, built like `SpotifyModel`: track and play state come from Music's own
/// distributed notification (no permission), AppleScript only for position, artwork and the buttons, and only
/// while Music is already running (AppleScript would launch it otherwise).
@MainActor
@Observable
final class MusicModel: NSObject {
    static let bundleID = "com.apple.Music"

    private(set) var track: SpotifyTrack?
    private var trackID: String?
    private var durationSeconds: Double = 0
    private var positionAtUpdate: Double = 0
    private var updatedAt = Date()
    private var artwork: [String: NSImage] = [:]
    var onChange: (() -> Void)?

    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(playerInfo(_:)),
                                                            name: Notification.Name("com.apple.Music.playerInfo"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appTerminated(_:)),
                                                          name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    @objc private func playerInfo(_ note: Notification) {
        guard let info = note.userInfo else { return }
        let state = info["Player State"] as? String ?? ""
        guard state == "Playing" || state == "Paused" else { clear(); return }
        let id = (info["PersistentID"].map { "\($0)" }) ?? (info["Name"] as? String ?? "")
        if let ms = info["Total Time"] as? Double { durationSeconds = ms / 1000 }
        let changed = id != trackID
        if changed { positionAtUpdate = 0 }
        trackID = id
        updatedAt = Date()
        var current = track ?? SpotifyTrack(title: "", artist: "", artwork: nil, progress: 0, playing: false)
        current.title = info["Name"] as? String ?? current.title
        current.artist = info["Artist"] as? String ?? current.artist
        current.playing = state == "Playing"
        if changed { current.artwork = artwork[id] }
        track = current
        current.progress = progress
        track = current
        onChange?()
        if changed, Self.isRunning { fetchPositionAndArtwork() }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.bundleID else { return }
        clear()
    }

    private func clear() {
        track = nil
        trackID = nil
        onChange?()
    }

    var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        let elapsed = (track?.playing ?? false) ? Date().timeIntervalSince(updatedAt) : 0
        return min(1, max(0, (positionAtUpdate + elapsed) / durationSeconds))
    }

    /// When the Launchpad opens: if Music runs but we have no track yet, ask it once (first use asks for Automation).
    func islandOpened() {
        guard Self.isRunning else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self else { return }
            if self.track == nil { self.askMusic() } else { self.fetchPositionAndArtwork() }
        }
    }

    private func askMusic() {
        guard let info = run("""
            tell application "Music"
                if player state is stopped then return ""
                set t to current track
                return (persistent ID of t) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (duration of t) & linefeed & (player position) & linefeed & (player state as text)
            end tell
            """)?.stringValue, !info.isEmpty else { return }
        let parts = info.components(separatedBy: "\n")
        guard parts.count >= 6 else { return }
        trackID = parts[0]
        durationSeconds = Double(parts[3]) ?? 0
        positionAtUpdate = Double(parts[4]) ?? 0
        updatedAt = Date()
        track = SpotifyTrack(title: parts[1], artist: parts[2], artwork: artwork[parts[0]], progress: progress, playing: parts[5] == "playing")
        onChange?()
        fetchPositionAndArtwork()
    }

    private func fetchPositionAndArtwork() {
        guard Self.isRunning, let id = trackID else { return }
        if let pos = run("tell application \"Music\" to return player position")?.stringValue, let value = Double(pos) {
            positionAtUpdate = value
            updatedAt = Date()
        }
        if artwork[id] == nil,
           let data = run("tell application \"Music\" to return data of artwork 1 of current track")?.data,
           let image = NSImage(data: data) {
            artwork[id] = image
            if artwork.count > 20 { artwork = [id: image] }
        }
        if var current = track {
            current.artwork = artwork[id]
            current.progress = progress
            track = current
            onChange?()
        }
    }

    func send(_ command: SpotifyCommand) {
        guard Self.isRunning else { return }
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        _ = run("tell application \"Music\" to \(verb)")
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error { Log.app.error("Music AppleScript failed: \(String(describing: error[NSAppleScript.errorBriefMessage] ?? ""), privacy: .public)"); return nil }
        return result
    }
}
