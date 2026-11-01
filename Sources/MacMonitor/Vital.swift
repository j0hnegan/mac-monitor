import Foundation

enum Health: Int, Comparable {
    case green, amber, red

    static func < (lhs: Health, rhs: Health) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct Vital: Identifiable {
    enum Kind: String, CaseIterable, Codable {
        case memory = "Memory"
        case cpu = "CPU"
        case battery = "Battery"
        case disk = "Disk"
        case uptime = "Uptime"
        case temperature = "Temperature"
    }

    let kind: Kind
    let health: Health
    let value: String
    var context: String? = nil
    var details: [String] = []

    var id: Kind { kind }
}
