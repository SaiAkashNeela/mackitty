import SwiftUI

/// MacKitty design tokens: a calm, light, professional system.
/// Neutral greys carry the layout; a single teal accent (taken from the mint
/// rim-light in the app icon) marks primary actions and live state.
enum Theme {
    // Canvas
    static let canvas = Color(red: 0.961, green: 0.961, blue: 0.969)       // #F5F5F7
    static let canvasDeep = Color(red: 0.925, green: 0.925, blue: 0.937)   // #ECECEF
    static let card = Color.white
    static let ink = Color(red: 0.067, green: 0.075, blue: 0.098)          // #111319

    // Accent & signal
    static let accent = Color(red: 0.051, green: 0.580, blue: 0.533)       // #0D9488
    static let accentStrong = Color(red: 0.059, green: 0.463, blue: 0.431) // #0F766E
    static let accentSoft = Color(red: 0.051, green: 0.580, blue: 0.533).opacity(0.10)
    static let success = Color(red: 0.086, green: 0.639, blue: 0.290)      // #16A34A
    static let warning = Color(red: 0.851, green: 0.467, blue: 0.024)      // #D97706
    static let danger = Color(red: 0.863, green: 0.149, blue: 0.149)       // #DC2626
    static let info = Color(red: 0.145, green: 0.388, blue: 0.922)         // #2563EB
    static let violet = Color(red: 0.486, green: 0.227, blue: 0.929)       // #7C3AED
    static let rose = Color(red: 0.882, green: 0.114, blue: 0.282)         // #E11D48

    // Text & lines
    static let textPrimary = ink
    static let textSecondary = ink.opacity(0.62)
    static let textTertiary = ink.opacity(0.44)
    static let surface = ink.opacity(0.035)
    static let surfaceHover = ink.opacity(0.06)
    static let line = ink.opacity(0.08)
    static let lineStrong = ink.opacity(0.14)

    static let categoryPalette: [Color] = [accent, info, violet, warning, Color(red: 0.39, green: 0.45, blue: 0.55)]

    static func category(_ index: Int) -> Color { categoryPalette[index % categoryPalette.count] }

    // Type: SF Pro throughout; mono only for paths and byte counts.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func numeric(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// Section label: small, medium weight, secondary colour.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.textTertiary

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
    }
}

/// White card with a hairline border and a barely-there shadow.
struct CardPanel: ViewModifier {
    var radius: CGFloat = 12
    var tint: Color = .clear

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint.opacity(0.06)))
                    .shadow(color: Theme.ink.opacity(0.04), radius: 2, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            }
    }
}

extension View {
    func glassPanel(radius: CGFloat = 12, tint: Color = .clear) -> some View {
        modifier(CardPanel(radius: radius, tint: tint))
    }
}

/// Primary action: solid accent, white label.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Theme.accentStrong : tint)
            )
            .shadow(color: Theme.ink.opacity(isEnabled ? 0.10 : 0), radius: 1, y: 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary action: white with hairline.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(12.5, .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Theme.canvasDeep : Theme.card)
            )
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
