import SwiftUI

extension Color {
    static let night = Color(red: 0.045, green: 0.045, blue: 0.055)
    static let panel = Color.white.opacity(0.05)
    static let hairline = Color.white.opacity(0.09)
    static let gold = Color(red: 0.86, green: 0.66, blue: 0.28)
    static let parchment = Color(red: 0.92, green: 0.88, blue: 0.80)
    static let ash = Color(red: 0.58, green: 0.56, blue: 0.52)
}

extension Font {
    /// Антиква для цифр и заголовков, как в приключенческих трекерах.
    static func display(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

struct PanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hairline, lineWidth: 1))
    }
}

extension View {
    func panel() -> some View { modifier(PanelStyle()) }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.6)
            .textCase(.uppercase)
            .foregroundStyle(Color.gold.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.display(30, weight: .regular))
                .foregroundStyle(Color.gold)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ash)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum Fmt {
    static func km(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    /// Множественное число задаётся правилами языка в Localizable.xcstrings.
    static func days(_ n: Int) -> String {
        String(localized: "\(n) дней")
    }
}
