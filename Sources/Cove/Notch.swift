import AppKit

/// Where the notch is, in screen coordinates (origin bottom-left, like AppKit).
struct NotchGeometry {
    let screen: NSScreen
    let rect: NSRect
    /// False when no screen has a notch; then a fake one is drawn at the top centre.
    let isReal: Bool

    var centerX: CGFloat { rect.midX }
    var top: CGFloat { rect.maxY }
    var size: CGSize { rect.size }

    @MainActor static func current() -> NotchGeometry {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let height = screen.safeAreaInsets.top
            let rect = NSRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height)
            return NotchGeometry(screen: screen, rect: rect, isReal: true)
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 179, height: CGFloat = 32
        let rect = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        return NotchGeometry(screen: screen, rect: rect, isReal: false)
    }
}
