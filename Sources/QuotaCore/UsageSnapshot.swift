import Foundation

/// Parsed `GET https://claude.ai/api/organizations/{org}/usage` response.
/// The endpoint is internal and undocumented, so every field is optional
/// and unknown keys are ignored.
public struct UsageSnapshot: Equatable {
    public var fiveHour: PercentWindow?
    public var sevenDay: PercentWindow?
    public var limits: [LimitEntry] = []
    public var dollarWindows: [DollarWindow] = []
    public var extraUsage: ExtraUsage?
    public var spend: Spend?
    public var resetGrants: [ResetGrant] = []

    public init() {}

    public enum ParseError: Error { case notAnObject }

    public static func parse(_ data: Data) throws -> UsageSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.notAnObject
        }
        // A surprise in one block should not hide the rest.
        let raw = (try? ClaudeJSON.decoder.decode(RawUsage.self, from: data)) ?? RawUsage()

        var snapshot = UsageSnapshot()
        snapshot.fiveHour = raw.fiveHour
        snapshot.sevenDay = raw.sevenDay
        snapshot.limits = raw.limits ?? []
        snapshot.extraUsage = raw.extraUsage
        snapshot.spend = raw.spend
        snapshot.resetGrants = raw.cedarEmber?.grants ?? []
        snapshot.dollarWindows = object.keys.sorted().compactMap { key in
            dollarWindow(key: key, value: object[key])
        }
        return snapshot
    }

    private static func dollarWindow(key: String, value: Any?) -> DollarWindow? {
        guard let dict = value as? [String: Any],
              let limit = ClaudeJSON.number(dict["limit_dollars"]),
              let used = ClaudeJSON.number(dict["used_dollars"])
        else { return nil }
        let remaining = ClaudeJSON.number(dict["remaining_dollars"]) ?? max(limit - used, 0)
        let resetsAt = (dict["resets_at"] as? String).flatMap(ClaudeJSON.parseDate)
        var isLocked = false
        if let reason = dict["locked_reason"], !(reason is NSNull) { isLocked = true }
        return DollarWindow(key: key, limit: limit, used: used, remaining: remaining,
                            resetsAt: resetsAt, isLocked: isLocked)
    }
}

private struct RawUsage: Decodable {
    var fiveHour: PercentWindow?
    var sevenDay: PercentWindow?
    var limits: [LimitEntry]?
    var extraUsage: ExtraUsage?
    var spend: Spend?
    var cedarEmber: GrantBlock?

    struct GrantBlock: Decodable { var grants: [ResetGrant]? }
}

public extension UsageSnapshot {
    /// The included grant that is currently being consumed, if any.
    func activeIncluded(now: Date) -> DollarWindow? {
        dollarWindows.filter { $0.isActive(now: now) }.max { $0.remaining < $1.remaining }
    }

    /// Monthly spend limit; prefers `spend`, falls back to `extra_usage`.
    var monthlyBudget: MonthlyBudget? {
        if let spend, let limit = spend.limit?.value {
            return MonthlyBudget(used: spend.used?.value ?? 0, limit: limit, enabled: spend.enabled ?? true)
        }
        if let extra = extraUsage, let limitMinor = extra.monthlyLimit {
            let scale = pow(10, Double(extra.decimalPlaces ?? 2))
            return MonthlyBudget(used: (extra.usedCredits ?? 0) / scale, limit: limitMinor / scale,
                                 enabled: extra.isEnabled ?? false)
        }
        return nil
    }

    /// Percent limits; prefers the normalized `limits` list.
    var percentLimits: [PercentLimit] {
        let fromList = limits.compactMap { entry -> PercentLimit? in
            guard let kind = entry.kind, let percent = entry.percent else { return nil }
            return PercentLimit(kind: kind, percent: percent, resetsAt: entry.resetsAt)
        }
        if !fromList.isEmpty { return fromList }
        var result: [PercentLimit] = []
        if let w = fiveHour, let u = w.utilization {
            result.append(PercentLimit(kind: "session", percent: u, resetsAt: w.resetsAt))
        }
        if let w = sevenDay, let u = w.utilization {
            result.append(PercentLimit(kind: "weekly_all", percent: u, resetsAt: w.resetsAt))
        }
        return result
    }

    /// The single value shown in the menu bar.
    /// Included grant while it lasts, then the monthly budget, then percent limits.
    func headline(now: Date = Date()) -> Headline {
        if let included = activeIncluded(now: now) { return .included(included) }
        if let budget = monthlyBudget, budget.enabled, budget.limit > 0 { return .monthly(budget) }
        if let worst = percentLimits.max(by: { $0.percent < $1.percent }) { return .percent(worst) }
        return .unknown
    }
}

/// The monthly spend limit resets at the start of the billing month.
/// The API does not return this date, so it is an approximation.
public func nextMonthlyReset(after now: Date, calendar: Calendar = .current) -> Date {
    let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
    return calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
}

/// "3d left", or two units below 2 so the last stretch stays precise: "1d 5h left", "1h 20m left".
public func timeLeft(until date: Date, now: Date) -> String {
    let minutes = Int(date.timeIntervalSince(now) / 60)
    if minutes <= 0 { return "expired" }
    let (days, hours) = (minutes / 1440, minutes / 60)
    if days >= 2 { return "\(days)d left" }
    if days == 1 { return "1d \(hours - 24)h left" }
    if hours >= 2 { return "\(hours)h left" }
    if hours == 1 { return "1h \(minutes - 60)m left" }
    return "\(minutes)m left"
}
