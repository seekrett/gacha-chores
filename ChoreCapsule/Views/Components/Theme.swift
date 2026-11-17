import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    func adjusted(brightness delta: CGFloat) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(hue: h, saturation: s, brightness: min(1, max(0, b + delta)), opacity: a)
    }
}

enum Palette {
    static let berry = Color(hex: 0xE2508B)
    static let pink = Color(hex: 0xFF9EC4)
    static let lavender = Color(hex: 0xB8A4FF)
    static let mint = Color(hex: 0x7FDDC4)
    static let sky = Color(hex: 0x8CC8FF)
    static let gold = Color(hex: 0xFFC845)
    static let peach = Color(hex: 0xFFB38A)
    static let ink = Color(hex: 0x3A2C4E)
    static let sparks = Color(hex: 0xF5A300)
    static let glitter = Color(hex: 0x9C7BFF)
    static let ticket = Color(hex: 0xF0609A)
    static let rainbow: [Color] = [Color(hex: 0xFF8FB8), Color(hex: 0xFFD66B), Color(hex: 0x8AF0C0), Color(hex: 0x8CC8FF), Color(hex: 0xC59BFF)]
}

extension Currency {
    var icon: String {
        switch self {
        case .sparks: "sparkle"
        case .glitter: "diamond.fill"
        case .tickets: "ticket.fill"
        }
    }

    var color: Color {
        switch self {
        case .sparks: Palette.sparks
        case .glitter: Palette.glitter
        case .tickets: Palette.ticket
        }
    }

    var name: String {
        switch self {
        case .sparks: "Sparks"
        case .glitter: "Glitter"
        case .tickets: "Tickets"
        }
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [Palette.pink.opacity(0.22), Palette.lavender.opacity(0.14), .clear],
                           startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct CurrencyPill: View {
    let currency: Currency
    let amount: Int
    var big = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: currency.icon)
            Text(amount, format: .number)
                .contentTransition(.numericText(value: Double(amount)))
                .monospacedDigit()
        }
        .font(big ? .title3.bold() : .subheadline.bold())
        .padding(.horizontal, big ? 14 : 10)
        .padding(.vertical, big ? 8 : 5)
        .background(Capsule().fill(currency.color.opacity(0.16)))
        .foregroundStyle(currency.color)
        .animation(.snappy, value: amount)
    }
}

struct BalanceBar: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        HStack(spacing: 8) {
            CurrencyPill(currency: .sparks, amount: store.state.sparks)
            CurrencyPill(currency: .tickets, amount: store.state.tickets)
            CurrencyPill(currency: .glitter, amount: store.state.glitter)
            Spacer(minLength: 0)
        }
    }
}

struct Tag: View {
    let text: String
    var icon: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .lineLimit(1)
        .fixedSize()
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .foregroundStyle(color)
    }
}

struct BubblyButtonStyle: ButtonStyle {
    var color: Color = Palette.berry

    func makeBody(configuration: Configuration) -> some View {
        BubblyBody(configuration: configuration, color: color)
    }

    private struct BubblyBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color.gradient))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.18))
                        .frame(height: 10)
                        .padding(.horizontal, 10)
                        .padding(.top, 3)
                }
                .shadow(color: color.opacity(0.35), radius: configuration.isPressed ? 2 : 8, y: configuration.isPressed ? 1 : 4)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

struct RarityBadge: View {
    let rarity: Rarity
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<rarity.stars, id: \.self) { _ in
                Image(systemName: "star.fill").font(.system(size: 8, weight: .bold))
            }
            Text(rarity.label.uppercased())
                .font(.caption2.weight(.heavy))
                .padding(.leading, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(rarity.color.gradient))
        .foregroundStyle(.white)
    }
}

extension String {
    /// "your partner" → "Your partner", without lowercasing the rest like `capitalized` does.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
