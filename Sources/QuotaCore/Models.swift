import Foundation

/// Percent-based window (Pro/Max: 5-hour session, weekly).
public struct PercentWindow: Decodable, Equatable {
    public var utilization: Double?
    public var resetsAt: Date?
}

/// Normalized entry of the `limits` array (populated on Pro/Max, empty on Enterprise).
public struct LimitEntry: Decodable, Equatable {
    public var kind: String?
    public var group: String?
    public var percent: Double?
    public var severity: String?
    public var resetsAt: Date?
    public var isActive: Bool?
}

/// A dollar-denominated allowance, e.g. the Enterprise "Included usage" grant.
/// Found by shape (any top-level object with `limit_dollars`), because the
/// API keys are rotating code names (`copper_kite`, ...).
public struct DollarWindow: Equatable {
    public var key: String
    public var limit: Double
    public var used: Double
    public var remaining: Double
    /// For the included grant this is the expiry date.
    public var resetsAt: Date?
    public var isLocked: Bool

    public var usedFraction: Double { limit > 0 ? min(max(used / limit, 0), 1) : 1 }

    public func isActive(now: Date) -> Bool {
        !isLocked && remaining > 0 && (resetsAt.map { $0 > now } ?? true)
    }
}

/// `extra_usage` block. Amounts are in minor units (cents), scaled by `decimal_places`.
public struct ExtraUsage: Decodable, Equatable {
    public var isEnabled: Bool?
    public var monthlyLimit: Double?
    public var usedCredits: Double?
    public var currency: String?
    public var decimalPlaces: Int?
    public var spendLimitReached: Bool?
}

public struct Money: Decodable, Equatable {
    public var amountMinor: Double
    public var currency: String?
    public var exponent: Int?

    public var value: Double { amountMinor / pow(10, Double(exponent ?? 2)) }
}

/// `spend` block: the monthly per-user spend limit set by the org admin.
public struct Spend: Decodable, Equatable {
    public var used: Money?
    public var limit: Money?
    public var percent: Double?
    public var severity: String?
    public var enabled: Bool?
}

/// Promotional usage-limit reset (e.g. "one usage-limit reset for Pro and Max").
public struct ResetGrant: Decodable, Equatable, Identifiable {
    public var id: String
    public var label: String?
    public var resetsLeft: Int?
    public var endsAt: Date?
}

public struct MonthlyBudget: Equatable {
    public var used: Double
    public var limit: Double
    public var enabled: Bool

    public init(used: Double, limit: Double, enabled: Bool) {
        self.used = used
        self.limit = limit
        self.enabled = enabled
    }

    public var remaining: Double { max(limit - used, 0) }
    public var usedFraction: Double { limit > 0 ? min(max(used / limit, 0), 1) : 1 }
}

public struct PercentLimit: Equatable {
    public var kind: String
    public var percent: Double
    public var resetsAt: Date?

    /// "session" → "Session", "weekly_all" → "Week", "weekly_opus" → "Week · Opus".
    /// Kinds are snake_case and new ones appear without notice, so build the title from the parts.
    public var title: String {
        var parts = kind.split(separator: "_").map { String($0).capitalized }
        guard !parts.isEmpty else { return kind }
        if parts[0] == "Weekly" { parts[0] = "Week" }
        parts.removeAll { $0 == "All" }
        let scope = parts.dropFirst().joined(separator: " ")
        return scope.isEmpty ? parts[0] : "\(parts[0]) · \(scope)"
    }
}

/// `GET /api/account`: who is signed in. The id recognizes a login that is already listed,
/// the email tells apart colleagues in the same org.
public struct ClaudeAccount: Equatable {
    public var id: String
    public var email: String?

    public static func parse(_ data: Data) throws -> ClaudeAccount {
        struct Raw: Decodable { var uuid: String; var emailAddress: String? }
        let raw = try ClaudeJSON.decoder.decode(Raw.self, from: data)
        return ClaudeAccount(id: raw.uuid, email: raw.emailAddress)
    }
}

public struct Organization: Codable, Equatable, Hashable, Identifiable {
    public var uuid: String
    public var name: String
    /// e.g. `["raven", "chat", "raven_enterprise"]`; API-only Console orgs lack `chat`.
    public var capabilities: [String]?
    public var id: String { uuid }

    public init(uuid: String, name: String, capabilities: [String]? = nil) {
        self.uuid = uuid
        self.name = name
        self.capabilities = capabilities
    }

    public var hasClaudeAI: Bool { capabilities?.contains("chat") ?? true }

    /// The personal plan, e.g. "Pro"; nil for team and enterprise orgs, whose name says enough.
    public var planName: String? {
        if capabilities?.contains("claude_max") == true { return "Max" }
        if capabilities?.contains("claude_pro") == true { return "Pro" }
        return nil
    }

    /// Personal orgs are named "<email>'s Organization"; show just the email.
    public var displayName: String {
        ["'s Organization", "’s Organization"]
            .first { name.hasSuffix($0) }
            .map { String(name.dropLast($0.count)) } ?? name
    }

    /// Parses `GET /api/organizations`, keeping only orgs with a claude.ai usage page.
    public static func parseList(_ data: Data) throws -> [Organization] {
        try ClaudeJSON.decoder.decode([Organization].self, from: data).filter(\.hasClaudeAI)
    }
}
