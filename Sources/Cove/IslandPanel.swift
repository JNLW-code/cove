import AppKit
import SwiftUI

/// Borderless, non-activating panel that never takes focus.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Content view: owns the hover tracking area and accepts the first click without activating the app.
final class IslandHostView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

final class HostingView: NSHostingView<IslandRoot> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the panel, decides the mode and frame, runs hover, pin, peeks and the demo.
@MainActor
final class IslandController: NSObject {
    let island: Island
    let actions = IslandActions()
    private let panel: IslandPanel
    private let host: IslandHostView
    private let hosting: HostingView
    private var notch = NotchGeometry.current()

    private var hoverTask: Task<Void, Never>?
    private var tightenTask: Task<Void, Never>?
    /// Frames shown since the panel was last tightened; the panel covers all of them until the animation settles.
    private var pendingFrames: [NSRect] = []
    private var peekTask: Task<Void, Never>?
    private var pendingPeekSeconds: Double?
    private var demoTask: Task<Void, Never>?
    private var demoStep = 0
    private var outsideClickMonitor: Any?
    /// Called when the toolbar's settings button is pressed (the app opens its menu-bar menu).
    var onOpenMenu: (() -> Void)?

    nonisolated(unsafe) private static weak var shared: IslandController?

    static let openAnimation = Animation.spring(response: 0.36, dampingFraction: 0.78)
    static let closeAnimation = Animation.easeInOut(duration: 0.22)
    static let switchAnimation = Animation.spring(response: 0.22, dampingFraction: 0.85)

