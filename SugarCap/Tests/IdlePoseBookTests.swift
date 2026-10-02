import CoreGraphics
import XCTest

@testable import SugarCap

/// 자세 데이터화(2026-10-03) 대조: 번들 `idle-poses.json`을 해석한 결과가 코드에 박혀 있던
/// 자세 규칙·자리·움직임(`IdleCast.roshu/kain`, `IdleMotion.place/frame(_: IdlePose …)`)과 같아야 한다.
final class IdlePoseBookTests: XCTestCase {
    private let photo = IdlePhoto(slot: CGSize(width: 393, height: 852 * 0.84))
    private let steps = [0, 30, 50, 80, 100]

    func testBookCoversEveryHardCodedPoseWithSameRule() throws {
        for cast in [IdleCast.roshu, IdleCast.kain] {
            let set = try XCTUnwrap(IdlePoseBook.sets[cast.character], cast.character)
            XCTAssertEqual(set.zero, cast.zero.rawValue)
            XCTAssertEqual(Set(set.poses.keys), Set(cast.poses.keys.map(\.rawValue)), cast.character)
            for (pose, old) in cast.poses {
                let new = try XCTUnwrap(set.poses[pose.rawValue]).rule
                let label = "\(cast.character)/\(pose.rawValue)"
                XCTAssertEqual(new.art, old.art, label)
                XCTAssertEqual(new.mirror, old.mirror, label)
                XCTAssertEqual(new.minStep, old.minStep, label)
                XCTAssertEqual(new.maxStep, old.maxStep, label)
                XCTAssertEqual(new.opacity, old.opacity, label)
                XCTAssertEqual(new.limbDirection, old.limbDirection, label)
                XCTAssertEqual(new.reflection, old.reflection, label)
                XCTAssertEqual(new.shadow, old.shadow, label)
            }
        }
    }

    func testPlacementMatchesHardCodedPlacement() throws {
        for cast in [IdleCast.roshu, IdleCast.kain] {
            let set = try XCTUnwrap(IdlePoseBook.sets[cast.character])
            for (pose, rule) in cast.poses {
                let spec = try XCTUnwrap(set.poses[pose.rawValue])
                let art = try XCTUnwrap(IdleRig.arts[cast.character]?[rule.art])
                let scale = photo.height * cast.scalePerPhotoHeight
                XCTAssertEqual(spec.pivotOnRim, pose == .inCup)
                for step in steps {
                    let old = IdleMotion.place(pose, cast: cast, step: step, photo: photo, art: art, scale: scale)
                    let new = IdleMotion.place(spec, cast: cast, step: step, photo: photo, art: art, scale: scale)
                    XCTAssertEqual(Double(new.x), Double(old.x), accuracy: 1e-9, "\(pose.rawValue) \(step)")
                    XCTAssertEqual(Double(new.y), Double(old.y), accuracy: 1e-9, "\(pose.rawValue) \(step)")
                }
            }
        }
    }

    func testMotionMatchesHardCodedMotionOverTime() throws {
        for cast in [IdleCast.roshu, IdleCast.kain] {
            let set = try XCTUnwrap(IdlePoseBook.sets[cast.character])
            for (pose, rule) in cast.poses {
                let spec = try XCTUnwrap(set.poses[pose.rawValue])
                for i in 0..<1200 {
                    let t = Double(i) * 0.0371
                    let old = IdleMotion.frame(pose, cast: cast, rule: rule, t: t, photo: photo, walkBaseX: 200)
                    let new = IdleMotion.frame(spec, cast: cast, t: t, photo: photo, walkBaseX: 200)
                    assertClose(new, old, "\(cast.character)/\(pose.rawValue) t=\(t)")
                }
            }
        }
    }

    func testRejectsUnknownTarget() {
        let json = #"""
        {"x": {"zero": "a", "poses": {"a": {"art": "a", "unlock": 1, "place": {"x": 0.5, "y": "bottom"},
          "motion": [{"to": "nose", "shape": "wave", "amp": 1, "period": 1}]}}}}
        """#
        XCTAssertThrowsError(try IdlePoseBook.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? IdlePoseBook.BookError, .badTarget(pose: "a", target: "nose"))
        }
    }

    private func assertClose(_ a: IdleFrame, _ b: IdleFrame, _ label: String) {
        let pairs: [(Double, Double, String)] = [
            (a.dx, b.dx, "dx"), (a.dy, b.dy, "dy"), (a.rot, b.rot, "rot"), (a.flip, b.flip, "flip"),
            (a.bodyDy, b.bodyDy, "bodyDy"), (a.sx, b.sx, "sx"), (a.sy, b.sy, "sy"),
        ]
        for (x, y, name) in pairs {
            XCTAssertEqual(x, y, accuracy: 1e-9, "\(label) \(name)")
        }
        XCTAssertEqual(Set(a.limbs.keys), Set(b.limbs.keys), label)
        for (name, value) in b.limbs {
            XCTAssertEqual(a.limbs[name] ?? .nan, value, accuracy: 1e-9, "\(label) limb \(name)")
        }
        XCTAssertEqual(Set(a.shift.keys), Set(b.shift.keys), label)
        for (name, value) in b.shift {
            XCTAssertEqual(Double(a.shift[name]?.dx ?? .nan), Double(value.dx), accuracy: 1e-9, "\(label) shift \(name)")
            XCTAssertEqual(Double(a.shift[name]?.dy ?? .nan), Double(value.dy), accuracy: 1e-9, "\(label) shift \(name)")
        }
    }
}
