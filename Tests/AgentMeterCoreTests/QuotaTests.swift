import XCTest
@testable import AgentMeterCore

private actor StubTransport: QuotaTransport {
    let result: HTTPResult
    var requests: [URLRequest] = []
    init(status: Int = 200, data: Data = Data(), retry: String? = nil) { result = HTTPResult(data: data, status: status, retryAfter: retry) }
    func send(_ request: URLRequest) async throws -> HTTPResult { requests.append(request); return result }
    func captured() -> [URLRequest] { requests }
}
private final class CountingCredentialLoader: CredentialLoading, @unchecked Sendable {
    var calls = 0
    let credential: OAuthCredential
    init(expired: Bool = false) {
        credential = OAuthCredential(accessToken: "synthetic", accountID: nil, expiresAt: Date().addingTimeInterval(expired ? -3600 : 3600))
    }
    func read(provider: Provider, locations: CredentialLocations, allowPrompt: Bool) throws -> OAuthCredential {
        calls += 1; return credential
    }
}
private final class BlockedCredentialLoader: CredentialLoading, @unchecked Sendable {
    var calls = 0
    func read(provider: Provider, locations: CredentialLocations, allowPrompt: Bool) throws -> OAuthCredential {
        calls += 1; throw QuotaError.keychain(-25308)
    }
}
final class QuotaTests: XCTestCase {
    func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    func codex(_ used: Any = 28) throws -> Data {
        try data(["rate_limit": ["primary_window": ["used_percent": used, "limit_window_seconds": 604800, "reset_at": 1794000000], "secondary_window": ["used_percent": 0, "limit_window_seconds": 18000]]])
    }
    func claude() throws -> Data { try data(["five_hour": ["utilization": 20.5, "resets_at": "2026-10-29T06:00:00Z"], "seven_day": ["utilization": 100, "resets_at": "2026-11-01T06:00:00.000Z"]]) }
    func testCodexWindowDurationRatherThanSlot() throws {
        let value = try QuotaClient.decode(codex(), provider: .codex)
        XCTAssertEqual(value.windows[0].remaining, 72); XCTAssertEqual(value.windows[0].title, "주간 한도")
        XCTAssertEqual(value.windows[1].remaining, 100); XCTAssertEqual(value.windows[1].title, "5시간 한도")
    }
    func testClaudePercentageAndResetDate() throws {
        let value = try QuotaClient.decode(claude(), provider: .claude)
        XCTAssertEqual(value.windows.map(\.remaining), [79.5, 0]); XCTAssertNotNil(value.windows[1].resetsAt)
    }
    func testMissingWindowDoesNotBecomeZero() throws {
        let value = try QuotaClient.decode(data(["five_hour": NSNull(), "seven_day": ["utilization": 15]]), provider: .claude)
        XCTAssertEqual(value.windows.count,1); XCTAssertEqual(value.windows[0].minutes,10080)
        XCTAssertThrowsError(try QuotaClient.decode(data(["five_hour": NSNull()]),provider:.claude))
    }
    func testRejectBooleanStringAndOutOfRangePercentages() throws {
        for value: Any in [true, "28", -1, 101] {
            let result = try QuotaClient.decode(codex(value), provider: .codex)
            XCTAssertEqual(result.windows.count,1) // Only the valid secondary survives.
        }
    }
    func testCountdownAndExpired() {
        let w = QuotaWindow(id:"x",minutes:300,used:100,resetsAt:Date(timeIntervalSince1970:7260))
        XCTAssertEqual(w.countdown(at:Date(timeIntervalSince1970:0)),"2시간 1분 후 리셋")
        XCTAssertTrue(w.expired(at:Date(timeIntervalSince1970:7260))); XCTAssertEqual(w.remaining,0)
    }
    func testInvalidBody() { XCTAssertThrowsError(try QuotaClient.decode(Data("html".utf8),provider:.codex)) }
    func testCredentialsAreProjectedWithoutRefreshToken() throws {
        let credential = try CredentialReader.decode(data(["tokens":["access_token":"synthetic-access", "account_id":"synthetic-account", "refresh_token":"DO_NOT_COPY"]]),provider:.codex)
        XCTAssertEqual(credential.accessToken,"synthetic-access"); XCTAssertEqual(credential.accountID,"synthetic-account")
    }
    func testExpiredClaudeCredentials() throws {
        XCTAssertThrowsError(try CredentialReader.decode(data(["claudeAiOauth":["accessToken":"synthetic", "expiresAt":1]]),provider:.claude)) { XCTAssertEqual($0 as? QuotaError,.expiredLogin) }
    }
    func testClaudeInferenceOnlyTokenCannotQueryQuota() throws {
        XCTAssertThrowsError(try CredentialReader.decode(data(["claudeAiOauth":["accessToken":"synthetic", "scopes":["user:inference"]]]),provider:.claude)) { XCTAssertEqual($0 as? QuotaError,.scope) }
    }
    func testAPIKeyAndMCPOnlyCredentialsNotUsed() throws {
        XCTAssertThrowsError(try CredentialReader.decode(data(["OPENAI_API_KEY":"synthetic"]),provider:.codex))
        XCTAssertThrowsError(try CredentialReader.decode(data(["mcpOAuth":[:]]),provider:.claude))
    }
    func testCredentialHeaderInjectionRejected() throws {
        XCTAssertThrowsError(try CredentialReader.decode(data(["tokens":["access_token":"x\r\nInjected: true"]]),provider:.codex))
    }
    func testDirectCodexRequest() async throws {
        let transport = StubTransport(data: try codex())
        let service = DirectQuotaService(transport: transport)
        let value = try await service.fetch(provider:.codex,credential:OAuthCredential(accessToken:"synthetic",accountID:"account"))
        XCTAssertEqual(value.windows.count,2)
        let requests = await transport.captured(); let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString,"https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.httpMethod,"GET"); XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer synthetic")
        XCTAssertEqual(request.value(forHTTPHeaderField:"ChatGPT-Account-Id"),"account")
    }
    func testDirectClaudeRequestAndPrivacy() async throws {
        let transport = StubTransport(data: try claude()); let service = DirectQuotaService(transport:transport)
        let value = try await service.fetch(provider:.claude,credential:OAuthCredential(accessToken:"SECRET_TEST_VALUE",accountID:nil))
        let requests = await transport.captured()
        XCTAssertEqual(requests.first?.url?.host,"api.anthropic.com")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField:"anthropic-beta"),"oauth-2025-04-20")
        XCTAssertFalse(String(decoding:try JSONEncoder().encode(value),as:UTF8.self).contains("SECRET_TEST_VALUE"))
    }
    func testHTTPFailuresDoNotBecomeQuota() async throws {
        for (status, expected): (Int,QuotaError) in [(401,.expiredLogin),(403,.scope),(302,.redirected),(503,.server)] {
            let service = DirectQuotaService(transport: StubTransport(status:status))
            do { _ = try await service.fetch(provider:.codex,credential:OAuthCredential(accessToken:"synthetic",accountID:nil)); XCTFail("Expected error") }
            catch { XCTAssertEqual(error as? QuotaError,expected) }
        }
    }
    func testRateLimitBackoff() async throws {
        let transport = StubTransport(status:429,retry:"600"); let service = DirectQuotaService(transport:transport)
        for _ in 0..<2 {
            do { _ = try await service.fetch(provider:.claude,credential:OAuthCredential(accessToken:"synthetic",accountID:nil)); XCTFail("Expected rate limit") }
            catch { XCTAssertEqual(error as? QuotaError,.rateLimited) }
        }
        let requests = await transport.captured(); XCTAssertEqual(requests.count,1)
    }
    func testAutomaticRefreshNeverLoadsDefaultKeychain() async throws {
        let loader = CountingCredentialLoader()
        let service = DirectQuotaService(transport: StubTransport(data: try claude()), credentialLoader: loader)
        let locations = CredentialLocations(claudeHome: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"))
        for _ in 0..<3 {
            do { _ = try await service.fetch(provider: .claude, locations: locations); XCTFail("Must require explicit connection") }
            catch { XCTAssertEqual(error as? QuotaError, .connectionRequired) }
        }
        XCTAssertEqual(loader.calls, 0)
    }
    func testRepeatedQuotaRequestsReuseOneCredentialRead() async throws {
        let loader = CountingCredentialLoader(); let transport = StubTransport(data: try claude())
        let service = DirectQuotaService(transport: transport, credentialLoader: loader)
        _ = try await service.fetch(provider: .claude, allowKeychainPrompt: true)
        for _ in 0..<4 { _ = try await service.fetch(provider: .claude) }
        XCTAssertEqual(loader.calls, 1)
        let requests = await transport.captured(); XCTAssertEqual(requests.count, 5)
        await service.clearCredentials()
        do { _ = try await service.fetch(provider: .claude); XCTFail("Cache was cleared") }
        catch { XCTAssertEqual(error as? QuotaError, .connectionRequired) }
        XCTAssertEqual(loader.calls, 1)
    }
    func testUnauthorizedDoesNotTriggerKeychainRetry() async throws {
        let loader = CountingCredentialLoader()
        let service = DirectQuotaService(transport: StubTransport(status: 401), credentialLoader: loader)
        do { _ = try await service.fetch(provider: .claude, allowKeychainPrompt: true); XCTFail("401") }
        catch { XCTAssertEqual(error as? QuotaError, .expiredLogin) }
        do { _ = try await service.fetch(provider: .claude); XCTFail("No background credential retry") }
        catch { XCTAssertEqual(error as? QuotaError, .connectionRequired) }
        XCTAssertEqual(loader.calls, 1)
    }
    func testExpiredCredentialDoesNotSendHTTPOrRetryKeychain() async throws {
        let loader = CountingCredentialLoader(expired: true); let transport = StubTransport(data: try claude())
        let service = DirectQuotaService(transport: transport, credentialLoader: loader)
        do { _ = try await service.fetch(provider: .claude, allowKeychainPrompt: true); XCTFail("Expired credential") }
        catch { XCTAssertEqual(error as? QuotaError, .expiredLogin) }
        do { _ = try await service.fetch(provider: .claude); XCTFail("No background credential retry") }
        catch { XCTAssertEqual(error as? QuotaError, .connectionRequired) }
        XCTAssertEqual(loader.calls, 1)
        let requests = await transport.captured(); XCTAssertTrue(requests.isEmpty)
    }
    func testExplicitConnectionExposesKeychainStatusWithoutBackgroundRetry() async throws {
        let loader = BlockedCredentialLoader()
        let service = DirectQuotaService(transport: StubTransport(data: try claude()), credentialLoader: loader)
        do { _ = try await service.fetch(provider: .claude, allowKeychainPrompt: true); XCTFail("Expected Keychain failure") }
        catch {
            XCTAssertEqual(error as? QuotaError, .keychain(-25308))
            XCTAssertTrue((error as? QuotaError)?.message.contains("-25308") == true)
        }
        do { _ = try await service.fetch(provider: .claude); XCTFail("No background retry") }
        catch { XCTAssertEqual(error as? QuotaError, .connectionRequired) }
        XCTAssertEqual(loader.calls, 1)
    }
}
