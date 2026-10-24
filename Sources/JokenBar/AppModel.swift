import Foundation
import QuotaCore
import ServiceManagement
import WebKit

struct Account: Codable, Identifiable, Equatable {
    var id: UUID
    var organizations: [Organization]
}

enum OrgState {
    case loading
    case loaded(UsageSnapshot)
    case failed(String)
    case needsLogin
    /// e.g. an API Console org without a claude.ai usage page.
    case unavailable
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var states: [String: OrgState] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    /// The last refresh could not reach claude.ai; the cards keep their last data.
    @Published private(set) var isOffline = false
    /// The popover's settings section; collapses whenever the popover closes.
    /// `settingsExpanded` drives the chevron, `settingsReveal` (0…1) the animated height.
    @Published var settingsExpanded = false
    @Published var settingsReveal: CGFloat = 0
    /// Natural height of the settings section, measured once it is shown.
    var settingsHeight: CGFloat = 0
    @Published var hotKeyEnabled: Bool {
        didSet { UserDefaults.standard.set(hotKeyEnabled, forKey: Keys.hotKeyEnabled) }
    }

    private var sessions: [UUID: ClaudeSession] = [:]
    private var loginWindow: LoginWindowController?

    private enum Keys {
        static let accounts = "accounts"
        static let hotKeyEnabled = "hotKeyEnabled"
    }

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: Keys.accounts)
            .flatMap { try? JSONDecoder().decode([Account].self, from: $0) }
        _accounts = Published(initialValue: saved ?? [])
        _hotKeyEnabled = Published(initialValue: defaults.object(forKey: Keys.hotKeyEnabled) as? Bool ?? true)
    }

    // MARK: Menu bar

    /// The org shown in the menu bar: the topmost one that loaded.
    var menuBarSnapshot: UsageSnapshot? {
        for account in accounts {
            for org in account.organizations {
                if case .loaded(let snapshot)? = states[org.uuid] { return snapshot }
            }
        }
        return nil
    }

    // MARK: Refresh

    func refreshIfStale() async {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        await refreshAll()
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var offline = false
        for account in accounts {
            if await !refresh(account) { offline = true }
        }
        isOffline = offline
        // Offline, "Updated" keeps the time of the data still shown.
        if !offline { lastRefresh = Date() }
    }

    /// Returns false when claude.ai could not be reached.
    private func refresh(_ account: Account) async -> Bool {
        let session = session(for: account.id)
        do {
            let orgs = try await session.organizations()
            updateOrganizations(orgs, for: account.id)
        } catch let error as ClaudeError where error.isAuthError {
            for org in account.organizations { states[org.uuid] = .needsLogin }
            return true
        } catch {
            // Keep the last known org list and try usage anyway.
        }
        let orgs = accounts.first { $0.id == account.id }?.organizations ?? []
        var reached = true
        for org in orgs {
            if states[org.uuid] == nil { states[org.uuid] = .loading }
            do {
                states[org.uuid] = .loaded(try await session.usage(orgID: org.uuid))
            } catch let error as ClaudeError where error.isAuthError || error.isNotFound {
                states[org.uuid] = .unavailable
            } catch ClaudeError.offline {
                reached = false
                if case .loaded? = states[org.uuid] { continue }
                states[org.uuid] = .failed(ClaudeError.offline.localizedDescription)
            } catch {
                states[org.uuid] = .failed(error.localizedDescription)
            }
        }
        return reached
    }

    private func session(for accountID: UUID) -> ClaudeSession {
        if let existing = sessions[accountID] { return existing }
        let created = ClaudeSession(accountID: accountID)
        sessions[accountID] = created
        return created
    }

    // MARK: Accounts

    /// Pass an existing account to sign in again, or nil to add a new one.
    func login(_ account: Account? = nil) {
        let accountID = account?.id ?? UUID()
        loginWindow = LoginWindowController(
            accountID: accountID,
            onSuccess: { [weak self] orgs in
                guard let self else { return }
                if !self.accounts.contains(where: { $0.id == accountID }) {
                    self.accounts.append(Account(id: accountID, organizations: orgs))
                    self.saveAccounts()
                }
                self.updateOrganizations(orgs, for: accountID)
                self.sessions[accountID] = nil
                Task { await self.refreshAll() }
            },
            onClose: { [weak self] in self?.loginWindow = nil }
        )
        loginWindow?.start()
    }

    /// Drag-to-reorder in settings; the order also decides the menu bar org.
    func moveAccounts(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        saveAccounts()
    }

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        for org in account.organizations { states[org.uuid] = nil }
        sessions[account.id] = nil
        saveAccounts()
        Task { try? await WKWebsiteDataStore.remove(forIdentifier: account.id) }
    }

    /// Deletes cookie stores no account refers to, e.g. when removing an account
    /// failed because its web view still held the store. Run before any session exists.
    func removeOrphanedDataStores() async {
        let known = Set(accounts.map(\.id))
        // Listing stores before any other WebKit object exists crashes inside WebKit
        // (its main run loop isn't set up yet); creating a throwaway store does that.
        _ = WKWebsiteDataStore.nonPersistent()
        for id in await WKWebsiteDataStore.allDataStoreIdentifiers where !known.contains(id) {
            try? await WKWebsiteDataStore.remove(forIdentifier: id)
        }
    }

    private func updateOrganizations(_ orgs: [Organization], for accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }),
              accounts[index].organizations != orgs
        else { return }
        accounts[index].organizations = orgs
        saveAccounts()
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: Keys.accounts)
        }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }
}

private extension ClaudeError {
    var isNotFound: Bool {
        if case .http(404) = self { return true }
        return false
    }
}
