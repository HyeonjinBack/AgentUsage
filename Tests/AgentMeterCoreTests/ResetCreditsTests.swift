import XCTest
@testable import AgentMeterCore

private actor CouponTransport: QuotaTransport {
    let couponResult: HTTPResult
    var requests: [URLRequest] = []
    init(status: Int = 200, body: Data, retry: String? = nil) {
        couponResult = HTTPResult(data: body, status: status, retryAfter: retry)
    }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        if request.url?.path == "/backend-api/wham/usage" {
            return HTTPResult(data: Data(#"{"rate_limit":{"primary_window":{"used_percent":20,"limit_window_seconds":18000}}}"#.utf8), status: 200)
        }
        return couponResult
    }
    func captured() -> [URLRequest] { requests }
}

private actor PendingUsageTransport: QuotaTransport {
    let started: XCTestExpectation
    private var usageResponse: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var paths: [String] = []

    init(started: XCTestExpectation) { self.started = started }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? ""
        paths.append(path)
        if path == "/backend-api/wham/usage" {
            if !released {
                await withCheckedContinuation {
                    usageResponse = $0
                    started.fulfill()
                }
            }
            return HTTPResult(data: Data(#"{"rate_limit":{"primary_window":{"used_percent":20,"limit_window_seconds":18000}}}"#.utf8), status: 200)
        }
        return HTTPResult(data: Data(#"{"available_count":0}"#.utf8), status: 200)
    }

    func finishUsage() {
        released = true
        usageResponse?.resume()
        usageResponse = nil
    }
}

final class ResetCreditsTests: XCTestCase {
    func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    func row(_ id: String, expiry: Any = "2027-01-02T12:30:00.123456Z", status: String = "available") -> [String: Any] {
        ["id": id, "reset_type": "codex_rate_limits", "status": status, "expires_at": expiry]
    }
    func testResetCreditsDatesAndAuthoritativeCount() throws {
        let result = try QuotaClient.decodeResetCredits(data([
            "available_count": 3, "credits": [row("later", expiry: "2027-01-03T12:30:00Z"), row("first")],
            "history_enabled": true, "total_earned_count": 8
        ]))
        XCTAssertEqual(result.availableCount, 3)
        XCTAssertEqual(result.availableCredits.map(\.id), ["first", "later"])
        XCTAssertNotNil(result.availableCredits.first?.expiresAt) // ISO timestamps include microseconds.
        XCTAssertFalse(result.completeExpiryDetails)
    }
    func testCountOnlyAndMissingExpiryNeverBecomeZeroOrUnlimited() throws {
        for details: Any in [NSNull(), [] as [[String: Any]], [row("one", expiry: NSNull())]] {
            let result = try QuotaClient.decodeResetCredits(data(["available_count": 2, "credits": details]))
            XCTAssertEqual(result.availableCount, 2)
            XCTAssertFalse(result.completeExpiryDetails)
            if let credit = result.availableCredits.first {
                XCTAssertEqual(credit.countdown(at: Date()), "만료 시각 미제공")
            }
        }
        let missing = try QuotaClient.decodeResetCredits(data(["available_count": 2]))
        XCTAssertNil(missing.credits)
    }
    func testInvalidCountDoesNotBecomeNoCoupons() throws {
        for count: Any in [true, -1, 0.5, "3", NSNull()] {
            XCTAssertThrowsError(try QuotaClient.decodeResetCredits(data(["available_count": count, "credits": []])))
        }
        XCTAssertThrowsError(try QuotaClient.decodeResetCredits(data(["credits": []])))
        let zero = try QuotaClient.decodeResetCredits(data(["available_count": 0, "credits": []]))
        XCTAssertEqual(zero.availableCount, 0)
    }
    func testAvailableRowsExcludeRedeemedAndDeduplicateIDs() throws {
        let result = try QuotaClient.decodeResetCredits(data([
            "available_count": 1, "credits": [row("one"), row("one"), row("old", status: "redeemed")]
        ]))
        XCTAssertEqual(result.availableCredits.map(\.id), ["one"])
        XCTAssertTrue(result.completeExpiryDetails)
    }
    func testCouponCountdownAfterDayAndAtExpiry() {
        let now = Date(timeIntervalSince1970: 0)
        let expiry = now.addingTimeInterval(103 * 3600 + 28 * 60)
        let credit = RateLimitResetCredit(id: "one", resetType: "codex_rate_limits", status: "available", expiresAt: expiry)
        XCTAssertEqual(credit.countdown(at: now), "103시간 28분 남음")
        XCTAssertEqual(credit.countdown(at: now.addingTimeInterval(60)), "103시간 27분 남음")
        XCTAssertEqual(credit.countdown(at: expiry.addingTimeInterval(-1)), "1분 남음")
        XCTAssertEqual(credit.countdown(at: expiry), "유효기간 만료 · 갱신 필요")
        XCTAssertEqual(credit.countdown(at: expiry.addingTimeInterval(60)), "유효기간 만료 · 갱신 필요")
    }
    func testInvalidExpiryDoesNotCrashCountdown() throws {
        for expiry: Any in [true, Double.greatestFiniteMagnitude, "not-a-date"] {
            let result = try QuotaClient.decodeResetCredits(data(["available_count": 1, "credits": [row("one", expiry: expiry)]]))
            let credit = try XCTUnwrap(result.availableCredits.first)
            XCTAssertNil(credit.expiresAt)
            XCTAssertEqual(credit.countdown(at: Date()), "만료 시각 미제공")
        }
    }
    func testCodexFetchAddsReadOnlyCouponQueryWithSameAccount() async throws {
        let transport = CouponTransport(body: try data(["available_count": 1, "credits": [row("one")]]))
        let service = DirectQuotaService(transport: transport)
        let result = try await service.fetch(provider: .codex, credential: OAuthCredential(accessToken: "SYNTHETIC_TEST_CREDENTIAL", accountID: "synthetic-account"))
        XCTAssertEqual(result.windows.first?.remaining, 80)
        XCTAssertEqual(result.resetCredits?.availableCount, 1)
        XCTAssertNil(result.resetCreditsError)
        let requests = await transport.captured()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://chatgpt.com/backend-api/wham/usage",
            "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
        ])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer SYNTHETIC_TEST_CREDENTIAL")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "synthetic-account")
        }
        let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        XCTAssertFalse(encoded.contains("SYNTHETIC_TEST_CREDENTIAL"))
        XCTAssertFalse(encoded.contains("synthetic-account"))
    }
    func testCouponFailureDoesNotDiscardWorkingQuota() async throws {
        for status in [401, 403, 404, 500, 302] {
            let transport = CouponTransport(status: status, body: Data())
            let result = try await DirectQuotaService(transport: transport).fetch(provider: .codex, credential: OAuthCredential(accessToken: "synthetic", accountID: nil))
            XCTAssertEqual(result.windows.first?.remaining, 80)
            XCTAssertNil(result.resetCredits)
            XCTAssertNotNil(result.resetCreditsError)
        }
    }
    func testCouponRateLimitBackoffDoesNotBlockQuotaRequests() async throws {
        let transport = CouponTransport(status: 429, body: Data(), retry: "600")
        let service = DirectQuotaService(transport: transport)
        for _ in 0..<2 {
            let result = try await service.fetch(provider: .codex, credential: OAuthCredential(accessToken: "synthetic", accountID: nil))
            XCTAssertEqual(result.windows.first?.remaining, 80)
            XCTAssertEqual(result.resetCreditsError, QuotaError.rateLimited.message)
        }
        let requests = await transport.captured()
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("/usage") == true }.count, 2)
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("/rate-limit-reset-credits") == true }.count, 1)
    }

    func testCancelDuringCodexUsageDoesNotStartCouponRequest() async {
        let started = expectation(description: "Codex usage request started")
        let transport = PendingUsageTransport(started: started)
        let service = DirectQuotaService(transport: transport)
        let task = Task {
            try await service.fetch(provider: .codex, credential: OAuthCredential(accessToken: "synthetic", accountID: nil))
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await transport.finishUsage()
        guard case .failure(let error) = await task.result else {
            return XCTFail("Cancelled usage request returned a snapshot")
        }
        XCTAssertTrue(error is CancellationError)
        let paths = await transport.paths
        XCTAssertEqual(paths, ["/backend-api/wham/usage"])
    }
}
