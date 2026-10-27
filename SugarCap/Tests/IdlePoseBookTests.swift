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
                    let overlays = Set(art.parts.filter(\.isOverlay).map(\.name))
                    XCTAssertTrue(Set(frame.show.keys).isSubset(of: overlays), "\(label) show \(frame.show.keys)")
                }
                if spec.pivot == .rimLine {
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
        XCTAssertFalse(kain.allows("swim", step: 30, unlockedLevel: top))
        XCTAssertTrue(kain.allows("swim", step: 50, unlockedLevel: top))
        XCTAssertFalse(kain.allows("rim-stand", step: 0, unlockedLevel: top))
    }

    /// 단계 보상(SPEC §9.8): 자세는 풀린 단계까지만. 0% 자세는 해금과 상관없다.
    func testUnlockGatesPoses() throws {
        let roshu = try XCTUnwrap(IdleCast.roshu.poseSet)
        XCTAssertTrue(roshu.allows("walk", step: 30, unlockedLevel: 1))
        XCTAssertFalse(roshu.allows("in-cup", step: 30, unlockedLevel: 2))
        XCTAssertTrue(roshu.allows("in-cup", step: 30, unlockedLevel: 3))
        XCTAssertFalse(roshu.allows("doze-lean", step: 80, unlockedLevel: 4))
        XCTAssertTrue(roshu.allows("doze-lean", step: 80, unlockedLevel: 5))
        XCTAssertFalse(roshu.allows("wave", step: 80, unlockedLevel: 5))
        XCTAssertTrue(roshu.allows("wave", step: 80, unlockedLevel: 6))
        let kain = try XCTUnwrap(IdleCast.kain.poseSet)
        XCTAssertFalse(kain.allows("rim-stand", step: 80, unlockedLevel: 1))
        XCTAssertTrue(kain.allows("rim-stand", step: 80, unlockedLevel: 2))
        XCTAssertFalse(kain.allows("swim", step: 80, unlockedLevel: 2))
        XCTAssertFalse(kain.allows("lie-left", step: 80, unlockedLevel: 3))
        XCTAssertTrue(kain.allows("lie-left", step: 80, unlockedLevel: 4))
        XCTAssertTrue(kain.allows("lie-right", step: 1, unlockedLevel: 4))
        XCTAssertFalse(kain.allows("lie-right", step: 0, unlockedLevel: 4))
        XCTAssertFalse(kain.allows("doze-one-leg", step: 80, unlockedLevel: 4))
        XCTAssertTrue(kain.allows("doze-one-leg", step: 80, unlockedLevel: 5))
        XCTAssertTrue(kain.allows("floor-sit", step: 0, unlockedLevel: 1))
        // 물건 자세(대표님 2026-10-27): 단계와 별개로 그 물건을 열어 받았을 때만, 1%부터.
        XCTAssertFalse(roshu.allows("hug-strawberry", step: 80, unlockedLevel: 10))
        XCTAssertFalse(roshu.allows("hug-strawberry", step: 80, unlockedLevel: 10, items: ["coffee-bean"]))
        XCTAssertTrue(roshu.allows("hug-strawberry", step: 80, unlockedLevel: 1, items: ["strawberry"]))
        XCTAssertFalse(roshu.allows("hug-strawberry-left", step: 80, unlockedLevel: 10))
        XCTAssertTrue(roshu.allows("hug-strawberry-left", step: 80, unlockedLevel: 1, items: ["strawberry"]))
        XCTAssertTrue(roshu.allows("slump-right", step: 30, unlockedLevel: 1))
        XCTAssertFalse(roshu.allows("slump-right", step: 0, unlockedLevel: 1))
        XCTAssertFalse(kain.allows("floor-sit-right", step: 0, unlockedLevel: 1))
        XCTAssertTrue(kain.allows("floor-sit-right", step: 100, unlockedLevel: 1))
        XCTAssertFalse(roshu.allows("hug-strawberry", step: 0, unlockedLevel: 1, items: ["strawberry"]))
        XCTAssertFalse(kain.allows("bean-balance-left", step: 80, unlockedLevel: 10, items: ["strawberry"]))
        XCTAssertTrue(kain.allows("bean-balance-right", step: 1, unlockedLevel: 1, items: ["coffee-bean"]))
        XCTAssertFalse(roshu.allows("sugar-cube-left", step: 80, unlockedLevel: 10, items: ["strawberry"]))
        XCTAssertTrue(roshu.allows("sugar-cube-left", step: 1, unlockedLevel: 1, items: ["sugar-cube"]))
        XCTAssertTrue(roshu.allows("sugar-cube-right", step: 100, unlockedLevel: 1, items: ["sugar-cube"]))
        XCTAssertFalse(kain.allows("cinnamon-stick-left", step: 80, unlockedLevel: 10, items: ["coffee-bean"]))
        XCTAssertTrue(kain.allows("cinnamon-stick-left", step: 1, unlockedLevel: 1, items: ["cinnamon-stick"]))
        XCTAssertTrue(kain.allows("cinnamon-stick-right", step: 100, unlockedLevel: 1, items: ["cinnamon-stick"]))
        // 물건 id는 선물 물건 목록에 있어야 한다(오타면 영영 안 풀린다).
        let itemIDs = Set(GiftContent.items.map(\.id))
        for cast in casts {
            for (name, spec) in try XCTUnwrap(cast.poseSet).poses {
                if let item = spec.item { XCTAssertTrue(itemIDs.contains(item), "\(cast.character) \(name) \(item)") }
            }
        }
        // Lv1이어도 1% 이상이면 뽑을 자세가 있다(빈 풀이면 0% 자세로 떨어져 엉뚱해진다).
        for cast in casts {
            let set = try XCTUnwrap(cast.poseSet)
            for step in steps where step > 0 {
                XCTAssertTrue(set.poses.keys.contains { set.allows($0, step: step, unlockedLevel: 1) }, "\(cast.character) \(step)")
            }
        }
    }

    /// 카인 시나몬 스틱(대표님 2026-10-27 "뒤에거는 안움직이게"): 날아오를 때 몸과 앞 스틱만 들리고 뒤 스틱·전체 자리는 그대로.
    func testCinnamonLiftsOnlyFrontStick() throws {
        let set = try XCTUnwrap(IdleCast.kain.poseSet)
        for name in ["cinnamon-stick-left", "cinnamon-stick-right"] {
            let spec = try XCTUnwrap(set.poses[name])
            for t in stride(from: 0.0, to: 8.0, by: 0.1) {
                let m = IdleMotion.frame(spec, cast: .kain, t: t, photo: photo, walkBaseX: 200)
                XCTAssertEqual(m.dy, 0, "\(name) \(t)")
                XCTAssertEqual(m.rot, 0, "\(name) \(t)")
                XCTAssertEqual(m.shift["foot_stick_back"] ?? .zero, .zero, "\(name) \(t)")
                XCTAssertEqual(Double(m.shift["foot_stick_front"]?.dy ?? 0), m.bodyDy, accuracy: 1e-9, "\(name) \(t)")
            }
            let up = IdleMotion.frame(spec, cast: .kain, t: 3.7, photo: photo, walkBaseX: 200)
            XCTAssertLessThan(up.bodyDy, -1, name)
        }
    }

    /// 바꿔 끼우는 조각(2026-10-06): 카인 졸기는 고개가 반 넘게 떨어지면 감은 눈, 번쩍 뒤엔 반 감은 눈.
    func testDozeSwapsToClosedEyes() throws {
        let set = try XCTUnwrap(IdleCast.kain.poseSet)
        let spec = try XCTUnwrap(set.poses["doze-one-leg"])
        let at = { (t: Double) in IdleMotion.frame(spec, cast: .kain, t: t, photo: self.photo, walkBaseX: 200) }
        XCTAssertFalse(at(0.5).shows("eye_closed"))
        XCTAssertTrue(at(2.5).shows("eye_closed"))
        XCTAssertFalse(at(3.3).shows("eye_closed"))
        XCTAssertFalse(at(5.0).shows("eye_closed"))
    }

    /// 카인 헤엄 한 바퀴(2026-10-06): 그림 가운데를 축으로 360도 돌고, 주기 끝과 처음의 각도가 같아 이음매가 없다.
    /// 각설탕(대표님 2026-10-27 "계산으로 보이는 면적이랑 각도 조정"): 쉴 땐 원화 그대로, 기울면 앞 아래 꼭짓점은 바닥에 남고
    /// 딛는 모서리 쪽 옆면이 좁아지고 윗면이 넓어진다. 보이는 면은 세 장 그대로(흔들흔들 범위).
    /// 잔 뒤에서 삐져 있기(대표님 2026-10-27): 정면 서 있는 그림을 작게, 잔 뒤 오른쪽 가장자리에. 처음 뽑을 때만 나오도록
    /// `awayPoses`로 묶이고, 다른 대기 자세보다 작으며, 반투명 대신 벽 색을 덮는다(투명도 1 그대로).
    func testSulkBackStandsSmallBehindCup() throws {
        let set = try XCTUnwrap(IdleCast.roshu.poseSet)
        XCTAssertEqual(set.awayPoses, ["sulk-back"])
        XCTAssertEqual(try XCTUnwrap(IdleCast.kain.poseSet).awayPoses, [])
        let spec = try XCTUnwrap(set.poses["sulk-back"])
        XCTAssertEqual(spec.rule.art, "stand")
        XCTAssertEqual(spec.rule.opacity, 1)
        let away = try XCTUnwrap(spec.rule.away)
        XCTAssertGreaterThan(away.fade, 0)
        XCTAssertLessThan(away.fade, 1)
        XCTAssertTrue(set.allows("sulk-back", step: 50, unlockedLevel: 1))
        XCTAssertTrue(IdleOnlooker.hostAvoids(guest: .caffeine).contains("sulk-back"), "가장자리 카인과 겹친다")
        let sulk = try XCTUnwrap(IdleSprite(side: .sugar, pose: "sulk-back", step: 50, size: slot))
        let walk = try XCTUnwrap(IdleSprite(side: .sugar, pose: "walk", step: 50, size: slot))
        let sulkHeight = Double(sulk.art.bbox.height) * sulk.scale
        let walkHeight = Double(walk.art.bbox.height) * walk.scale
        XCTAssertEqual(sulkHeight / walkHeight, away.scale, accuracy: 1e-6)
        XCTAssertLessThan(Double(sulk.base.y), Double(walk.base.y), "잔 앞 바닥보다 뒤(위)에 선다")
        // 뒤 물러난 자세를 빼고 뽑으면 절대 안 나온다(앱을 쓰는 도중 다시 뽑기).
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let pose = set.pick(
                step: 50, unlockedLevel: 10, items: ["strawberry", "sugar-cube"], avoiding: set.awayPoses,
                using: &generator
            )
            XCTAssertNotEqual(pose, "sulk-back")
        }
    }

    func testSugarCubeTiltsByComputation() throws {
        let art = try XCTUnwrap(IdleRig.arts["roshu"]?["sugar-cube"])
        let cube = try XCTUnwrap(art.cube)
        XCTAssertEqual(Set(cube.faces.map(\.name)), Set(art.parts.filter(\.isCube).map(\.name)))
        XCTAssertFalse(art.parts.contains { $0.isCube && ($0.isBack || $0.isFoot) }, "각설탕 면은 팔다리가 아니다")
        let rest = IdleCubeMath.pose(cube, degrees: 0, scale: 0.05)
        XCTAssertEqual(rest.faces.count, 3)
        for face in rest.faces {
            XCTAssertTrue(face.transform.isIdentityish, face.face.name)
            XCTAssertEqual(face.shade, 1, accuracy: 1e-9)
        }
        XCTAssertTrue(rest.rider.isIdentityish)
        func area(_ pose: IdleCubeMath.Pose, _ name: String) throws -> Double {
            let t = try XCTUnwrap(pose.faces.first { $0.face.name == name }).transform
            return abs(Double(t.a * t.d - t.b * t.c))
        }
        for degrees in [5.0, -5.0] {
            let tilted = IdleCubeMath.pose(cube, degrees: degrees, scale: 0.05)
            XCTAssertEqual(tilted.faces.count, 3, "\(degrees)")
            let corner = IdleCubeMath.project(cube, .zero, scale: 0.05)
            let moved = corner.applying(try XCTUnwrap(tilted.faces.first { $0.face.name == "cube_right" }).transform)
            XCTAssertEqual(moved.x, corner.x, accuracy: 1e-6, "앞 아래 꼭짓점은 바닥에 그대로")
            XCTAssertEqual(moved.y, corner.y, accuracy: 1e-6)
            XCTAssertGreaterThan(try area(tilted, "cube_top"), 1)
            XCTAssertLessThan(try area(tilted, degrees > 0 ? "cube_left" : "cube_right"), 1)
            XCTAssertEqual(try area(tilted, degrees > 0 ? "cube_right" : "cube_left"), 1, accuracy: 1e-9)
            XCTAssertFalse(tilted.rider.isIdentityish)
        }
    }

    func testSwimSpinsFullTurnSeamlessly() throws {
        let set = try XCTUnwrap(IdleCast.kain.poseSet)
        let spec = try XCTUnwrap(set.poses["swim"])
        XCTAssertEqual(spec.pivot, .center)
        guard case .channels(let channels) = spec.motion else { return XCTFail("swim motion") }
        let spin = try XCTUnwrap(channels.first { if case .spin = $0.shape { true } else { false } })
        guard case let .spin(period, at, length) = spin.shape else { return XCTFail("spin") }
        XCTAssertEqual(abs(spin.amp), 360)
        XCTAssertEqual(spin.value(at: at - 0.01), 0)
        XCTAssertEqual(spin.value(at: at + length / 2), spin.amp / 2, accuracy: 1e-9)
        XCTAssertEqual(spin.value(at: period - 0.001), spin.amp)
        XCTAssertEqual(spin.value(at: period), 0)
    }

    /// 기포: 같은 시각이면 같은 값(순수 함수), 헤엄에만 나오고, 몇 개 안 되며 화면 안 유한한 값.
    func testBubblesArePureAndSparse() throws {
        let cast = IdleCast.kain
        let set = try XCTUnwrap(cast.poseSet)
        let scale = photo.height * cast.scalePerPhotoHeight
        let base = CGPoint(x: 180, y: 500)
        let pivot = CGPoint(x: 40, y: 40)
        for (name, spec) in set.poses {
            var seen = 0
            for i in 0..<300 {
                let t = Double(i) * 0.053
                let a = IdleMotion.bubbles(spec, cast: cast, t: t, photo: photo, base: base, pivot: pivot, scale: scale)
                let b = IdleMotion.bubbles(spec, cast: cast, t: t, photo: photo, base: base, pivot: pivot, scale: scale)
                XCTAssertEqual(a, b, "\(name) t=\(t)")
                XCTAssertLessThanOrEqual(a.count, 6, "\(name) t=\(t)")
                for bubble in a {
                    XCTAssertTrue(bubble.center.x.isFinite && bubble.center.y.isFinite && bubble.radius > 0, name)
                    XCTAssertTrue((0...1).contains(bubble.alpha), name)
                }
                seen += a.count
            }
            XCTAssertEqual(seen > 0, ["swim", "swim-front"].contains(name), name)
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
                // 잔 뒤 물러난 자세는 누를 수 없다(대표님 2026-10-27 "건드려지지도 않게").
                XCTAssertEqual(sprite.contains(onBody, t: 0), sprite.rule.away == nil, "\(side) \(name)")
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

private extension CGAffineTransform {
    var isIdentityish: Bool {
        abs(a - 1) < 1e-9 && abs(b) < 1e-9 && abs(c) < 1e-9 && abs(d - 1) < 1e-9 && abs(tx) < 1e-6 && abs(ty) < 1e-6
    }
}
