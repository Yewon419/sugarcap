import SwiftUI

/// 어젯밤 마감을 못 한 날, 앱을 열면 가장 먼저 뜨는 전체 화면(2026-09-27 대표님: "아예 전체 화면에 띄우고 그거부터 처리하게").
/// 닫기 버튼은 없다. 먹이거나("먹이러 가기"·"안 마셨어요"), 마셨다고 답해야("마셨어요") 오늘 화면으로 간다.
/// 먹이기는 이 화면 안에서 먹이기 화면으로 바뀐다. 먹이기를 도중에 닫으면 다시 이 화면이 뜬다.
struct YesterdayGate: Identifiable, Equatable {
    enum Kind: Equatable {
        /// 어제 앱은 열었지만 마감하지 않았다.
        case feed
        /// 어제 앱을 열지 않았다.
        case askNoDrink
    }

    let kind: Kind
    let day: DayKey
    let sugarLeftG: Double
    let caffeineLeftMg: Double
    let limits: DailyLimits
    var sugarOverG: Double = 0
    var caffeineOverMg: Double = 0

    var id: String { "\(day.rawValue)-\(kind == .feed ? "feed" : "ask")" }
}

struct YesterdayGateView: View {
    let gate: YesterdayGate
    let opening: FeedingOpening
    let onFeed: (FeedingRequest) throws -> [FeedResult]
    let onDrank: () -> Void

    @State private var feeding: FeedingRequest?

    var body: some View {
        if let feeding {
            FeedingView(request: feeding, opening: opening, onFeed: { try onFeed(feeding) })
        } else {
            gateScreen
        }
    }

    private var dateText: String {
        let components = DateComponents(year: gate.day.year, month: gate.day.month, day: gate.day.day, hour: 12)
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.month().day().weekday(.wide))
    }

    private var gateScreen: some View {
        ZStack(alignment: .topLeading) {
            CupView(
                step: CupLevel.step(remaining: gate.sugarLeftG, limit: gate.limits.sugarG),
                setID: CupSide.sugar.cupSetID
            )
            .ignoresSafeArea()
            // 글자 자리는 벽 색으로 받쳐 읽히게 한다(번짐 없이 위에서 아래로 한 번).
            LinearGradient(
                stops: [.init(color: CupView.wallColor, location: 0), .init(color: CupView.wallColor.opacity(0.9), location: 0.34), .init(color: CupView.wallColor.opacity(0), location: 0.52)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                Text("어제 · \(dateText)")
                    .dateLabel()
                    .padding(.top, 8)
                Text(gate.kind == .feed ? "어젯밤 마감을 못 했어요" : "어제는 기록이 없어요")
                    .kicker()
                    .padding(.top, 28)
                Text(gate.kind == .feed ? "남은 음료를\n아직 못 먹였어요" : "어제 음료를\n안 마셨나요?")
                    .font(AppFont.pretendard(34, .bold, relativeTo: .largeTitle))
                    .tracking(AppFont.displayTracking(for: 34))
                    .lineSpacing(2)
                    .padding(.top, 12)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    gate.kind == .feed
                        ? "로슈와 카인이 기다리고 있어요. 먹이고 오늘을 시작해요."
                        : "안 마셨다면 하루 기준만큼 가득 먹일 수 있어요."
                )
                .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .padding(.top, 10)
                if gate.kind == .feed {
                    HStack(spacing: 24) {
                        amount(gate.sugarLeftG, side: .sugar)
                        amount(gate.caffeineLeftMg, side: .caffeine)
                    }
                    .padding(.top, 18)
                }
            }
            .padding(.horizontal, 24)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 18) {
                HStack(alignment: .bottom, spacing: 18) {
                    waiting(.sugar, height: 130)
                    waiting(.caffeine, height: 104)
                }
                actions
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private func amount(_ value: Double, side: CupSide) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Amount.number(value))
                    .font(AppFont.pretendard(28, .bold, relativeTo: .title))
                    .tracking(-1)
                    .monospacedDigit()
                Text(side.unit)
                    .font(AppFont.pretendard(13, .medium, relativeTo: .footnote))
            }
            Text("남은 \(side.label) · \(side.characterName) 몫")
                .font(AppFont.pretendard(12, .regular, relativeTo: .caption))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func waiting(_ side: CupSide, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text("기다렸어요")
                .font(AppFont.pretendard(12, .semibold, relativeTo: .caption))
                .foregroundStyle(.tint)
                .padding(.horizontal, 12)
                .frame(minHeight: 28)
                .background(.white.opacity(0.8), in: Capsule())
            Image(side.characterAsset)
                .resizable()
                .scaledToFit()
                .frame(height: height)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var actions: some View {
        switch gate.kind {
        case .feed:
            Button {
                start(sugarLeft: gate.sugarLeftG, caffeineLeft: gate.caffeineLeftMg, sugarOver: gate.sugarOverG, caffeineOver: gate.caffeineOverMg)
            } label: {
                Text("먹이러 가기")
                    .ctaLabel()
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("gate-feed")
        case .askNoDrink:
            VStack(spacing: 6) {
                Button {
                    start(sugarLeft: gate.limits.sugarG, caffeineLeft: gate.limits.caffeineMg, sugarOver: 0, caffeineOver: 0)
                } label: {
                    Text("안 마셨어요")
                        .ctaLabel()
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier("gate-no-drink")
                Button("마셨어요", action: onDrank)
                    .font(AppFont.pretendard(15, .semibold, relativeTo: .subheadline))
                    .tapTarget()
                    .accessibilityIdentifier("gate-drank")
            }
        }
    }

    private func start(sugarLeft: Double, caffeineLeft: Double, sugarOver: Double, caffeineOver: Double) {
        let request = FeedingRequest(
            kind: .pastDay(gate.day), sugarLeftG: sugarLeft, caffeineLeftMg: caffeineLeft, limits: gate.limits,
            sugarOverG: sugarOver, caffeineOverMg: caffeineOver
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { feeding = request }
    }
}
