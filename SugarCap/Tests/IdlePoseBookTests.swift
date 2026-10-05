import CoreGraphics
import XCTest

@testable import SugarCap

/// 번들 `idle-poses.json`(자세 데이터, `design/assets/characters/<캐릭터>/poses.json`)의 구조 검사.
/// 자세를 poses.json에 더할 때 그림·팔다리 이름 오타나 단계 규칙 실수를 여기서 잡는다.
/// 코드에 박혀 있던 자세와의 1:1 대조는 데이터화 커밋(2026-10-03)의 CI에서 통과한 뒤 옛 코드와 함께 지웠다.
final class IdlePoseBookTests: XCTestCase {
    private let slot = CGSize(width: 393, height: 852 * 0.84)
    private var photo: IdlePhoto { IdlePhoto(slot: slot) }
    private let steps = [0, 1, 30, 50, 80, 100]
    private let casts = [IdleCast.roshu, IdleCast.kain]

    func testEveryPoseNamesExistingArtAndLimbs() throws {
        for cast in casts {
            let set = try XCTUnwrap(cast.poseSet, cast.character)
            XCTAssertNotNil(set.poses[set.zero], "\(cast.character) zero")
            for (name, spec) in set.poses {
                let label = "\(cast.character)/\(name)"
                let art = try XCTUnwrap(IdleRig.arts[cast.character]?[spec.rule.art], label)
                let parts = Set(art.parts.map(\.name))
                XCTAssertTrue(Set(spec.rule.limbDirection.keys).isSubset(of: parts), label)
                for t in [0.0, 1.7, 4.9, 6.4] {
                    let frame = IdleMotion.frame(spec, cast: cast, t: t, photo: photo, walkBaseX: 200)
                    XCTAssertTrue(Set(frame.limbs.keys).isSubset(of: parts), "\(label) limbs \(frame.limbs.keys)")
                    XCTAssertTrue(Set(frame.shift.keys).isSubset(of: parts), "\(label) shift")
                }
                if spec.pivotOnRim {
                    XCTAssertNotNil(art.rimLineY, "\(label) pivot rimLine")
                }
                XCTAssertGreaterThanOrEqual(spec.unlock, 1, label)
            }
        }
    }

    func testPlacementAndMotionAreFinite() throws {
        for cast in casts {
            let set = try XCTUnwrap(cast.poseSet)
            let scale = photo.height * cast.scalePerPhotoHeight
            for (name, spec) in set.poses {
                let art = try XCTUnwrap(IdleRig.arts[cast.character]?[spec.rule.art])
                for step in steps {
                    let point = IdleMotion.place(spec, cast: cast, step: step, photo: photo, art: art, scale: scale)
                    XCTAssertTrue(point.x.isFinite && point.y.isFinite, "\(name) \(step)")
                }
                for i in 0..<400 {
                    let t = Double(i) * 0.0371
                    let f = IdleMotion.frame(spec, cast: cast, t: t, photo: photo, walkBaseX: 200)
                    let values = [f.dx, f.dy, f.rot, f.flip, f.bodyDy, f.sx, f.sy] + Array(f.limbs.values)
                    XCTAssertTrue(values.allSatisfy(\.isFinite), "\(cast.character)/\(name) t=\(t)")
                }
            }
        }
    }

    func testPickHonorsStepRules() throws {
        var generator = SystemRandomNumberGenerator()
        for cast in casts {
            let set = try XCTUnwrap(cast.poseSet)
            XCTAssertEqual(set.pick(step: 0, unlockedLevel: 1, using: &generator), set.zero)
            for step in steps where step > 0 {
                for level in [1, 3, AffinityMath.maxLevel] {
                    for _ in 0..<40 {
                        let pose = set.pick(step: step, unlockedLevel: level, using: &generator)
                        XCTAssertTrue(set.allows(pose, step: step, unlockedLevel: level), "\(cast.character) \(pose) at \(step) Lv\(level)")
                    }
                }
            }
        }
        let top = AffinityMath.maxLevel
        let roshu = try XCTUnwrap(IdleCast.roshu.poseSet)
        XCTAssertFalse(roshu.allows("in-cup", step: 80, unlockedLevel: top))
        XCTAssertFalse(roshu.allows("slump", step: 50, unlockedLevel: top))
        XCTAssertTrue(roshu.allows("slump", step: 0, unlockedLevel: 1))
        let kain = try XCTUnwrap(IdleCast.kain.poseSet)
        XCTAssertFalse(kain.allows("swim", step: 10, unlockedLevel: top))
        XCTAssertTrue(kain.allows("swim", step: 30, unlockedLevel: top))
        XCTAssertFalse(kain.allows("rim-stand", step: 0, unlockedLevel: top))
    }

