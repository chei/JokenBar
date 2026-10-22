import Foundation
import Testing
@testable import QuotaCore

struct UsageSnapshotTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func date(_ string: String) -> Date { ClaudeJSON.parseDate(string)! }

    @Test func enterpriseIncludedGrantIsHeadline() throws {
        let snapshot = try UsageSnapshot.parse(fixture("enterprise_usage"))

        #expect(snapshot.dollarWindows.count == 1)
        let included = snapshot.dollarWindows[0]
        #expect(included.key == "copper_kite")
        #expect(included.limit == 1000)
        #expect(abs(included.remaining - 789.237149) < 1e-6)
        #expect(included.resetsAt == date("2026-11-14T23:31:02.349838+00:00"))

        #expect(snapshot.monthlyBudget == MonthlyBudget(used: 0, limit: 150, enabled: true))

        let headline = snapshot.headline(now: date("2026-10-19T12:00:00Z"))
        #expect(headline == .included(included))
        #expect(headline.shortText == "$789")
        #expect(headline.level == .ok)
    }

    @Test func enterpriseFallsBackToMonthlyAfterIncludedExpires() throws {
        let snapshot = try UsageSnapshot.parse(fixture("enterprise_usage"))
        let headline = snapshot.headline(now: date("2026-11-16T12:00:00Z"))
        #expect(headline == .monthly(MonthlyBudget(used: 0, limit: 150, enabled: true)))
        #expect(headline.shortText == "$150")
    }

    @Test func extraUsageFallbackWhenSpendMissing() throws {
        var snapshot = try UsageSnapshot.parse(fixture("enterprise_usage"))
        snapshot.spend = nil
        #expect(snapshot.monthlyBudget == MonthlyBudget(used: 0, limit: 150, enabled: true))
    }

    @Test func proUsesPercentLimits() throws {
        let snapshot = try UsageSnapshot.parse(fixture("pro_usage"))

        #expect(snapshot.dollarWindows.isEmpty)
        #expect(snapshot.monthlyBudget == nil)
        #expect(snapshot.percentLimits.map(\.kind) == ["session", "weekly_all"])

        let headline = snapshot.headline(now: date("2026-10-19T08:00:00Z"))
        #expect(headline.shortText == "3%")
        #expect(headline.level == .ok)

        #expect(snapshot.resetGrants.count == 1)
        #expect(snapshot.resetGrants[0].resetsLeft == 1)
        #expect(snapshot.resetGrants[0].endsAt == date("2026-10-22T16:00:00+00:00"))
    }

    @Test func unexpectedShapesDoNotThrow() throws {
        let data = Data(#"{"limits": "surprise", "new_thing": {"limit_dollars": 50, "used_dollars": 45}}"#.utf8)
        let snapshot = try UsageSnapshot.parse(data)
        #expect(snapshot.dollarWindows.first?.remaining == 5)
        #expect(snapshot.headline().level == .critical)
    }

    @Test func dateParsingWithMicroseconds() throws {
        let parsed = try #require(ClaudeJSON.parseDate("2026-10-19T09:39:59.648617+00:00"))
        let whole = try #require(ClaudeJSON.parseDate("2026-10-19T09:39:59Z"))
        #expect(abs(parsed.timeIntervalSince(whole) - 0.648617) < 1e-5)
    }

    @Test func nextMonthlyResetIsFirstOfNextMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let reset = nextMonthlyReset(after: date("2026-10-19T12:00:00Z"), calendar: calendar)
        #expect(reset == date("2026-11-01T00:00:00Z"))
    }

    @Test func organizationsKeepOnlyClaudeAIOrgs() throws {
        let orgs = try Organization.parseList(fixture("organizations"))
        #expect(orgs.map(\.uuid) == ["org-enterprise", "org-personal"])
        #expect(orgs.first?.name == "Example Org")
    }

    @Test func displayNameShowsEmailForPersonalOrgs() throws {
        let orgs = try Organization.parseList(fixture("organizations"))
        #expect(orgs.map(\.displayName) == ["Example Org", "user@example.com"])

        let curly = Organization(uuid: "x", name: "user@example.com’s Organization")
        #expect(curly.displayName == "user@example.com")
    }

    @Test func levelThresholds() {
        #expect(Level(remainingFraction: 0.8) == .ok)
        #expect(Level(remainingFraction: 0.3) == .warning)
        #expect(Level(remainingFraction: 0.1) == .critical)
    }
}
