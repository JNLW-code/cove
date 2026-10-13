import AppKit
import SwiftUI

/// Which look the island uses. `system` follows the macOS appearance.
enum ThemeMode: String, CaseIterable, Sendable {
    case dark, light, system
}

/// Status tints. Working = accent, needs you = orange, done = green, blocked = red, focus = indigo (Do Not Disturb).
enum Tint: Sendable {
    case accent, needsYou, done, blocked, focus
}

/// Every colour the island draws, resolved for one theme. Colour set "B Lifted" from the mockup.
struct Palette {
    let isDark: Bool
    let island, tile, rim, deny, allowBackground, allowText: Color
    let label, secondaryLabel, tertiaryLabel, quaternaryLabel: Color
    let accent, needsYou, done, blocked, focus: Color
    /// Anything drawn on the black notch shape uses these (dark appearance) in both themes.
    let onBlackLabel, onBlackSecondary, onBlackTertiary, onBlackQuaternary: Color

    func color(_ tint: Tint) -> Color {
        switch tint {
        case .accent: accent
        case .needsYou: needsYou
        case .done: done
        case .blocked: blocked
        case .focus: focus
        }
    }
}

/// All colour and font lookups live here. Colours are macOS system colours, resolved through the
/// chosen NSAppearance so the island theme is independent of macOS's own appearance.
@MainActor
enum Theme {
    static func appearance(for mode: ThemeMode) -> NSAppearance {
        switch mode {
        case .dark: NSAppearance(named: .darkAqua) ?? NSApp.effectiveAppearance
        case .light: NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance
        case .system: NSApp.effectiveAppearance
        }
    }

    static func palette(_ mode: ThemeMode) -> Palette {
        let app = appearance(for: mode)
        let isDark = app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let dark = NSAppearance(named: .darkAqua) ?? app
        let opposite = NSAppearance(named: isDark ? .aqua : .darkAqua) ?? app
        func c(_ color: NSColor, _ a: NSAppearance = app) -> Color { Color(nsColor: resolve(color, in: a)) }
        let islandColor = resolve(isDark ? .underPageBackgroundColor : .windowBackgroundColor, in: app)
        return Palette(
            isDark: isDark,
            island: Color(nsColor: islandColor),
            tile: Color(nsColor: blend(resolve(.secondarySystemFill, in: app), over: islandColor)),
            rim: c(.separatorColor),
            deny: c(.unemphasizedSelectedContentBackgroundColor),
            allowBackground: c(.windowBackgroundColor, opposite),
            allowText: c(.labelColor, opposite),
            label: c(.labelColor), secondaryLabel: c(.secondaryLabelColor),
            tertiaryLabel: c(.tertiaryLabelColor), quaternaryLabel: c(.quaternaryLabelColor),
            accent: c(.controlAccentColor), needsYou: c(.systemOrange), done: c(.systemGreen),
            blocked: c(.systemRed), focus: c(.systemIndigo),
            onBlackLabel: c(.labelColor, dark), onBlackSecondary: c(.secondaryLabelColor, dark),
            onBlackTertiary: c(.tertiaryLabelColor, dark), onBlackQuaternary: c(.quaternaryLabelColor, dark)
        )
    }

    // MARK: Fonts (SF Pro; digits are monospaced so numbers never jitter)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func digits(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }

    // MARK: Resolution

    static func resolve(_ color: NSColor, in appearance: NSAppearance) -> NSColor {
        var out = color
        appearance.performAsCurrentDrawingAppearance {
            out = color.usingColorSpace(.sRGB) ?? color
        }
        return out
    }

    /// Composites a translucent system fill over a solid base so the result is a solid colour.
    static func blend(_ top: NSColor, over base: NSColor) -> NSColor {
        guard let t = top.usingColorSpace(.sRGB), let b = base.usingColorSpace(.sRGB) else { return base }
        let a = t.alphaComponent
        return NSColor(srgbRed: t.redComponent * a + b.redComponent * (1 - a),
                       green: t.greenComponent * a + b.greenComponent * (1 - a),
                       blue: t.blueComponent * a + b.blueComponent * (1 - a),
                       alpha: 1)
    }
}
