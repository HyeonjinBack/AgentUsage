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
    @Published var quotas: [Provider: QuotaSnapshot] = [:]
    @Published var errors: [Provider: QuotaError] = [:]
    @Published var busy = false
    @Published var enabled = UserDefaults.standard.bool(forKey: "directEnabled")
    @Published var paused = false
    @Published var now = Date()
    @Published var codexHome = UserDefaults.standard.string(forKey: "codexHome") ?? CredentialLocations().codexHome.path
    @Published var claudeHome = UserDefaults.standard.string(forKey: "claudeHome") ?? CredentialLocations().claudeHome.path
    private let service = DirectQuotaService()
    private var generation = UUID()
    let systemMonitor = SystemMonitor()
    private var lastFetch = Date.distantPast
    init() {
        Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.enabled, !self.paused {
                    let tick = Date()
                    // Only this minute tick invalidates the quota countdown views.
                    if tick.timeIntervalSince(self.now) >= 60 { self.now = tick }
                    // System metrics publish to their own view, not the quota model.
                    self.systemMonitor.capture()
                    if tick.timeIntervalSince(self.lastFetch) >= 180 {
                        Task { [weak self] in await self?.refresh() }
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
    func refresh(allowPrompt: Bool = false, provider: Provider? = nil) async {
        guard !busy, !paused, enabled else { return }
        busy = true; lastFetch = Date(); defer { busy = false }
        let defaults = UserDefaults.standard
        let locations = CredentialLocations(codexHome: defaults.string(forKey: "codexHome").map { URL(fileURLWithPath: $0) }, claudeHome: defaults.string(forKey: "claudeHome").map { URL(fileURLWithPath: $0) })
        let operation = generation
        let service = service
        await withTaskGroup(of: (Provider, QuotaSnapshot?, QuotaError?).self) { group in
            for p in provider.map({ [$0] }) ?? Provider.allCases {
                group.addTask {
                    do { return (p, try await service.fetch(provider: p, locations: locations, allowKeychainPrompt: allowPrompt), nil) }
                    catch { return (p, nil, (error as? QuotaError) ?? .unavailable) }
                }
            }
            for await (p, value, error) in group {
                guard enabled, generation == operation else { continue }
                if let value { quotas[p] = value; errors[p] = nil }
                else {
                    // Preserve the actionable result of the last explicit connection.
                    if error != .connectionRequired || errors[p]?.requiresConnection != true { errors[p] = error }
                    if error?.requiresConnection == true { quotas[p] = nil }
                }
            }
        }
    }
    func connect() {
        guard !busy else { return }
        NSApp.activate(ignoringOtherApps: true)
        generation = UUID()
        UserDefaults.standard.set(codexHome, forKey: "codexHome"); UserDefaults.standard.set(claudeHome, forKey: "claudeHome")
        UserDefaults.standard.set(true, forKey: "directEnabled"); enabled = true
        paused = false; quotas = [:]; errors = [:]
        Task { await service.clearCredentials(); await refresh(allowPrompt: true) }
    }
    func disconnect() {
        generation = UUID(); enabled = false; quotas = [:]; errors = [:]; systemMonitor.clear()
        UserDefaults.standard.set(false, forKey: "directEnabled")
        Task { await service.clearCredentials() }
    }
    func connectClaude() {
        guard !busy, enabled else { return }
        NSApp.activate(ignoringOtherApps: true)
        paused = false
        Task {
            await service.clearCredentials(provider: .claude)
            await refresh(allowPrompt: true, provider: .claude)
        }
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
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let foreground: NSColor = colorScheme == .dark ? .white : .black
        let ai = MenuBarBadge.render(
            codexSession: model.bar(.codex, minutes: 300), codexWeekly: model.bar(.codex, minutes: 10080),
            claudeSession: model.bar(.claude, minutes: 300), claudeWeekly: model.bar(.claude, minutes: 10080),
            codexIcon: BadgeAssets.codex, claudeIcon: BadgeAssets.claude
        )
        let system = SystemMenuBarBadge.render(cpu: monitor.sample?.cpu, memoryUsed: monitor.sample?.memoryUsed,
                                             memoryTotal: monitor.sample?.memoryTotal, foreground: foreground)
        Image(nsImage: SystemMenuBarBadge.combine(ai: ai, system: system, foreground: foreground))
            .renderingMode(.original)
            .accessibilityLabel("Codex 세션 \(model.bar(.codex, minutes: 300)), 주간 \(model.bar(.codex, minutes: 10080)). Claude 세션 \(model.bar(.claude, minutes: 300)), 주간 \(model.bar(.claude, minutes: 10080)). \(systemDescription)")
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
            if !model.enabled {
                Text("Codex·Claude의 남은 한도와 리셋 시간을 한눈에 확인하세요.").foregroundStyle(.secondary)
                Text("기존 Codex·Claude Code 로그인으로 서비스에 직접 연결합니다. 로그인 정보는 기기에서 읽고, 한도 조회에만 사용합니다. Claude 연결 시 macOS 키체인 접근을 요청할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                Button("한도 확인 시작") { model.connect() }.buttonStyle(.borderedProminent)
            } else {
                ForEach(Provider.allCases, id: \.self) { provider in card(provider) }
                SystemMetricsView(monitor: model.systemMonitor)
            }
            Divider()
            HStack {
                Button("새로고침") { Task { await model.refresh() } }.disabled(model.busy || !model.enabled || model.paused)
                Button(model.paused ? "재개" : "일시 중지") { model.paused.toggle(); if !model.paused { Task { await model.refresh() } } }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                Button("종료") { NSApp.terminate(nil) }
            }.buttonStyle(.borderless).font(.caption)
        }
    }
    func card(_ provider: Provider) -> some View {
        let snapshot = model.quotas[provider]
        let stale = model.errors[provider] != nil || snapshot.map { model.now.timeIntervalSince($0.updated) >= 600 } == true
        return VStack(alignment: .leading, spacing: 12) {
            HStack { Text(provider.title).font(.headline); Spacer(); if stale { Text("이전 값").font(.caption).foregroundStyle(.orange) } }
            if let snapshot {
                ForEach(snapshot.windows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.title).font(.subheadline)
                            Spacer()
                            Text(window.expired(at: model.now) ? "갱신 필요" : String(format: "%.0f%% 남음", window.remaining)).font(.system(.headline, design: .rounded)).monospacedDigit()
                        }
                        if !window.expired(at: model.now) {
                            ProgressView(value: window.remaining, total: 100).tint(stale ? .gray : window.remaining < 20 ? .orange : .teal)
                        }
                        Text(window.countdown(at: model.now)).font(.caption).foregroundStyle(.secondary)
                        if let reset = window.resetsAt { Text(reset.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary) }
                    }
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
struct SystemMetricsView: View {
    @ObservedObject var monitor: SystemMonitor
    var body: some View {
        if let s = monitor.sample {
            HStack {
                Label(s.cpu.map { String(format: "CPU %.0f%%", $0) } ?? "CPU …", systemImage: "cpu")
                Spacer()
                Text(s.memoryUsed >= 0 ? String(format: "%.1f GB", s.memoryUsed / 1e9) : "메모리 —")
                Spacer()
                Label(s.battery.map { String(format: "%.0f%%", $0) } ?? "—", systemImage: s.onAC ? "battery.100percent.bolt" : "battery.75percent")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct ConnectionView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Text("한도 연결").font(.title2.bold())
            Text("AgentMeter \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 버전")")
                .font(.caption).foregroundStyle(.secondary)
            Text("Codex·Claude Code에 로그인한 구독 계정을 사용합니다. 인증정보를 새로 저장하거나 외부 CLI를 실행하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            Button("로그인 정보 연결 / 키체인 접근 허용") { model.connect() }.disabled(model.busy)
            Button("연결 해제") { model.disconnect() }
            DisclosureGroup("사용자 지정 로그인 폴더") {
                TextField("Codex 홈", text: $model.codexHome)
                TextField("Claude 홈", text: $model.claudeHome)
                Text("사용자 지정 Claude 폴더는 해당 폴더의 로그인 파일을 읽습니다. 기본 Claude 프로필은 macOS 키체인을 사용합니다.").font(.caption)
            }
            Divider()
            Text("3분마다 한도를 조회합니다. 메뉴 막대는 각 아이콘 오른쪽 위에 세션 잔여량, 아래에 주간 잔여량을 표시합니다. 10분 이상 지난 값이나 조회 실패는 — 로 표시합니다. 이 버전은 이력을 저장하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            Text("로그인이 만료되면 Codex·Claude Code에서 갱신한 뒤 새로고침하세요. 자동 조회와 새로고침은 기본 Claude 프로필의 키체인에 접근하지 않습니다. 인증 갱신은 위 연결 버튼에서만 수행합니다.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
