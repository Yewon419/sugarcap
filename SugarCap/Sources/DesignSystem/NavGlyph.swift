import SwiftUI

/// 오늘 화면 모서리 버튼 전용 아이콘(2026-10-05 프로토 `TAB_ICON`). 슈가캡 잔 한 계열:
/// 24 격자, 선 1.6, 둥근 끝, 음료는 늘 채운다. 색은 바깥 `foregroundStyle`을 따른다.
enum NavGlyph {
    /// 식탁 위 잔 셋, 음료가 왼쪽부터 줄어든다.
    case trends
    /// 잔을 가로지르는 기준선과 손잡이.
    case settings
    /// 다섯 갈래 별 윤곽. 무료일 때만 보이는 Pro 버튼(2026-10-13 대표님).
    case pro
    /// 쿠폰 한 장(양옆 홈)에 도장 칸 둘, 앞 칸은 찍혀 채워졌다. 2주 스탬프판(2026-11-05).
    case stamp
}

struct NavGlyphView: View {
    let glyph: NavGlyph
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, canvasSize in
            context.scaleBy(x: canvasSize.width / 24, y: canvasSize.height / 24)
            let line = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            switch glyph {
            case .trends:
                for (x, top) in [(1.8, 10.0), (9.7, 13.5), (17.6, 17.0)] {
                    context.stroke(Self.trendGlass(x: x), with: .foreground, style: line)
                    context.fill(Self.trendLiquid(x: x, top: top), with: .foreground)
                }
                context.stroke(Path { $0.move(to: CGPoint(x: 1, y: 21.5)); $0.addLine(to: CGPoint(x: 23, y: 21.5)) }, with: .foreground, style: line)
            case .settings:
                context.stroke(Self.settingsGlass, with: .foreground, style: line)
                context.stroke(Path { $0.move(to: CGPoint(x: 2.5, y: 10.5)); $0.addLine(to: CGPoint(x: 16, y: 10.5)) }, with: .foreground, style: line)
                context.fill(Path(ellipseIn: CGRect(x: 16.5, y: 8, width: 5, height: 5)), with: .foreground)
            case .pro:
                context.stroke(Self.star, with: .foreground, style: line)
            case .stamp:
                context.stroke(Self.coupon, with: .foreground, style: line)
                context.fill(Path(ellipseIn: CGRect(x: 6, y: 9.5, width: 5, height: 5)), with: .foreground)
                context.stroke(Path(ellipseIn: CGRect(x: 13, y: 9.5, width: 5, height: 5)), with: .foreground, style: line)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static func trendGlass(x: Double) -> Path {
        Path { path in
            path.move(to: CGPoint(x: x, y: 7.5))
            path.addLine(to: CGPoint(x: x + 4.6, y: 7.5))
            path.addLine(to: CGPoint(x: x + 4.1, y: 19))
            path.addLine(to: CGPoint(x: x + 0.5, y: 19))
            path.closeSubpath()
        }
    }

    private static func trendLiquid(x: Double, top: Double) -> Path {
        Path { path in
            path.move(to: CGPoint(x: x + 0.55, y: top))
            path.addLine(to: CGPoint(x: x + 4.05, y: top))
            path.addLine(to: CGPoint(x: x + 3.7, y: 19))
            path.addLine(to: CGPoint(x: x + 0.9, y: 19))
            path.closeSubpath()
        }
    }

    /// 바깥 꼭짓점 반지름 9.6, 안쪽 4.1. 무게중심을 맞추려 가운데를 조금 내렸다.
    private static let star = Path { path in
        for index in 0 ..< 10 {
            let radius: Double = index % 2 == 0 ? 9.6 : 4.1
            let angle: Double = -Double.pi / 2 + Double(index) * Double.pi / 5
            let point = CGPoint(x: 12 + radius * cos(angle), y: 12.8 + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
    }

    /// 가로 20 × 세로 14 쿠폰. 양옆 가운데를 반지름 2 반원으로 파냈다.
    private static let coupon = Path { path in
        path.move(to: CGPoint(x: 4.5, y: 5))
        path.addLine(to: CGPoint(x: 19.5, y: 5))
        path.addQuadCurve(to: CGPoint(x: 22, y: 7.5), control: CGPoint(x: 22, y: 5))
        path.addLine(to: CGPoint(x: 22, y: 10))
        path.addCurve(to: CGPoint(x: 22, y: 14), control1: CGPoint(x: 19.33, y: 10), control2: CGPoint(x: 19.33, y: 14))
        path.addLine(to: CGPoint(x: 22, y: 16.5))
        path.addQuadCurve(to: CGPoint(x: 19.5, y: 19), control: CGPoint(x: 22, y: 19))
        path.addLine(to: CGPoint(x: 4.5, y: 19))
        path.addQuadCurve(to: CGPoint(x: 2, y: 16.5), control: CGPoint(x: 2, y: 19))
        path.addLine(to: CGPoint(x: 2, y: 14))
        path.addCurve(to: CGPoint(x: 2, y: 10), control1: CGPoint(x: 4.67, y: 14), control2: CGPoint(x: 4.67, y: 10))
        path.addLine(to: CGPoint(x: 2, y: 7.5))
        path.addQuadCurve(to: CGPoint(x: 4.5, y: 5), control: CGPoint(x: 2, y: 5))
        path.closeSubpath()
    }

    /// 아래 모서리는 프로토의 반지름 1.7 호를 2차 곡선으로 옮겼다.
    private static let settingsGlass = Path { path in
        path.move(to: CGPoint(x: 6.5, y: 3.5))
        path.addLine(to: CGPoint(x: 15.5, y: 3.5))
        path.addLine(to: CGPoint(x: 14.3, y: 19.9))
        path.addQuadCurve(to: CGPoint(x: 12.6, y: 21.5), control: CGPoint(x: 14.2, y: 21.5))
        path.addLine(to: CGPoint(x: 9.4, y: 21.5))
        path.addQuadCurve(to: CGPoint(x: 7.7, y: 19.9), control: CGPoint(x: 7.8, y: 21.5))
        path.closeSubpath()
    }
}
