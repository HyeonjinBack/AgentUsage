import SwiftUI
import AppKit
import AgentMeterCore

struct QuotaFooterView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 12) {
            if model.enabled {
                HStack(spacing: 8) {
                    Text(updateStatus)
                    Spacer()
                    if let sample = monitor.sample, let battery = sample.battery {
                        let percent = String(format: "%.0f%%", battery)
                        Label(percent, systemImage: batterySymbol(for: battery, charging: sample.charging))
                            .monospacedDigit()
                            .accessibilityLabel(sample.charging ? "배터리 \(percent), 충전 중" : "배터리 \(percent)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            }

            HStack(spacing: 6) {
                if model.enabled {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("새로고침", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FooterButtonStyle(prominent: true))
                    .disabled(model.busy || model.paused)

                    Button {
                        model.paused.toggle()
                        if !model.paused {
                            Task { await model.refresh() }
                        }
                    } label: {
                        Label(model.paused ? "재개" : "일시 중지", systemImage: model.paused ? "play.fill" : "pause.fill")
                            .frame(minWidth: 64)
                    }
                    .buttonStyle(FooterButtonStyle(prominent: false))
                } else {
                    Spacer(minLength: 0)
                }

                Menu {
                    SettingsLink { Label("설정", systemImage: "gearshape") }
                    Divider()
                    Button("종료", systemImage: "power") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.primary.opacity(0.15))
                        .allowsHitTesting(false)
                }
                .help("설정 및 종료")
                .accessibilityLabel("설정 및 종료")
            }
            .font(.caption.weight(.medium))
        }
    }

    private var updateStatus: String {
        if model.busy { return "한도 조회 중" }
        guard let lastUpdate = model.quotas.values.map(\.updated).max() else { return "한도 조회 기록 없음" }
        if model.now.timeIntervalSince(lastUpdate) < 60 { return "방금 업데이트" }
        return "최근 조회 \(lastUpdate.formatted(date: .omitted, time: .shortened))"
    }

    private func batterySymbol(for percent: Double, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

private struct FooterButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(.primary.opacity(configuration.isPressed ? 0.24 : prominent ? 0.14 : 0.04), in: shape)
            .overlay { shape.strokeBorder(.primary.opacity(prominent ? 0 : 0.15)) }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
    }
}
