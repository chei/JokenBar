import QuotaCore
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var model: AppModel
    let toggleSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("JokenBar").font(.headline)
            if model.accounts.isEmpty {
                Text("See your Claude usage limits at a glance.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.accounts) { account in
                    ForEach(account.organizations) { org in
                        OrgCard(account: account, org: org)
                    }
                }
            }
            Divider()
            if !model.accounts.isEmpty {
                FooterView()
            }
            VStack(alignment: .leading, spacing: 0) {
                if model.accounts.isEmpty {
                    SettingsView()
                } else {
                    SettingsDisclosure(toggle: toggleSettings)
                    if model.settingsReveal > 0 {
                        // Revealed from the top, frame by frame, like "Other Networks" in
                        // the Wi-Fi menu; the popover follows the growing height.
                        SettingsView()
                            .padding(.top, 10)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { geometry in
                                Color.clear.onAppear { model.settingsHeight = geometry.size.height }
                                    .onChange(of: geometry.size.height) { model.settingsHeight = $1 }
                            })
                            .frame(height: model.settingsReveal * model.settingsHeight, alignment: .top)
                            .clipped()
                            .allowsHitTesting(model.settingsReveal == 1)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 340)
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
            if !snapshot.hasLimits {
                Text("No usage data for this plan").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(snapshot.dollarWindows, id: \.key) { window in
                GaugeRow(
                    title: "Included",
                    used: window.usedFraction,
                    footnote: window.resetsAt.map { "expires \(Fmt.day($0)) · \(timeLeft(until: $0, now: now))" },
                    total: window.limit
                )
            }
            if let budget = snapshot.monthlyBudget, budget.enabled {
                let reset = nextMonthlyReset(after: now)
                GaugeRow(
                    title: "Monthly",
                    used: budget.usedFraction,
                    // The API returns no reset date; assume midnight on the 1st.
                    footnote: timeLeft(until: reset, now: now),
                    total: budget.limit
                )
            }
            ForEach(snapshot.percentLimits, id: \.kind) { limit in
                GaugeRow(
                    title: limit.title,
                    used: limit.percent / 100,
                    footnote: limit.resetsAt.map { reset in
                        // Weekly windows end within 7 days, so the weekday is unambiguous.
                        let when = limit.kind == "session" ? Fmt.time(reset) : Fmt.weekday(reset)
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
    /// Dollar limit, shown after the title ("Monthly · $200"); nil for percent-only limits.
    var total: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                HStack(spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium))
                    if let total {
                        Text("· \(Fmt.usd(total, decimals: 0))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(Int((used * 100).rounded()))% used")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            UsageBar(used: used)
            if let footnote {
                Text(footnote)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
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
            if let status {
                Text(status)
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

    private var status: String? {
        let updated = model.lastRefresh?.formatted(date: .omitted, time: .shortened)
        if model.isOffline { return updated.map { "Offline · updated \($0)" } ?? "Offline" }
        return updated.map { "Updated \($0)" }
    }
}

/// Full-width disclosure row, like "Other Networks" in the Wi-Fi menu.
private struct SettingsDisclosure: View {
    @EnvironmentObject private var model: AppModel
    let toggle: () -> Void

    var body: some View {
        MenuRow(title: "Settings", action: toggle) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(model.settingsExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: model.settingsExpanded)
        }
        .font(.headline)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    // Groups get the same 10pt rhythm as the rest of the popover; rows within a group sit closer.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
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
                    }
                }
                // The only sensible step without accounts, so prominent then.
                if model.accounts.isEmpty {
                    Button("Add Account…") { model.login() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Add Account…") { model.login() }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                SwitchRow(title: "Launch at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }
                ))
                SwitchRow(title: "Hotkey", shortcut: "⌃⌥J", isOn: $model.hotKeyEnabled)
            }
        }
        // Lines up with the "Settings" row's text; without accounts there is no such row.
        .padding(.horizontal, model.accounts.isEmpty ? 0 : 6)
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
        .listRowInsets(EdgeInsets())
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
                trailing.foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            // Faint grey like the rows in the Wi-Fi menu, not a blue menu selection.
            .background(isHovered ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 4))
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

    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).hour().minute())
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}
