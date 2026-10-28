import AppKit
import SwiftUI

/// Borderless, non-activating panel that never takes focus.
final class IslandPanel: NSPanel {
    /// Key only so the reply box can take typing; as a non-activating panel it never activates the app.
    override var canBecomeKey: Bool { true }
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
    private var hotKeys: HotKeys?
    private var launchpadMonitors: [Any] = []
    private var hotCornerMonitor: Any?
    private var hotCornerArmed = true
    /// The app that had the keyboard when the Launchpad opened; it gets it back when the Launchpad closes.
    private var launchpadPrevious: NSRunningApplication?
    /// Set by an outside click: the click itself picks the next app, so nothing is handed back.
    private var closingByClick = false
    private var swipeTurned = false
    private var peekSources: PeekSources?
    private var focusWatcher: FocusWatcher?
    private var peekQueue: [(PeekContent, Double)] = []
    private var recentPeekKeys: [String: Date] = [:]
    /// The Claude side panel on the right edge of the screen.
    let sidePanel: SidePanelController

    nonisolated(unsafe) private static weak var shared: IslandController?

    static let openAnimation = Animation.spring(response: 0.32, dampingFraction: 0.8)
    static let closeAnimation = Animation.easeInOut(duration: 0.22)
    static let switchAnimation = Animation.spring(response: 0.22, dampingFraction: 0.85)