    init(island: Island) {
        self.island = island
        island.notchSize = notch.size
        host = IslandHostView(frame: NSRect(origin: .zero, size: notch.size))
        hosting = HostingView(rootView: IslandRoot(island: island, actions: actions))
        panel = IslandPanel(contentRect: notch.rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        actions.controller = self
        Self.shared = self

        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true

        hosting.sizingOptions = []
        hosting.frame = host.bounds
        hosting.autoresizingMask = [.width, .height]
        host.addSubview(hosting)
        panel.contentView = host
        host.onEnter = { [weak self] in self?.mouseEntered() }
        host.onExit = { [weak self] in self?.mouseExited() }
        panel.orderFrontRegardless()

        island.claude.onPeek = { [weak self] content, seconds in self?.showPeek(content, seconds: seconds) }
        island.claude.onChanged = { [weak self] in self?.claudeChanged() }
        let socket = ClaudeSocket(onMessage: { [weak self] message in self?.island.claude.handle(message) },
                                  onRequestClosed: { [weak self] id in self?.island.claude.requestClosed(id) })
        island.claude.socket = socket
        do { try socket.start() } catch { Log.app.error("Socket failed: \(error.localizedDescription, privacy: .public)") }

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(appearanceChanged), name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    // MARK: Modes and frames

    private func frame(for mode: Island.Mode) -> NSRect {
        let size = island.contentSize(for: mode)
        return NSRect(x: notch.centerX - size.width / 2, y: notch.top - size.height, width: size.width, height: size.height)
    }

    /// The mode the island falls back to when nothing is open.
    private var baseMode: Island.Mode {
        if island.peek != nil { return .peek }
        if island.compactContent != nil { return .compact }
        return .resting
    }

    /// Claude sessions changed: refresh the pill, or the open island's size.
    private func claudeChanged() {
        if island.mode == .resting || island.mode == .compact {
            if island.mode != baseMode { show(baseMode, animation: Self.switchAnimation) }
        } else if island.mode == .expanded {
            show(.expanded, animation: Self.switchAnimation)
        }
    }

    func rowClicked(_ session: ClaudeSession) {
        island.claude.bringForward(session)
        collapse()
    }

    /// Grows the panel to cover old and new, animates the content, then tightens the frame when the animation is done.
    func show(_ mode: Island.Mode, animation: Animation?, settle: Double = 0.4) {
        tightenTask?.cancel()
        if mode != .expanded { setPinned(false) }
        let target = frame(for: mode)
        if pendingFrames.isEmpty { pendingFrames = [panel.frame] }
        pendingFrames.append(target)
        let union = pendingFrames.dropFirst().reduce(pendingFrames[0]) { $0.union($1) }
        if union != panel.frame { panel.setFrame(union, display: true) }
        if mode == .expanded { panel.hasShadow = true }
        if let animation, !island.reduceMotion {
            withAnimation(animation) { island.mode = mode }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { island.mode = mode }
        }
        tightenTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(settle * 1000)), tolerance: .milliseconds(20))
            guard !Task.isCancelled, let self, self.island.mode == mode else { return }
            self.pendingFrames = []
            self.panel.setFrame(target, display: true)
            self.panel.hasShadow = mode == .expanded
            self.panel.invalidateShadow()
        }
    }

    func expand() {
        guard island.mode != .expanded else { return }
        island.volume.refresh()
        haptic()
        show(.expanded, animation: Self.openAnimation, settle: 0.55)
    }

    func collapse() {
        island.editing = false
        setPinned(false)
        island.claude.markDoneSeen()
        show(baseMode, animation: Self.closeAnimation)
        if let seconds = pendingPeekSeconds { startPeekTimer(seconds) }
    }

    // MARK: Hover and pin

    private func mouseEntered() {
        guard !island.demo, !island.pinned, island.mode != .expanded else { return }
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250), tolerance: .milliseconds(30))
            guard !Task.isCancelled, let self else { return }
            self.expand()
        }
    }

    private func mouseExited() {
        hoverTask?.cancel()
        hoverTask = nil
        guard !island.demo, !island.pinned, island.mode == .expanded else { return }
        collapse()
    }

    func togglePin() {
        guard island.mode == .expanded else { return }
        setPinned(!island.pinned)
        haptic()
    }

    private func setPinned(_ pinned: Bool) {
        island.pinned = pinned
        if pinned, outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                Task { @MainActor in IslandController.shared?.outsideClick() }
            }
        } else if !pinned, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func outsideClick() {
        guard island.pinned, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    func toggleEdit() {
        withAnimation(Self.switchAnimation) { island.editing.toggle() }
        if island.editing {
            setPinned(true)
        } else if !island.demo {
            setPinned(false)
            if !panel.frame.contains(NSEvent.mouseLocation) { collapse() }
        }
    }

    func toggleTheme() {
        island.setTheme(island.palette.isDark ? .light : .dark)
    }

    func openMenu() {
        onOpenMenu?()
    }

    func spotify(_ command: SpotifyCommand) {
        // Wired to Spotify in step 7.
    }

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    // MARK: Compact and peeks

    func setCompact(_ content: CompactContent?) {
        island.compact = content
        if island.mode == .resting || island.mode == .compact {
            show(baseMode, animation: Self.switchAnimation)
        }
    }

    /// Closes the open island (if any) so the compact pill or a peek can be seen. Used by the dev commands.
    func closeIfExpanded() {
        if island.mode == .expanded { show(baseMode, animation: Self.closeAnimation) }
    }

    /// Shows one peek for `seconds`, then returns to the base mode. A new peek replaces the old one.
    /// While the island is open the peek waits and shows when the island closes.
    func showPeek(_ content: PeekContent, seconds: Double = 3) {
        peekTask?.cancel()
        peekTask = nil
        island.peek = content
        if island.mode == .expanded {
            pendingPeekSeconds = seconds
            return
        }
        show(.peek, animation: Self.switchAnimation)
        startPeekTimer(seconds)
    }

    private func startPeekTimer(_ seconds: Double) {
        pendingPeekSeconds = nil
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)), tolerance: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            self.peekTask = nil
            self.island.peek = nil
            if self.island.mode == .peek { self.show(self.baseMode, animation: Self.closeAnimation) }
        }
    }

    // MARK: Demo

    func toggleDemo() {
        if island.demo { stopDemo() } else { startDemo() }
    }

    private func startDemo() {
        holdDemo()
        demoStep = 0
        runDemoStep()
    }

    /// Demo state without the automatic cycling: sample data is shown and hover is off, for the dev commands.
    func holdDemo() {
        demoTask?.cancel()
        island.demo = true
        setPinned(false)
    }

    func stopDemo() {
        demoTask?.cancel()
        peekTask?.cancel()
        peekTask = nil
        pendingPeekSeconds = nil
        island.demo = false
        island.claude.setDemoSessions([])
        island.editing = false
        island.compact = nil
        island.peek = nil
        Demo.clear(island)
        show(.resting, animation: Self.closeAnimation)
    }

    func nextDemoStep() {
        guard island.demo else { return }
        demoTask?.cancel()
        runDemoStep()
    }

    private func runDemoStep() {
        let steps = Demo.steps
        steps[demoStep % steps.count](self)
        demoStep += 1
        demoTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2600), tolerance: .milliseconds(100))
            guard !Task.isCancelled, let self, self.island.demo else { return }
            self.runDemoStep()
        }
    }

    // MARK: Environment changes

    @objc private func screensChanged() {
        notch = NotchGeometry.current()
        island.notchSize = notch.size
        panel.setFrame(frame(for: island.mode), display: true)
    }

    @objc private func appearanceChanged() {
        island.appearanceDidChange()
    }

    @objc private func accessibilityChanged() {
        island.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
