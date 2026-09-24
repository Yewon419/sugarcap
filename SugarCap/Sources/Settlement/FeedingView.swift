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
    /// 컵 장면 단계를 고르는 데만 쓴다(남은 비율). 적립 계산은 저장소가 따로 한다.
    var limits: DailyLimits = .default

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

/// 먹이기 화면(2026-09-24 디자인). 컵 장면이 배경이고 그 위에 남은 양과 캐릭터가 얹힌다.
/// 남은 당은 로슈에게, 남은 카페인은 카인에게(§4.7). 먹이면 컵이 비고 캐릭터가 반응한다.
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

    /// 먹이기 전엔 남은 만큼 차 있고, 먹이면 컵이 빈다.
    private var cupStep: Int {
        isFed ? 0 : CupLevel.step(remaining: request.sugarLeftG, limit: request.limits.sugarG)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CupView(step: cupStep)
                .ignoresSafeArea()

            // 위·아래 흰 스크림. 글자와 버튼이 사진 위에서 묻히지 않게 한다.
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.96), location: 0),
                        .init(color: .white.opacity(0.8), location: 0.7),
                        .init(color: .white.opacity(0), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 330)
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.9), location: 0.5),
                        .init(color: .white, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 260)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            headline
        }
        .overlay(alignment: .topTrailing) {
            Button("닫기") { dismiss() }
                .font(.system(size: 15))
                .padding(.trailing, 24)
                .padding(.top, 8)
                .accessibilityIdentifier("feeding-close")
        }
        .overlay(alignment: .bottom) { characters }
        .safeAreaInset(edge: .bottom) { footer }
        .sensoryFeedback(.success, trigger: isFed) { _, fed in fed }
        .sheet(item: $paywall) { feature in
            PaywallView(feature: feature)
        }
        .sheet(isPresented: $isAffinityPresented) {
            AffinityView()
        }
    }

    /// 소제목 → 남은 당(주인공 숫자) → 누구에게 가는지 두 줄.
    private var headline: some View {
        let sugar = isFed ? 0 : request.sugarLeftG
        let caffeine = isFed ? 0 : request.caffeineLeftMg

        return VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .kicker()
                .padding(.top, 44)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(Amount.number(sugar))
                    .heroNumber()
                    .contentTransition(.numericText())
                Text(CupSide.sugar.unit)
                    .heroUnit()
                    .padding(.leading, 2)
            }
            .animation(.spring(response: 0.5), value: isFed)
            // 두 캡션은 한 덩어리로 숫자 밑에 붙인다. 옆·아래로 갈라 두면 큰 글자에서 남남으로 읽혔다.
            VStack(alignment: .leading, spacing: 4) {
                Text(isFed ? "로슈가 먹었어요" : "남은 당을 로슈에게")
                Text(
                    isFed
                        ? "카페인은 카인이 먹었어요"
                        : "카페인 \(Amount.number(caffeine)) \(CupSide.caffeine.unit)는 카인에게"
                )
            }
            .font(.system(size: 13))
            .tracking(0.3)
            .foregroundStyle(.secondary)
            .padding(.top, 6)

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }
        }
        .padding(.leading, 24)
        .accessibilityElement(children: .combine)
    }

    /// 로슈는 크게 왼쪽, 카인은 작게 오른쪽. 먹이면 한 번 튄다.
    private var characters: some View {
        HStack(alignment: .bottom) {
            character(.sugar, size: 200)
            Spacer()
            character(.caffeine, size: 110)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 132)
    }

    private func character(_ side: CupSide, size: CGFloat) -> some View {
        let result = results?.first { $0.side == side }
        return VStack(spacing: 6) {
            if isFed {
                Text(reaction(side, result: result))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: size)
                .scaleEffect(bounce ? 1.12 : 1, anchor: .bottom)
                .accessibilityLabel(side.characterName)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                if isFed { dismiss() } else { feed() }
            } label: {
                Text(isFed ? "완료" : "먹이기")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier(isFed ? "feeding-done" : "feeding-feed")

            if isFed {
                Button("호감도 자세히") {
                    if pro.isPro {
                        isAffinityPresented = true
                    } else {
                        paywall = .affinityDetail
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .accessibilityIdentifier("feeding-affinity")
            } else if request.kind == .closeToday {
                Text("마감 뒤에 마신 음료도 오늘 몫으로 빠져요")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
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
