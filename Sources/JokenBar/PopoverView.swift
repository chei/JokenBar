import QuotaCore
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("JokenBar").font(.headline)
                    Text("Track your Claude usage limits. You can add both work and personal accounts.")
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
            if model.settingsExpanded || model.accounts.isEmpty {
                Divider()
                SettingsView()
            }
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
                    if model.visibleOrgs.count > 1 {
                        Button {
                            model.primaryOrgID = org.uuid
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                        }
                        .buttonStyle(.borderless)
                        .help(isFavorite ? "Shown in menu bar" : "Show in menu bar")
                    }
                    Text(org.displayName).font(.headline).lineLimit(1)
                    Spacer()
                    Button {
                        model.remove(account)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove account")
                }
                content
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var isFavorite: Bool { model.favoriteOrgID == org.uuid }

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

/// Styled after claude.ai: the track turns faintly blue once usage has started,
/// so an untouched limit (e.g. monthly while included usage lasts) stays grey.
private struct UsageBar: View {
    let used: Double

    private static let fill = Color(red: 36 / 255, green: 126 / 255, blue: 224 / 255)

    var body: some View {
        let fraction = min(max(used, 0), 1)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(fraction > 0 ? Self.fill.opacity(0.18) : Color.primary.opacity(0.12))
                Capsule().fill(Self.fill)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 5)
    }
}

private struct FooterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
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
            if !model.accounts.isEmpty {
                Button {
                    model.settingsExpanded.toggle()
                } label: {
                    Image(systemName: model.settingsExpanded ? "gearshape.fill" : "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MenuRow(title: "Add Account…") { model.login() }
            Divider()
            SwitchRow(title: "Launch at Login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.launchAtLogin = $0 }
            ))
            SwitchRow(title: "Global Shortcut", shortcut: "⌃⌥J", isOn: $model.hotKeyEnabled)
            Divider()
            MenuRow(title: "Quit JokenBar", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

/// A plain, menu-like row that highlights on hover.
private struct MenuRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void
    @State private var isHovered = false
    /// Expanding the section can lay a row out under a still mouse, which AppKit
    /// reports as hover; only highlight once the mouse has actually moved.
    @State private var mouseAtAppear: NSPoint?

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(isHovered ? Color.white : Color.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .background(isHovered ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { mouseAtAppear = NSEvent.mouseLocation }
        .onContinuousHover { phase in
            switch phase {
            case .active: isHovered = NSEvent.mouseLocation != mouseAtAppear
            case .ended: isHovered = false
            }
        }
    }
}

private struct SwitchRow: View {
    let title: String
    var shortcut: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let shortcut {
                Text(shortcut).foregroundStyle(.secondary)
            }
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 6)
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
