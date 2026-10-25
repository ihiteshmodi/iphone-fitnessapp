import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Dark theme with green accents, matching the approved mockups.
enum Theme {
    static let background = Color(hex: 0x0A0C0B)
    static let card = Color(hex: 0x141816)
    static let card2 = Color(hex: 0x1B211E)
    static let line = Color(hex: 0x232A26)
    static let text = Color(hex: 0xF2F5F3)
    static let muted = Color(hex: 0x8A9690)
    static let green = Color(hex: 0x2EE887)
    static let greenSoft = Color(hex: 0x8AF0BD)
    static let greenDeep = Color(hex: 0x2A8A5C)
    static let amber = Color(hex: 0xF5C542)
    static let red = Color(hex: 0xFF6B6B)
    static let onGreen = Color(hex: 0x04130A)
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 14
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? Theme.green.opacity(0.10) : Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(highlighted ? Theme.green.opacity(0.35) : Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

extension View {
    func card(padding: CGFloat = 14, highlighted: Bool = false) -> some View {
        modifier(CardStyle(padding: padding, highlighted: highlighted))
    }

    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(0.6)
            .foregroundColor(Theme.muted)
    }
}

struct Pill: View {
    enum Tone { case green, amber, red, grey }
    let text: String
    var tone: Tone = .green

    private var colors: (fg: Color, bg: Color) {
        switch tone {
        case .green: return (Theme.green, Theme.green.opacity(0.15))
        case .amber: return (Theme.amber, Theme.amber.opacity(0.15))
        case .red: return (Theme.red, Theme.red.opacity(0.15))
        case .grey: return (Theme.muted, Theme.card2)
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(colors.fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(colors.bg)
            .clipShape(Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var ghost = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(ghost ? Theme.green : Theme.onGreen)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(ghost ? Theme.card2 : Theme.green)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ghost ? Theme.line : .clear, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
