import Foundation

public enum Level: Equatable {
    case ok, warning, critical

    public init(remainingFraction: Double) {
        if remainingFraction > 0.5 {
            self = .ok
        } else if remainingFraction > 0.2 {
            self = .warning
        } else {
            self = .critical
        }
    }
}

public enum Headline: Equatable {
    case included(DollarWindow)
    case monthly(MonthlyBudget)
    case percent(PercentLimit)
    case unknown

    public var remainingFraction: Double? {
        switch self {
        case .included(let w): return w.remainingFraction
        case .monthly(let b): return b.remainingFraction
        case .percent(let p): return max(0, 1 - p.percent / 100)
        case .unknown: return nil
        }
    }

    public var level: Level? { remainingFraction.map(Level.init(remainingFraction:)) }

    /// Compact menu bar text: remaining dollars, or used percent for Pro/Max.
    public var shortText: String {
        switch self {
        case .included(let w): return Self.compactUSD(w.remaining)
        case .monthly(let b): return Self.compactUSD(b.remaining)
        case .percent(let p): return "\(Int(p.percent.rounded()))%"
        case .unknown: return "–"
        }
    }

    static func compactUSD(_ value: Double) -> String {
        value >= 10_000 ? "$\(Int(value / 1000))k" : "$\(Int(value.rounded(.down)))"
    }
}
