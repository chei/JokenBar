import AppKit
import QuotaCore
import WebKit

/// Shows claude.ai's own login page (email code, Google or company SSO)
/// and closes itself as soon as `/api/organizations` answers.
@MainActor
final class LoginWindowController: NSWindowController, NSWindowDelegate {
    private let webView: WKWebView
    private let onSuccess: ([Organization], _ userID: String?) -> Void
    private let onClose: () -> Void
    private var pollTask: Task<Void, Never>?
    private var succeeded = false

    init(accountID: UUID, onSuccess: @escaping ([Organization], _ userID: String?) -> Void, onClose: @escaping () -> Void) {
        self.onSuccess = onSuccess
        self.onClose = onClose
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = ClaudeSession.dataStore(for: accountID)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = safariUserAgent

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 780),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Claude"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func start() {
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.checkLogin()
            }
        }
    }

    private func checkLogin() async {
        guard !succeeded, let url = webView.url, url.host == "claude.ai",
              !url.path.hasPrefix("/login"), !webView.isLoading
        else { return }
        guard let data = try? await WebFetcher.get("/api/organizations", in: webView),
              let orgs = try? Organization.parseList(data), !orgs.isEmpty
        else { return }
        let userID = (try? await WebFetcher.get("/api/account", in: webView))
            .flatMap { try? ClaudeAccount.parseID($0) }
        succeeded = true
        pollTask?.cancel()
        onSuccess(orgs, userID)
        close()
    }

    func windowWillClose(_ notification: Notification) {
        pollTask?.cancel()
        onClose()
    }
}
