import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Colour

extension Color {
    /// A colour that resolves differently in light and dark, so every surface in the
    /// app adapts without a single `colorScheme` check at the call site.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        self.init(hex: light)
        #endif
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

/// The design tokens from the approved screens. Light values first, dark second —
/// the same pairing the mockups use, so a change here moves both themes together.
enum Tokens {
    static let background    = Color(light: 0xFAF7F2, dark: 0x12100E)
    static let card          = Color(light: 0xFFFFFF, dark: 0x1C1917)
    static let cardRecessed  = Color(light: 0xF4EFE7, dark: 0x171513)
    static let border        = Color(light: 0xE8E1D6, dark: 0x2A2724)
    static let divider       = Color(light: 0xF0EAE0, dark: 0x262220)

    static let textPrimary   = Color(light: 0x1A1714, dark: 0xF7F3EE)
    static let textSecondary = Color(light: 0x4A443C, dark: 0xC9C0B7)
    static let textTertiary  = Color(light: 0x6F665C, dark: 0x9A928A)
    static let textMuted     = Color(light: 0x7D746A, dark: 0x8A8279)
    static let textFaint     = Color(light: 0x938A7E, dark: 0x6E665F)

    /// Amber has two jobs: a fill you put dark ink on, and a text/icon tone that has
    /// to survive on white. They are deliberately different values in light mode.
    static let accentFill    = Color(light: 0xE8940F, dark: 0xFFB03A)
    static let accentText    = Color(light: 0xB0710A, dark: 0xFFB03A)
    static let accentSurface = Color(light: 0xFFF4E0, dark: 0x241C12)
    static let accentBorder  = Color(light: 0xF0DFC0, dark: 0x3A2C18)
    static let accentLabel   = Color(light: 0x9A6A0C, dark: 0xC79A55)
    static let inkOnAccent   = Color(light: 0x23201C, dark: 0x12100E)

    static let track         = Color(light: 0xE3DBCE, dark: 0x332D28)
    static let thumbBorder   = Color(light: 0xE0D8CB, dark: 0x332D28)

    /// Warm radial wash behind the ringing and Lock Screen presentations.
    static func ringingBackground(_ scheme: ColorScheme) -> RadialGradient {
        let stops: [Gradient.Stop] = scheme == .dark
            ? [.init(color: Color(hex: 0x2A1C0C), location: 0),
               .init(color: Color(hex: 0x16110C), location: 0.58),
               .init(color: Color(hex: 0x0D0B09), location: 1)]
            : [.init(color: Color(hex: 0xFFEFD4), location: 0),
               .init(color: Color(hex: 0xFBF5EB), location: 0.58),
               .init(color: Color(hex: 0xF5EFE5), location: 1)]
        return RadialGradient(
            gradient: Gradient(stops: stops),
            center: UnitPoint(x: 0.5, y: 0.34),
            startRadius: 0,
            endRadius: 520
        )
    }
}

// MARK: - Typography

/// Set `useBundledFonts` to true once Bricolage Grotesque and Instrument Sans are
/// added to the target and listed under `UIAppFonts`. Until then the app renders in
/// the system face — correct proportions, no missing-font surprises.
enum Typo {
    static var useBundledFonts = false

    private static let displayFace = "BricolageGrotesque-SemiBold"
    private static let bodyFace = "InstrumentSans-Regular"
    private static let bodyFaceSemibold = "InstrumentSans-SemiBold"

    /// Every font is declared `relativeTo:` a text style, which is what makes the
    /// whole app scale with the reader's Dynamic Type setting.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        useBundledFonts
            ? .custom(displayFace, size: size, relativeTo: style)
            : .system(style, design: .default).weight(.semibold)
    }

    static func body(_ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        let heavy: Set<Font.Weight> = [.semibold, .bold, .heavy, .black]
        return useBundledFonts
            ? .custom(heavy.contains(weight) ? bodyFaceSemibold : bodyFace, size: size, relativeTo: style)
            : .system(style).weight(weight)
    }

    /// Section headers: small, tracked, uppercase.
    static var sectionLabel: Font { body(10, relativeTo: .caption2, weight: .bold) }
    static var rowLabel: Font { body(15, relativeTo: .subheadline) }
    static var rowValue: Font { body(15, relativeTo: .subheadline, weight: .semibold) }
    static var caption: Font { body(12, relativeTo: .caption, weight: .regular) }
}

// MARK: - Metrics

enum Metrics {
    /// Apple's minimum comfortable hit target. Nothing tappable goes below this.
    static let minTapTarget: CGFloat = 44
    static let rowHeight: CGFloat = 48
    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 16
    static let gutter: CGFloat = 20

    /// On iPad and landscape iPhone a full-bleed form looks stretched, so content
    /// is capped and centred rather than reflowed into an unfamiliar layout.
    static let readableWidth: CGFloat = 620
}

// MARK: - Shared modifiers

private struct ReadableWidth: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: Metrics.readableWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Caps the content column so the layout stays legible from iPhone SE to iPad Pro.
    func readableWidth() -> some View { modifier(ReadableWidth()) }

    /// A card surface matching the mockups.
    func cardSurface(radius: CGFloat = Metrics.cardRadius, tinted: Bool = false) -> some View {
        background(tinted ? Tokens.accentSurface : Tokens.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tinted ? Tokens.accentBorder : Tokens.border, lineWidth: 1)
            )
    }
}
