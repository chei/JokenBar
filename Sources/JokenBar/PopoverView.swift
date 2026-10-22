import QuotaCore
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("JokenBar").font(.headline)
                    Text("Add a claude.ai account below. You can add both work and personal accounts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.accounts) { account in
                    ForEach(account.organizations) { org in
                        OrgCard(account: account, org: org)
                    }
                }
            }
            Divider()
            FooterView()
        }
        .padding(14)
        .frame(width: 340)
    }
}

private struct OrgCard: View {
    @EnvironmentObject private var model: AppModel
    let account: Account
    let org: Organization

    var body: some View {
        if case .unavailable? = model.states[org.uuid] {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(org.name).font(.headline).lineLimit(1)
                    Spacer()
                    Button {
                        model.primaryOrgID = org.uuid
                    } label: {
                        Image(systemName: isPrimary ? "menubar.arrow.up.rectangle" : "menubar.rectangle")
                    }
                    .buttonStyle(.borderless)
                    .help("Show in menu bar")
                    Menu {
                        Button("Sign In Again…") { model.login(account) }
                        Button("Remove Account", role: .destructive) { model.remove(account) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                content
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var isPrimary: Bool { model.primaryOrgID == org.uuid }

    @ViewBuilder private var content: some View {
        switch model.states[org.uuid] {
        case .loaded(let snapshot)?:
            UsageDetails(snapshot: snapshot)
        case .failed(let message)?:
            Text(message).font(.caption).foregroundStyle(.secondary)
        case .needsLogin?:
            Button("Session expired – Sign In…") { model.login(account) }
        case .loading?, nil, .unavailable?:
            ProgressView().controlSize(.small)
        }
    }
}

private struct UsageDetails: View {
    let snapshot: UsageSnapshot

    var body: some View {
        let now = Date()
        let includedActive = snapshot.activeIncluded(now: now) != nil
        VStack(alignment: .leading, spacing: 10) {
            ForEach(snapshot.dollarWindows, id: \.key) { window in
                GaugeRow(
                    title: "Included usage",
                    used: 1 - window.remainingFraction,
                    value: "\(Fmt.usd(window.remaining)) left of \(Fmt.usd(window.limit, decimals: 0))",
                    footnote: window.resetsAt.map { "expires \(Fmt.date($0)) · \(Fmt.relative($0, now: now))" }
                )
            }
            if let budget = snapshot.monthlyBudget, budget.enabled {
                let reset = nextMonthlyReset(after: now)
                GaugeRow(
                    title: "Monthly limit",
                    used: 1 - budget.remainingFraction,
                    value: "\(Fmt.usd(budget.used)) / \(Fmt.usd(budget.limit, decimals: 0)) spent",
                    footnote: (includedActive ? "Untouched while included usage lasts · " : "")
                        + "resets ≈ \(Fmt.day(reset)) · \(Fmt.relative(reset, now: now))"
                )
            }
            ForEach(snapshot.percentLimits, id: \.kind) { limit in
                GaugeRow(
                    title: Fmt.limitTitle(limit.kind),
                    used: limit.percent / 100,
                    value: "\(Int(limit.percent.rounded()))% used",
                    footnote: limit.resetsAt.map { "resets \(Fmt.date($0)) · \(Fmt.relative($0, now: now))" }
                )
            }
            ForEach(snapshot.resetGrants.filter { ($0.resetsLeft ?? 0) > 0 }) { grant in
                Label {
                    Text("\(grant.resetsLeft ?? 0) free limit reset(s)"
                        + (grant.endsAt.map { " · expires \(Fmt.date($0))" } ?? ""))
                } icon: {
                    Image(systemName: "gift")
                }
                .font(.caption)
                .help(grant.label ?? "")
            }
        }
    }
}

private struct GaugeRow: View {
    let title: String
    /// 0…1, fills from the left like the bars on claude.ai's usage page.
    let used: Double
    let value: String
    let footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            UsageBar(used: used)
            if let footnote {
                Text(footnote).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct UsageBar: View {
    let used: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.blue)
                    .frame(width: geometry.size.width * min(max(used, 0), 1))
            }
        }
        .frame(height: 5)
    }
}

private struct FooterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }
                ))
            }
            .toggleStyle(.checkbox)
            .font(.caption)
            HStack {
                if let lastRefresh = model.lastRefresh {
                    Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing)
                .help("Refresh")
                Spacer()
                Button("Add Account…") { model.login() }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
    }
}

enum Fmt {
    static func usd(_ value: Double, decimals: Int = 2) -> String {
        "$" + String(format: "%.\(decimals)f", value)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func relative(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "expired" }
        let days = Int(seconds / 86_400)
        if days >= 1 { return "\(days)d left" }
        let hours = Int(seconds / 3_600)
        if hours >= 1 { return "\(hours)h left" }
        return "\(max(1, Int(seconds / 60)))m left"
    }

    static func limitTitle(_ kind: String) -> String {
        switch kind {
        case "session": return "5-hour limit"
        case "weekly_all": return "Weekly limit"
        default: return kind
        }
    }
}
