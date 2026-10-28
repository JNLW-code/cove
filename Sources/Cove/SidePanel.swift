import AppKit
import SwiftUI

/// The Claude side panel: 420 pt wide on the right edge, menu bar to Dock. Slides in when the mouse rests on the
/// right edge of the screen (or ⌃⌥C), slides out when the mouse leaves unless a click pinned it; Esc, ⌃⌥C or a
/// click outside close a pinned one. Non-activating: whatever app James is in stays in front.
@MainActor
final class SidePanelController {
    static let width: CGFloat = 420
    static let edgeDwell = 250   // ms the mouse must rest on the edge before the panel slides in
    static let leaveGrace = 300  // ms after the mouse leaves before an unpinned panel slides out

    private let island: Island
    private let actions: IslandActions
    private let panel: IslandPanel
    private let host: IslandHostView
    private let hosting: PanelHostingView
    /// A 1 pt strip down the right edge of the screen; its tracking area is what notices the mouse at the edge.
    private let edge: NSPanel
    private let edgeHost: IslandHostView
    private var dwellTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var slideTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var previous: NSRunningApplication?
    private let reader = ChatReader()
    private var screenFrame = NSRect.zero

    nonisolated(unsafe) private static weak var shared: SidePanelController?

    init(island: Island, actions: IslandActions) {
        self.island = island
        self.actions = actions
        host = IslandHostView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 600))
        hosting = PanelHostingView(rootView: SidePanelRoot(island: island, actions: actions))
        panel = IslandPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        edgeHost = IslandHostView(frame: NSRect(x: 0, y: 0, width: 1, height: 600))
        edge = NSPanel(contentRect: edgeHost.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        Self.shared = self

        for window in [panel, edge] {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
        }
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        edge.hasShadow = false
        edge.ignoresMouseEvents = false

        hosting.sizingOptions = []
        hosting.frame = host.bounds
        hosting.autoresizingMask = [.width, .height]
        host.addSubview(hosting)
        panel.contentView = host
        host.onEnter = { [weak self] in self?.leaveTask?.cancel() }
        host.onExit = { [weak self] in self?.mouseLeftPanel() }
        edge.contentView = edgeHost
        edgeHost.onEnter = { [weak self] in self?.edgeEntered() }
        edgeHost.onExit = { [weak self] in self?.dwellTask?.cancel() }
        layout()
        edge.orderFrontRegardless()
    }

    /// The panel spans the visible height of the notch screen (under the menu bar, above the Dock), flush right.
    func layout() {
        let screen = NotchGeometry.current().screen
        screenFrame = screen.frame
        let visible = screen.visibleFrame
        let height = visible.height
        edge.setFrame(NSRect(x: screen.frame.maxX - 1, y: visible.minY, width: 1, height: height), display: false)
        if island.panelOpen {
            panel.setFrame(NSRect(x: screen.frame.maxX - Self.width, y: visible.minY, width: Self.width, height: height), display: true)
        } else {
            panel.setFrame(NSRect(x: screen.frame.maxX, y: visible.minY, width: Self.width, height: height), display: false)
        }
    }

    private var openFrame: NSRect { NSRect(x: screenFrame.maxX - Self.width, y: panel.frame.minY, width: Self.width, height: panel.frame.height) }
    private var closedFrame: NSRect { NSRect(x: screenFrame.maxX, y: panel.frame.minY, width: Self.width, height: panel.frame.height) }

    // MARK: Open and close

    func toggle() {
        if island.panelOpen { close() } else { open(pinned: true) }
    }

    /// Slides the panel in. `pinned` is for ⌃⌥C and the menu: those should not vanish when the mouse moves.
    func open(pinned: Bool) {
        dwellTask?.cancel(); leaveTask?.cancel(); slideTask?.cancel()
        if !island.panelOpen {
            island.panelOpen = true
            previous = NSWorkspace.shared.frontmostApplication
            panel.setFrame(closedFrame, display: false)
            panel.orderFrontRegardless()
            slide(to: openFrame)
            installKeyMonitor()
            refresh(now: true)
        }
        if pinned { setPinned(true) }
    }

    func close() {
        dwellTask?.cancel(); leaveTask?.cancel(); slideTask?.cancel()
        guard island.panelOpen else { return }
        island.panelOpen = false
        setPinned(false)
        removeKeyMonitor()
        let wasKey = panel.isKeyWindow
        panel.makeFirstResponder(nil)
        slide(to: closedFrame) { [weak self] in self?.panel.orderOut(nil) }
        if wasKey { IslandController.handBack(to: previous) }
        previous = nil
    }

    private func slide(to frame: NSRect, then done: (@MainActor @Sendable () -> Void)? = nil) {
        if island.reduceMotion {
            panel.setFrame(frame, display: true)
            done?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated { done?() }
        })
    }

    // MARK: Hover

    private func edgeEntered() {
        guard !island.panelOpen, !island.demo else { return }
        dwellTask?.cancel()
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.edgeDwell), tolerance: .milliseconds(30))
            guard !Task.isCancelled, let self else { return }
            // Still on the edge (a quick brush past it should not open anything).
            guard NSEvent.mouseLocation.x >= self.screenFrame.maxX - 2 else { return }
            self.open(pinned: false)
        }
    }

    private func mouseLeftPanel() {
        guard island.panelOpen, !island.panelPinned else { return }
        leaveTask?.cancel()
        leaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.leaveGrace), tolerance: .milliseconds(30))
            guard !Task.isCancelled, let self, self.island.panelOpen, !self.island.panelPinned else { return }
            guard !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.close()
        }
    }

    // MARK: Pin and keys

    func togglePin() {
        guard island.panelOpen else { return }
        setPinned(!island.panelPinned)
    }

    /// A click on the panel's background pins it and gives it the keyboard, so Esc works.
    func clickedInside() {
        guard island.panelOpen else { return }
        if !island.panelPinned { setPinned(true) }
        if !panel.isKeyWindow { panel.makeKey() }
    }

    private func setPinned(_ pinned: Bool) {
        island.panelPinned = pinned
        if pinned, outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                Task { @MainActor in SidePanelController.shared?.outsideClick() }
            }
        } else if !pinned, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func outsideClick() {
        guard island.panelOpen, island.panelPinned, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        close()
    }

    /// Esc closes the panel once it has the keyboard (after a click in it). Other keys pass through.
    /// Any click in the panel pins it (seen here, before SwiftUI, so a click on text or a button counts too).
    private func installKeyMonitor() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, event.window === SidePanelController.shared?.panel else { return event }
                Task { @MainActor in SidePanelController.shared?.close() }
                return nil
            }
        }
        if clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                if event.window === SidePanelController.shared?.panel { Task { @MainActor in SidePanelController.shared?.clickedInside() } }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
    }

    // MARK: Content

    func select(_ session: ClaudeSession) {
        island.panelSessionID = session.id
        refresh(now: true)
    }

    /// Reads what the transcript has added. Hook events arrive up to 100 a minute; while the panel is open the
    /// reads are spaced at least half a second apart, and nothing is read while it is closed.
    func refresh(now: Bool = false) {
        guard island.panelOpen else { return }
        if !now, refreshTask != nil { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if !now { try? await Task.sleep(for: .milliseconds(500), tolerance: .milliseconds(50)) }
            guard !Task.isCancelled, let self else { return }
            self.refreshTask = nil
            await self.load()
        }
    }

    private func load() async {
        guard let session = island.panelSession, let path = session.transcriptPath, !path.isEmpty else { return }
        let id = session.id
        let items = await reader.load(session: id, transcript: path)
        guard let s = island.claude.session(id) ?? island.claude.sessions.first(where: { $0.id == id }) else { return }
        if s.chat != items { s.chat = items }
        s.chatLoaded = true
    }

    func forget(session id: String) {
        Task { [reader] in await reader.forget(session: id) }
    }
}

/// The panel's SwiftUI host: takes the first click even though Cove is never the active app (plain NSHostingView
/// swallows it), so one click on a rail square or the background is enough.
final class PanelHostingView: NSHostingView<SidePanelRoot> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
