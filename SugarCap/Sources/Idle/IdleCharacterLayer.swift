import SwiftUI

/// 오늘 화면 컵 장면 위의 캐릭터 대기 자세(프로토타입 `design/proto/characters.html`을 옮김).
/// 컵 장면(`CupView`)의 사진 칸 안에 사진과 한 묶음으로 그린다. 바깥에 overlay로 얹으면 컵을 넘길 때
/// 한 박자 늦게 따라왔다(대표님 2026-09-29).
///
/// 규칙: 앱을 열 때마다 허용된 자세 중 하나를 뽑고, 자세 사이 전환 동작은 없다. 기록으로 단계가 바뀌어
/// 지금 자세가 허용되지 않게 되면 그때만 다시 뽑는다. 0%면 로슈는 철푸덕, 카인은 바닥에 앉기.
/// 자세는 풀린 단계(`AffinityMath.unlockedLevel`)까지만 나온다. Pro가 끝나 지금 자세가 잠기면 다시 뽑는다.
/// 동작 줄이기면 자세는 그대로 두고 움직임·깜빡임을 멈춘다.
struct IdleCharacterLayer: View {
    let side: CupSide
    let step: Int
    /// 움직여도 되는지. 옆 면이거나 컵을 넘기는 중(끄는 중·제자리로 붙는 중)이면 멈춘다.
    /// 넘기는 동안 매 프레임 다시 그리면 캐릭터가 컵보다 한 박자 늦게 따라온다(대표님 2026-09-29).
    let isActive: Bool
    /// 대기 자세가 풀린 호감도 단계(§9.8).
    let unlockedLevel: Int
    /// 캐릭터 밖을 누른 자리(전역 좌표). 오늘 화면은 이걸 컵 누르기로 받는다(2026-10-05).
    var onMiss: (CGPoint) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var pose: String?
    @State private var start = Date()
    /// 멈춘 시각. 다시 움직일 때 멈춘 만큼 `start`를 미뤄 동작이 이어지게 한다(걷던 자리에서 튀지 않게).
    @State private var pausedAt: Date?
    @State private var seed = UInt64.random(in: 0 ... UInt64.max)
    /// 마지막으로 눌린 시각. 누르면 살짝 움찔한다(대표님 2026-10-04: "살짝 움찔하는 정도").
    @State private var flinchAt: Date?

    var body: some View {
        GeometryReader { proxy in
            if let pose, let sprite = IdleSprite(side: side, pose: pose, step: step, size: proxy.size) {
                let frozen = frozenTime
                TimelineView(.animation(minimumInterval: nil, paused: frozen != nil || pausedAt != nil)) { timeline in
                    let t = frozen ?? (pausedAt ?? timeline.date).timeIntervalSince(start)
                    let blink = frozen == nil ? IdleMotion.blink(t: t, seed: seed) : 0
                    let flinch = flinchAt.map { IdleMotion.flinch(age: timeline.date.timeIntervalSince($0)) } ?? 0
                    Canvas { context, _ in
                        sprite.draw(in: &context, t: t, blink: blink, flinch: flinch)
                    }
                }
                // 캐릭터 위를 누를 때만 움찔하고, 그 밖은 `onMiss`로 넘긴다. 컵 넘기기(부모의 끌기)는 손가락이 움직이면 그쪽으로 간다.
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .global) { location in
                    let origin = proxy.frame(in: .global).origin
                    let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                    let now = Date()
                    if sprite.contains(local, t: now.timeIntervalSince(start)) {
                        flinchAt = now
                    } else {
                        onMiss(location)
                    }
                }
            }
        }
        // 동작 줄이기·멈춘 화면·넘기는 중에는 누르기를 받지 않는다(움찔도 움직임이라).
        .allowsHitTesting(isActive && frozenTime == nil)
        .accessibilityHidden(true)
        .onAppear {
            if pose == nil { repick() }
        }
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                if let pausedAt { start = start.addingTimeInterval(Date().timeIntervalSince(pausedAt)) }
                pausedAt = nil
            } else if pausedAt == nil {
                pausedAt = Date()
            }
        }
        .onChange(of: step) { _, newStep in
            if isAllowed(step: newStep, unlockedLevel: unlockedLevel) { return }
            repick()
        }
        .onChange(of: unlockedLevel) { _, newLevel in
            if isAllowed(step: step, unlockedLevel: newLevel) { return }
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

    private func isAllowed(step: Int, unlockedLevel: Int) -> Bool {
        guard let pose else { return false }
        return side.idleCast.poseSet?.allows(pose, step: step, unlockedLevel: unlockedLevel) == true
    }

    private func repick() {
        start = Date()
        if pausedAt != nil { pausedAt = start }
        #if DEBUG
        // CI 스크린샷 전용: `-idlePose swim`. 이 캐릭터에 없는 자세면 무시한다. 해금과 상관없이 보인다.
        if let forced = UserDefaults.standard.string(forKey: "idlePose"),
           side.idleCast.poseSet?.poses[forced] != nil {
            pose = forced
            return
        }
        #endif
        var generator = SystemRandomNumberGenerator()
        pose = side.idleCast.poseSet?.pick(step: step, unlockedLevel: unlockedLevel, using: &generator)
    }
}