    init(island: Island) {
        self.island = island
        island.notchSize = notch.size
        island.screenWidth = notch.screen.frame.width
        host = IslandHostView(frame: NSRect(origin: .zero, size: notch.size))
        hosting = HostingView(rootView: IslandRoot(island: island, actions: actions))
        panel = IslandPanel(contentRect: notch.rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        sidePanel = SidePanelController(island: island, actions: actions)
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

        island.spotifyModel.onChange = { [weak self] in
            guard let self, !self.island.demo else { return }
            self.island.spotify = self.island.spotifyModel.track
            self.refitIfOpen()
        }
        island.musicModel.onChange = { [weak self] in
            guard let self, !self.island.demo else { return }
            self.island.music = self.island.musicModel.track
            self.refitIfOpen()
        }
        island.weatherModel.onChange = { [weak self] in
            guard let self, !self.island.demo else { return }
            self.island.weather = self.island.weatherModel.now
            self.refitIfOpen()
        }
        island.calendarModel.onChange = { [weak self] in
            guard let self, !self.island.demo else { return }
            self.island.nextEvent = self.island.calendarModel.next
            if self.island.mode == .expanded { self.show(.expanded, animation: Self.switchAnimation) }
        }
        // The models may already have data from their init (calendar loads at once); copy it now.
        island.spotify = island.spotifyModel.track
        island.music = island.musicModel.track
        island.weather = island.weatherModel.now
        island.nextEvent = island.calendarModel.next
        island.claude.onPeek = { [weak self] content, seconds in self?.showPeek(content, seconds: seconds) }
        peekSources = PeekSources { [weak self] content, key in self?.showPeek(content, seconds: 3, key: key) }
        focusWatcher = FocusWatcher { [weak self] content, key in self?.showPeek(content, seconds: 3, key: key) }
        focusWatcher?.startIfPossible()
        island.claude.onChanged = { [weak self] in self?.claudeChanged() }
        island.claude.onCardsChanged = { [weak self] in self?.cardsChanged() }
        island.claude.onSessionEnded = { [weak self] id in
            guard let self else { return }
            self.sidePanel.forget(session: id)
            if self.island.panelSessionID == id { self.island.panelSessionID = nil; self.sidePanel.refresh(now: true) }
        }
        hotKeys = HotKeys(onAllow: { [weak self] in self?.answerFront(allow: true) },
                          onDeny: { [weak self] in self?.answerFront(allow: false) },
                          onLaunchpad: { [weak self] in self?.toggleLaunchpad() },
                          onPanel: { [weak self] in self?.sidePanel.toggle() })
        island.hotKeyAllow = hotKeys?.allow.display ?? island.hotKeyAllow
        island.hotKeyDeny = hotKeys?.deny.display ?? island.hotKeyDeny
        island.hotKeyLaunchpad = hotKeys?.launchpad.display ?? island.hotKeyLaunchpad
        island.hotKeyPanel = hotKeys?.panel.display ?? island.hotKeyPanel
        hotKeys?.registerLaunchpad()
        hotKeys?.registerPanel()
        setHotCorner(Settings.hotCorner)
        let socket = ClaudeSocket(onMessage: { [weak self] message in self?.island.claude.handle(message) },
                                  onRequestClosed: { [weak self] id in self?.island.claude.requestClosed(id) })
        island.claude.socket = socket
        do { try socket.start() } catch { Log.app.error("Socket failed: \(error.localizedDescription, privacy: .public)") }

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(appearanceChanged), name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    /// A tile or widget got data while the island is open: the open shape re-measures itself.
    private func refitIfOpen() {
        if island.mode == .expanded || island.mode == .launchpad { show(island.mode, animation: Self.switchAnimation) }
    }

    // MARK: Modes and frames

    private func frame(for mode: Island.Mode) -> NSRect {
        // Re-read the notch every time: screens come and go (external display, sleep) and a stale
        // centre would put the island off screen.
        let fresh = NotchGeometry.current()
        if fresh.rect != notch.rect { notch = fresh; island.notchSize = fresh.size }
        let size = island.contentSize(for: mode)
        return NSRect(x: notch.centerX - size.width / 2, y: notch.top - size.height, width: size.width, height: size.height)
    }

    /// The mode the island falls back to when nothing is open.
    private var baseMode: Island.Mode {
        if island.peek != nil { return .peek }
        if island.compactContent != nil { return .compact }
        return .resting
    }

    /// Claude sessions changed: refresh the pill, or the open island's size, and the side panel's conversation.
    private func claudeChanged() {
        sidePanel.refresh()
        if island.mode == .resting || island.mode == .compact {
            if island.mode != baseMode { show(baseMode, animation: Self.switchAnimation) }
        } else if island.mode == .expanded {
            show(.expanded, animation: Self.switchAnimation)
        }
    }

    /// A card arrived or the front one changed: open the island on it, keep it open, arm the shortcuts.
    private func cardsChanged() {
        island.cardIndex = 0
        if island.claude.frontCard != nil { hotKeys?.register() } else { hotKeys?.unregister() }
        if island.claude.frontCard != nil || island.claude.frontQuestion != nil {
            if island.mode != .expanded { show(.expanded, animation: Self.openAnimation, settle: 0.55); haptic() }
            else { show(.expanded, animation: Self.switchAnimation) }
            setPinned(true)
        } else {
            if island.mode == .expanded, !panel.frame.contains(NSEvent.mouseLocation) { collapse() }
            else if island.mode == .expanded { setPinned(false); show(.expanded, animation: Self.switchAnimation) }
        }
    }

    /// The menu opened: if Full Disk Access was granted since launch, the Focus watch can start now.
    func startFocusIfPossible() { focusWatcher?.startIfPossible() }

    /// Shortcuts changed in the menu: update the labels and re-register if a card is showing.
    func shortcutsChanged() {
        island.hotKeyAllow = hotKeys?.allow.display ?? island.hotKeyAllow
        island.hotKeyDeny = hotKeys?.deny.display ?? island.hotKeyDeny
        island.hotKeyLaunchpad = hotKeys?.launchpad.display ?? island.hotKeyLaunchpad
        island.hotKeyPanel = hotKeys?.panel.display ?? island.hotKeyPanel
        if island.claude.frontCard != nil { hotKeys?.register() }
        hotKeys?.registerLaunchpad()
        hotKeys?.registerPanel()
    }

    // MARK: Launchpad

    func toggleLaunchpad() {
        if island.mode == .launchpad { collapse() } else { openLaunchpad() }
    }

    /// The big grid of apps hanging from the notch. The panel takes the keyboard for the search field
    /// without activating Cove; the app you were in stays in front and gets the keys back on close.
    func openLaunchpad() {
        guard island.mode != .launchpad else { return }
        hoverTask?.cancel()
        island.launchpadQuery = ""
        island.launchpadPage = 0
        island.launchpadFolder = nil
        island.replyingTo = nil; island.notingFor = nil; island.editing = false
        launchpadPrevious = NSWorkspace.shared.frontmostApplication
        if !island.demo {
            island.toggles.refresh()
            island.volume.refresh()
            island.brightness.refresh()
            island.spotifyModel.islandOpened()
            island.musicModel.visible = true
            island.musicModel.islandOpened()
            island.weatherModel.islandOpened()
        }
        haptic()
        show(.launchpad, animation: Self.openAnimation, settle: 0.55)
        setPinned(true)
        panel.makeKey()
        installLaunchpadMonitors()
    }

    /// Enter in the search field, or a click on an icon.
    func launch(_ app: AppEntry) {
        haptic()
        island.apps.open(app)
        launchpadPrevious = nil   // the app just opened should keep the keyboard, not the one before
        collapse()
    }

    func launchFirst() {
        if let app = island.launchpadApps.first { launch(app) }
    }

    /// Esc: clears the search first, then leaves an open folder, then closes.
    func launchpadEscape() {
        if !island.launchpadQuery.isEmpty { island.launchpadQuery = ""; island.launchpadPage = 0 }
        else if island.launchpadFolder != nil { openFolder(nil) }
        else { collapse() }
    }

    /// The "By category" button: folders on or off (remembered).
    func toggleCategories() {
        haptic()
        withAnimation(Self.switchAnimation) {
            island.launchpadCategories.toggle()
            island.launchpadFolder = nil
            island.launchpadPage = 0
        }
    }

    /// A folder's icons, or the back arrow (nil).
    func openFolder(_ category: AppCategory?) {
        withAnimation(Self.switchAnimation) {
            island.launchpadFolder = category
            island.launchpadPage = 0
        }
    }

    func launchpadStep(_ delta: Int) {
        let count = island.launchpadPageCount
        guard count > 1 else { return }
        withAnimation(Self.switchAnimation) { island.launchpadPage = (island.launchpadPage + delta + count) % count }
    }

    /// Two-finger swipe turns a page; one page per gesture.
    private func installLaunchpadMonitors() {
        removeLaunchpadMonitors()
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self, self.island.mode == .launchpad else { return event }
            if event.phase == .began || event.momentumPhase == .began { self.swipeTurned = false }
            if !self.swipeTurned, abs(event.scrollingDeltaX) > 25, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                self.swipeTurned = true
                self.launchpadStep(event.scrollingDeltaX < 0 ? 1 : -1)
            }
            return event
        }) { launchpadMonitors.append(m) }
    }

    private func removeLaunchpadMonitors() {
        launchpadMonitors.forEach(NSEvent.removeMonitor)
        launchpadMonitors = []
    }

    /// Hot corner (top-left of the notch screen) opens the Launchpad; it re-arms once the mouse has left the corner.
    func setHotCorner(_ on: Bool) {
        if on, hotCornerMonitor == nil {
            // Global monitor handlers run on the main thread; no hop, no allocation per mouse move.
            hotCornerMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
                if Thread.isMainThread { MainActor.assumeIsolated { IslandController.shared?.mouseMovedForCorner() } }
                else { Task { @MainActor in IslandController.shared?.mouseMovedForCorner() } }
            }
        } else if !on, let monitor = hotCornerMonitor {
            NSEvent.removeMonitor(monitor)
            hotCornerMonitor = nil
        }
    }

    private func mouseMovedForCorner() {
        let frame = notch.screen.frame
        let loc = NSEvent.mouseLocation
        let inCorner = loc.x <= frame.minX + 2 && loc.y >= frame.maxY - 2
        if inCorner, hotCornerArmed {
            hotCornerArmed = false
            if island.mode != .launchpad { openLaunchpad() }
        } else if !inCorner, loc.x > frame.minX + 30 || loc.y < frame.maxY - 30 {
            hotCornerArmed = true
        }
    }

    private func answerFront(allow: Bool) {
        guard let card = island.displayedCard else { return }
        answer(card, allow: allow)
    }

    /// × on a card, or ‹ › between the sessions needing you.
    func dismissCard(_ session: ClaudeSession) {
        island.claude.dismiss(session)
        island.cardIndex = 0
        show(.expanded, animation: Self.switchAnimation)
    }

    func stepCard(_ delta: Int) {
        let count = island.claude.attentionQueue.count
        guard count > 1 else { return }
        island.cardIndex = (island.cardIndex + delta + count) % count
        island.claude.frontCardShownAt = Date()
        island.claude.frontCardFullySeen = false
        show(.expanded, animation: Self.switchAnimation)
    }

    /// Allow or Deny from a button or shortcut, on the island's card or the side panel's. Ignored for 400 ms after
    /// a card appears or moves on. `seen` is the panel's own "scrolled to the end" for a long command; the island's
    /// card tracks that in the model.
    func answer(_ card: PermissionCard, allow: Bool, message: String? = nil, seen: Bool? = nil) {
        let onIsland = island.displayedCard?.id == card.id
        let onPanel = island.panelOpen && island.panelSession?.id == card.sessionID && island.claude.card(for: island.panelSession!)?.id == card.id
        guard onIsland || onPanel else { return }
        let guarded = card.id == island.claude.frontCard?.id ? island.claude.frontCardGuarded
            : Date().timeIntervalSince(card.received) < ClaudeModel.guardSeconds
        guard !guarded else { return }
        if allow, !card.isPlan, Island.isLong(card.command), !(seen ?? island.claude.frontCardFullySeen) { return }
        haptic()
        island.claude.answer(card, allow: allow, message: message)
        let word = card.isPlan ? (allow ? "Plan approved" : "Keep planning") : (allow ? "Allowed" : "Denied")
        island.claude.session(card.sessionID)?.lastAnswerWord = word
        let content = card.isPlan
            ? (allow ? PeekContent(symbol: "checkmark", icon: nil, tint: .done, word: word, second: nil)
                     : PeekContent(symbol: "arrow.uturn.left", icon: nil, tint: .needsYou, word: word, second: nil))
            : (allow ? PeekContent(symbol: "checkmark", icon: nil, tint: .done, word: word, second: nil)
                     : PeekContent(symbol: "xmark", icon: nil, tint: .blocked, word: word, second: nil))
        if island.claude.frontCard == nil { showPeek(content, seconds: 1.5) }
    }

    /// An answer picked on a question card: back through the waiting hook, and Claude carries on with it.
    func answerQuestion(_ card: QuestionCard, answers: [String: String]) {
        let onPanel = island.panelOpen && island.panelSession.flatMap { island.claude.question(for: $0) }?.id == card.id
        guard !island.claude.frontCardGuarded, island.displayedQuestion?.id == card.id || onPanel else { return }
        haptic()
        island.claude.answer(card, answers: answers)
        island.claude.session(card.sessionID)?.lastAnswerWord = "Answered"
        Log.app.notice("Question answered from the island")
        if island.claude.frontCard == nil, island.claude.frontQuestion == nil {
            showPeek(PeekContent(symbol: "checkmark", icon: nil, tint: .done, word: "Answered", second: nil), seconds: 1.5)
        }
    }

    /// A reply typed on the card. Through the waiting hook if Claude just stopped, else typed into the app.
    func sendReply(_ text: String, to session: ClaudeSession) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        haptic()
        island.replyingTo = nil; island.notingFor = nil
        let previous = NSWorkspace.shared.frontmostApplication
        if island.claude.replyThroughHook(session, text: trimmed) {
            Log.app.notice("Reply delivered through the Stop hook")
            island.replyStatus = "Sent"
            collapse()
            Self.handBack(to: previous)
            return
        }
        island.replyStatus = "Typing it into the app…"
        collapse()
        Task { [weak self] in
            guard let self else { return }
            if let problem = await Typist.deliver(trimmed, to: session) {
                Log.app.error("Reply not typed: \(problem, privacy: .public)")
                self.island.replyStatus = problem
                self.showPeek(PeekContent(symbol: "exclamationmark.triangle", icon: nil, tint: .needsYou, word: "Reply not sent", second: String(problem.prefix(60))), seconds: 4)
            } else {
                Log.app.notice("Reply typed into the Claude app")
                self.island.replyStatus = nil
                session.lastMessage = nil
                session.doneSeen = true
                self.island.claude.markDoneSeen()
                // Hand the screen back to what James was doing.
                if let previous, previous.bundleIdentifier != Typist.claudeBundle {
                    try? await Task.sleep(for: .milliseconds(400))
                    Self.handBack(to: previous)
                }
            }
        }
    }

    func rowClicked(_ session: ClaudeSession) {
        island.claude.releaseQuestion(for: session)   // Open on a question: Claude asks in the app instead
        island.claude.bringForward(session)
        collapse()
    }

    /// Grows the panel to cover old and new, animates the content, then tightens the frame when the animation is done.
    func show(_ mode: Island.Mode, animation: Animation?, settle: Double = 0.4) {
        tightenTask?.cancel()
        if mode != .expanded, mode != .launchpad { setPinned(false) }
        if island.mode == .launchpad, mode != .launchpad { leaveLaunchpad() }
        let target = frame(for: mode)
        if pendingFrames.isEmpty { pendingFrames = [panel.frame] }
        pendingFrames.append(target)
        let union = pendingFrames.dropFirst().reduce(pendingFrames[0]) { $0.union($1) }
        if union != panel.frame { panel.setFrame(union, display: true) }
        if mode == .expanded || mode == .launchpad { panel.hasShadow = true }
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
            self.panel.hasShadow = mode == .expanded || mode == .launchpad
            self.panel.invalidateShadow()
        }
    }

    /// Leaving the Launchpad for any other mode: drop its monitors and hand the keyboard back, unless a click
    /// on another app closed it (that click picks the next app).
    private func leaveLaunchpad() {
        removeLaunchpadMonitors()
        island.musicModel.visible = false
        island.launchpadQuery = ""
        panel.makeFirstResponder(nil)
        if !closingByClick { Self.handBack(to: launchpadPrevious) }
        launchpadPrevious = nil
    }

    /// Makes `previous` the key app again (Cove, non-activating, can hold the keyboard while that app stays in front).
    /// Nothing happens for Cove itself or for an app that has quit since: launching it again would be a surprise.
    static func handBack(to previous: NSRunningApplication?) {
        guard let previous, previous != NSRunningApplication.current, !previous.isTerminated, let url = previous.bundleURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// `byHover` is a real mouse-over; only then may a first-time permission prompt (Calendar) appear.
    func expand(byHover: Bool = false) {
        guard island.mode != .expanded, island.mode != .launchpad else { return }
        island.volume.refresh()
        if !island.demo {
            island.spotifyModel.islandOpened()
            island.weatherModel.islandOpened()
            if byHover, !island.hidden.contains(.calendar) { island.calendarModel.requestIfNeeded() }
        }
        haptic()
        show(.expanded, animation: Self.openAnimation, settle: 0.55)
    }

    /// Opens or closes the reply line under a row; the island stays open while it is showing.
    /// Right-click → note: a line under the row to type it; Return keeps it on the row until the session ends.
    func editNote(for session: ClaudeSession) {
        island.replyingTo = nil
        island.notingFor = session.id
        setPinned(true)
        show(.expanded, animation: Self.switchAnimation)
    }

    func setNote(_ text: String?, for session: ClaudeSession) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        session.note = trimmed.isEmpty ? nil : trimmed
        island.notingFor = nil
        island.claude.onChanged?()
        show(.expanded, animation: Self.switchAnimation)
    }

    func toggleReply(for session: ClaudeSession) {
        if island.replyingTo == session.id { island.replyingTo = nil } else { island.replyingTo = session.id; setPinned(true) }
        show(.expanded, animation: Self.switchAnimation)
    }

    func collapse() {
        island.editing = false
        island.replyingTo = nil; island.notingFor = nil
        setPinned(false)
        panel.makeFirstResponder(nil)
        island.claude.markDoneSeen()
        for s in island.claude.sessions where s.replyRequestID != nil && s.doneSeen { island.claude.closeReply(s) }
        show(baseMode, animation: Self.closeAnimation)
        if let seconds = pendingPeekSeconds { startPeekTimer(seconds) }
    }

    // MARK: Hover and pin

    private func mouseEntered() {
        guard !island.demo, !island.pinned, island.mode != .expanded, island.mode != .launchpad else { return }
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200), tolerance: .milliseconds(30))
            guard !Task.isCancelled, let self else { return }
            self.expand(byHover: true)
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
        closingByClick = true
        collapse()
        closingByClick = false
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

    /// The ◐ button cycles Dark → Light → Glass.
    func toggleTheme() {
        switch island.themeMode {
        case .dark: island.setTheme(.light)
        case .light, .system: island.setTheme(.glass)
        case .glass: island.setTheme(.dark)
        }
    }

    func openMenu() {
        onOpenMenu?()
    }

    func spotify(_ command: SpotifyCommand) {
        guard !island.demo else { return }
        island.spotifyModel.send(command)
    }

    /// The Now playing widget's buttons go to whichever player is showing.
    func nowPlaying(_ command: SpotifyCommand) {
        guard !island.demo else { return }
        if island.nowPlayingIsSpotify { island.spotifyModel.send(command) } else { island.musicModel.send(command) }
    }

    /// The Calendar tile: the event opens in Calendar and the island closes.
    func openCalendarEvent() {
        guard !island.demo else { return }
        haptic()
        island.calendarModel.openNext()
        collapse()
    }

    func toggleWidget(_ widget: LaunchpadWidget) {
        island.setWidget(widget, shown: island.hiddenWidgets.contains(widget))
        if island.mode == .launchpad { show(.launchpad, animation: Self.switchAnimation) }
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

    /// Shows one peek for `seconds`, then returns to the base mode. One peek at a time: a new one waits its turn.
    /// The same `key` within 5 s counts as one peek. While the island is open the peek waits and shows when it closes.
    func showPeek(_ content: PeekContent, seconds: Double = 3, key: String? = nil) {
        if let key {
            if let last = recentPeekKeys[key], Date().timeIntervalSince(last) < 5 { return }
            recentPeekKeys[key] = Date()
            if recentPeekKeys.count > 50 { recentPeekKeys = recentPeekKeys.filter { Date().timeIntervalSince($0.value) < 5 } }
        }
        if peekTask != nil || ((island.mode == .expanded || island.mode == .launchpad) && island.peek != nil) {
            if peekQueue.count < 4 { peekQueue.append((content, seconds)) }
            return
        }
        peekTask?.cancel()
        peekTask = nil
        island.peek = content
        if Settings.sound { NSSound(named: "Pop")?.play() }
        if island.mode == .expanded || island.mode == .launchpad {
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
            if !self.peekQueue.isEmpty {
                let (next, seconds) = self.peekQueue.removeFirst()
                try? await Task.sleep(for: .milliseconds(350))
                self.showPeek(next, seconds: seconds)
            }
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
        island.claude.endDemo()
        island.music = island.musicModel.track
        island.spotify = island.spotifyModel.track
        island.weather = island.weatherModel.now
        island.nextEvent = island.calendarModel.next
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
        island.screenWidth = notch.screen.frame.width
        panel.setFrame(frame(for: island.mode), display: true)
        sidePanel.layout()
    }

    @objc private func appearanceChanged() {
        island.appearanceDidChange()
    }

    @objc private func accessibilityChanged() {
        island.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
