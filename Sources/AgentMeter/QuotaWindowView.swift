import SwiftUI
import AgentMeterCore

struct QuotaWindowView: View {
    let window: QuotaWindow
    let now: Date
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.title).font(.subheadline)
                Spacer()
                Text(window.expired(at: now) ? "갱신 필요" : String(format: "%.0f%% 남음", window.remaining))
                    .font(.system(.headline, design: .rounded)).monospacedDigit()
            }
            if !window.expired(at: now) {
                ProgressView(value: window.remaining, total: 100)
                    .tint(stale ? .gray : window.remaining < 20 ? .orange : .teal)
            }
            HStack(alignment: .firstTextBaseline) {
                Label("초기화까지", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(window.countdown(at: now))
                    .fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(window.expired(at: now) ? Color.orange : Color.primary)
                    .multilineTextAlignment(.trailing)
            }.font(.caption)
            HStack(alignment: .firstTextBaseline) {
                Text("다음 초기화").foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let reset = window.resetsAt {
                    Text(reset, format: .dateTime.locale(Locale(identifier: "ko_KR"))
                        .month().day().weekday(.abbreviated).hour().minute())
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("서비스에서 시각 미제공").foregroundStyle(.secondary)
                }
            }.font(.caption)
            .help("Mac의 현재 시간대(\(TimeZone.current.identifier)) 기준")
        }
        .accessibilityElement(children: .combine)
    }
}
