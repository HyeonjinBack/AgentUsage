import Foundation
import CoreFoundation

public enum QuotaClient {
    public static func decode(_ data: Data, provider: Provider, now: Date = Date()) throws -> QuotaSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QuotaError.invalid }
        var windows: [QuotaWindow] = []
        switch provider {
        case .codex:
            guard let limit = root["rate_limit"] as? [String: Any] else { throw QuotaError.unavailable }
            for key in ["primary_window", "secondary_window"] {
                guard let w = limit[key] as? [String: Any], let used = percentage(w["used_percent"]) else { continue }
                let seconds = number(w["limit_window_seconds"])
                let minutes = seconds.flatMap { $0 > 0 && $0 <= 31536000 && $0.truncatingRemainder(dividingBy: 60) == 0 ? Int($0 / 60) : nil }
                windows.append(QuotaWindow(id: key, minutes: minutes, used: used, resetsAt: quotaDate(w["reset_at"])))
            }
        case .claude:
            for (key, minutes) in [("five_hour", 300), ("seven_day", 10080)] {
                guard let w = root[key] as? [String: Any], let used = percentage(w["utilization"]) else { continue }
                windows.append(QuotaWindow(id: key, minutes: minutes, used: used, resetsAt: quotaDate(w["resets_at"])))
            }
        }
        guard !windows.isEmpty else { throw QuotaError.unavailable }
        return QuotaSnapshot(provider: provider, windows: windows, updated: now, source: provider == .codex ? "ChatGPT 직접 연결" : "Claude 직접 연결")
    }
    public static func decodeResetCredits(_ data: Data) throws -> RateLimitResetCredits {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = number(root["available_count"]), let count = Int(exactly: value), count >= 0 else {
            throw QuotaError.invalid
        }
        let credits: [RateLimitResetCredit]?
        if root["credits"] == nil || root["credits"] is NSNull {
            credits = nil
        } else if let rows = root["credits"] as? [[String: Any]] {
            var seen: Set<String> = []
            credits = rows.compactMap { row in
                guard let id = row["id"] as? String, !id.isEmpty,
                      let resetType = row["reset_type"] as? String,
                      let status = row["status"] as? String, seen.insert(id).inserted else { return nil }
                return RateLimitResetCredit(id: id, resetType: resetType, status: status,
                                            expiresAt: quotaDate(row["expires_at"]))
            }
        } else {
            throw QuotaError.invalid
        }
        return RateLimitResetCredits(availableCount: count, credits: credits)
    }
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    private static func percentage(_ value: Any?) -> Double? {
        guard let value = number(value), (0...100).contains(value) else { return nil }; return value
    }
}

struct HTTPResult: Sendable {
    var data: Data
    var status: Int
    var retryAfter: String?
}
protocol QuotaTransport: Sendable { func send(_ request: URLRequest) async throws -> HTTPResult }

