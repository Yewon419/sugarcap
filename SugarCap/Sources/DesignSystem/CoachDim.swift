import SwiftUI

/// 튜토리얼 덮개(2026-10-27 첫 먹이기에서 시작, 2026-11-05 첫 기록 안내와 같이 쓴다). 화면을 낮추고 `holes`만 밝게 남긴다.
/// 구멍 가장자리는 부드럽게 번진다(베타 피드백 빌드 342 대표님 "누끼 따지 말고 가장자리만 부드럽게 어둡게",
/// "주변을 더 어둡게 해서 컵이랑 로슈만 밝게, 테두리 따지 마"). 에어브러시 금지 규칙보다 이 지시가 우선이다.
/// 누르기는 그대로 아래로 간다. 구멍 좌표는 이 뷰가 놓인 칸 기준이다.
struct CoachDim: View {
    struct Hole: Equatable {
        let rect: CGRect
        let radius: CGFloat
    }

    let holes: [Hole]

    private static let dim = 0.74
    /// 번지는 폭(pt). 번진 만큼 안쪽이 덜 밝아지지 않게 구멍을 그만큼 넓혀 뚫는다.
    private static let feather: CGFloat = 26

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(Self.dim)))
            context.blendMode = .destinationOut
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: Self.feather))
                for hole in holes {
                    let rect = hole.rect.insetBy(dx: -Self.feather * 0.5, dy: -Self.feather * 0.5)
                    let shape = RoundedRectangle(cornerRadius: hole.radius + Self.feather * 0.5, style: .continuous).path(in: rect)
                    layer.fill(shape, with: .color(.black))
                }
            }
        }
        .compositingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 컵 사진 속 잔 자리(화면 좌표). `CupView`와 같은 사진 틀(화면 높이 84%, 바닥에서 4% 띄움)에 잔 치수(`CupSetGeometry`)를 얹어 잰다.
    static func cupRect(screen: CGSize, side: CupSide, step: Int) -> CGRect {
        let slotHeight = screen.height * CupView.heightRatio
        let slotTop = screen.height * (1 - CupView.heightRatio - CupView.liftRatio)
        let photo = IdlePhoto(slot: CGSize(width: screen.width, height: slotHeight))
        let cast = side.idleCast
        let axis = cast.glassAxis(step: step)
        let top = photo.point(axis - 0.31, cast.rimLine(step: step).back - 0.03)
        let bottom = photo.point(axis + 0.31, cast.bottom + 0.025)
        return CGRect(x: top.x, y: slotTop + top.y, width: bottom.x - top.x, height: bottom.y - top.y)
    }
}
