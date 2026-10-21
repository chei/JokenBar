import Foundation

enum ClaudeJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(string)")
            }
            return date
        }
        return decoder
    }()

    /// Parses ISO 8601 dates with any number of fractional digits,
    /// e.g. `2026-10-19T09:39:59.648617+00:00`.
    static func parseDate(_ string: String) -> Date? {
        var base = string
        var fraction = 0.0
        if let dot = string.firstIndex(of: ".") {
            let afterDot = string[string.index(after: dot)...]
            let digits = afterDot.prefix { $0.isNumber }
            fraction = Double("0." + digits) ?? 0
            base = String(string[..<dot]) + String(afterDot.dropFirst(digits.count))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: base).map { $0.addingTimeInterval(fraction) }
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let i as Int: return Double(i)
        default: return nil
        }
    }
}
