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

    /// Compact menu bar text: always the used percentage.
    public var shortText: String {
        guard let remainingFraction else { return "–" }
        return "\(Int(((1 - remainingFraction) * 100).rounded()))%"
    }
}
