import XCTest
@testable import QuotaCore

final class UsageSnapshotTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func date(_ string: String) -> Date { ClaudeJSON.parseDate(string)! }

    func testEnterpriseIncludedGrantIsHeadline() throws {
        let snapshot = try UsageSnapshot.parse(fixture("enterprise_usage"))

        XCTAssertEqual(snapshot.dollarWindows.count, 1)
        let included = snapshot.dollarWindows[0]
        XCTAssertEqual(included.key, "copper_kite")
        XCTAssertEqual(included.limit, 1000)
        XCTAssertEqual(included.remaining, 789.237149, accuracy: 1e-6)
        XCTAssertEqual(included.resetsAt, date("2026-11-14T23:31:02.349838+00:00"))

        XCTAssertEqual(snapshot.monthlyBudget, MonthlyBudget(used: 0, limit: 150, enabled: true))

        let headline = snapshot.headline(now: date("2026-10-19T12:00:00Z"))
        XCTAssertEqual(headline, .included(included))
        XCTAssertEqual(headline.shortText, "$789")
        XCTAssertEqual(headline.level, .ok)
    }

    func testEnterpriseFallsBackToMonthlyAfterIncludedExpires() throws {
        let snapshot = try UsageSnapshot.parse(fixture("enterprise_usage"))
        let headline = snapshot.headline(now: date("2026-11-16T12:00:00Z"))
        XCTAssertEqual(headline, .monthly(MonthlyBudget(used: 0, limit: 150, enabled: true)))
        XCTAssertEqual(headline.shortText, "$150")
    }

    func testExtraUsageFallbackWhenSpendMissing() throws {
        var snapshot = try UsageSnapshot.parse(fixture("enterprise_usage"))
        snapshot.spend = nil
        XCTAssertEqual(snapshot.monthlyBudget, MonthlyBudget(used: 0, limit: 150, enabled: true))
    }

    func testProUsesPercentLimits() throws {
        let snapshot = try UsageSnapshot.parse(fixture("pro_usage"))

        XCTAssertTrue(snapshot.dollarWindows.isEmpty)
        XCTAssertNil(snapshot.monthlyBudget)
        XCTAssertEqual(snapshot.percentLimits.map(\.kind), ["session", "weekly_all"])

        let headline = snapshot.headline(now: date("2026-10-19T08:00:00Z"))
        XCTAssertEqual(headline.shortText, "3%")
        XCTAssertEqual(headline.level, .ok)

        XCTAssertEqual(snapshot.resetGrants.count, 1)
        XCTAssertEqual(snapshot.resetGrants[0].resetsLeft, 1)
        XCTAssertEqual(snapshot.resetGrants[0].endsAt, date("2026-10-22T16:00:00+00:00"))
    }

    func testUnexpectedShapesDoNotThrow() throws {
        let data = Data(#"{"limits": "surprise", "new_thing": {"limit_dollars": 50, "used_dollars": 45}}"#.utf8)
        let snapshot = try UsageSnapshot.parse(data)
        XCTAssertEqual(snapshot.dollarWindows.first?.remaining, 5)
        XCTAssertEqual(snapshot.headline().level, .critical)
    }

    func testDateParsingWithMicroseconds() {
        let parsed = ClaudeJSON.parseDate("2026-10-19T09:39:59.648617+00:00")
        let whole = ClaudeJSON.parseDate("2026-10-19T09:39:59Z")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.timeIntervalSince(whole!), 0.648617, accuracy: 1e-5)
    }

    func testNextMonthlyReset() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let reset = nextMonthlyReset(after: date("2026-10-19T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(reset, date("2026-11-01T00:00:00Z"))
    }

    func testOrganizationsKeepOnlyClaudeAIOrgs() throws {
        let orgs = try Organization.parseList(fixture("organizations"))
        XCTAssertEqual(orgs.map(\.uuid), ["org-enterprise"])
        XCTAssertEqual(orgs.first?.name, "Example Org")
    }

    func testLevelThresholds() {
        XCTAssertEqual(Level(remainingFraction: 0.8), .ok)
        XCTAssertEqual(Level(remainingFraction: 0.3), .warning)
        XCTAssertEqual(Level(remainingFraction: 0.1), .critical)
    }
}
