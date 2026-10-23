import SwiftUI

/// 먹이기 장면의 캐릭터(2026-10-01 HTML 시안 `design/proto/feeding-v2.html` 확정, 대표님 선택 "컵에 붙어 조르기").
/// 오늘 화면 대기 자세 리그·배율로 그린다. 로슈 = watch(컵 왼쪽에 매달려 까치발),
/// 카인 = walk 옆모습(컵 오른쪽 아래 바닥에서 컵을 보며 발 동동, 대표님 2026-10-23. 그 전엔 가장자리에 정면으로 섰다).
/// 방울을 받으면 통통 두 번 뛰고, 그 뒤 숨 쉬며 깜빡인다.
///
/// 화면 전체(`ignoresSafeArea`)에 깔아 컵 사진 틀(`CupView`: 높이 84%, 아래 8% 띄움)과 같은 좌표를 쓴다.
/// 말풍선은 컵 쪽(로슈 = 머리 오른쪽, 카인 = 머리 왼쪽)에 붙인다(글자가 길어져도 머리를 안 가린다).
struct FeedingCharacter: View {
    /// emptied·puzzled·patting·savoring = 먹일 게 없는 날(남은 0) 빈 컵 털기(2026-10-02 시안 `design/proto/feeding-empty.html`):
    /// 눌러도 안 나옴 → 갸웃 → 컵을 톡톡 세 번 → 작은 방울을 눈 감고 아껴 먹기.
    enum Mood: Equatable { case asking, sulking, waiting, ready, eaten, emptied, puzzled, patting, savoring }

