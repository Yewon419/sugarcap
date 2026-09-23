import OSLog
import SwiftUI

/// 무엇을 먹이는지. 오늘 화면이 정산 상태를 보고 고른다(SPEC §4.7).
struct FeedingRequest: Identifiable, Equatable {
    enum Kind: Equatable {
        /// 오늘 마감. 적립은 하루가 바뀐 뒤 최종 값으로 한다.
        case closeToday
        /// 어제 미마감분 또는 "안 마셨어요". 하루가 끝났으니 바로 적립한다.
        case pastDay(DayKey)
    }

    let kind: Kind
    let sugarLeftG: Double
    let caffeineLeftMg: Double

    var id: String {
        switch kind {
        case .closeToday: return "close-today"
        case .pastDay(let day): return "past-\(day.rawValue)"
        }
    }

    func left(_ side: CupSide) -> Double {
        switch side {
        case .sugar: return sugarLeftG
        case .caffeine: return caffeineLeftMg
        }
    }
}

/// 남은 당은 로슈에게, 남은 카페인은 카인에게 먹인다(§4.7). 먹이기 전엔 남은 양, 먹인 뒤엔 반응.
/// 무료 범위라 호감도 수치는 보여 주지 않고 단계 상승만 알린다(§6, 수치 확인은 Pro).
struct FeedingView: View {
    let request: FeedingRequest
    let onFeed: () throws -> [FeedResult]

    @Environment(\.dismiss) private var dismiss
    @Environment(ProStore.self) private var pro
    @State private var results: [FeedResult]?
    @State private var paywall: ProFeature?
    @State private var isAffinityPresented = false
    @State private var errorText: String?
    @State private var bounce = false

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "feeding")

    private var isFed: Bool { results != nil }

    private var title: String {
        switch request.kind {
        case .closeToday: return "오늘 마감"
        case .pastDay: return "어제 남은 음료"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(CupSide.allCases) { side in
                        characterCard(side)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if isFed, request.kind == .closeToday {
                        Text("마감 뒤에 마신 음료도 오늘 몫으로 빠져요. 하루가 바뀌면 반영돼요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if isFed {
                        Button("호감도 자세히") {
                            if pro.isPro {
                                isAffinityPresented = true
                            } else {
                                paywall = .affinityDetail
                            }
                        }
                        .font(.subheadline)
                        .accessibilityIdentifier("feeding-affinity")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("feeding-close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if isFed { dismiss() } else { feed() }
                } label: {
                    Text(isFed ? "완료" : "먹이기")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .background(.background)
                .accessibilityIdentifier(isFed ? "feeding-done" : "feeding-feed")
            }
            .sensoryFeedback(.success, trigger: isFed) { _, fed in fed }
            .sheet(item: $paywall) { feature in
                PaywallView(feature: feature)
            }
            .sheet(isPresented: $isAffinityPresented) {
                AffinityView()
            }
        }
    }

    private func characterCard(_ side: CupSide) -> some View {
        let result = results?.first { $0.side == side }
        let shown = isFed ? 0 : request.left(side)

        return HStack(spacing: 16) {
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .scaleEffect(bounce ? 1.15 : 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(side.characterName)
                    .font(.headline)
                Text("남은 \(side.label) \(Amount.number(shown)) \(side.unit)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.secondary)
                if isFed {
                    Text(reaction(side, result: result))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func reaction(_ side: CupSide, result: FeedResult?) -> String {
        if let result, result.leveledUp {
            return "한 단계 더 친해졌어요 · Lv \(result.levelAfter)"
        }
        return request.left(side) > 0 ? "맛있게 먹었어요" : "빈 컵이어도 반가워해요"
    }

    private func feed() {
        do {
            let fed = try onFeed()
            withAnimation(.spring(response: 0.4, dampingFraction: 1)) {
                results = fed
            }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
                bounce = true
            }
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    bounce = false
                }
            }
        } catch {
            Self.logger.error("먹이기 저장 실패(\(request.id, privacy: .public)): \(String(describing: error), privacy: .public)")
            errorText = "저장하지 못했어요. 다시 시도해 주세요."
        }
    }
}

#Preview {
    FeedingView(
        request: FeedingRequest(kind: .closeToday, sugarLeftG: 18, caffeineLeftMg: 150),
        onFeed: { [] }
    )
    .environment(ProStore(previewPlans: ProStore.mockPlans, isPro: false))
}
