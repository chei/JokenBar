import Foundation
import QuotaCore
import WebKit

enum ClaudeError: LocalizedError {
    case http(Int)
    case badResponse
    case loadFailed(Error)
    /// claude.ai could not be reached: no network, DNS failure, timeout.
    case offline

    var errorDescription: String? {
        switch self {
        case .http(let status): return "HTTP \(status)"
        case .badResponse: return "Unexpected response from claude.ai"
        case .loadFailed(let error): return error.localizedDescription
        case .offline: return "Offline"
        }
    }

    var isAuthError: Bool {
        if case .http(let status) = self { return status == 401 || status == 403 }
        return false
    }
}

/// Safari user agent: Google sign-in refuses embedded web views with the default one,
/// and it keeps Cloudflare happy.
let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

enum WebFetcher {
    /// Runs `fetch(path)` inside a page on claude.ai, so cookies, SSO and
    /// Cloudflare clearance all come from the web view's own data store.
    @MainActor
    static func get(_ path: String, in webView: WKWebView) async throws -> Data {
        let js = """
        try {
            const r = await fetch(path, {credentials: 'include', headers: {accept: 'application/json'}});
            return [r.status, await r.text()];
        } catch {
            return [0, ''];
        }
        """
        let result: Any = try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(js, arguments: ["path": path], in: nil, in: .defaultClient) { result in
                continuation.resume(with: result)
            }
        }
        guard let pair = result as? [Any], pair.count == 2,
              let status = (pair[0] as? NSNumber)?.intValue,
              let body = pair[1] as? String
        else { throw ClaudeError.badResponse }
        // A same-origin fetch or body read only fails when the network does.
        if status == 0 { throw ClaudeError.offline }
        guard (200..<300).contains(status) else { throw ClaudeError.http(status) }
        return Data(body.utf8)
    }
}

/// One signed-in claude.ai login. Each account has its own isolated
/// cookie store, so a work SSO login and a personal login can coexist.
@MainActor
final class ClaudeSession: NSObject, WKNavigationDelegate {
    static func dataStore(for accountID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: accountID)
    }

    private let webView: WKWebView
    private var isLoaded = false
    private var loadContinuation: CheckedContinuation<Void, Error>?

    init(accountID: UUID) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.dataStore(for: accountID)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = safariUserAgent
        super.init()
        webView.navigationDelegate = self
    }

    func organizations() async throws -> [Organization] {
        try Organization.parseList(try await get("/api/organizations"))
    }

    func user() async throws -> ClaudeAccount {
        try ClaudeAccount.parse(try await get("/api/account"))
    }

    func usage(orgID: String) async throws -> UsageSnapshot {
        try UsageSnapshot.parse(try await get("/api/organizations/\(orgID)/usage"))
    }

    private func get(_ path: String) async throws -> Data {
        try await ensureLoaded()
        return try await WebFetcher.get(path, in: webView)
    }

    /// Loads a tiny same-origin page once, so `fetch` runs with claude.ai as origin.
    private func ensureLoaded() async throws {
        if isLoaded { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.load(URLRequest(url: URL(string: "https://claude.ai/robots.txt")!))
        }
        isLoaded = true
    }

    private func finishLoad(_ error: Error?) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        if let error {
            continuation.resume(throwing: Self.isNetworkFailure(error) ? ClaudeError.offline : ClaudeError.loadFailed(error))
        } else {
            continuation.resume()
        }
    }

    private static func isNetworkFailure(_ error: Error) -> Bool {
        let codes: Set<URLError.Code> = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut,
            .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
            .internationalRoamingOff, .dataNotAllowed,
        ]
        return (error as? URLError).map { codes.contains($0.code) } ?? false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoad(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoad(error)
    }
}
