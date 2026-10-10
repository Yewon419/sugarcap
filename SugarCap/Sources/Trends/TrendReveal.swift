import SwiftUI

/// 추이 첫 등장(SPEC §4.9, 시안 `design/proto/gift-open.html` 7~10). `r` = 첫 선물로 추이가 열린 뒤 초.
/// 잔이 왼쪽에서 하나씩 미끄러져 들어오고 → 캐릭터가 들어오고 → 글자가 위에서 내려오고 → 안내 3단계.
/// 전부 `r`의 순수 함수다. 동작 줄이기면 연출 없이 안내만 뜬다.
enum TrendReveal {
    static let cupsStart = 0.45
    static let cupStagger = 0.09
    static let cupLength = 0.5
    /// 로슈 `TrendWalkIn` 시작 시각. 걷기는 그 뒤 `TrendWalkIn.delay`에 출발한다(시안 1.4초).
    static let walkStart = 0.5
    static let castAt = walkStart + TrendWalkIn.delay
    static let textStart = castAt + 1.95
    static let textStagger = 0.06
    static let textLength = 0.45
    static let coachAt = textStart + 0.9

    /// 잔 줄의 가로 밀림(pt). 화면 왼쪽 밖에서 들어와 살짝 지나쳤다 선다.
    static func cupShift(_ r: Double, index: Int, width: Double) -> Double {
        let a: Double = cupsStart + cupStagger * Double(index)
        let k: Double = Motion.seg(r, a, a + cupLength) { Ease.backOut($0, overshoot: 1.1) }
        return -(width + 20) * (1 - k)
    }

    /// 지면 글자 줄(위에서부터 번호)의 불투명도와 세로 밀림.
    static func line(_ r: Double, index: Int) -> (opacity: Double, y: Double) {
        let a: Double = textStart + textStagger * Double(index)
        let k: Double = Motion.seg(r, a, a + textLength, Ease.power3Out)
        return (k, -28 * (1 - k))
    }

    /// 카인은 앉은 그림이라 걷지 않고 위에서 떨어져 앉는다(오늘 화면 선물과 같은 동작).
    static func drop(_ r: Double) -> (opacity: Double, y: Double) {
        let k: Double = Motion.seg(r, castAt, castAt + 0.45, Ease.power2In)
        return (r >= castAt ? 1 : 0, -120 * (1 - k))
    }
}

/// 첫 등장 동안만 시계를 돌린다. `start`가 없으면(등장 끝·동작 줄이기) 끝난 모습 그대로.
struct TrendRevealClock<Content: View>: View {
    let start: Date?
    /// Debug 스크린샷용으로 멈춘 시각(초).
    let frozenAt: Double?
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        if let start {
            TimelineView(.animation(minimumInterval: nil, paused: frozenAt != nil)) { timeline in
                content(frozenAt ?? timeline.date.timeIntervalSince(start))
            }
        } else {
            content(.infinity)
        }
    }
}

/// 안내가 가리키는 자리.
enum TrendCoachSpot: Hashable {
    case todayCup
    case cups
    case range
}

struct TrendCoachStep {
    let spot: TrendCoachSpot
    let message: String
}

/// 안내(추이 첫 등장 끝). 가리키는 자리만 또렷한 둥근 구멍으로 남기고 어둡게 한 뒤 말풍선을 띄운다(그라데이션 없음).
/// 구멍 밖 누르기는 막고, 말풍선 버튼으로만 넘어간다.
struct TrendCoachOverlay: View {
    let steps: [TrendCoachStep]
    let index: Int
    /// 자리별 화면 좌표. 매 프레임 지금 자리를 받는다.
    let frames: [TrendCoachSpot: CGRect]
    let onNext: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let step = steps[min(index, steps.count - 1)]
            let hole = frames[step.spot].map { $0.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -6, dy: -6) }
            ZStack {
                Canvas { context, size in
                    var shade = Path(CGRect(origin: .zero, size: size))
                    if let hole { shade.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14), style: .continuous) }
                    context.fill(shade, with: .color(.black.opacity(GiftOpeningTimeline.dim)), style: FillStyle(eoFill: true))
                }
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)
                bubble(step)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(hole, in: proxy.size))
                    .padding(Self.edge(hole, in: proxy.size), Self.gap(hole, in: proxy.size))
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
    }

    /// 구멍이 화면 아래쪽이면 말풍선을 구멍 위에, 위쪽이면 아래에 둔다.
    private static func isLow(_ hole: CGRect?, in size: CGSize) -> Bool {
        guard let hole else { return false }
        return hole.midY > size.height / 2
    }

    private static func alignment(_ hole: CGRect?, in size: CGSize) -> Alignment {
        hole == nil ? .center : (isLow(hole, in: size) ? .bottom : .top)
    }

    private static func edge(_ hole: CGRect?, in size: CGSize) -> Edge.Set {
        isLow(hole, in: size) ? .bottom : .top
    }

    private static func gap(_ hole: CGRect?, in size: CGSize) -> CGFloat {
        guard let hole else { return 0 }
        return isLow(hole, in: size) ? size.height - hole.minY + 16 : hole.maxY + 16
    }

    private func bubble(_ step: TrendCoachStep) -> some View {
        let isLast = index >= steps.count - 1
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("추이 보는 법")
                    .font(AppFont.pretendard(12, .semibold, relativeTo: .caption))
                Spacer(minLength: 8)
                Text(verbatim: "\(index + 1) / \(steps.count)")
                    .font(AppFont.pretendard(12, .medium, relativeTo: .caption))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            Text(step.message)
                .font(AppFont.pretendard(17, .semibold, relativeTo: .body))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Button(action: onNext) {
                Text(isLast ? LocalizedStringKey("확인") : LocalizedStringKey("다음"))
                    .font(AppFont.pretendard(15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.ink, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 12)
            .accessibilityIdentifier("trend-coach-next")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