// Never forward credentials to a redirected host. No cookie jar, URL cache, or disk persistence.
final class DirectTransport: NSObject, QuotaTransport, URLSessionTaskDelegate, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil; config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 2097152 else { throw QuotaError.invalid }
        return HTTPResult(data: data, status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor DirectQuotaService {
    private let transport: any QuotaTransport
    private let credentialLoader: any CredentialLoading
    private var credentials: [String: OAuthCredential] = [:]
    private var retryDates: [Provider: Date] = [:]
    private var resetCreditRetryDate: Date?
    public init() { transport = DirectTransport(); credentialLoader = LocalCredentialLoader() }
    init(transport: any QuotaTransport, credentialLoader: any CredentialLoading = LocalCredentialLoader()) {
        self.transport = transport; self.credentialLoader = credentialLoader
    }
    public func clearCredentials(provider: Provider? = nil) {
        if let provider { credentials = credentials.filter { !$0.key.hasPrefix(provider.rawValue + ":") } }
        else { credentials.removeAll() }
    }
    public func fetch(provider: Provider, locations: CredentialLocations = CredentialLocations(), allowKeychainPrompt: Bool = false) async throws -> QuotaSnapshot {
        if let date = retryDates[provider], date > Date() { throw QuotaError.rateLimited }
        let home = provider == .codex ? locations.codexHome : locations.claudeHome
        let key = provider.rawValue + ":" + home.standardizedFileURL.path
        let credential: OAuthCredential
        if provider == .claude, let cached = credentials[key] {
            guard cached.expiresAt.map({ $0 > Date() }) ?? true else {
                credentials[key] = nil; throw QuotaError.expiredLogin
            }
            credential = cached
        } else {
            if provider == .claude, !allowKeychainPrompt,
               home.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").standardizedFileURL {
                throw QuotaError.connectionRequired
            }
            credential = try credentialLoader.read(provider: provider, locations: locations, allowPrompt: allowKeychainPrompt)
            guard credential.expiresAt.map({ $0 > Date() }) ?? true else { throw QuotaError.expiredLogin }
            if provider == .claude { credentials[key] = credential }
        }
        do { return try await fetch(provider: provider, credential: credential) }
        catch let error as QuotaError {
            if [.expiredLogin, .login, .scope].contains(error) { credentials[key] = nil }
            throw error
        }
    }
    func fetch(provider: Provider, credential: OAuthCredential) async throws -> QuotaSnapshot {
        if let date = retryDates[provider], date > Date() { throw QuotaError.rateLimited }
        let endpoint = provider == .codex ? "https://chatgpt.com/backend-api/wham/usage" : "https://api.anthropic.com/api/oauth/usage"
        let request = makeRequest(endpoint: endpoint, provider: provider, credential: credential)
        let result: HTTPResult
        do { result = try await transport.send(request) }
        catch let e as QuotaError { throw e }
        catch let e as URLError { throw e.code == .timedOut ? QuotaError.timeout : QuotaError.network }
        catch { throw QuotaError.network }
        switch result.status {
        case 200:
            var snapshot = try QuotaClient.decode(result.data, provider: provider)
            if provider == .codex {
                do { snapshot.resetCredits = try await fetchResetCredits(credential: credential) }
                catch { snapshot.resetCreditsError = ((error as? QuotaError) ?? .unavailable).message }
            }
            return snapshot
        case 401: throw QuotaError.expiredLogin
        case 403: throw QuotaError.scope
        case 429:
            let delay = Double(result.retryAfter ?? "") ?? 300
            retryDates[provider] = Date().addingTimeInterval(min(3600, max(30, delay)))
            throw QuotaError.rateLimited
        case 300..<400: throw QuotaError.redirected
        case 500..<600: throw QuotaError.server
        default: throw QuotaError.unavailable
        }
    }

    private func makeRequest(endpoint: String, provider: Provider, credential: OAuthCredential) -> URLRequest {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentMeter/0.2.6", forHTTPHeaderField: "User-Agent")
        if provider == .codex, let account = credential.accountID { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        if provider == .claude { request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta") }
        return request
    }

    private func fetchResetCredits(credential: OAuthCredential) async throws -> RateLimitResetCredits {
        if let retry = resetCreditRetryDate, retry > Date() { throw QuotaError.rateLimited }
        // Read-only details endpoint used by Codex. Never call the /consume route.
        let request = makeRequest(endpoint: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits",
                                  provider: .codex, credential: credential)
        let result: HTTPResult
        do { result = try await transport.send(request) }
        catch let error as QuotaError { throw error }
        catch let error as URLError { throw error.code == .timedOut ? QuotaError.timeout : QuotaError.network }
        catch { throw QuotaError.network }
        switch result.status {
        case 200: return try QuotaClient.decodeResetCredits(result.data)
        case 401: throw QuotaError.expiredLogin
        case 403: throw QuotaError.scope
        case 429:
            let delay = Double(result.retryAfter ?? "") ?? 300
            resetCreditRetryDate = Date().addingTimeInterval(min(3600, max(30, delay)))
            throw QuotaError.rateLimited
        case 300..<400: throw QuotaError.redirected
        case 500..<600: throw QuotaError.server
        default: throw QuotaError.unavailable
        }
    }
}
