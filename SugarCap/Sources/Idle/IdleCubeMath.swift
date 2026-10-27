import CoreGraphics
import Foundation
import simd

/// 소품 정육면체(로슈 각설탕)를 기울인 모습(대표님 2026-10-27 "계산으로 보이는 면적이랑 각도 조정", 흔들흔들만).
/// 3D로 돌린 정육면체를 같은 평행 투영으로 다시 비추므로 면마다 아핀 변환 하나로 정확히 옮겨진다.
/// 기울기 0이면 변환은 항등이라 원화 그대로다. 좌표는 그림 pt(캔버스 픽셀 × scale). 전부 순수 함수.
enum IdleCubeMath {
    struct FaceDraw {
        let face: IdleCube.Face
        /// 쉬는 자리의 면을 기운 자리로 옮기는 변환.
        let transform: CGAffineTransform
        /// 면 밝기 배율(기운 방향으로 다시 계산한 밝기 ÷ 원화 밝기).
        let shade: Double
    }

    struct Pose {
        /// 화면 쪽을 보는 면만, 뒤에서 앞 순서.
        let faces: [FaceDraw]
        /// 올라선 캐릭터를 옮기는 변환: 딛는 자리가 윗면을 따라가고, 기운 만큼에서 버티는 몫을 뺀 만큼 돈다.
        let rider: CGAffineTransform
    }

    /// 기울기(도). 양수면 앞 왼쪽 아래 모서리(x축)를, 음수면 앞 오른쪽 아래 모서리(z축)를 딛고 뒤가 들린다.
    /// 두 모서리 다 앞 아래 꼭짓점(origin)을 지나 그 꼭짓점은 바닥에 그대로 있다.
    static func rotation(degrees: Double) -> simd_quatd {
        let a = degrees * Double.pi / 180
        return a >= 0 ? simd_quatd(angle: -a, axis: SIMD3(1, 0, 0)) : simd_quatd(angle: -a, axis: SIMD3(0, 0, 1))
    }

    static func pose(_ cube: IdleCube, degrees: Double, scale: Double) -> Pose {
        let turn = rotation(degrees: degrees)
        let view = viewer(cube)
        let light = light(cube, view: view)
        let faces: [FaceDraw] = cube.faces.compactMap { face in
            let normal = turn.act(face.normal)
            guard simd_dot(normal, view) > 0 else { return nil }
            let rest = frame(cube, corner: face.corner, u: face.u, v: face.v, scale: scale)
            let moved = frame(
                cube, corner: turn.act(face.corner), u: turn.act(face.u), v: turn.act(face.v), scale: scale
            )
            return FaceDraw(
                face: face, transform: rest.inverted().concatenating(moved),
                shade: brightness(normal, light: light) / brightness(face.normal, light: light)
            )
        }
        let stand = SIMD3(cube.stand.x, 1, cube.stand.y)
        let from = project(cube, stand, scale: scale)
        let to = project(cube, turn.act(stand), scale: scale)
        let up0 = project(cube, SIMD3(0, 1, 0), scale: scale)
        let up1 = project(cube, turn.act(SIMD3(0, 1, 0)), scale: scale)
        let base = project(cube, .zero, scale: scale)
        let tilt =
            (atan2(up1.y - base.y, up1.x - base.x) - atan2(up0.y - base.y, up0.x - base.x)) * (1 - cube.lean)
        let rider = CGAffineTransform(translationX: -from.x, y: -from.y)
            .concatenating(CGAffineTransform(rotationAngle: tilt))
            .concatenating(CGAffineTransform(translationX: to.x, y: to.y))
        return Pose(faces: faces, rider: rider)
    }

    /// 정육면체 점 → 그림 pt.
    static func project(_ cube: IdleCube, _ p: SIMD3<Double>, scale: Double) -> CGPoint {
        CGPoint(
            x: (Double(cube.origin.x) + p.x * Double(cube.ex.dx) + p.y * Double(cube.ey.dx) + p.z * Double(cube.ez.dx)) * scale,
            y: (Double(cube.origin.y) + p.x * Double(cube.ex.dy) + p.y * Double(cube.ey.dy) + p.z * Double(cube.ez.dy)) * scale
        )
    }

    /// 면 좌표(u, v ∈ 0…1) → 그림 pt.
    private static func frame(
        _ cube: IdleCube, corner: SIMD3<Double>, u: SIMD3<Double>, v: SIMD3<Double>, scale: Double
    ) -> CGAffineTransform {
        let o = project(cube, corner, scale: scale)
        let pu = project(cube, corner + u, scale: scale)
        let pv = project(cube, corner + v, scale: scale)
        return CGAffineTransform(a: pu.x - o.x, b: pu.y - o.y, c: pv.x - o.x, d: pv.y - o.y, tx: o.x, ty: o.y)
    }

    /// 보는 사람 쪽 방향(정육면체 단위): 화면 한 점으로 겹치는 3D 방향, 윗면이 보이는 쪽.
    static func viewer(_ cube: IdleCube) -> SIMD3<Double> {
        let ey = cube.ey
        let ez = cube.ez
        let det = Double(ey.dx * ez.dy - ez.dx * ey.dy)
        guard abs(det) > 1e-9 else { return SIMD3(0, 1, 0) }
        // x = 1일 때 ex + y·ey + z·ez = 0을 푼다.
        let bx = -Double(cube.ex.dx)
        let by = -Double(cube.ex.dy)
        let y = (bx * Double(ez.dy) - Double(ez.dx) * by) / det
        let z = (Double(ey.dx) * by - bx * Double(ey.dy)) / det
        let view = simd_normalize(SIMD3(1, y, z))
        return view.y < 0 ? -view : view
    }

    /// 빛은 왼쪽 앞 위(그림자 규칙과 같다).
    private static func light(_ cube: IdleCube, view: SIMD3<Double>) -> SIMD3<Double> {
        let left = simd_normalize(SIMD3(cube.ex.dx < 0 ? 1.0 : -1.0, 0, cube.ez.dx > 0 ? -1.0 : 1.0))
        return simd_normalize(view + 0.6 * left + SIMD3(0, 1.2, 0))
    }

    private static func brightness(_ normal: SIMD3<Double>, light: SIMD3<Double>) -> Double {
        0.62 + 0.38 * max(0, simd_dot(normal, light))
    }
}
