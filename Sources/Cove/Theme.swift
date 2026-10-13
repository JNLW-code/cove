import AppKit

/// Which look the island uses. `system` follows the macOS appearance.
enum ThemeMode: String, CaseIterable, Sendable {
    case dark, light, system
}

/// Every colour and font the app draws comes from here. Colours are macOS system colours,
/// resolved through the chosen appearance so the island theme is independent of macOS's own.
/// Colour set "B Lifted" from the mockup.
@MainActor
enum Theme {
    static var mode: ThemeMode = .dark

    /// The appearance colours are resolved through.
    static var appearance: NSAppearance {
        switch mode {
        case .dark: return NSAppearance(named: .darkAqua) ?? NSApp.effectiveAppearance
        case .light: return NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance
        case .system: return NSApp.effectiveAppearance
        }
    }

    static var isDark: Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// The other appearance, used for the Allow pill so it always stands out.
    private static var opposite: NSAppearance {
        NSAppearance(named: isDark ? .aqua : .darkAqua) ?? appearance
    }

    private static let darkAqua = NSAppearance(named: .darkAqua)

    // MARK: Fills

    static var island: NSColor { resolve(isDark ? .underPageBackgroundColor : .windowBackgroundColor) }
    static var tile: NSColor { blend(resolve(.secondarySystemFill), over: island) }
    static var rim: NSColor { resolve(.separatorColor) }
    static var deny: NSColor { resolve(.unemphasizedSelectedContentBackgroundColor) }
    static var allowBackground: NSColor { resolve(.windowBackgroundColor, in: opposite) }
    static var allowText: NSColor { resolve(.labelColor, in: opposite) }
    /// The real notch and every peek/pill are this.
    static let black = NSColor.black

    // MARK: Text

    static var label: NSColor { resolve(.labelColor) }
    static var secondaryLabel: NSColor { resolve(.secondaryLabelColor) }
    static var tertiaryLabel: NSColor { resolve(.tertiaryLabelColor) }
    static var quaternaryLabel: NSColor { resolve(.quaternaryLabelColor) }

    // MARK: Accent and status

    static var accent: NSColor { resolve(.controlAccentColor) }
    static var needsYou: NSColor { resolve(.systemOrange) }
    static var done: NSColor { resolve(.systemGreen) }
    static var blocked: NSColor { resolve(.systemRed) }
    static var focus: NSColor { resolve(.systemIndigo) }

    /// Anything drawn on the black notch shape uses dark-appearance colours in both themes.
    static func onBlack(_ color: NSColor) -> NSColor { resolve(color, in: darkAqua) }

    // MARK: Fonts (SF Pro; digits are monospaced so numbers never jitter)

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func digits(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: Resolution

    static func resolve(_ color: NSColor, in appearance: NSAppearance? = nil) -> NSColor {
        var out = color
        (appearance ?? Self.appearance).performAsCurrentDrawingAppearance {
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
