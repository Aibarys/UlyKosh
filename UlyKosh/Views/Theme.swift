import SwiftUI

extension Color {
    static let sand = Color(red: 0.965, green: 0.925, blue: 0.835)
    static let sandDeep = Color(red: 0.88, green: 0.80, blue: 0.66)
    static let terracotta = Color(red: 0.76, green: 0.38, blue: 0.24)
    static let steppe = Color(red: 0.50, green: 0.60, blue: 0.33)
    static let sky = Color(red: 0.55, green: 0.74, blue: 0.88)
    static let ink = Color(red: 0.22, green: 0.16, blue: 0.11)
    static let inkSoft = Color(red: 0.48, green: 0.40, blue: 0.32)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum Fmt {
    static func km(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    static func days(_ n: Int) -> String {
        let rem10 = n % 10, rem100 = n % 100
        if rem10 == 1 && rem100 != 11 { return "\(n) день" }
        if (2...4).contains(rem10) && !(12...14).contains(rem100) { return "\(n) дня" }
        return "\(n) дней"
    }
}