/// 한 자세를 화면에 그리는 데 필요한 고정값(틀 크기·단계가 같으면 매 프레임 같다).
/// 그리는 순서: 유리 반사 → 바닥 그림자 → 캐릭터.
/// 캐릭터는 바닥 층(뒤쪽 발) → 몸 층(뒤쪽 팔다리 → 몸통 → 눈꺼풀 → 앞쪽 팔다리).
/// 몸 층은 발끝 선을 기준으로 숨 쉬고(sx, sy) 오르내린다(bodyDy). 발은 바닥 층이라 제자리다.
struct IdleSprite {
    let cast: IdleCast
    let rule: IdlePoseRule
    let spec: IdlePoseSpec
    let art: IdleArt
    let photo: IdlePhoto
    /// 컵 누끼. 반사를 유리 안으로 자른다.
    let cutout: String
    let step: Int
    let bounds: CGRect
    /// 캔버스 픽셀 → pt.
    let scale: Double
    /// 기준점이 놓일 화면 위 자리.
    let base: CGPoint
    /// 그림 안 기준점(pt). 전체 회전·반전의 중심.
    let pivot: CGPoint
    /// 그림 안 발끝 선(pt). 몸 층 숨쉬기의 기준.
    let footY: Double

    init?(side: CupSide, pose: String, step: Int, size: CGSize) {
        let cast = side.idleCast
        guard size.width > 0, size.height > 0,
              let spec = cast.poseSet?.poses[pose],
              let art = IdleRig.arts[cast.character]?[spec.rule.art]
        else { return nil }
        let photo = IdlePhoto(slot: size)
        let scale = photo.height * cast.scalePerPhotoHeight
        self.cast = cast
        rule = spec.rule
        self.spec = spec
        self.art = art
        self.photo = photo
        self.step = step
        self.scale = scale
        cutout = CupLevel.cutoutName(setID: side.cupSetID, step: step)
        bounds = CGRect(origin: .zero, size: size)
        base = IdleMotion.place(spec, cast: cast, step: step, photo: photo, art: art, scale: scale)
        let pivotY = spec.pivotOnRim ? (art.rimLineY ?? Double(art.bbox.maxY)) : Double(art.bbox.maxY)
        pivot = CGPoint(x: Double(art.bbox.midX) * scale, y: pivotY * scale)
        footY = Double(art.bbox.maxY) * scale
    }

    /// `flinch`: 눌렸을 때 움찔(0 ~ 1, `IdleMotion.flinch`). 기준점을 축으로 아래로 눌렸다 돌아온다.
    func draw(in context: inout GraphicsContext, t: Double, blink: Double, flinch: Double) {
        let m = IdleMotion.frame(spec, cast: cast, t: t, photo: photo, walkBaseX: base.x)
        if let reflection = rule.reflection {
            drawReflection(reflection, in: context, m: m, flinch: flinch)
        }
        if let shadow = rule.shadow {
            drawShadow(shadow, in: context, m: m)
        }
        let sprite = placed(context, m: m, flinch: flinch)
        if rule.opacity < 1 {
            // 한 덩어리로 비치게 층으로 묶는다. 조각마다 투명도를 주면 몸 밑 팔다리 뿌리가 비친다.
            var layer = sprite
            layer.opacity = rule.opacity
            layer.drawLayer { inner in drawParts(in: inner, m: m, blink: blink) }
        } else {
            drawParts(in: sprite, m: m, blink: blink)
        }
    }

