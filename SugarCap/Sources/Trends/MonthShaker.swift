import CoreMotion
import SpriteKit
import SwiftUI
import UIKit

/// 셰이커에 굴러다니는 선물 하나(프로토 `inventory`). 키가 같으면 달을 옮겨도 같은 몸이다.
struct ShakerGift: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case item(String)
        case heart
        case cap
    }

    /// `item:<id>:<n>` · `cap:<n>` · `heart:<n>`.
    let key: String
    let kind: Kind

    /// 물건 → 병뚜껑 → 마음 순서(프로토와 같다). 처음 쏟을 때 이 순서로 자리를 나눈다.
    static func list(_ inventory: MonthInventory) -> [ShakerGift] {
        var seen: [String: Int] = [:]
        let items = inventory.items.map { id -> ShakerGift in
            let count = (seen[id] ?? 0) + 1
            seen[id] = count
            return ShakerGift(key: "item:\(id):\(count)", kind: .item(id))
        }
        let caps = (0..<max(inventory.caps, 0)).map { ShakerGift(key: "cap:\($0)", kind: .cap) }
        let hearts = (0..<max(inventory.hearts, 0)).map { ShakerGift(key: "heart:\($0)", kind: .heart) }
        return items + caps + hearts
    }
}

/// 월 달력 셰이커(프로토 `design/proto/trends-month-dump.html` Planck → SpriteKit 이식, 2026-10-27 3단계).
/// 벽 = 둥근 화면 테두리(R 48) + 달력 격자 덩어리(사각). 제목·요일·합계 글씨는 막지 않는다.
/// 기울이면 그쪽으로 쏠리고(CoreMotion 중력), 흔들면 튀어 오른다. 동작 줄이기면 보이지 않게 가라앉힌 뒤 멈춰 둔다.
/// 단위: 프로토 px = 앱 pt. SpriteKit 중력은 m/s²(150 pt = 1 m), 속도는 pt/s.
@MainActor
final class MonthShakerScene: SKScene {
    private static let itemSize: CGFloat = 44
    private static let heartSize: CGFloat = 26
    private static let capSize: CGFloat = 25
    /// 프로토 G = 1400 px/s².
    private static let gravity: CGFloat = 1400 / 150
    private static let maxSpeed: CGFloat = 1800
    private static let cornerRadius: CGFloat = 48
    private static let ink = UIColor(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255, alpha: 1)
    private static let amber = UIColor(red: 0xE3 / 255, green: 0xC2 / 255, blue: 0x9F / 255, alpha: 1)

    private struct Body {
        let node: SKNode
        let key: String
    }

    private var bodies: [Body] = []
    private var shownSide: CupSide?
    private var pending: (gifts: [ShakerGift], side: CupSide)?
    private var reduceMotion = false
    /// 격자 자리(SwiftUI 좌표, 왼쪽 위 원점). 장면 좌표는 y를 뒤집는다.
    private var gridFrame: CGRect = .zero
    private var builtGrid: CGRect = .zero
    private var builtSize: CGSize = .zero
    private var frameNode: SKNode?
    private var gridNode: SKNode?
    private let motion = CMMotionManager()
    private var lastKick: TimeInterval = 0
    private var settling = false
    private var settleUntil: TimeInterval?
    private var hulls: [String: [CGPoint]] = [:]
    private var textures: [String: SKTexture] = [:]

    override init() {
        super.init(size: CGSize(width: 1, height: 1))
        scaleMode = .resizeFill
        backgroundColor = .clear
        physicsWorld.gravity = CGVector(dx: 0, dy: -Self.gravity)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("MonthShakerScene is created in code only")
    }

    // MARK: - 바깥에서

    /// 보는 달의 보관함. 면이 바뀌거나 처음이면 다 다시 쏟고, 달만 바뀌면 달라진 것만 더하고 뺀다.
    func show(_ gifts: [ShakerGift], side: CupSide, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        pending = (gifts, side)
    }

    func setGrid(_ frame: CGRect) {
        gridFrame = frame
    }

    func startMotion() {
        guard !reduceMotion, motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates()
    }

