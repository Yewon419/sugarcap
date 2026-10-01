import SwiftUI

/// 리그 그림 한 장을 호출한 쪽이 정한 자리·배율·자세로 그린다(먹이기 캐릭터, 마무리 요약).
/// 층 순서·팔다리 규칙은 오늘 화면 `IdleSprite`와 같다: 바닥 층(발) → 몸 층(뒤쪽 팔다리 → 몸통 → 눈꺼풀 → 앞쪽 팔다리).
/// 팔다리는 `limbDirection`이 있는 것만 돈다(0 = 양쪽, ±1 = 자른 끝이 몸에 숨는 쪽만).
struct RigPainter {
    let character: String
    let artName: String
    let art: IdleArt
    /// 캔버스 픽셀 → pt.
    let scale: Double
    let lidPad: Double
    let limbDirection: [String: Double]

    init?(character: String, art artName: String, scale: Double, lidPad: Double, limbDirection: [String: Double]) {
        guard scale > 0, let art = IdleRig.arts[character]?[artName] else { return nil }
        self.character = character
        self.artName = artName
        self.art = art
        self.scale = scale
        self.lidPad = lidPad
        self.limbDirection = limbDirection
    }

    /// 그림 높이(pt).
    var height: Double { Double(art.bbox.height) * scale }
    var width: Double { Double(art.bbox.width) * scale }

    /// 그림 안 기준점(bbox 아래 가운데, pt). 전체 회전·눌림의 중심이자 몸 층 숨쉬기의 기준.
    private var pivot: CGPoint { CGPoint(x: Double(art.bbox.midX) * scale, y: Double(art.bbox.maxY) * scale) }

    /// 기준점을 `base`에 놓고 그린다. `squash`는 발밑 기준 전체 눌림(1이면 세로 8% 줄고 가로 6% 늘어남).
    func draw(in context: GraphicsContext, base: CGPoint, m: IdleFrame, squash: Double, blink: Double) {
        let p = pivot
        var ground = context
        ground.translateBy(x: base.x + m.dx, y: base.y + m.dy)
        ground.rotate(by: .degrees(m.rot))
        ground.scaleBy(x: m.flip * (1 + 0.06 * squash), y: 1 - 0.08 * squash)
        ground.translateBy(x: -p.x, y: -p.y)

        for part in art.parts where !part.isFront && part.isFoot {
            drawLimb(part, in: ground, m: m)
        }
        var body = ground
        body.translateBy(x: p.x, y: p.y + m.bodyDy)
        body.scaleBy(x: m.sx, y: m.sy)
        body.translateBy(x: -p.x, y: -p.y)
        for part in art.parts where !part.isFront && !part.isFoot {
            drawLimb(part, in: body, m: m)
        }
        drawImage("body", frame: art.body, in: body)
        if blink > 0 {
            for eye in art.eyes {
                let w = Double(eye.box.width)
                let h = Double(eye.box.height)
                let rect = CGRect(
                    x: (Double(eye.box.minX) - w * lidPad) * scale,
                    y: (Double(eye.box.minY) - h * lidPad) * scale,
                    width: w * (1 + lidPad * 2) * scale,
                    height: h * (1 + lidPad * 2) * scale * blink
                )
                body.fill(Path(ellipseIn: rect), with: .color(IdleSprite.color(hex: eye.lid)))
            }
        }
        for part in art.parts where part.isFront {
            drawLimb(part, in: body, m: m)
        }
    }

    private func drawLimb(_ part: IdleArt.Part, in parent: GraphicsContext, m: IdleFrame) {
        let amount = m.limbs[part.name] ?? 0
        let angle: Double =
            if let direction = limbDirection[part.name] {
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
        context.draw(Image("idle-\(character)-\(artName)-\(part)"), in: rect)
    }
}

/// 리그 동작 조각(먹이기·요약 공용). 전부 시각의 순수 함수다.
enum RigMotion {
    static func bump(_ t: Double, _ a: Double, _ len: Double) -> Double {
        guard t >= a, t <= a + len else { return 0 }
        return sin(Double.pi * (t - a) / len)
    }

    static func smooth(_ x: Double) -> Double {
        let v = min(1, max(0, x))
        return v * v * (3 - 2 * v)
    }

    static func remainder(_ t: Double, _ period: Double) -> Double {
        let r = t.truncatingRemainder(dividingBy: period)
        return r < 0 ? r + period : r
    }

    /// 발밑 기준으로 부풀었다 가라앉는 숨.
    static func breathe(_ m: inout IdleFrame, t: Double, period: Double, amount: Double) {
        let k = sin(2 * Double.pi * t / period)
        m.sy *= 1 + amount * k
        m.sx *= 1 - amount * 0.5 * k
    }

    /// `at`부터 통통 두 번(0.34초 간격). 반환: 뜬 높이(pt), 눌림(뜨기 직전·착지), 공중 정도(0~1).
    static func hops(_ t: Double, at: Double, height: Double) -> (lift: Double, squash: Double, air: Double) {
        var lift = 0.0
        var squash = 0.0
        var air = 0.0
        for start in [at, at + 0.34] {
            let k = bump(t, start, 0.28)
            lift += height * k
            air += k
            squash += bump(t, start - 0.06, 0.08) + bump(t, start + 0.28, 0.1)
        }
        return (lift, squash, air)
    }
}
