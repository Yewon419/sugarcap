import SwiftUI

/// 대기 영상(`CupIdleOverlay`)이 없는 잔의 대기 모션: 잔 겉에 맺힌 물방울(대표님 2026-11-03 "망고스무디·초코프라페는
/// 안 움직이니 음료 회전 대신 겉에 물방울 맺혀 떨어지는 걸로"). 작은 방울은 제자리에 맺혀 있고, 큰 방울 몇 개가 자라다가
/// 멈칫거리며 흘러내려 젖은 길을 남긴다. 그 길의 작은 방울은 쓸려 없어졌다가 길이 마르면 다시 맺힌다.
///
/// 모양은 시각 t의 순수 함수다(번호 해시로 자리를 정해 매 프레임 같다). 에어브러시 없이 단색 면·또렷한 선만 쓴다.
/// 좌표는 937×1666 사진 캔버스 px. 잔 옆선은 아메리카노 잔 누끼에서 쟀다(영상 없는 망고·프라페가 모두 이 잔).
/// 프로토타입에서 망고 100%·프라페 50%로 세기를 맞췄다.
struct CupCondensation: View {
    let setID: String
    let step: Int
    /// 넘기는 중·화면 밖이면 멈춘다(리포 CLAUDE.md, 매 프레임 그리는 뷰).
    let isActive: Bool

    @State private var start = Date()
    @State private var pausedAt: Date?

    var body: some View {
        if let liquid = CupSetGeometry.of(setID)?.liquid[step] {
            let field = CondensationField(liquid: liquid, seed: Self.seed(setID))
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: pausedAt != nil)) { timeline in
                let t = (pausedAt ?? timeline.date).timeIntervalSince(start)
                Canvas { context, size in
                    let scale = size.width / CondensationField.canvasWidth
                    context.scaleBy(x: scale, y: scale)
                    field.draw(in: &context, t: t)
                }
            }
            .allowsHitTesting(false)
            .onChange(of: isActive, initial: true) { _, active in
                if active {
                    if let pausedAt { start = start.addingTimeInterval(Date().timeIntervalSince(pausedAt)) }
                    pausedAt = nil
                } else if pausedAt == nil {
                    pausedAt = Date()
                }
            }
        }
    }

    /// 세트마다 방울 배치가 다르게. `hashValue`는 실행마다 바뀌어 스크린샷이 흔들리니 직접 센다.
    private static func seed(_ setID: String) -> UInt32 {
        setID.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
    }
}

struct CondensationField {
    static let canvasWidth: CGFloat = 937
    static let canvasHeight: Double = 1666
    /// 맺히는 구간 아래 끝(잔 두꺼운 바닥 위).
    static let zoneBottom: Double = 1370

    let top: Double
    let seed: UInt32

    init(liquid: Double, seed: UInt32) {
        // 차가운 음료가 닿은 수면 조금 아래부터 맺힌다.
        top = (liquid + 0.03) * Self.canvasHeight
        self.seed = seed
    }

    private var zoneHeight: Double { max(0, Self.zoneBottom - top) }

    struct Drop {
        var x: Double
        var y: Double
        var rx: Double
        var ry: Double
        var alpha: Double
        var clear: Double
    }

    struct Trail {
        let x: Double
        let top: Double
        let tip: Double
        let width: Double
        let fade: Double
        let residue: [Drop]
    }

    func draw(in context: inout GraphicsContext, t: Double) {
        guard zoneHeight > 40 else { return }
        let (drops, trails) = sliders(t: t)
        for trail in trails {
            let rect = CGRect(x: trail.x - trail.width / 2, y: trail.top, width: trail.width, height: max(0, trail.tip - trail.top))
            let path = Path(roundedRect: rect, cornerRadius: trail.width / 2)
            context.fill(path, with: .color(.white.opacity(0.14 * trail.fade)))
            for bead in trail.residue { Self.paint(bead, in: &context, large: false) }
        }
        for bead in beads(drops: drops, trails: trails) { Self.paint(bead, in: &context, large: false) }
        for drop in drops { Self.paint(drop, in: &context, large: true) }
    }

    /// 자라다 흘러내리는 큰 방울. 한 바퀴(P초)마다 자리를 새로 뽑는다.
    private func sliders(t: Double) -> ([Drop], [Trail]) {
        let count = max(1, Int((5 * zoneHeight / 770).rounded()))
        var drops: [Drop] = []
        var trails: [Trail] = []
        for i in 0 ..< count {
            let period: Double = 11 + 5 * hash(i, 10)
            let local: Double = t + hash(i, 11) * period
            let cycle = Int((local / period).rounded(.down))
            let u: Double = local - Double(cycle) * period
            let key = i * 1000 + cycle
            let y0: Double = top + zoneHeight * (0.04 + 0.45 * hash(key, 20))
            let x: Double = Self.faceX(y: y0, u: hash(key, 21))
            let r1: Double = 10 + 5 * hash(key, 22)
            let yEnd: Double = min(Self.zoneBottom - r1, y0 + 220 + 420 * hash(key, 23))
            let grow: Double = 0.35 * period
            let slideStart: Double = grow + 0.6
            let slideLength: Double = 1.8 + 1.2 * hash(key, 24)
            let slideEnd: Double = slideStart + slideLength

            var y = y0
            var r = r1
            var stretch: Double = 1
            var alpha: Double = min(1, u / 0.8)
            var wet: Double = 0
            if u < grow {
                let k: Double = u / grow
                r = r1 * (0.3 + 0.7 * (1 - (1 - k) * (1 - k)))
            } else if u < slideStart {
                stretch = 1 + 0.06 * sin((u - grow) * 18)
            } else if u < slideEnd {
                let p: Double = (u - slideStart) / slideLength
                y = Self.slideY(y0, yEnd, p)
                let ahead: Double = Self.slideY(y0, yEnd, min(1, p + 0.02))
                let speed: Double = (ahead - y) / (0.02 * slideLength)
                stretch = 1 + 0.45 * min(1, speed / 400)
                r = r1 * (1 - 0.35 * p)
                wet = 1
            } else {
                y = yEnd
                r = r1 * 0.65
                alpha = max(0, 1 - (u - slideEnd) / 2.5)
                wet = max(0, 1 - (u - slideEnd) / 3)
            }
            if alpha > 0 {
                let squeeze: Double = stretch.squareRoot()
                drops.append(Drop(x: x, y: y, rx: r / squeeze, ry: r * stretch, alpha: alpha, clear: r1))
            }
            if u >= slideStart, wet > 0 {
                var residue: [Drop] = []
                for k in 0 ..< 4 {
                    let along: Double = (Double(k) + 0.5) / 4 * (yEnd - y0)
                    let yk: Double = y0 + along + (hash(key, 30 + k) - 0.5) * 30
                    guard yk < y - r else { continue }
                    let xk: Double = x + (hash(key, 40 + k) - 0.5) * r1 * 0.3
                    let rk: Double = r1 * (0.18 + 0.1 * hash(key, 50 + k))
                    residue.append(Drop(x: xk, y: yk, rx: rk, ry: rk, alpha: wet, clear: 0))
                }
                trails.append(Trail(x: x, top: y0 - 0.3 * r1, tip: y, width: 0.5 * r1, fade: wet, residue: residue))
            }
        }
        return (drops, trails)
    }

