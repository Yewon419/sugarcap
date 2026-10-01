import SwiftUI

/// 먹이기 장면의 캐릭터(2026-10-01 HTML 시안 `design/proto/feeding-v2.html` 확정, 대표님 선택 "컵에 붙어 조르기").
/// 오늘 화면 대기 자세 리그·배율로 그린다. 로슈 = watch(컵 옆에 매달려 까치발), 카인 = rim-stand(가장자리에서 발 동동).
/// 방울을 받으면 통통 두 번 뛰고, 그 뒤 숨 쉬며 깜빡인다.
///
/// 화면 전체(`ignoresSafeArea`)에 깔아 컵 사진 틀(`CupView`: 높이 84%, 아래 8% 띄움)과 같은 좌표를 쓴다.
/// 말풍선은 머리 오른쪽에 왼쪽 끝을 붙인다(글자가 길어져도 머리를 안 가린다).
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

                let bubbleX: Double = Double(base.x) + (side == .sugar ? 22 : 26)
                let bubbleY: Double = Double(base.y) - painter.height + (side == .sugar ? -2 : 14)
                NightBubble(text: bubble)
                    .fixedSize()
                    .id(bubble)
                    .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                    .frame(width: 0, height: 0, alignment: .leading)
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
        let pose: IdlePose = side == .sugar ? .watch : .rimStand
        guard let rule = cast.rule(pose), height > 0 else { return nil }
        let photoHeight = height * CupView.heightRatio
        return RigPainter(
            character: cast.character, art: rule.art, scale: photoHeight * cast.scalePerPhotoHeight,
            lidPad: cast.lidPad, limbDirection: rule.limbDirection
        )
    }

    /// 기준점(발밑 가운데). 로슈 = 오늘 화면 watch 자리.
    /// 카인 = 가장자리 오른쪽(가운데에서 가장자리 폭 .35). 오늘 화면 자리(가운데)면 주인공 숫자 "mg"와 머리가 겹친다.
    /// 앞 가장자리 선은 타원이라 옆으로 갈수록 올라간다(가장자리 반폭 = .5).
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
            let rim = cast.rimLine(step: step)
            let along = kainAlong / 0.5
            let middle: Double = (rim.back + rim.front) / 2
            let half: Double = (rim.front - rim.back) / 2
            let y: Double = middle + half * (1 - along * along).squareRoot()
            point = photo.point(0.498 + kainAlong * 0.477, y)
        }
        return CGPoint(x: point.x, y: point.y + slotTop)
    }

    private static let kainAlong = 0.35

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

    /// 로슈 · 컵 옆에 매달려 조르기. 오늘 화면은 5.5초마다 까치발 한 번, 여기선 1.3초마다 두 번.
    private static func roshu(mood: Mood, t: Double, since: Double, unit: Double) -> Pose {
        var p = Pose()
        switch mood {
        case .asking:
            let v = RigMotion.remainder(t, 1.3)
            let k: Double = RigMotion.bump(v, 0, 0.28) + RigMotion.bump(v, 0.36, 0.28)
            p.frame.bodyDy = -4.2 * k * unit
            p.frame.limbs["arm"] = 14 * k
            p.frame.sy = 1 + 0.02 * k
        case .sulking:
            // 기준을 넘긴 날: 천천히 한 번씩만.
            let k = RigMotion.bump(RigMotion.remainder(t, 2.6), 0, 0.5)
            p.frame.bodyDy = -2.2 * k * unit
            p.frame.limbs["arm"] = 6 * k
        case .waiting:
            // 방울이 나오면 까치발을 든 채 동동.
            let up = RigMotion.smooth(since / 0.25)
            let w = abs(sin(2 * Double.pi * since / 0.7))
            p.frame.bodyDy = (-3.6 * up - 1.2 * w) * unit
            p.frame.limbs["arm"] = 12 * up + 5 * w
        case .ready:
            p.frame.bodyDy = -5.5 * unit
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
            p.frame.bodyDy = -4 * up * unit
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

    /// 카인 · 가장자리에 서서 발 동동. 오늘 화면처럼 발밑을 축으로 아주 느리게 흔들린다.
    private static func kain(mood: Mood, t: Double, since: Double, unit: Double) -> Pose {
        var p = Pose()
        p.frame.rot = 0.8 * sin(2 * Double.pi * t / 3.6)
        switch mood {
        case .asking:
            // 오른발로 톡톡(0.55초마다), 톡 할 때 몸이 살짝 내려앉는다.
            let v = RigMotion.remainder(t, 0.55)
            p.frame.limbs["leg_right"] = -16 * RigMotion.bump(v, 0, 0.2)
            p.frame.bodyDy = RigMotion.bump(v, 0.14, 0.12) * unit
        case .sulking:
            let v = RigMotion.remainder(t, 1.4)
            p.frame.limbs["leg_right"] = -10 * RigMotion.bump(v, 0, 0.3)
            p.frame.rot -= 3
        case .waiting:
            // 두 발 번갈아 동동.
            let k = sin(Double.pi * since / 0.36)
            p.frame.limbs["leg_right"] = -12 * max(0, k)
            p.frame.limbs["leg_left"] = 12 * max(0, -k)
            p.frame.bodyDy = -0.8 * abs(k) * unit
        case .ready:
            p.frame.bodyDy = -1.5 * unit
            p.frame.sy = 1.03
        case .eaten:
            let hop = RigMotion.hops(since, at: 0.05, height: 14 * unit)
            p.frame.dy = -hop.lift
            p.squash = hop.squash
            p.frame.limbs["leg_left"] = 12 * hop.air
            p.frame.limbs["leg_right"] = -12 * hop.air
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
            p.frame.limbs["leg_right"] = -24 * lift
            p.frame.bodyDy = -1.2 * lift * unit
            p.squash = 0.875 * squash
        case .savoring:
            savor(&p, since: since, hop: 8 * unit, sway: 5, period: 1.9)
        }
        return p
    }
}

/// 마무리 요약의 캐릭터: 정면(로슈 stand, 카인 rim-stand)으로 위에서 콩 떨어져 들어오고,
/// 숫자가 다 세질 즈음 둘이 같이 한 번 뛴 뒤 숨 쉬며 깜빡인다. 로슈는 손 인사, 카인은 발 까딱.
/// 크기는 v1 그대로(로슈 150pt, 카인 137pt: 오늘 화면 대기 자세 비율, 빌드 103 대표님 피드백).
/// 틀은 그림 높이 + 위 여유(`headroom`)다. 쓰는 쪽에서 위 여유만큼 겹쳐 둔다.
struct SummaryCharacter: View {
    let side: CupSide
    let isIn: Bool
    /// 들어오는 시각(요약이 열린 뒤 초).
    let delay: Double

    static let headroom: CGFloat = 70

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inAt: Date?

    static func height(_ side: CupSide) -> CGFloat { side == .sugar ? 150 : 137 }

    var body: some View {
        let height = Self.height(side)
        TimelineView(.animation(minimumInterval: nil, paused: frozenTime != nil || inAt == nil)) { timeline in
            let u: Double = frozenTime ?? inAt.map { timeline.date.timeIntervalSince($0) } ?? 0
            Canvas { context, size in
                guard isIn, let painter = self.painter(height: height), let rigPose = self.pose(u: u) else { return }
                let blink: Double = frozenTime == nil ? IdleMotion.blink(t: u, seed: side == .sugar ? 13 : 14) : 0
                painter.draw(
                    in: context, base: CGPoint(x: size.width / 2, y: size.height),
                    m: rigPose.frame, squash: rigPose.squash, blink: blink
                )
            }
        }
        .frame(height: height + Self.headroom)
        .accessibilityHidden(true)
        .onChange(of: isIn, initial: true) { _, value in
            inAt = value ? Date() : nil
        }
    }

    private var frozenTime: Double? {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "idleAt") != nil { return 10 }
        #endif
        return reduceMotion ? 10 : nil
    }

    private func painter(height: CGFloat) -> RigPainter? {
        let cast = side.idleCast
        let art = side == .sugar ? "stand" : "rim-stand"
        guard let bbox = IdleRig.arts[cast.character]?[art]?.bbox, bbox.height > 0 else { return nil }
        let direction: [String: Double] = side == .sugar
            ? ["arm_left": 0, "arm_right": 0, "foot_left": 0, "foot_right": 0]
            : ["leg_left": 0, "leg_right": 0]
        return RigPainter(
            character: cast.character, art: art, scale: Double(height) / Double(bbox.height),
            lidPad: cast.lidPad, limbDirection: direction
        )
    }

    /// 들어오기 전이면 nil.
    private func pose(u: Double) -> FeedingCharacter.Pose? {
        guard u >= delay else { return nil }
        var p = FeedingCharacter.Pose()
        let fall = min(1, (u - delay) / 0.38)
        p.frame.dy = -Double(Self.headroom) * (1 - fall * fall)
        let land = RigMotion.bump(u, delay + 0.38, 0.16)
        let cheer = RigMotion.hops(u, at: side == .sugar ? 1.45 : 1.51, height: 18)
        p.frame.dy -= cheer.lift
        p.squash = 1.25 * land + cheer.squash
        if side == .sugar {
            let wave: Double = RigMotion.smooth((u - 2.6) / 0.15) * (1 - RigMotion.smooth((u - 3.5) / 0.2))
            let swing: Double = -14 - 10 * sin(2 * Double.pi * (u - 2.6) / 0.36)
            p.frame.limbs["arm_left"] = 18 * cheer.air
            p.frame.limbs["arm_right"] = -18 * cheer.air + wave * swing
        } else {
            let kick: Double = RigMotion.bump(u, 3.2, 0.3) + RigMotion.bump(u, 3.6, 0.3)
            p.frame.limbs["leg_left"] = 10 * cheer.air
            p.frame.limbs["leg_right"] = -10 * cheer.air - 9 * kick
        }
        if u > delay + 0.5 {
            RigMotion.breathe(
                &p.frame, t: u - delay - 0.5,
                period: side == .sugar ? 1.7 : 1.9, amount: side == .sugar ? 0.016 : 0.012
            )
        }
        return p
    }
}

