import CoreGraphics
import Foundation
import OSLog

/// 대기 자세 그림 한 장의 정보(`design/assets/characters/export_ios.py`가 만든 `idle-rig.json`).
/// 좌표는 전부 원화 캔버스 픽셀이다. 조각 그림은 0.2배로 줄여 번들했고, 프레임 크기로 늘려 그린다.
struct IdleArt: Sendable {
    struct Eye: Sendable {
        let box: CGRect
        let lid: String
    }

    struct Part: Sendable {
        let name: String
        let isFront: Bool
        /// 바꿔 끼우는 얼굴 조각(감은 눈 등): 몸 위·눈꺼풀 위에 그리고, 돌지 않으며, `show.<이름>`이 0.5 이상일 때만 보인다.
        let isOverlay: Bool
        /// 계산으로 기울이는 소품 정육면체의 면(`IdleCube`). 캐릭터 밑에 따로 그린다.
        let isCube: Bool
        /// 잔 앞에 걸친 조각(빼꼼 로슈 손). 잔 뒤 자세(`IdlePoseRule.behindCup`)에서 지우지 않고 잔 위에 따로 그린다.
        let isOverCup: Bool
        let frame: CGRect
        let pivot: CGPoint

        /// 발은 바닥 층이라 몸이 숨 쉬거나 까치발을 해도 제자리다.
        var isFoot: Bool { !isOverlay && !isCube && !isOverCup && name.hasPrefix("foot") }

        /// 몸 뒤에 그리는 팔다리.
        var isBack: Bool { !isFront && !isOverlay && !isCube && !isOverCup }
    }

    let bbox: CGRect
    let rimLineY: Double?
    let eyes: [Eye]
    let body: CGRect
    let parts: [Part]
    /// 캐릭터가 올라선 소품 정육면체(로슈 각설탕). 없으면 nil.
    let cube: IdleCube?
}

/// 면 세 장으로 그린 정육면체(`design/assets/characters/sugar_cube.py`). 평행 투영이라
/// 화면 점 = origin + x·ex + y·ey + z·ez (x, y, z ∈ 0…1). origin은 앞 아래 꼭짓점, ey가 위,
/// ex는 왼쪽 뒤, ez는 오른쪽 뒤로 간다. 좌표는 원화 캔버스 픽셀.
struct IdleCube: Sendable {
    struct Face: Sendable {
        let name: String
        /// u = v = 0인 꼭짓점과 u·v 방향(정육면체 단위).
        let corner: SIMD3<Double>
        let u: SIMD3<Double>
        let v: SIMD3<Double>
        /// 바깥 법선(정육면체 단위).
        let normal: SIMD3<Double>
    }

    let origin: CGPoint
    let ex: CGVector
    let ey: CGVector
    let ez: CGVector
    /// 뒤에서 앞 순서(옆면 → 윗면).
    let faces: [Face]
    /// 캐릭터가 딛는 윗면 자리(x, z). 윗면은 y = 1.
    let stand: SIMD2<Double>
    /// 캐릭터가 각설탕 기울기에 반대로 버티는 몫(0 = 같이 기운다).
    let lean: Double
}