    /// 제자리에 맺힌 작은 방울. 젖은 길·큰 방울 자리에 있으면 지운다.
    private func beads(drops: [Drop], trails: [Trail]) -> [Drop] {
        let count = Int((110 * zoneHeight / 770).rounded())
        var result: [Drop] = []
        for j in 0 ..< count {
            let y: Double = top + zoneHeight * hash(j, 1)
            let x: Double = Self.faceX(y: y, u: hash(j, 2))
            let h: Double = hash(j, 3)
            let r: Double = 4 + 6 * h * h
            var alpha: Double = 1
            for trail in trails where abs(x - trail.x) < trail.width + r && y > trail.top - r && y < trail.tip {
                alpha = min(alpha, 1 - trail.fade)
            }
            for drop in drops where hypot(x - drop.x, y - drop.y) < drop.clear + r {
                alpha = 0
            }
            if alpha > 0.01 { result.append(Drop(x: x, y: y, rx: r, ry: r, alpha: alpha, clear: 0)) }
        }
        return result
    }

    /// 물방울 하나: 옅은 흰 몸통 + 먹색 테 + 아래쪽 먹색 초승달(굴절 그늘) + 왼쪽 위 하이라이트.
    private static func paint(_ d: Drop, in context: inout GraphicsContext, large: Bool) {
        let body = Path(ellipseIn: CGRect(x: d.x - d.rx, y: d.y - d.ry, width: 2 * d.rx, height: 2 * d.ry))
        let ink = Color(red: 40 / 255, green: 30 / 255, blue: 25 / 255)
        context.fill(body, with: .color(.white.opacity(0.26 * d.alpha)))
        context.stroke(body, with: .color(ink.opacity(0.22 * d.alpha)), lineWidth: max(1.2, 0.1 * d.rx))
        context.drawLayer { layer in
            layer.clip(to: body)
            var crescent = body
            crescent.addEllipse(in: CGRect(x: d.x - d.rx, y: d.y - 0.22 * d.ry - d.ry, width: 2 * d.rx, height: 2 * d.ry))
            layer.fill(crescent, with: .color(ink.opacity(0.3 * d.alpha)), style: FillStyle(eoFill: true))
        }
        let shine = CGRect(x: d.x - 0.6 * d.rx, y: d.y - 0.57 * d.ry, width: 0.6 * d.rx, height: 0.44 * d.ry)
        context.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.95 * d.alpha)))
        if large {
            let caustic = CGRect(x: d.x - 0.15 * d.rx, y: d.y + 0.41 * d.ry, width: 0.6 * d.rx, height: 0.18 * d.ry)
            context.fill(Path(ellipseIn: caustic), with: .color(.white.opacity(0.4 * d.alpha)))
        }
    }

    /// 아메리카노 잔 옆선(누끼 알파, y 500·1350에서 잰 직선) 안쪽 80%에서 u(0~1) 자리.
    private static func faceX(y: Double, u: Double) -> Double {
        let left: Double = 202 + 57 * (y - 500) / 850
        let right: Double = 732 - 64 * (y - 500) / 850
        let width: Double = right - left
        return left + width * (0.1 + 0.8 * u)
    }

    /// 멈칫거리며 빨라지는 미끄럼. q - a·sin(2πnq)/(2πn)은 a < 1이면 늘 내려간다.
    private static func slideY(_ y0: Double, _ y1: Double, _ p: Double) -> Double {
        let q: Double = pow(p, 1.5)
        let turns: Double = 3
        let wobble: Double = 0.8 * sin(2 * Double.pi * turns * q) / (2 * Double.pi * turns)
        return y0 + (y1 - y0) * (q - wobble)
    }

    private func hash(_ a: Int, _ b: Int) -> Double {
        var x: UInt32 = UInt32(truncatingIfNeeded: a) &* 374_761_393
        x = x &+ UInt32(truncatingIfNeeded: b) &* 668_265_263
        x = x &+ seed &* 2_246_822_519
        x = (x ^ (x >> 13)) &* 1_274_126_177
        x ^= x >> 16
        return Double(x) / 4_294_967_296
    }
}