    /// 화면 좌표 → 그림 좌표(pt): 기준점을 자리에 놓고 돌리고 뒤집는다.
    private func placed(_ parent: GraphicsContext, m: IdleFrame, flinch: Double) -> GraphicsContext {
        var sprite = parent
        sprite.translateBy(x: base.x + m.dx, y: base.y + m.dy)
        if flinch > 0 {
            sprite.scaleBy(x: 1 + Self.flinchWiden * flinch, y: 1 - Self.flinchSquash * flinch)
        }
        sprite.rotate(by: .degrees(m.rot))
        sprite.scaleBy(x: m.flip, y: 1)
        sprite.translateBy(x: -pivot.x, y: -pivot.y)
        return sprite
    }

    /// 움찔할 때 세로로 눌리고 가로로 퍼지는 비율.
    private static let flinchSquash = 0.07
    private static let flinchWiden = 0.035

    /// 화면 위 점이 시각 t의 캐릭터 위인지. 그림 틀을 놓인 자리로 옮긴 사각형에 손가락 여유를 둔다.
    func contains(_ point: CGPoint, t: Double) -> Bool {
        let m = IdleMotion.frame(spec, cast: cast, t: t, photo: photo, walkBaseX: base.x)
        let box = CGRect(
            x: Double(art.bbox.minX) * scale, y: Double(art.bbox.minY) * scale,
            width: Double(art.bbox.width) * scale, height: Double(art.bbox.height) * scale
        )
        let radians: Double = m.rot * Double.pi / 180
        let transform = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(scaleX: m.flip, y: 1))
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: base.x + m.dx, y: base.y + m.dy))
        return box.applying(transform).insetBy(dx: -8, dy: -8).contains(point)
    }

    // MARK: 유리 반사

    /// 캐릭터를 잔 가운데 쪽으로 당겨 옅게 한 번 더 그리고 누끼로 잘라 유리 안에만 남긴다(프로토타입 `drawGlass`).
    /// 가로는 반사 가운데를 축으로 뒤집고(`mirror`) 누른다(`squeeze`). 가장자리는 선명하게 둔다(대표님 지시).
    private func drawReflection(_ reflection: IdleReflection, in context: GraphicsContext, m: IdleFrame, flinch: Double) {
        let look = cast.reflectionLook
        let cx: Double = Double(base.x) + m.dx
        let axis = photo.left + cast.glassAxis(step: step) * photo.width
        let toX = cx + (axis - cx) * reflection.toward
        let flip: Double = (reflection.mirror ?? look.mirror) ? -1 : 1
        var glass = context
        glass.clipToLayer { mask in
            mask.draw(Image(cutout), in: photo.rect)
        }
        glass.opacity = look.opacity
        glass.drawLayer { layer in
            var mirrored = layer
            mirrored.translateBy(x: toX, y: -reflection.up * photo.unit)
            mirrored.scaleBy(x: flip * look.squeeze, y: 1)
            mirrored.translateBy(x: -cx, y: 0)
            let sprite = placed(mirrored, m: m, flinch: flinch)
            if let tint = look.tint {
                // 로슈: 몸통 조각만 그려 몸 색 한 가지로 칠한다(팔다리·얼굴 없는 윤곽).
                drawImage("body", frame: art.body, in: bodyLayer(sprite, m: m))
                layer.blendMode = .sourceIn
                layer.fill(Path(bounds), with: .color(Self.color(hex: tint)))
            } else {
                drawParts(in: sprite, m: m, blink: 0)
            }
        }
    }

    // MARK: 그림자

    /// 넓고 옅은 그늘 + 진한 접지(프로토타입 `makeShadow`). 빛이 왼쪽 앞 위라 그늘은 오른쪽 뒤로 밀린다.
    /// 로슈 걷기는 발마다 접지를 두고, 든 발일수록 작고 옅게.
    /// 프로토타입은 곱하기 합성이지만 캔버스 안에서는 사진과 섞이지 않아 보통 합성으로 그린다(흰 바닥 위라 차이 미미).
    private func drawShadow(_ shadow: IdleShadow, in context: GraphicsContext, m: IdleFrame) {
        let u = photo.unit
        let cx: Double = Double(base.x) + m.dx
        let baseY = Double(base.y)
        let bw = Double(art.bbox.width) * scale
        drawShade(
            Self.ambient,
            center: CGPoint(x: cx + bw * shadow.dx, y: baseY + bw * shadow.dy),
            width: bw * shadow.w * 1.35, height: bw * shadow.h, strength: 1, in: context
        )
        guard shadow.feet else {
            drawShade(
                Self.contact,
                center: CGPoint(x: cx + bw * shadow.dx * 0.2, y: baseY - 0.5 * u),
                width: bw * shadow.w * 0.9, height: bw * 0.07, strength: 1, in: context
            )
            return
        }
        for part in art.parts where part.isFoot {
            let shift = m.shift[part.name] ?? .zero
            let footX = Double(part.frame.midX) * scale
            let x: Double = cx + (footX + Double(shift.dx) - Double(pivot.x)) * m.flip
            let lift: Double = -Double(shift.dy) / (IdleMotion.stepLift * u)
            let lifted = min(1.0, max(0.0, lift))
            drawShade(
                Self.contact,
                center: CGPoint(x: x, y: baseY),
                width: Double(part.frame.width) * scale * 1.5, height: bw * 0.08,
                strength: 1 - 0.45 * lifted, in: context
            )
        }
    }

    private static let ambient = Gradient(stops: [
        .init(color: Color(red: 120 / 255, green: 104 / 255, blue: 108 / 255).opacity(0.55), location: 0),
        .init(color: Color(red: 120 / 255, green: 104 / 255, blue: 108 / 255).opacity(0.3), location: 0.45),
        .init(color: Color(red: 120 / 255, green: 104 / 255, blue: 108 / 255).opacity(0.1), location: 0.75),
        .init(color: Color(red: 120 / 255, green: 104 / 255, blue: 108 / 255).opacity(0), location: 1),
    ])

    private static let contact = Gradient(stops: [
        .init(color: Color(red: 70 / 255, green: 56 / 255, blue: 60 / 255).opacity(0.8), location: 0),
        .init(color: Color(red: 70 / 255, green: 56 / 255, blue: 60 / 255).opacity(0.45), location: 0.4),
        .init(color: Color(red: 70 / 255, green: 56 / 255, blue: 60 / 255).opacity(0), location: 1),
    ])

    /// 타원 하나를 가운데서 바깥으로 흐려지게 칠한다. `strength`만큼 작고 옅어진다.
    private func drawShade(
        _ gradient: Gradient, center: CGPoint, width: Double, height: Double,
        strength: Double, in context: GraphicsContext
    ) {
        guard width > 0, height > 0, strength > 0 else { return }
        // 흐림 필터 + drawLayer로 그렸을 때 CI 스크린샷에 아무것도 안 나왔다(2026-09-29 빌드 101).
        // 그라데이션이 가장자리에서 이미 0이라 흐림 없이 늘린 좌표계에 바로 칠한다.
        var shade = context
        shade.opacity = strength
        shade.translateBy(x: center.x, y: center.y)
        shade.scaleBy(x: width * strength / 2, y: height * strength / 2)
        shade.fill(
            Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
            with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1)
        )
    }

    // MARK: 캐릭터

    /// 몸 층: 발끝 선을 기준으로 숨 쉬고 오르내린다.
    private func bodyLayer(_ ground: GraphicsContext, m: IdleFrame) -> GraphicsContext {
        var body = ground
        body.translateBy(x: pivot.x, y: footY + m.bodyDy)
        body.scaleBy(x: m.sx, y: m.sy)
        body.translateBy(x: -pivot.x, y: -footY)
        return body
    }

    private func drawParts(in ground: GraphicsContext, m: IdleFrame, blink: Double) {
        for part in art.parts where part.isBack && part.isFoot {
            drawLimb(part, in: ground, m: m)
        }
        let body = bodyLayer(ground, m: m)
        for part in art.parts where part.isBack && !part.isFoot {
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
        for part in art.parts where part.isOverlay && m.shows(part.name) {
            drawImage(part.name, frame: part.frame, in: body)
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

    /// "#RRGGBB". 형식은 그림 정보를 읽을 때(`IdleRig`)와 설정(`IdleCast`)에서 걸렀다.
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
