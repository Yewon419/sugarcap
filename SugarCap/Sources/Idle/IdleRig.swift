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
        let frame: CGRect
        let pivot: CGPoint

        /// 발은 바닥 층이라 몸이 숨 쉬거나 까치발을 해도 제자리다.
        var isFoot: Bool { name.hasPrefix("foot") }
    }

    let bbox: CGRect
    let rimLineY: Double?
    let eyes: [Eye]
    let body: CGRect
    let parts: [Part]
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

    private struct RawArt: Decodable {
        let bbox: [Double]
        let rimLineY: Double?
        let eyes: [RawEye]
        let body: [Double]
        let parts: [RawPart]

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
                    guard part.z == "back" || part.z == "front" else { throw RigError.badLayer(part.z) }
                    return IdleArt.Part(
                        name: part.name, isFront: part.z == "front",
                        frame: try IdleRig.frame(part.frame), pivot: try IdleRig.point(part.pivot)
                    )
                }
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
}
