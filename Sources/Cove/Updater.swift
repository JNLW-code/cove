import AppKit
import Sparkle

/// In-app updates through Sparkle: the feed is the repo's appcast.xml, each update is signed with the EdDSA key whose
/// public half is in Info.plist (SUPublicEDKey), and the new app must carry the same "Cove Dev" signature as the old.
/// Checks once a day in the background; "Check for Updates…" in the menu checks now.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    /// Test builds (COVE_UI_TEST=1) may point the feed at a local server and install without any dialog.
    nonisolated private static let testFeed: String? = {
        let env = ProcessInfo.processInfo.environment
        return env["COVE_UI_TEST"] == "1" ? env["COVE_FEED"] : nil
    }()

    override init() {
        super.init()
        let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        if Self.testFeed != nil { c.updater.automaticallyDownloadsUpdates = true }
        c.startUpdater()
        controller = c
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    /// Test only: a silent check that downloads the update and installs it at once (see `willInstallUpdateOnQuit`).
    func checkInBackground() { controller?.updater.checkForUpdatesInBackground() }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? { Self.testFeed }

    /// Test only: Sparkle has the update ready and would wait for quit; install it now and relaunch.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard Self.testFeed != nil else { return false }
        immediateInstallHandler()
        return true
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        Log.app.notice("Update feed read: \(appcast.items.count) item(s)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Log.app.notice("Update available: \(item.displayVersionString, privacy: .public)")
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Log.app.notice("No update: \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Log.app.error("Update failed: \(error.localizedDescription, privacy: .public)")
    }
}
