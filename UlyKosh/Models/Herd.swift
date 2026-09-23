import Foundation

struct HerdDelta: Codable, Hashable {
    var sheep: Int = 0
    var horses: Int = 0
    var camels: Int = 0

    static let zero = HerdDelta()

    static func + (lhs: HerdDelta, rhs: HerdDelta) -> HerdDelta {
        HerdDelta(sheep: lhs.sheep + rhs.sheep, horses: lhs.horses + rhs.horses, camels: lhs.camels + rhs.camels)
    }
}

struct Herd: Hashable {
    let sheep: Int
    let horses: Int
    let camels: Int
}
