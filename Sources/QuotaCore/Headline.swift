import Foundation

public enum Level: Equatable {
    case ok, warning, critical

    /// Orange from 75% used, red from 90% used.
    public init(usedFraction: Double) {
        if usedFraction < 0.75 {
            self = .ok
        } else if usedFraction < 0.9 {
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

    public var usedFraction: Double? {
        switch self {
        case .included(let w): return w.usedFraction
        case .monthly(let b): return b.usedFraction
        case .percent(let p): return min(p.percent / 100, 1)
        case .unknown: return nil
        }
    }

    public var level: Level? { usedFraction.map(Level.init(usedFraction:)) }

    /// Compact menu bar text: always the used percentage.
    public var shortText: String {
        guard let usedFraction else { return "–" }
        return "\(Int((usedFraction * 100).rounded()))%"
    }
}