    let side: CupSide
    /// 지금 보이는 컵 단계(가장자리 선).
    let step: Int
    let mood: Mood
    let bubble: String
    /// 방울을 끌어다 놓는 자리(좌표 공간 "feed").
    @Binding var targetFrame: CGRect

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var moodSince = Date()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if let painter = Self.painter(side: side, height: size.height), size.width > 0 {
                let base = Self.base(side: side, step: step, size: size)
                let frozen = frozenTime
                TimelineView(.animation(minimumInterval: nil, paused: frozen != nil)) { timeline in
                    let t: Double = frozen ?? timeline.date.timeIntervalSince(start)
                    let since: Double = frozen == nil ? timeline.date.timeIntervalSince(moodSince) : 10
                    let unit: Double = Double(size.height * CupView.heightRatio) / IdlePhoto.referenceHeight
                    let rigPose = Self.pose(side: side, mood: mood, t: t, since: since, unit: unit)
                    let idleBlink: Double = frozen == nil ? IdleMotion.blink(t: t, seed: side == .sugar ? 11 : 12) : 0
                    let blink: Double = max(idleBlink, rigPose.eyesClosed)
                    Canvas { context, _ in
                        painter.draw(in: context, base: base, m: rigPose.frame, squash: rigPose.squash, blink: blink)
                    }
                }
                .accessibilityHidden(true)

                let isLeft = side == .sugar
                let bubbleX: Double = Double(base.x) + (isLeft ? 22 : -22)
                let bubbleY: Double = Double(base.y) - painter.height - 2
                NightBubble(text: bubble)
                    .fixedSize()
                    .id(bubble)
                    .transition(.scale(scale: 0.85, anchor: isLeft ? .leading : .trailing).combined(with: .opacity))
                    .frame(width: 0, height: 0, alignment: isLeft ? .leading : .trailing)
                    .position(x: bubbleX, y: bubbleY)
                    .accessibilityLabel("\(side.characterName): \(bubble)")

                Color.clear
                    .onAppear { targetFrame = Self.target(base: base, painter: painter, origin: geo.frame(in: .named("feed")).origin) }
                    .onChange(of: geo.frame(in: .named("feed"))) { _, frame in
                        targetFrame = Self.target(base: base, painter: painter, origin: frame.origin)
                    }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bubble)
        .onChange(of: mood) { _, _ in moodSince = Date() }
    }

    /// 멈춘 시각. 동작 줄이기면 0, CI 스크린샷(Debug `-idleAt`)이면 그 시각.
    private var frozenTime: Double? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "idleAt") != nil {
            return UserDefaults.standard.double(forKey: "idleAt")
        }
        #endif
        return reduceMotion ? 0 : nil
    }

    // MARK: 자리·배율

    private static func painter(side: CupSide, height: Double) -> RigPainter? {
        let cast = side.idleCast
        let pose = side == .sugar ? "watch" : "walk"
        guard let rule = cast.poseSet?.poses[pose]?.rule, height > 0 else { return nil }
        let photoHeight = height * CupView.heightRatio
        return RigPainter(
            character: cast.character, art: rule.art, scale: photoHeight * cast.scalePerPhotoHeight,
            lidPad: cast.lidPad, limbDirection: rule.limbDirection
        )
    }

    /// 기준점(발밑 가운데). 로슈 = 오늘 화면 watch 자리, 카인 = 그 맞은편(잔 가운데 .498을 축으로 뒤집은 자리) 바닥.
    static func base(side: CupSide, step: Int, size: CGSize) -> CGPoint {
        let cast = side.idleCast
        let slot = CGSize(width: size.width, height: size.height * CupView.heightRatio)
        let photo = IdlePhoto(slot: slot)
        let slotTop = size.height * (1 - CupView.heightRatio - CupView.liftRatio)
        let point: CGPoint
        switch side {
        case .sugar:
            point = photo.point(0.25, cast.bottom - 0.005)
        case .caffeine:
            point = photo.point(0.746, cast.bottom - 0.005)
        }
        return CGPoint(x: point.x, y: point.y + slotTop)
    }

    /// 몸 둘레를 조금 넓힌 사각형(화면 좌표 → "feed" 좌표).
    private static func target(base: CGPoint, painter: RigPainter, origin: CGPoint) -> CGRect {
        CGRect(
            x: base.x - painter.width / 2 + origin.x, y: base.y - painter.height + origin.y,
            width: painter.width, height: painter.height
        )
    }

    // MARK: 동작

    struct Pose {
        var frame = IdleFrame()
        var squash = 0.0
        /// 눈 감기(0~1). 깜빡임과 큰 쪽을 쓴다.
        var eyesClosed = 0.0
    }

    /// 톡톡 치는 시각(patting이 된 뒤 초). 방울은 세 번째에 나온다(`FeedingView`가 같은 박자로 컵을 흔든다).
    static let patTimes = [0.3, 0.7, 1.1]

    private static func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
        RigMotion.smooth((t - a) / (b - a))
    }

    /// 아껴 먹기: 한 번 콩 → 눈 감고 좌우로 살랑 → 눈 뜨고 숨쉬기.
    private static func savor(_ p: inout Pose, since: Double, hop: Double, sway: Double, period: Double) {
        p.frame.dy = -hop * RigMotion.bump(since, 0.05, 0.28)
        p.squash = RigMotion.bump(since, -0.01, 0.08) + RigMotion.bump(since, 0.33, 0.1)
        let closed: Double = ramp(since, 0.4, 0.5) * (1 - ramp(since, 1.35, 1.45))
        p.eyesClosed = closed
        p.frame.rot += sway * sin(2 * Double.pi * (since - 0.45) / 0.8) * closed
        RigMotion.breathe(&p.frame, t: since, period: period, amount: 0.014)
    }

    /// t = 화면을 연 뒤 시각, since = 지금 기분이 된 뒤 시각. unit = 393×852 기준 pt 배율.
    static func pose(side: CupSide, mood: Mood, t: Double, since: Double, unit: Double) -> Pose {
        side == .sugar ? roshu(mood: mood, t: t, since: since, unit: unit) : kain(mood: mood, t: t, since: since, unit: unit)
    }

    /// 로슈 까치발 최대 높이(393pt 기준). watch 그림은 발이 몸과 떨어진 조각이라 몸만 올리면 발 뿌리가 드러나 다리가
    /// 늘어나 보인다. 뿌리 길이를 넘기면 몸과 다리가 떨어져 보인다(빌드 258 대표님 "몸이랑 다리 분리"). 오늘 화면 watch와 같은 값.
    private static let tiptoe = 2.2

    /// 로슈 · 컵 옆에 매달려 조르기. 오늘 화면은 5.5초마다 까치발 한 번, 여기선 1.3초마다 두 번.
    private static func roshu(mood: Mood, t: Double, since: Double, unit: Double) -> Pose {
        var p = Pose()
        switch mood {
        case .asking:
            let v = RigMotion.remainder(t, 1.3)
            let k: Double = RigMotion.bump(v, 0, 0.28) + RigMotion.bump(v, 0.36, 0.28)
            p.frame.bodyDy = -tiptoe * k * unit
            p.frame.limbs["arm"] = 14 * k
            p.frame.sy = 1 + 0.02 * k
        case .sulking:
            // 기준을 넘긴 날: 천천히 한 번씩만.
            let k = RigMotion.bump(RigMotion.remainder(t, 2.6), 0, 0.5)
            p.frame.bodyDy = -tiptoe * k * unit
            p.frame.limbs["arm"] = 6 * k
        case .waiting:
            // 방울이 나오면 까치발을 든 채 동동.
            let up = RigMotion.smooth(since / 0.25)
            let w = abs(sin(2 * Double.pi * since / 0.7))
            p.frame.bodyDy = -tiptoe * (0.7 * up + 0.3 * w) * unit
            p.frame.limbs["arm"] = 12 * up + 5 * w
        case .ready:
            p.frame.bodyDy = -tiptoe * unit
            p.frame.limbs["arm"] = 20
            p.frame.sy = 1.03
        case .eaten:
            let hop = RigMotion.hops(since, at: 0.05, height: 16 * unit)
            p.frame.dy = -hop.lift
            p.squash = hop.squash
            p.frame.limbs["arm"] = 20 * (1 - RigMotion.smooth((since - 0.7) / 0.3))
            RigMotion.breathe(&p.frame, t: since, period: 1.7, amount: 0.016)
        case .emptied:
            // 누르는 순간 기대하며 까치발 → 아무것도 안 나오자 내려앉는다.
            let up: Double = ramp(since, 0, 0.22) * (1 - ramp(since, 0.45, 0.65))
            p.frame.bodyDy = -tiptoe * up * unit
            p.frame.limbs["arm"] = 14 * up
        case .puzzled:
            // 갸웃: 컵에서 몸을 떼며 바깥으로 기운다.
            p.frame.rot = -9 * ramp(since, 0, 0.28)
            p.squash = 0.75 * RigMotion.bump(since, -0.02, 0.12)
        case .patting:
            // 팔이 작아서(watch 그림) 몸으로 읽히게: 치기 전 뒤로 빠졌다가 칠 때 컵 쪽으로 쏠린다.
            var arm = 0.0, lean = 0.0, wind = 0.0, dip = 0.0
            for a in patTimes {
                arm += ramp(since, a - 0.24, a - 0.05) * (1 - ramp(since, a - 0.02, a + 0.03))
                wind += RigMotion.bump(since, a - 0.24, 0.22)
                lean += RigMotion.bump(since, a - 0.03, 0.17)
                dip += RigMotion.bump(since, a, 0.12)
            }
            p.frame.limbs["arm"] = 34 * arm
            p.frame.rot = -9 * (1 - ramp(since, 0, 0.18)) + 6 * lean - 4 * wind
            p.frame.bodyDy = 1.4 * dip * unit
        case .savoring:
            p.frame.limbs["arm"] = 20 * (1 - ramp(since, 0.3, 0.6))
            savor(&p, since: since, hop: 9 * unit, sway: 4, period: 1.8)
        }
        return p
    }

    /// 카인 · 컵 옆 바닥에 옆으로 서서 발 동동. 발밑을 축으로 아주 느리게 흔들린다. 다리는 walk 그림의 앞(near)·뒤(far).
    private static func kain(mood: Mood, t: Double, since: Double, unit: Double) -> Pose {
        var p = Pose()
        p.frame.rot = 0.8 * sin(2 * Double.pi * t / 3.6)
        switch mood {
        case .asking:
            // 오른발로 톡톡(0.55초마다), 톡 할 때 몸이 살짝 내려앉는다.
            let v = RigMotion.remainder(t, 0.55)
            p.frame.limbs["leg_near"] = -16 * RigMotion.bump(v, 0, 0.2)
            p.frame.bodyDy = RigMotion.bump(v, 0.14, 0.12) * unit
        case .sulking:
            let v = RigMotion.remainder(t, 1.4)
            p.frame.limbs["leg_near"] = -10 * RigMotion.bump(v, 0, 0.3)
            p.frame.rot -= 3
        case .waiting:
            // 두 발 번갈아 동동.
            let k = sin(Double.pi * since / 0.36)
            p.frame.limbs["leg_near"] = -12 * max(0, k)
            p.frame.limbs["leg_far"] = 12 * max(0, -k)
            p.frame.bodyDy = -0.8 * abs(k) * unit
        case .ready:
            p.frame.bodyDy = -1.5 * unit
            p.frame.sy = 1.03
        case .eaten:
            let hop = RigMotion.hops(since, at: 0.05, height: 14 * unit)
            p.frame.dy = -hop.lift
            p.squash = hop.squash
            p.frame.limbs["leg_far"] = 12 * hop.air
            p.frame.limbs["leg_near"] = -12 * hop.air
            RigMotion.breathe(&p.frame, t: since, period: 1.9, amount: 0.012)
        case .emptied:
            let up: Double = ramp(since, 0, 0.22) * (1 - ramp(since, 0.45, 0.65))
            p.frame.bodyDy = -1.8 * up * unit
            p.frame.sy = 1 + 0.03 * up
        case .puzzled:
            // 갸웃: 발밑 축으로 고개를 젖힌다(소개의 카인 갸웃과 같은 몸짓).
            p.frame.rot += 13 * ramp(since, 0, 0.28)
        case .patting:
            // 쿵쿵: 오른발을 들었다가 가장자리를 쿵. 디딜 때 몸이 눌린다.
            var lift = 0.0, squash = 0.0
            for a in patTimes {
                lift += ramp(since, a - 0.24, a - 0.05) * (1 - ramp(since, a - 0.02, a + 0.02))
                squash += RigMotion.bump(since, a, 0.12)
            }
            p.frame.rot += 13 * (1 - ramp(since, 0, 0.18))
            p.frame.limbs["leg_near"] = -24 * lift
            p.frame.bodyDy = -1.2 * lift * unit
            p.squash = 0.875 * squash
        case .savoring:
            savor(&p, since: since, hop: 8 * unit, sway: 5, period: 1.9)
        }
        return p
    }
}