    func stopMotion() {
        motion.stopDeviceMotionUpdates()
        physicsWorld.gravity = CGVector(dx: 0, dy: -Self.gravity)
    }

    // MARK: - 매 프레임

    override func update(_ currentTime: TimeInterval) {
        guard size.width > 1, size.height > 1, gridFrame.width > 0 else { return }
        buildWalls()
        if let pending {
            self.pending = nil
            apply(pending.gifts, side: pending.side)
        }
        finishSettling(currentTime)
        readMotion(currentTime)
    }

    override func didSimulatePhysics() {
        for body in bodies {
            guard let physics = body.node.physicsBody else { continue }
            let velocity = physics.velocity
            let speed = hypot(velocity.dx, velocity.dy)
            if speed > Self.maxSpeed {
                physics.velocity = CGVector(dx: velocity.dx * Self.maxSpeed / speed, dy: velocity.dy * Self.maxSpeed / speed)
            }
        }
    }

    /// 화면을 기울인 방향이 아래(프로토 `setTilt`). 바닥에 눕히면 기울기를 알 수 없어 그냥 아래로 둔다.
    /// 흔들면(사용자 가속 1.6 g 넘음) 다 같이 튀어 오른다.
    private func readMotion(_ now: TimeInterval) {
        guard !reduceMotion, let data = motion.deviceMotion else { return }
        let gx = CGFloat(data.gravity.x)
        let gy = CGFloat(data.gravity.y)
        let tilt = hypot(gx, gy)
        physicsWorld.gravity = tilt < 0.25
            ? CGVector(dx: 0, dy: -Self.gravity)
            : CGVector(dx: gx / tilt * Self.gravity, dy: gy / tilt * Self.gravity)
        let shake = data.userAcceleration
        let strength = (shake.x * shake.x + shake.y * shake.y + shake.z * shake.z).squareRoot()
        if strength > 1.6, now - lastKick > 0.5 {
            lastKick = now
            kick()
        }
    }

    /// 프로토 `kick`: 옆으로 ±9 m/s, 위로 6~16 m/s(× 50 px/m), 회전 ±4 rad/s.
    private func kick() {
        for body in bodies {
            guard let physics = body.node.physicsBody else { continue }
            physics.velocity.dx += CGFloat.random(in: -450...450)
            physics.velocity.dy += CGFloat.random(in: 300...800)
            physics.angularVelocity = CGFloat.random(in: -4...4)
        }
    }

    // MARK: - 벽

