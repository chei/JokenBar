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
            if !model.accounts.isEmpty {
                SettingsDisclosure()
            }
            if model.settingsExpanded || model.accounts.isEmpty {
                SettingsView()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity))
            }
        }
        .padding(14)
        .frame(width: 340)
        // Pin content to the top while the popover window resizes, so only the
        // settings section moves when it opens or closes.
        .frame(maxHeight: .infinity, alignment: .top)
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
                Text(org.displayName).font(.headline).lineLimit(1)
                content
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

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
        VStack(alignment: .leading, spacing: 10) {
            ForEach(snapshot.dollarWindows, id: \.key) { window in
                GaugeRow(
                    title: "Included",
                    used: 1 - window.remainingFraction,
                    footnote: window.resetsAt.map { "expires \(Fmt.day($0)) · \(timeLeft(until: $0, now: now))" },
                    total: window.limit
                )
            }
            if let budget = snapshot.monthlyBudget, budget.enabled {
                let reset = nextMonthlyReset(after: now)
                GaugeRow(
                    title: "Monthly",
                    used: 1 - budget.remainingFraction,
                    footnote: "resets ≈ \(Fmt.day(reset)) · \(timeLeft(until: reset, now: now))",
                    total: budget.limit
                )
            }
            ForEach(snapshot.percentLimits, id: \.kind) { limit in
                GaugeRow(
                    title: Fmt.limitTitle(limit.kind),
                    used: limit.percent / 100,
                    footnote: limit.resetsAt.map { reset in
                        let when = limit.kind == "session" ? Fmt.time(reset) : Fmt.date(reset)
                        return "resets \(when) · \(timeLeft(until: reset, now: now))"
                    }
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
    let footnote: String?
    /// Dollar limit, shown as "Total $200"; nil for percent-only limits.
    var total: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int((used * 100).rounded()))% used")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            UsageBar(used: used)
            HStack {
                if let footnote { Text(footnote) }
                Spacer()
                if let total { Text("Total \(Fmt.usd(total, decimals: 0))") }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
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
        }
    }
}

/// Full-width disclosure row, like "Other Networks" in the Wi-Fi menu.
private struct SettingsDisclosure: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        MenuRow(title: "Settings") {
            withAnimation(.easeInOut(duration: 0.2)) { model.settingsExpanded.toggle() }
        } trailing: {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(model.settingsExpanded ? 90 : 0))
        }
        .font(.headline)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !model.accounts.isEmpty {
                List {
                    ForEach(model.accounts) { account in
                        AccountRow(account: account)
                    }
                    .onMove { model.moveAccounts(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(model.accounts.count) * 26)
                if model.accounts.count > 1 {
                    Text("Drag to reorder · the top account is shown in the menu bar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            }
            Button("Add Account…") { model.login() }
                .padding(.horizontal, 6)
            Divider()
            SwitchRow(title: "Launch at Login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.launchAtLogin = $0 }
            ))
            SwitchRow(title: "Global Shortcut", shortcut: "⌃⌥J", isOn: $model.hotKeyEnabled)
            Divider()
            HStack {
                Spacer()
                Button("Quit JokenBar") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 6)
        }
    }
}

private struct AccountRow: View {
    @EnvironmentObject private var model: AppModel
    let account: Account

    var body: some View {
        HStack {
            Text(account.organizations.map(\.displayName).joined(separator: ", "))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                model.remove(account)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove account")
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// A plain, menu-like row that highlights on hover.
private struct MenuRow<Trailing: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let trailing: Trailing
    @State private var isHovered = false
    /// Expanding the section can lay a row out under a still mouse, which AppKit
    /// reports as hover; only highlight once the mouse has actually moved.
    @State private var mouseAtAppear: NSPoint?

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                trailing.foregroundStyle(isHovered ? Color.white : Color.secondary)
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

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func limitTitle(_ kind: String) -> String {
        switch kind {
        case "session": return "Session"
        case "weekly_all": return "Week"
        default: return kind
        }
    }
}
