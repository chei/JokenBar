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
        #expect(headline.shortText == "21%")
        #expect(headline.level == .ok)
    }

    @Test func enterpriseFallsBackToMonthlyAfterIncludedExpires() throws {
        let snapshot = try UsageSnapshot.parse(fixture("enterprise_usage"))
        let headline = snapshot.headline(now: date("2026-11-16T12:00:00Z"))
        #expect(headline == .monthly(MonthlyBudget(used: 0, limit: 150, enabled: true)))
        #expect(headline.shortText == "0%")
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

    @Test func proHeadlineIsSessionEvenWhenWeeklyIsHigher() throws {
        let json = String(decoding: try fixture("pro_usage"), as: UTF8.self)
            .replacingOccurrences(of: "\"percent\": 0", with: "\"percent\": 40")
        let snapshot = try UsageSnapshot.parse(Data(json.utf8))
        #expect(snapshot.percentLimits.map(\.percent) == [3, 40])
        #expect(snapshot.headline().shortText == "3%")
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

    @Test func timeLeftUsesTwoUnitsBelowTwo() {
        let now = date("2026-10-19T12:00:00Z")
        let left = { (minutes: Double) in timeLeft(until: now.addingTimeInterval(minutes * 60), now: now) }
        #expect(left(3 * 1440 + 100) == "3d left")
        #expect(left(2 * 1440) == "2d left")
        #expect(left(1440 + 5 * 60 + 30) == "1d 5h left")
        #expect(left(5 * 60 + 59) == "5h left")
        #expect(left(80) == "1h 20m left")
        #expect(left(59.5) == "59m left")
        #expect(left(-1) == "expired")
    }

    @Test func organizationsKeepOnlyClaudeAIOrgs() throws {
        let orgs = try Organization.parseList(fixture("organizations"))
        #expect(orgs.map(\.uuid) == ["org-enterprise", "org-personal"])
        #expect(orgs.first?.name == "Example Org")
    }

    @Test func accountIdentifiesTheUser() throws {
        #expect(try ClaudeAccount.parse(fixture("account")) == ClaudeAccount(id: "user-1", email: "user@example.com"))
    }

    @Test func planNameOnlyForPersonalPlans() throws {
        let orgs = try Organization.parseList(fixture("organizations"))
        #expect(orgs.map(\.planName) == [nil, "Pro"])
    }

    @Test func displayNameShowsEmailForPersonalOrgs() throws {
        let orgs = try Organization.parseList(fixture("organizations"))
        #expect(orgs.map(\.displayName) == ["Example Org", "user@example.com"])

        let curly = Organization(uuid: "x", name: "user@example.com’s Organization")
        #expect(curly.displayName == "user@example.com")
    }

    @Test func emptyResponseHasNoLimits() throws {
        #expect(try UsageSnapshot.parse(Data("{}".utf8)).hasLimits == false)
    }

    @Test func limitTitlesAreReadable() {
        func title(_ kind: String) -> String { PercentLimit(kind: kind, percent: 0).title }
        #expect(title("session") == "Session")
        #expect(title("weekly_all") == "Week")
        #expect(title("weekly_opus") == "Week · Opus")
        #expect(title("weekly_oauth_apps") == "Week · Oauth Apps")
    }

    @Test func levelThresholds() {
        #expect(Level(usedFraction: 0.74) == .ok)
        #expect(Level(usedFraction: 0.75) == .warning)
        #expect(Level(usedFraction: 0.89) == .warning)
        #expect(Level(usedFraction: 0.9) == .critical)
    }
}