/// 마무리 요약 하늘: 초승달(흰 원을 남색 원으로 깎음)과 작은 별(단색 점, 천천히 반짝). 좌표는 402×874 비율.
struct NightSkyDecor: View {
    let isIn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Star {
        let x: Double
        let y: Double
        let r: Double
        let phase: Double
        let period: Double
    }

    private static let stars: [Star] = (0 ..< 30).map { i in
        func hash(_ n: Double) -> Double {
            let v = sin(Double(i + 1) * 91.3 + n * 47.7) * 43758.5453
            return v - v.rounded(.down)
        }
        return Star(
            x: 12 + hash(1) * 378, y: 290 + hash(2) * 320, r: 0.6 + hash(3) * 0.8,
            phase: hash(4) * 2 * Double.pi, period: 1.6 + hash(5) * 1.8
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let sx = size.width / 402
                let sy = size.height / 874
                for star in Self.stars {
                    let twinkle: Double = reduceMotion ? 0.8 : 0.55 + 0.45 * sin(star.phase + 2 * Double.pi * t / star.period)
                    let r: Double = star.r * Double(sx)
                    let x: Double = star.x * Double(sx)
                    let y: Double = star.y * Double(sy)
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(twinkle)))
                }
                let moon = CGRect(x: (342 - 17) * sx, y: 186 * sy - 17 * sx, width: 34 * sx, height: 34 * sx)
                let cut = CGRect(x: (350 - 15) * sx, y: 180 * sy - 15 * sx, width: 30 * sx, height: 30 * sx)
                context.fill(Path(ellipseIn: moon), with: .color(.wall))
                context.fill(Path(ellipseIn: cut), with: .color(.nightSky))
            }
        }
        .opacity(isIn ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: isIn)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