    private func sceneRect(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: size.height - frame.maxY, width: frame.width, height: frame.height)
    }

    private func buildWalls() {
        if builtSize != size {
            builtSize = size
            frameNode?.removeFromParent()
            let node = SKNode()
            let path = CGPath(
                roundedRect: CGRect(origin: .zero, size: size), cornerWidth: Self.cornerRadius,
                cornerHeight: Self.cornerRadius, transform: nil
            )
            let edge = SKPhysicsBody(edgeLoopFrom: path)
            edge.friction = 0.5
            node.physicsBody = edge
            addChild(node)
            frameNode = node
        }
        guard builtGrid != gridFrame else { return }
        builtGrid = gridFrame
        gridNode?.removeFromParent()
        let rect = sceneRect(gridFrame)
        let node = SKNode()
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        let wall = SKPhysicsBody(rectangleOf: rect.size)
        wall.isDynamic = false
        wall.friction = 0.5
        node.physicsBody = wall
        addChild(node)
        gridNode = node
    }

    // MARK: - 쏟기 · 더하기 · 빼기

    private func apply(_ gifts: [ShakerGift], side: CupSide) {
        guard side == shownSide, !bodies.isEmpty, !reduceMotion else {
            load(gifts, side: side)
            return
        }
        let want = Set(gifts.map(\.key))
        for body in bodies where !want.contains(body.key) { vanish(body.node) }
        bodies.removeAll { !want.contains($0.key) }
        let have = Set(bodies.map(\.key))
        // 화면 맨 위 테두리 바로 안쪽에서 놓는다(밖에 놓으면 벽 바깥에 갇힌다).
        for (index, gift) in gifts.filter({ !have.contains($0.key) }).enumerated() {
            let x = 24 + CGFloat.random(in: 0...1) * (size.width - 48)
            let top = 16 + CGFloat(index % 3) * 12 + CGFloat.random(in: 0...10)
            spawn(gift, side: side, index: index, at: CGPoint(x: x, y: size.height - top))
        }
    }

    /// 처음 · 면이 바뀔 때. 큰 물건은 격자 양옆 틈으로 못 빠지니 처음부터 격자 아래에 둔다. 작은 것만 위·아래 번갈아.
    private func load(_ gifts: [ShakerGift], side: CupSide) {
        for body in bodies { body.node.removeFromParent() }
        bodies = []
        shownSide = side
        settling = false
        physicsWorld.speed = 1
        let grid = sceneRect(gridFrame)
        for (index, gift) in gifts.enumerated() {
            let isItem: Bool
            if case .item = gift.kind { isItem = true } else { isItem = false }
            let below = isItem || index % 2 == 1
            let x = 20 + CGFloat((index * 67) % max(Int(size.width) - 40, 1))
            let y = below
                ? grid.minY - 20 - CGFloat(index % 3) * 12
                : size.height - 24 - CGFloat(index % 3) * 10
            spawn(gift, side: side, index: index, at: CGPoint(x: x, y: y))
        }
        if reduceMotion { settleHidden() }
    }

    /// 동작 줄이기: 안 보이게 빨리 가라앉힌 뒤(1.5초) 보이고 멈춘다. 끝 시각은 다음 `update`에서 잡는다.
    private func settleHidden() {
        for body in bodies { body.node.alpha = 0 }
        physicsWorld.speed = 2
        settleUntil = nil
        settling = true
    }

    private func finishSettling(_ now: TimeInterval) {
        guard settling else { return }
        guard let until = settleUntil else {
            settleUntil = now + 1.5
            return
        }
        guard now >= until else { return }
        settling = false
        settleUntil = nil
        physicsWorld.speed = 0
        for body in bodies { body.node.alpha = 1 }
    }

    /// 그 자리에서 뿅: 1 → 1.2 → 0, 200 ms(프로토 `vanish`).
    private func vanish(_ node: SKNode) {
        node.physicsBody = nil
        let grow = SKAction.scale(to: 1.2, duration: 0.07)
        grow.timingMode = .easeOut
        let shrink = SKAction.group([.scale(to: 0, duration: 0.13), .fadeOut(withDuration: 0.13)])
        shrink.timingMode = .easeOut
        node.run(.sequence([grow, shrink, .removeFromParent()]))
    }

    private func spawn(_ gift: ShakerGift, side: CupSide, index: Int, at point: CGPoint) {
        let node: SKSpriteNode
        let physics: SKPhysicsBody?
        switch gift.kind {
        case let .item(id):
            let texture = itemTexture(id)
            node = SKSpriteNode(texture: texture, size: Self.containSize(texture.size(), in: Self.itemSize))
            physics = hull(for: id).map { SKPhysicsBody(polygonFrom: Self.path($0)) }
        case .heart:
            node = SKSpriteNode(texture: art("heart-\(side.rawValue)") { Self.heartImage(side: side) })
            node.size = CGSize(width: Self.heartSize, height: Self.heartSize)
            physics = SKPhysicsBody(bodies: Self.heartHalves.map { SKPhysicsBody(polygonFrom: Self.path($0)) })
        case .cap:
            node = SKSpriteNode(texture: art("cap-\(side.rawValue)") { Self.capImage(side: side) })
            node.size = CGSize(width: Self.capSize * Self.capOverflow, height: Self.capSize * Self.capOverflow)
            physics = SKPhysicsBody(circleOfRadius: Self.capSize * 0.46)
        }
        node.position = point
        node.zRotation = -CGFloat(index) * 0.9
        if let physics {
            physics.density = 1
            physics.friction = 0.45
            physics.restitution = 0.12
            physics.linearDamping = 0.15
            // 프로토 1.5. SpriteKit은 0~1만 받는다.
            physics.angularDamping = 1
            physics.allowsRotation = true
            if case .item = gift.kind { physics.usesPreciseCollisionDetection = true }
            physics.velocity = CGVector(dx: CGFloat((index * 37) % 7 - 3) * 0.8 * 50, dy: 0)
            node.physicsBody = physics
        }
        addChild(node)
        bodies.append(Body(node: node, key: gift.key))
    }

    // MARK: - 그림 · 몸체

    private func art(_ key: String, draw: () -> UIImage) -> SKTexture {
        if let texture = textures[key] { return texture }
        let texture = SKTexture(image: draw())
        textures[key] = texture
        return texture
    }

    private func itemTexture(_ id: String) -> SKTexture {
        art("item-\(id)") { UIImage(named: "gift-item-\(id)") ?? UIImage() }
    }

    private func hull(for id: String) -> [CGPoint]? {
        if let hull = hulls[id] { return hull }
        guard let image = UIImage(named: "gift-item-\(id)"), let hull = Self.alphaHull(image, box: Self.itemSize) else {
            return nil
        }
        hulls[id] = hull
        return hull
    }

    private static func containSize(_ size: CGSize, in box: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: box, height: box) }
        let scale = min(box / size.width, box / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    /// 물건 이미지를 상자(44)에 contain으로 그린 뒤 불투명 픽셀(알파 > 60)의 볼록 껍질, 꼭짓점 8개 이하(프로토 `hullOf`).
    /// 점은 상자 가운데 원점, y 위쪽(장면 좌표).
    private static func alphaHull(_ image: UIImage, box: CGFloat) -> [CGPoint]? {
        guard let cgImage = image.cgImage else { return nil }
        let density = 2
        let side = Int(box) * density
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            let fit = containSize(CGSize(width: cgImage.width, height: cgImage.height), in: CGFloat(side))
            let rect = CGRect(
                x: (CGFloat(side) - fit.width) / 2, y: (CGFloat(side) - fit.height) / 2, width: fit.width, height: fit.height
            )
            context.draw(cgImage, in: rect)
            return true
        }
        guard drawn else { return nil }
        let half = box / 2
        let scale = CGFloat(density)
        var points: [CGPoint] = []
        // 비트맵 메모리 첫 줄이 그림 맨 위다.
        for row in 0..<side {
            for column in 0..<side where pixels[(row * side + column) * 4 + 3] > 60 {
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    points.append(CGPoint(x: CGFloat(column + dx) / scale - half, y: half - CGFloat(row + dy) / scale))
                }
            }
        }
        let hull = convexHull(points)
        return hull.count >= 3 ? hull : nil
    }

    /// 볼록 껍질(반시계)을 꼭짓점 `limit`개 이하로. 넓이 기여가 가장 작은 꼭짓점부터 지운다(프로토 `convex`).
    static func convexHull(_ input: [CGPoint], limit: Int = 8) -> [CGPoint] {
        let points = input.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard points.count > 2 else { return points }
        func cross(_ o: CGPoint, _ p: CGPoint, _ q: CGPoint) -> CGFloat {
            (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x)
        }
        var lower: [CGPoint] = []
        for point in points {
            while lower.count > 1, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 { lower.removeLast() }
            lower.append(point)
        }
        var upper: [CGPoint] = []
        for point in points.reversed() {
            while upper.count > 1, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 { upper.removeLast() }
            upper.append(point)
        }
        var hull = Array(lower.dropLast()) + Array(upper.dropLast())
        while hull.count > limit {
            var smallest = 0
            var least = CGFloat.infinity
            for index in hull.indices {
                let previous = hull[(index - 1 + hull.count) % hull.count]
                let next = hull[(index + 1) % hull.count]
                let area = abs(cross(previous, hull[index], next))
                if area < least {
                    least = area
                    smallest = index
                }
            }
            hull.remove(at: smallest)
        }
        return hull
    }

    // MARK: 마음

    /// 프로토 `heartPath`(100 상자, y 아래쪽).
    private static let heartCurves: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 50, y: 88), CGPoint(x: 18, y: 66), CGPoint(x: 6, y: 48), CGPoint(x: 10, y: 31)),
        (CGPoint(x: 10, y: 31), CGPoint(x: 14, y: 14), CGPoint(x: 36, y: 10), CGPoint(x: 50, y: 28)),
        (CGPoint(x: 50, y: 28), CGPoint(x: 64, y: 10), CGPoint(x: 86, y: 14), CGPoint(x: 90, y: 31)),
        (CGPoint(x: 90, y: 31), CGPoint(x: 94, y: 48), CGPoint(x: 82, y: 66), CGPoint(x: 50, y: 88)),
    ]

    /// 마음은 가운데가 오목해 볼록 다각형 하나로는 안 된다. 세로 가운데에서 갈라 반쪽마다 볼록 다각형으로 만든다.
    private static let heartHalves: [[CGPoint]] = {
        func sample(_ curve: (CGPoint, CGPoint, CGPoint, CGPoint)) -> [CGPoint] {
            (0...10).map { step in
                let t = CGFloat(step) / 10
                let u = 1 - t
                let a = u * u * u
                let b = 3 * u * u * t
                let c = 3 * u * t * t
                let d = t * t * t
                let x = a * curve.0.x + b * curve.1.x + c * curve.2.x + d * curve.3.x
                let y = a * curve.0.y + b * curve.1.y + c * curve.2.y + d * curve.3.y
                return CGPoint(x: x, y: y)
            }
        }
        let scale = heartSize / 100
        let left = sample(heartCurves[0]) + sample(heartCurves[1])
        let right = sample(heartCurves[2]) + sample(heartCurves[3])
        return [left, right].map { half in
            convexHull(half.map { CGPoint(x: ($0.x - 50) * scale, y: (50 - $0.y) * scale) })
        }
    }()

    /// 마음은 두 면 모두 테두리 없이 면 주인 색만(프로토 `giftHTML`).
    private static func heartImage(side: CupSide) -> UIImage {
        let size = CGSize(width: heartSize, height: heartSize)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            cg.scaleBy(x: heartSize / 100, y: heartSize / 100)
            let path = CGMutablePath()
            path.move(to: heartCurves[0].0)
            for curve in heartCurves { path.addCurve(to: curve.3, control1: curve.1, control2: curve.2) }
            path.closeSubpath()
            cg.addPath(path)
            cg.setFillColor((side == .sugar ? UIColor.white : amber).cgColor)
            cg.fillPath()
        }
    }

    // MARK: 병뚜껑

    /// 당 병뚜껑 바깥 먹색 선(굵기 14)이 100 상자 밖으로 3 넘친다. 그림을 그만큼 넓혀 그린다.
    private static let capOverflow: CGFloat = 1.1

    /// 톱니 21개(끝 46, 골 40) + 안쪽 원(27, 검정 .18). 당 = 흰 면 + 흰 테두리 9 + 바깥 먹색 .3 선 14, 카페인 = 황갈 면만.
    private static func capImage(side: CupSide) -> UIImage {
        let box = capSize * capOverflow
        return UIGraphicsImageRenderer(size: CGSize(width: box, height: box)).image { context in
            let cg = context.cgContext
            cg.translateBy(x: box / 2, y: box / 2)
            cg.scaleBy(x: capSize / 100, y: capSize / 100)
            cg.translateBy(x: -50, y: -50)
            let teeth = 21
            let gear = CGMutablePath()
            for index in 0...(teeth * 2) {
                let angle = CGFloat(index) / CGFloat(teeth * 2) * 2 * CGFloat.pi
                let radius: CGFloat = index % 2 == 1 ? 40 : 46
                let point = CGPoint(x: 50 + radius * cos(angle), y: 50 + radius * sin(angle))
                if index == 0 { gear.move(to: point) } else { gear.addLine(to: point) }
            }
            gear.closeSubpath()
            cg.setLineJoin(.round)
            if side == .sugar {
                cg.addPath(gear)
                cg.setStrokeColor(ink.withAlphaComponent(0.3).cgColor)
                cg.setLineWidth(14)
                cg.strokePath()
                cg.addPath(gear)
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(9)
                cg.strokePath()
            }
            cg.addPath(gear)
            cg.setFillColor((side == .sugar ? UIColor.white : amber).cgColor)
            cg.fillPath()
            cg.addEllipse(in: CGRect(x: 23, y: 23, width: 54, height: 54))
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.18).cgColor)
            cg.setLineWidth(3)
            cg.strokePath()
        }
    }
}
