import Foundation
public enum Provider: String, Codable, CaseIterable, Sendable {
    case codex, claude
    public var title: String { self == .codex ? "Codex" : "Claude Code" }
}
public struct SystemSample: Codable, Sendable {
    public var date: Date
    public var cpu: Double?
    public var memoryUsed: Double
    public var memoryTotal: Double
    public var compressed: Double
    public var battery: Double?
    public var charging: Bool
    public var onAC: Bool
}
public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var minutes: Int?
    public var used: Double
    public var resetsAt: Date?
    public var remaining: Double { max(0, min(100, 100 - used)) }
    public var title: String {
        switch minutes {
        case 300: return "5시간 한도"
        case 10080: return "주간 한도"
        case .some(let value): return "\(value / 60)시간 한도"
        case nil: return "추가 한도"
        }
    }
    public func expired(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }
    public func countdown(at now: Date) -> String {
        guard let resetsAt else { return "리셋 시각 미제공" }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return "리셋 시각 경과 · 갱신 필요" }
        let minutes = Int(ceil(seconds / 60)); let hours = minutes / 60
        if hours >= 24 { return "\(hours / 24)일 \(hours % 24)시간 후 리셋" }
        if hours > 0 { return "\(hours)시간 \(minutes % 60)분 후 리셋" }
        return "\(minutes)분 후 리셋"
    }
}
public struct QuotaSnapshot: Codable, Sendable {
    public var provider: Provider
    public var windows: [QuotaWindow]
    public var updated: Date
    public var source: String
}
public enum QuotaError: Error, Equatable, Sendable {
    case network, login, expiredLogin, connectionRequired, credentialAccess, scope, rateLimited, redirected, server, timeout, invalid, unavailable
    case keychain(Int32)
    public var rawValue: String {
        if case .keychain(let status) = self { return "keychain(\(status))" }
        return String(describing: self)
    }
    public var requiresConnection: Bool {
        switch self {
        case .login, .expiredLogin, .connectionRequired, .credentialAccess, .scope, .keychain: return true
        default: return false
        }
    }
    public var message: String {
        switch self {
        case .network: return "네트워크 연결을 확인한 뒤 새로고침하세요."
        case .login: return "Codex 또는 Claude Code에서 구독 계정으로 로그인하세요."
        case .expiredLogin: return "로그인이 만료됐습니다. 해당 도구에서 로그인을 갱신하세요."
        case .connectionRequired: return "앱 실행 후 Claude 연결이 필요합니다. 아래 연결 버튼을 눌러 주세요."
        case .credentialAccess: return "로그인 정보를 읽지 못했습니다. 연결 버튼을 누르고 macOS 키체인 창에서 허용해 주세요."
        case .keychain(let status): return "macOS 키체인 인증정보를 읽지 못했습니다 (오류 \(status)). Claude 연결 버튼으로 다시 시도해 주세요."
        case .scope: return "한도 조회 접근이 거부됐습니다. 구독 로그인과 계정 권한을 확인하세요."
        case .rateLimited: return "조회 요청이 제한됐습니다. 잠시 후 자동으로 다시 확인합니다."
        case .redirected: return "예상하지 않은 응답 경로입니다. 연결을 중단했습니다."
        case .server: return "서비스에서 오류를 반환했습니다. 잠시 후 다시 확인하세요."
        case .timeout: return "조회 시간이 초과됐습니다. 잠시 후 다시 시도하세요."
        case .invalid: return "한도 응답 형식을 읽을 수 없습니다."
        case .unavailable: return "이 계정의 한도 정보를 가져오지 못했습니다."
        }
    }
}
func quotaDate(_ value: Any?) -> Date? {
    if let n = value as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
    guard let text = value as? String else { return nil }
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}