    /// 단계 보상(SPEC §9.8): 자세는 풀린 단계까지만. 0% 자세는 해금과 상관없다.
    func testUnlockGatesPoses() throws {
        let roshu = try XCTUnwrap(IdleCast.roshu.poseSet)
        XCTAssertTrue(roshu.allows("walk", step: 30, unlockedLevel: 1))
        XCTAssertFalse(roshu.allows("in-cup", step: 30, unlockedLevel: 2))
        XCTAssertTrue(roshu.allows("in-cup", step: 30, unlockedLevel: 3))
        XCTAssertFalse(roshu.allows("hug-strawberry", step: 80, unlockedLevel: 3))
        XCTAssertTrue(roshu.allows("hug-strawberry", step: 80, unlockedLevel: 4))
        let kain = try XCTUnwrap(IdleCast.kain.poseSet)
        XCTAssertFalse(kain.allows("rim-stand", step: 80, unlockedLevel: 1))
        XCTAssertTrue(kain.allows("rim-stand", step: 80, unlockedLevel: 2))
        XCTAssertFalse(kain.allows("swim", step: 80, unlockedLevel: 2))
        XCTAssertTrue(kain.allows("floor-sit", step: 0, unlockedLevel: 1))
        // Lv1이어도 1% 이상이면 뽑을 자세가 있다(빈 풀이면 0% 자세로 떨어져 엉뚱해진다).
        for cast in casts {
            let set = try XCTUnwrap(cast.poseSet)
            for step in steps where step > 0 {
                XCTAssertTrue(set.poses.keys.contains { set.allows($0, step: step, unlockedLevel: 1) }, "\(cast.character) \(step)")
            }
        }
    }

    func testFreeUnlockStopsAtCap() {
        XCTAssertEqual(AffinityMath.unlockedLevel(level: 2, isPro: false), 2)
        XCTAssertEqual(AffinityMath.unlockedLevel(level: 7, isPro: false), AffinityMath.freeLevelCap)
        XCTAssertEqual(AffinityMath.unlockedLevel(level: 7, isPro: true), 7)
    }

    /// 누르면 움찔(2026-10-04): 짧게 움츠렸다가 풀리고, 끝나면 정확히 0으로 돌아온다.
    func testFlinchRisesThenSettles() {
        XCTAssertEqual(IdleMotion.flinch(age: -0.1), 0)
        XCTAssertEqual(IdleMotion.flinch(age: 0), 0)
        XCTAssertEqual(IdleMotion.flinch(age: 0.06), 1, accuracy: 1e-9)
        XCTAssertEqual(IdleMotion.flinch(age: IdleMotion.flinchDuration), 0)
        var previous = 1.0
        for i in 1...30 {
            let age = 0.06 + Double(i) * (IdleMotion.flinchDuration - 0.06) / 30
            let value = IdleMotion.flinch(age: age)
            XCTAssertLessThanOrEqual(value, previous, "age \(age)")
            previous = value
        }
    }

    /// 캐릭터 위를 눌렀는지: 자세마다 놓인 자리(기준점 바로 위)는 맞고, 화면 구석은 아니다.
    func testSpriteHitTest() throws {
        for side in CupSide.allCases {
            let set = try XCTUnwrap(side.idleCast.poseSet)
            for name in set.poses.keys {
                let sprite = try XCTUnwrap(IdleSprite(side: side, pose: name, step: 50, size: slot), name)
                let m = IdleMotion.frame(sprite.spec, cast: sprite.cast, t: 0, photo: photo, walkBaseX: sprite.base.x)
                let onBody = CGPoint(x: sprite.base.x + m.dx, y: sprite.base.y + m.dy - 4)
                XCTAssertTrue(sprite.contains(onBody, t: 0), "\(side) \(name)")
                XCTAssertFalse(sprite.contains(CGPoint(x: -100, y: -100), t: 0), "\(side) \(name)")
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
}