enum IdleRig {
    /// 캐릭터 id("roshu", "kain") → 그림 이름 → 정보. 읽기에 실패하면 비어 있고 캐릭터가 안 보인다(오류는 로그).
    static let arts: [String: [String: IdleArt]] = load(bundle: .main)

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "idle")

    static func load(bundle: Bundle) -> [String: [String: IdleArt]] {
        guard let url = bundle.url(forResource: "idle-rig", withExtension: "json") else {
            logger.error("idle-rig.json이 번들에 없음")
            return [:]
        }
        do {
            let raw = try JSONDecoder().decode([String: [String: RawArt]].self, from: Data(contentsOf: url))
            return try raw.mapValues { arts in try arts.mapValues { try $0.art() } }
        } catch {
            logger.error("idle-rig.json 읽기 실패: \(String(describing: error), privacy: .public)")
            return [:]
        }
    }

    enum RigError: Error {
        case badRect([Double])
        case badPoint([Double])
        case badLayer(String)
        case badColour(String)
        case badCube(String)
    }

    private struct RawEye: Decodable {
        let box: [Double]
        let lid: String
    }

    private struct RawPart: Decodable {
        let name: String
        let z: String
        let frame: [Double]
        let pivot: [Double]
    }

    private struct RawFace: Decodable {
        let name: String
        let span: [[Double]]
        let normal: [Double]
    }

    private struct RawCube: Decodable {
        let origin: [Double]
        let ex: [Double]
        let ey: [Double]
        let ez: [Double]
        let faces: [RawFace]
        let stand: [Double]
        let lean: Double

        func cube() throws -> IdleCube {
            IdleCube(
                origin: try IdleRig.point(origin),
                ex: try IdleRig.vector(ex), ey: try IdleRig.vector(ey), ez: try IdleRig.vector(ez),
                faces: try faces.map { face in
                    guard face.span.count == 3 else { throw RigError.badCube(face.name) }
                    return IdleCube.Face(
                        name: face.name,
                        corner: try IdleRig.unit(face.span[0], face.name),
                        u: try IdleRig.unit(face.span[1], face.name),
                        v: try IdleRig.unit(face.span[2], face.name),
                        normal: try IdleRig.unit(face.normal, face.name)
                    )
                },
                stand: try {
                    guard stand.count == 2 else { throw RigError.badCube("stand") }
                    return SIMD2(stand[0], stand[1])
                }(),
                lean: lean
            )
        }
    }

    private struct RawArt: Decodable {
        let bbox: [Double]
        let rimLineY: Double?
        let eyes: [RawEye]
        let body: [Double]
        let parts: [RawPart]
        let cube: RawCube?

        func art() throws -> IdleArt {
            IdleArt(
                bbox: try IdleRig.corners(bbox),
                rimLineY: rimLineY,
                eyes: try eyes.map { eye in
                    guard eye.lid.count == 7, eye.lid.hasPrefix("#"), UInt32(eye.lid.dropFirst(), radix: 16) != nil else {
                        throw RigError.badColour(eye.lid)
                    }
                    return IdleArt.Eye(box: try IdleRig.corners(eye.box), lid: eye.lid)
                },
                body: try IdleRig.frame(body),
                parts: try parts.map { part in
                    guard ["back", "front", "overlay", "cube", "cup"].contains(part.z) else {
                        throw RigError.badLayer(part.z)
                    }
                    return IdleArt.Part(
                        name: part.name, isFront: part.z == "front", isOverlay: part.z == "overlay",
                        isCube: part.z == "cube", isOverCup: part.z == "cup",
                        frame: try IdleRig.frame(part.frame), pivot: try IdleRig.point(part.pivot)
                    )
                },
                cube: try cube?.cube()
            )
        }
    }

    /// [x0, y0, x1, y1]
    private static func corners(_ v: [Double]) throws -> CGRect {
        guard v.count == 4 else { throw RigError.badRect(v) }
        return CGRect(x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1])
    }

    /// [x, y, w, h]
    private static func frame(_ v: [Double]) throws -> CGRect {
        guard v.count == 4 else { throw RigError.badRect(v) }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    private static func point(_ v: [Double]) throws -> CGPoint {
        guard v.count == 2 else { throw RigError.badPoint(v) }
        return CGPoint(x: v[0], y: v[1])
    }

    private static func vector(_ v: [Double]) throws -> CGVector {
        guard v.count == 2 else { throw RigError.badPoint(v) }
        return CGVector(dx: v[0], dy: v[1])
    }

    private static func unit(_ v: [Double], _ face: String) throws -> SIMD3<Double> {
        guard v.count == 3 else { throw RigError.badCube(face) }
        return SIMD3(v[0], v[1], v[2])
    }
}
