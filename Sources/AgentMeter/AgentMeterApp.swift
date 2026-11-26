import SwiftUI
import AppKit
import Combine
import AgentMeterCore

@MainActor final class SystemMonitor: ObservableObject {
    @Published private(set) var sample: SystemSample?
    private let sampler = SystemSampler()
    func capture() { sample = sampler.sample() }
    func clear() { sample = nil }
}

@MainActor final class AppModel: ObservableObject {
    private struct Request {
        let id: UUID
        let task: Task<Void, Never>
    }

    @Published var quotas: [Provider: QuotaSnapshot] = [:]
    @Published var errors: [Provider: QuotaError] = [:]
    @Published private var requests: [Provider: Request] = [:]
    @Published private(set) var selectedProviders = Provider.allCases.filter {
        UserDefaults.standard.object(forKey: "trackProvider.\($0.rawValue)") as? Bool ?? true
    }
    @Published var enabled = UserDefaults.standard.bool(forKey: "directEnabled")
    @Published var paused = false
    @Published var now = Date()
    @Published var codexHome = UserDefaults.standard.string(forKey: "codexHome") ?? CredentialLocations().codexHome.path
    @Published var claudeHome = UserDefaults.standard.string(forKey: "claudeHome") ?? CredentialLocations().claudeHome.path
    private let service = DirectQuotaService()
    private var credentialCleanup: Task<Void, Never>?
    let systemMonitor = SystemMonitor()
    private var lastFetch: [Provider: Date] = [:]
    var busy: Bool { !requests.isEmpty }

