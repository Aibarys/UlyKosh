import Foundation

/// Локализуемая строка контента. Ключ — русский текст, переводы в Localizable.xcstrings.
@inline(__always)
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}
