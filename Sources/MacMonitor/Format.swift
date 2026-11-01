import Foundation

enum Format {
    private static let gib = 1_073_741_824.0

    static func gigabytes(_ bytes: UInt64) -> Double { Double(bytes) / gib }

    /// Memory uses binary units like Activity Monitor; whole numbers drop the decimal ("32 GB").
    static func memory(_ bytes: UInt64) -> String {
        let gb = gigabytes(bytes)
        if gb < 1 { return "\(Int((gb * 1024).rounded())) MB" }
        return gb.rounded() == (gb * 10).rounded() / 10 ? "\(Int(gb.rounded())) GB" : String(format: "%.1f GB", gb)
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func plural(_ n: Int, _ unit: String, _ pluralUnit: String? = nil) -> String {
        "\(n.formatted()) \(n == 1 ? unit : pluralUnit ?? unit + "s")"
    }

    /// A fraction in plain words, e.g. 0.21 → "about a fifth of".
    static func share(_ fraction: Double) -> String {
        switch fraction {
        case 0.6...: "most of"
        case 0.45...: "about half of"
        case 0.3...: "about a third of"
        case 0.22...: "about a quarter of"
        case 0.15...: "about a fifth of"
        case 0.08...: "about a tenth of"
        default: "a small part of"
        }
    }

    /// Disk sizes in decimal units like Finder, without decimals ("630 GB").
    static func disk(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        let gb = Double(bytes) / 1e9
        return gb >= 10 ? "\(Int(gb.rounded())) GB" : formatter.string(fromByteCount: bytes)
    }
}
