import SwiftUI

/// 오늘 화면 컵 장면 위의 캐릭터 대기 자세(프로토타입 `design/proto/characters.html`을 옮김).
/// 컵 장면(`CupView`)의 overlay로 붙인다. 같은 틀이라 사진 좌표가 그대로 맞는다.
///
/// 규칙: 앱을 열 때마다 허용된 자세 중 하나를 뽑고, 자세 사이 전환 동작은 없다. 기록으로 단계가 바뀌어
/// 지금 자세가 허용되지 않게 되면 그때만 다시 뽑는다. 0%면 로슈는 철푸덕, 카인은 바닥에 앉기.
/// 동작 줄이기면 자세는 그대로 두고 움직임·깜빡임을 멈춘다.
struct IdleCharacterLayer: View {
    let side: CupSide
    let step: Int
    /// 지금 보이는 면만 움직인다. 옆 면은 멈춘 채 같이 밀려 온다.
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var pose: IdlePose?
    @State private var start = Date()
    @State private var seed = UInt64.random(in: 0 ... UInt64.max)

    var body: some View {
        GeometryReader { proxy in
            if let pose, let sprite = IdleSprite(side: side, pose: pose, step: step, size: proxy.size) {
                let frozen = frozenTime
                TimelineView(.animation(minimumInterval: nil, paused: frozen != nil || !isActive)) { timeline in
                    let t = frozen ?? timeline.date.timeIntervalSince(start)
                    let blink = frozen == nil ? IdleMotion.blink(t: t, seed: seed) : 0
                    Canvas { context, _ in
                        sprite.draw(in: &context, t: t, blink: blink)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if pose == nil { repick() }
        }
        .onChange(of: step) { _, newStep in
            if let pose, side.idleCast.allows(pose, step: newStep) { return }
            repick()
        }
        .onChange(of: scenePhase) { old, new in
            // 백그라운드에서 돌아오면 앱을 다시 연 것으로 보고 새로 뽑는다.
            if old == .background, new != .background { repick() }
        }
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

    private func repick() {
        start = Date()
        #if DEBUG
        // CI 스크린샷 전용: `-idlePose swim`. 이 캐릭터에 없는 자세면 무시한다.
        if let forced = UserDefaults.standard.string(forKey: "idlePose").flatMap(IdlePose.init(rawValue:)),
           side.idleCast.rule(forced) != nil {
            pose = forced
            return
        }
        #endif
        var generator = SystemRandomNumberGenerator()
        pose = side.idleCast.pick(step: step, using: &generator)
    }
}

/// 한 자세를 화면에 그리는 데 필요한 고정값(틀 크기·단계가 같으면 매 프레임 같다).
/// 그리는 순서: 바닥 층(뒤쪽 발) → 몸 층(뒤쪽 팔다리 → 몸통 → 눈꺼풀 → 앞쪽 팔다리).
/// 몸 층은 발끝 선을 기준으로 숨 쉬고(sx, sy) 오르내린다(bodyDy). 발은 바닥 층이라 제자리다.
struct IdleSprite {
    let cast: IdleCast
    let rule: IdlePoseRule
    let pose: IdlePose
    let art: IdleArt
    let photo: IdlePhoto
    /// 캔버스 픽셀 → pt.
    let scale: Double
    /// 기준점이 놓일 화면 위 자리.
    let base: CGPoint
    /// 그림 안 기준점(pt). 전체 회전·반전의 중심.
    let pivot: CGPoint
    /// 그림 안 발끝 선(pt). 몸 층 숨쉬기의 기준.
    let footY: Double

    init?(side: CupSide, pose: IdlePose, step: Int, size: CGSize) {
        let cast = side.idleCast
        guard size.width > 0, size.height > 0,
              let rule = cast.rule(pose),
              let art = IdleRig.arts[cast.character]?[rule.art]
        else { return nil }
        let photo = IdlePhoto(size: size)
        let scale = photo.height * cast.scalePerPhotoHeight
        self.cast = cast
        self.rule = rule
        self.pose = pose
        self.art = art
        self.photo = photo
        self.scale = scale
        base = IdleMotion.place(pose, cast: cast, step: step, photo: photo, art: art, scale: scale)
        // 로슈 컵 안 자세만 그림 속 가장자리 틈이 기준이다(가장자리 선에 맞춘다).
        let pivotY = pose == .inCup ? (art.rimLineY ?? Double(art.bbox.maxY)) : Double(art.bbox.maxY)
        pivot = CGPoint(x: Double(art.bbox.midX) * scale, y: pivotY * scale)
        footY = Double(art.bbox.maxY) * scale
    }

    func draw(in context: inout GraphicsContext, t: Double, blink: Double) {
        let m = IdleMotion.frame(pose, cast: cast, rule: rule, t: t, photo: photo, walkBaseX: base.x)
        var sprite = context
        sprite.translateBy(x: base.x + m.dx, y: base.y + m.dy)
        sprite.rotate(by: .degrees(m.rot))
        sprite.scaleBy(x: m.flip, y: 1)
        sprite.translateBy(x: -pivot.x, y: -pivot.y)
        if rule.opacity < 1 {
            // 한 덩어리로 비치게 층으로 묶는다. 조각마다 투명도를 주면 몸 밑 팔다리 뿌리가 비친다.
            sprite.opacity = rule.opacity
            sprite.drawLayer { layer in drawParts(in: layer, m: m, blink: blink) }
        } else {
            drawParts(in: sprite, m: m, blink: blink)
        }
    }

    private func drawParts(in ground: GraphicsContext, m: IdleFrame, blink: Double) {
        for part in art.parts where !part.isFront && part.isFoot {
            drawLimb(part, in: ground, m: m)
        }
        var body = ground
        body.translateBy(x: pivot.x, y: footY + m.bodyDy)
        body.scaleBy(x: m.sx, y: m.sy)
        body.translateBy(x: -pivot.x, y: -footY)
        for part in art.parts where !part.isFront && !part.isFoot {
            drawLimb(part, in: body, m: m)
        }
        drawImage("body", frame: art.body, in: body)
        if blink > 0 {
            for eye in art.eyes {
                let w = Double(eye.box.width)
                let h = Double(eye.box.height)
                let pad = cast.lidPad
                // 눈꺼풀은 위에서 아래로 내려온다(위 끝 고정, 높이만 줄였다 늘림).
                let rect = CGRect(
                    x: (Double(eye.box.minX) - w * pad) * scale,
                    y: (Double(eye.box.minY) - h * pad) * scale,
                    width: w * (1 + pad * 2) * scale,
                    height: h * (1 + pad * 2) * scale * blink
                )
                body.fill(Path(ellipseIn: rect), with: .color(Self.color(hex: eye.lid)))
            }
        }
        for part in art.parts where part.isFront {
            drawLimb(part, in: body, m: m)
        }
    }

    /// 팔다리 하나: 이음새 한쪽 끝(pivot)을 축으로 돌고, shift만큼 옮긴다.
    private func drawLimb(_ part: IdleArt.Part, in parent: GraphicsContext, m: IdleFrame) {
        let amount = m.limbs[part.name] ?? 0
        let angle: Double =
            if let direction = rule.limbDirection[part.name] {
                direction == 0 ? amount : direction * max(0, amount)
            } else {
                0
            }
        let shift = m.shift[part.name] ?? .zero
        let ox = Double(part.pivot.x) * scale
        let oy = Double(part.pivot.y) * scale
        var limb = parent
        limb.translateBy(x: shift.dx + ox, y: shift.dy + oy)
        limb.rotate(by: .degrees(angle))
        limb.translateBy(x: -ox, y: -oy)
        drawImage(part.name, frame: part.frame, in: limb)
    }

    private func drawImage(_ part: String, frame: CGRect, in context: GraphicsContext) {
        let rect = CGRect(
            x: Double(frame.minX) * scale, y: Double(frame.minY) * scale,
            width: Double(frame.width) * scale, height: Double(frame.height) * scale
        )
        context.draw(Image("idle-\(cast.character)-\(rule.art)-\(part)"), in: rect)
    }

    /// "#RRGGBB". 형식은 그림 정보를 읽을 때(`IdleRig`) 이미 걸렀다.
    static func color(hex: String) -> Color {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .black }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
