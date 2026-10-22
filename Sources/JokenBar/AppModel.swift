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
    @Published var primaryOrgID: String? {
        didSet { UserDefaults.standard.set(primaryOrgID, forKey: Keys.primaryOrg) }
    }

    private var sessions: [UUID: ClaudeSession] = [:]
    private var loginWindow: LoginWindowController?

    private enum Keys {
        static let accounts = "accounts"
        static let primaryOrg = "primaryOrgID"
    }

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: Keys.accounts)
            .flatMap { try? JSONDecoder().decode([Account].self, from: $0) }
        _accounts = Published(initialValue: saved ?? [])
        _primaryOrgID = Published(initialValue: defaults.string(forKey: Keys.primaryOrg))
    }

    // MARK: Menu bar

    /// The org shown in the menu bar: the starred one, else the first that loaded.
    var menuBarSnapshot: UsageSnapshot? {
        if let id = primaryOrgID, case .loaded(let snapshot)? = states[id] { return snapshot }
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
        defer {
            isRefreshing = false
            lastRefresh = Date()
        }
        for account in accounts {
            await refresh(account)
        }
    }

    private func refresh(_ account: Account) async {
        let session = session(for: account.id)
        do {
            let orgs = try await session.organizations()
            updateOrganizations(orgs, for: account.id)
        } catch let error as ClaudeError where error.isAuthError {
            for org in account.organizations { states[org.uuid] = .needsLogin }
            return
        } catch {
            // Keep the last known org list and try usage anyway.
        }
        let orgs = accounts.first { $0.id == account.id }?.organizations ?? []
        for org in orgs {
            if states[org.uuid] == nil { states[org.uuid] = .loading }
            do {
                states[org.uuid] = .loaded(try await session.usage(orgID: org.uuid))
            } catch let error as ClaudeError where error.isAuthError || error.isNotFound {
                states[org.uuid] = .unavailable
            } catch {
                states[org.uuid] = .failed(error.localizedDescription)
            }
        }
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

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        for org in account.organizations { states[org.uuid] = nil }
        sessions[account.id] = nil
        saveAccounts()
        Task { try? await WKWebsiteDataStore.remove(forIdentifier: account.id) }
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
