import SwiftUI
import AgentMeterCore

struct ResetCreditsView: View {
    let credits: RateLimitResetCredits?
    let errorMessage: String?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("초기화 쿠폰", systemImage: "ticket")
                Spacer()
                Text(credits.map { "\($0.availableCount)장" } ?? "—")
                    .fontWeight(.semibold).monospacedDigit()
            }.font(.subheadline)
            if let credits {
                if credits.availableCount == 0 {
                    Text("사용 가능한 초기화 쿠폰이 없습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    if let first = credits.availableCredits.first, first.expiresAt != nil {
                        HStack(alignment: .firstTextBaseline) {
                            Text(credits.completeExpiryDetails ? "가장 빠른 만료" : "확인된 가장 빠른 만료")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(first.countdown(at: now)).fontWeight(.semibold).monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(expiryColor(first))
                        }.font(.caption)
                        expiryDate(first)
                    } else {
                        Text("쿠폰 만료 시각을 제공받지 못했습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !credits.availableCredits.isEmpty {
                        DisclosureGroup("쿠폰별 만료 정보") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(credits.availableCredits) { credit in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(credit.title).foregroundStyle(.secondary)
                                            Spacer(minLength: 8)
                                            Text(credit.countdown(at: now)).monospacedDigit()
                                                .multilineTextAlignment(.trailing)
                                                .foregroundStyle(expiryColor(credit))
                                        }
                                        expiryDate(credit)
                                    }
                                }
                            }.font(.caption).padding(.top, 5)
                        }.font(.caption)
                    }
                    if credits.availableCredits.count < credits.availableCount {
                        Text("일부 쿠폰의 상세정보는 제공되지 않았습니다.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(errorMessage ?? "쿠폰 정보를 제공받지 못했습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func expiryDate(_ credit: RateLimitResetCredit) -> some View {
        if let expiry = credit.expiresAt {
            let formatted = expiry.formatted(.dateTime.locale(Locale(identifier: "ko_KR"))
                .month().day().weekday(.abbreviated).hour().minute())
            HStack {
                Spacer(minLength: 0)
                Text("만료: \(formatted)")
                    .monospacedDigit()
            }.font(.caption2).foregroundStyle(.secondary)
            .help("Mac의 현재 시간대(\(TimeZone.current.identifier)) 기준")
        }
    }

    private func expiryColor(_ credit: RateLimitResetCredit) -> Color {
        guard let expiry = credit.expiresAt else { return .secondary }
        return expiry.timeIntervalSince(now) <= 24 * 3600 ? .orange : .primary
    }
}
