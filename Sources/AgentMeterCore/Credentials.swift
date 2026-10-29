import Foundation
import Security

// Intentionally not Codable: credentials never belong in exports or diagnostics.
struct OAuthCredential {
    let accessToken: String
    let accountID: String?
    var expiresAt: Date? = nil
}

protocol CredentialLoading: Sendable {
    func read(provider: Provider, locations: CredentialLocations, allowPrompt: Bool) throws -> OAuthCredential
}
struct LocalCredentialLoader: CredentialLoading {
    func read(provider: Provider, locations: CredentialLocations, allowPrompt: Bool) throws -> OAuthCredential {
        try CredentialReader.read(provider: provider, locations: locations, allowPrompt: allowPrompt)
    }
}

public struct CredentialLocations: Sendable {
    public var codexHome: URL
    public var claudeHome: URL
    public init(codexHome: URL? = nil, claudeHome: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.codexHome = codexHome ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path)
        self.claudeHome = claudeHome ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? home.appendingPathComponent(".claude").path)
    }
}

enum CredentialReader {
    static func read(provider: Provider, locations: CredentialLocations, allowPrompt: Bool) throws -> OAuthCredential {
        switch provider {
        case .codex:
            // File-backed ChatGPT login. API keys cannot read subscription quota.
            let file = locations.codexHome.appendingPathComponent("auth.json")
            return try decode(fileData(file), provider: provider)
        case .claude:
            let defaultHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").standardizedFileURL
            if locations.claudeHome.standardizedFileURL == defaultHome {
                // No background Keychain calls at all, including noninteractive probes.
                guard allowPrompt else { throw QuotaError.connectionRequired }
                if let data = try keychain(service: "Claude Code-credentials", allowPrompt: true) {
                    return try decode(data, provider: provider)
                }
            }
            return try decode(fileData(locations.claudeHome.appendingPathComponent(".credentials.json")), provider: provider)
        }
    }
    private static func fileData(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { throw QuotaError.login }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1048576 else { throw QuotaError.invalid }
            return try Data(contentsOf: url)
        } catch let error as QuotaError { throw error }
        catch { throw QuotaError.credentialAccess }
    }
    private static func keychain(service: String, allowPrompt: Bool) throws -> Data? {
        guard allowPrompt else { throw QuotaError.connectionRequired }
        // Called only by an explicit connection action. Let legacy generic-password
        // ACLs use the system's normal authorization UI rather than a fresh LAContext.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw QuotaError.keychain(status) }
        guard let data = result as? Data else { throw QuotaError.invalid }
        return data
    }
    static func decode(_ data: Data, provider: Provider, now: Date = Date()) throws -> OAuthCredential {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QuotaError.invalid }
        let token: String
        let account: String?
        var expiresAt: Date?
        switch provider {
        case .codex:
            guard let values = object["tokens"] as? [String: Any], let value = values["access_token"] as? String else { throw QuotaError.login }
            token = value; account = values["account_id"] as? String
        case .claude:
            guard let values = object["claudeAiOauth"] as? [String: Any], let value = values["accessToken"] as? String else { throw QuotaError.login }
            if let scopes = values["scopes"] as? [String], !scopes.contains("user:profile") { throw QuotaError.scope }
            if let expiry = values["expiresAt"] as? Double {
                expiresAt = Date(timeIntervalSince1970: expiry / 1000)
                if expiresAt! <= now { throw QuotaError.expiredLogin }
            }
            token = value; account = nil
        }
        guard !token.isEmpty, token.count < 32768, !token.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw QuotaError.login }
        // Expiry is advisory; the server still validates the token/signature.
        let parts = token.split(separator: ".")
        if parts.count == 3 {
            var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            text += String(repeating: "=", count: (4 - text.count % 4) % 4)
            if let payload = Data(base64Encoded: text), let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
               let exp = claims["exp"] as? Double {
                if exp <= now.timeIntervalSince1970 { throw QuotaError.expiredLogin }
                let jwtExpiry = Date(timeIntervalSince1970: exp)
                expiresAt = expiresAt.map { min($0, jwtExpiry) } ?? jwtExpiry
            }
        }
        if let account, account.contains(where: { $0.isWhitespace || $0.isNewline }) { throw QuotaError.login }
        return OAuthCredential(accessToken: token, accountID: account, expiresAt: expiresAt)
    }
}