    init() {
        Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.enabled {
                    let tick = Date()
                    // Only this minute tick invalidates the quota countdown views.
                    if tick.timeIntervalSince(self.now) >= 60 { self.now = tick }
                    // System metrics publish to their own view, not the quota model.
                    if !self.paused {
                        self.systemMonitor.capture()
                        for provider in self.selectedProviders
                        where tick.timeIntervalSince(self.lastFetch[provider] ?? .distantPast) >= 180 {
                            self.refresh(provider: provider)
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
    func setTracking(_ provider: Provider, enabled: Bool) {
        guard selectedProviders.contains(provider) != enabled else { return }
        UserDefaults.standard.set(enabled, forKey: "trackProvider.\(provider.rawValue)")
        if enabled {
            selectedProviders = Provider.allCases.filter { $0 == provider || selectedProviders.contains($0) }
            refresh(provider: provider)
        } else {
            selectedProviders.removeAll { $0 == provider }
            requests.removeValue(forKey: provider)?.task.cancel()
            quotas.removeValue(forKey: provider)
            errors.removeValue(forKey: provider)
            lastFetch.removeValue(forKey: provider)
            clearCachedCredentials(for: provider)
        }
    }
    private func clearCachedCredentials(for provider: Provider? = nil) {
        credentialCleanup = Task { [service, previous = credentialCleanup] in
            await previous?.value
            await service.clearCredentials(provider: provider)
        }
    }
    func refresh(allowPrompt: Bool = false, provider: Provider? = nil) {
        guard !paused, enabled else { return }
        let targets = selectedProviders.filter {
            (provider == nil || provider == $0) && requests[$0] == nil
        }
        guard !targets.isEmpty else { return }
        now = Date()
        let defaults = UserDefaults.standard
        let locations = CredentialLocations(codexHome: defaults.string(forKey: "codexHome").map { URL(fileURLWithPath: $0) }, claudeHome: defaults.string(forKey: "claudeHome").map { URL(fileURLWithPath: $0) })
        for target in targets {
            let id = UUID()
            lastFetch[target] = now
            let task = Task { [weak self, service, credentialCleanup] in
                let result: Result<QuotaSnapshot, QuotaError>
                do {
                    await credentialCleanup?.value
                    try Task.checkCancellation()
                    if allowPrompt { await service.clearCredentials(provider: target) }
                    let snapshot = try await service.fetch(provider: target, locations: locations, allowKeychainPrompt: allowPrompt)
                    result = .success(snapshot)
                } catch {
                    result = .failure((error as? QuotaError) ?? .unavailable)
                }
                guard let self, self.requests[target]?.id == id else { return }
                self.requests[target] = nil
                self.apply(result, for: target)
            }
            requests[target] = Request(id: id, task: task)
        }
    }
    private func apply(_ result: Result<QuotaSnapshot, QuotaError>, for provider: Provider) {
        switch result {
        case .success(let snapshot):
            quotas[provider] = snapshot
            errors[provider] = nil
        case .failure(let error):
            // Preserve the actionable result of the last explicit connection.
            if error != .connectionRequired || errors[provider]?.requiresConnection != true {
                errors[provider] = error
            }
            if error.requiresConnection { quotas[provider] = nil }
        }
    }
    func connect() {
        guard !busy, !selectedProviders.isEmpty else { return }
        if selectedProviders.contains(.claude) { NSApp.activate(ignoringOtherApps: true) }
        UserDefaults.standard.set(codexHome, forKey: "codexHome"); UserDefaults.standard.set(claudeHome, forKey: "claudeHome")
        UserDefaults.standard.set(true, forKey: "directEnabled"); enabled = true
        paused = false; quotas = [:]; errors = [:]
        refresh(allowPrompt: true)
    }
    func disconnect() {
        for request in requests.values { request.task.cancel() }
        requests.removeAll()
        lastFetch.removeAll()
        enabled = false; quotas = [:]; errors = [:]; systemMonitor.clear()
        UserDefaults.standard.set(false, forKey: "directEnabled")
        clearCachedCredentials()
    }
    func connectClaude() {
        guard enabled, selectedProviders.contains(.claude), requests[.claude] == nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        paused = false
        refresh(allowPrompt: true, provider: .claude)
    }
    func bar(_ provider: Provider, minutes: Int) -> String {
        guard errors[provider] == nil, let snapshot = quotas[provider], now.timeIntervalSince(snapshot.updated) < 600,
              let window = snapshot.windows.first(where: { $0.minutes == minutes }), !window.expired(at: now) else { return "—" }
        return String(format: "%.0f%%", window.remaining)
    }
}

@main struct AgentMeterApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        MenuBarExtra {
            QuotaView(model: model).padding(20).frame(width: 370)
        } label: {
            StatusBarLabel(model: model, monitor: model.systemMonitor)
        }.menuBarExtraStyle(.window)
        Settings { ConnectionView(model: model).padding(24).frame(width: 520) }
    }
}
struct StatusBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: SystemMonitor
    @AppStorage("claudeIconStyle") private var claudeIconStyle: ClaudeIconStyle = .logo
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let foreground: NSColor = colorScheme == .dark ? .white : .black
        let groups = model.selectedProviders.map { provider in
            MenuBarBadge.Group(session: model.bar(provider, minutes: 300),
                               weekly: model.bar(provider, minutes: 10080),
                               icon: provider == .codex ? BadgeAssets.codex : claudeIconStyle.image)
        }
        let quotaDescriptions = model.selectedProviders.map { provider in
            "\(provider.title) 세션 \(model.bar(provider, minutes: 300)), 주간 \(model.bar(provider, minutes: 10080))"
        }
        let system = SystemMenuBarBadge.render(cpu: monitor.sample?.cpu, memoryUsed: monitor.sample?.memoryUsed,
                                             memoryTotal: monitor.sample?.memoryTotal, foreground: foreground)
        let badge = groups.isEmpty ? system : SystemMenuBarBadge.combine(
            ai: MenuBarBadge.render(groups), system: system, foreground: foreground
        )
        Image(nsImage: badge)
            .renderingMode(.original)
            .accessibilityLabel((quotaDescriptions + [systemDescription]).joined(separator: ". "))
    }
    private var systemDescription: String {
        guard let s = monitor.sample else { return "시스템 지표 측정 중" }
        let cpu = s.cpu.map { String(format: "CPU %.0f퍼센트 사용", $0) } ?? "CPU 측정 중"
        let memory = s.memoryUsed >= 0 ? String(format: "메모리 %.1fGB 사용", s.memoryUsed / 1e9) : "메모리 측정 불가"
        return "\(cpu), \(memory)"
    }
}
struct QuotaView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("얼마나 더 쓸 수 있지?").font(.title3.bold()); Spacer(); if model.busy { ProgressView().controlSize(.small) } }
            if model.selectedProviders.isEmpty {
                Text("설정에서 한도를 확인할 서비스를 켜세요.").foregroundStyle(.secondary)
            } else if !model.enabled {
                Text("남은 한도와 리셋 시간을 한눈에 확인하세요.").foregroundStyle(.secondary)
                Text("선택한 서비스의 기존 로그인으로 연결합니다. 로그인 정보는 한도 조회에만 사용합니다.").font(.caption).foregroundStyle(.secondary)
                if model.selectedProviders.contains(.claude) {
                    Text("Claude 연결 시 macOS 키체인 접근을 요청할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                }
                Button("한도 확인 시작") { model.connect() }.buttonStyle(.borderedProminent)
            } else {
                ForEach(model.selectedProviders, id: \.self) { provider in card(provider) }
            }
            QuotaFooterView(model: model, monitor: model.systemMonitor)
        }
    }
    func card(_ provider: Provider) -> some View {
        let snapshot = model.quotas[provider]
        let stale = model.errors[provider] != nil || snapshot.map { model.now.timeIntervalSince($0.updated) >= 600 } == true
        return VStack(alignment: .leading, spacing: 12) {
            HStack { Text(provider.title).font(.headline); Spacer(); if stale { Text("이전 값").font(.caption).foregroundStyle(.orange) } }
            if let snapshot {
                ForEach(snapshot.windows) { window in
                    QuotaWindowView(window: window, now: model.now, stale: stale)
                }
                if provider == .codex {
                    Divider()
                    ResetCreditsView(credits: snapshot.resetCredits, errorMessage: snapshot.resetCreditsError, now: model.now)
                }
                Text("\(snapshot.updated.formatted(date: .omitted, time: .standard)) 확인 · \(snapshot.source)").font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack { Text("5시간  —"); Spacer(); Text("주간  —") }.foregroundStyle(.secondary)
            }
            if let error = model.errors[provider] {
                Text(error.message).font(.caption).foregroundStyle(.orange)
                if provider == .claude, error.requiresConnection {
                    Button("Claude 연결 / 인증 다시 읽기") { model.connectClaude() }
                        .buttonStyle(.bordered).controlSize(.small).disabled(model.busy)
                        .help("이 버튼을 누를 때만 Claude 키체인 접근을 요청합니다.")
                }
            }
        }.padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct ConnectionView: View {
    @ObservedObject var model: AppModel
    @AppStorage("claudeIconStyle") private var claudeIconStyle: ClaudeIconStyle = .logo
    var body: some View {
        Form {
            Text("한도 연결").font(.title2.bold())
            Text("AgentMeter \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 버전")")
                .font(.caption).foregroundStyle(.secondary)
            Section("한도 조회 서비스") {
                ForEach(Provider.allCases, id: \.self) { provider in
                    Toggle(provider.title, isOn: Binding(
                        get: { model.selectedProviders.contains(provider) },
                        set: { model.setTracking(provider, enabled: $0) }
                    ))
                }
                Text("끈 서비스는 한도를 조회하지 않으며 메뉴 막대와 팝업에서 숨깁니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Codex·Claude Code에 로그인한 구독 계정을 사용합니다. 인증정보를 새로 저장하거나 외부 CLI를 실행하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            Button(model.selectedProviders.contains(.claude) ? "로그인 정보 연결 / 키체인 접근 허용" : "로그인 정보 연결") {
                model.connect()
            }.disabled(model.busy || model.selectedProviders.isEmpty)
            Button("연결 해제") { model.disconnect() }
            DisclosureGroup("사용자 지정 로그인 폴더") {
                TextField("Codex 홈", text: $model.codexHome)
                TextField("Claude 홈", text: $model.claudeHome)
                Text("사용자 지정 Claude 폴더는 해당 폴더의 로그인 파일을 읽습니다. 기본 Claude 프로필은 macOS 키체인을 사용합니다.").font(.caption)
            }
            Divider()
            Text("메뉴 막대 모양").font(.headline)
            Picker("Claude 아이콘", selection: $claudeIconStyle) {
                ForEach(ClaudeIconStyle.allCases) { style in
                    HStack(spacing: 8) {
                        if let image = style.image {
                            Image(nsImage: image).renderingMode(.template)
                                .resizable().scaledToFit().frame(width: 18, height: 18)
                        }
                        Text(style.title)
                    }.tag(style)
                }
            }
            .pickerStyle(.radioGroup)
            Text("선택한 아이콘은 메뉴 막대에 바로 적용되며 다음 실행에도 유지됩니다.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("3분마다 한도를 조회합니다. 메뉴 막대는 각 아이콘 오른쪽 위에 세션 잔여량, 아래에 주간 잔여량을 표시합니다. 상세 화면의 초기화까지 남은 시간은 1분마다 갱신하며, 다음 초기화 시각은 Mac의 시간대로 표시합니다. 10분 이상 지난 값이나 조회 실패는 — 로 표시합니다. 이 버전은 이력을 저장하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            Text("로그인이 만료되면 Codex·Claude Code에서 갱신한 뒤 새로고침하세요. 자동 조회와 새로고침은 기본 Claude 프로필의 키체인에 접근하지 않습니다. 인증 갱신은 위 연결 버튼에서만 수행합니다.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
