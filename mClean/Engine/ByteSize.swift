import Foundation

/// Mole prints sizes in decimal units ("118.4MB", "3.27GB", "468KB").
nonisolated enum ByteSize {
    private static let pattern = try! NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)\\s?(B|KB|MB|GB|TB)\\b")
    private static let multipliers: [String: Double] = [
        "B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12,
    ]

    /// The first size found in `text`, in bytes.
    static func parse(_ text: String) -> Int64? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[numberRange]),
              let multiplier = multipliers[String(text[unitRange])]
        else { return nil }
        return Int64(value * multiplier)
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Splits a formatted size into number and unit for large displays: ("1.6", "GB").
    static func parts(_ bytes: Int64) -> (value: String, unit: String) {
        let text = format(bytes)
        guard let space = text.lastIndex(where: \.isWhitespace) else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }
}
