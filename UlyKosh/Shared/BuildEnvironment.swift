import Foundation

/// Откуда установлено приложение. TestFlight-сборки получают отладочные инструменты, App Store — нет.
enum BuildEnvironment {
    case debug, testFlight, appStore

    static let current: BuildEnvironment = {
        #if DEBUG
        return .debug
        #else
        // У TestFlight-сборок квитанция называется sandboxReceipt, у App Store — receipt.
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" { return .testFlight }
        return .appStore
        #endif
    }()

    /// Показывать ли раздел «Отладка» в настройках.
    static var showsDebugTools: Bool { current != .appStore }

    var title: String {
        switch self {
        case .debug: return "Debug"
        case .testFlight: return "TestFlight"
        case .appStore: return "App Store"
        }
    }
}
