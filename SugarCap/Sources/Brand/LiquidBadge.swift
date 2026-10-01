import SwiftUI

/// 메뉴 썸네일: 동그란 원 안에 물결 윗면의 액체(SPEC §9.7). 사진 대신 음료마다 색만 다르다.
/// 높이는 모두 같다(약 2/3). 목록은 정지, 메뉴 패널의 큰 원만 `isFlowing`으로 천천히 출렁인다.
/// 색은 단색 면만 쓴다(그라데이션·글로우 없음, 리포 CLAUDE.md 모션 규칙).
struct LiquidBadge: View {
    let color: Color
    var size: CGFloat = 44
    var isFlowing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 카탈로그에 색이 없을 때(원격 갱신이 옛 형식이거나 직접 입력 기록). `colors.py`의 DEFAULT와 같다.
    static let fallbackHex = "#D9C2A0"
    static let fallback = Color(liquidHex: fallbackHex) ?? .gray

    var body: some View {
        if isFlowing, !reduceMotion {
            TimelineView(.animation) { timeline in
                content(phase: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            content(phase: 0)
        }
    }

    private func content(phase time: Double) -> some View {
        // 앞 물결과 뒤 물결이 어긋나게 돈다. 한 바퀴 약 4초.
        let front = time * 1.6
        let back = time * 1.1 + 1.9
        return ZStack {
            Circle().fill(Color(.secondarySystemFill))
            LiquidWave(level: 0.62, amplitude: 0.045, phase: back)
                .fill(color.opacity(0.45))
            LiquidWave(level: 0.66, amplitude: 0.04, phase: front)
                .fill(color)
        }
        .clipShape(Circle())
        // 탄산수처럼 옅은 색도 원이 보이게 테두리를 늘 둔다.
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 사각형 아래쪽을 채우는 물결 면. `level`은 바닥에서 윗면까지 높이 비율, `amplitude`는 높이 대비 물결 높이.
struct LiquidWave: Shape {
    var level: Double
    var amplitude: Double
    var phase: Double

    func path(in rect: CGRect) -> Path {
        let surface: Double = rect.maxY - rect.height * level
        let height: Double = rect.height * amplitude
        // 원 지름 안에 물결이 한 번 반 들어간다.
        let wavelength: Double = rect.width / 1.5
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x: Double = rect.minX
        while x <= rect.maxX {
            let angle: Double = (x - rect.minX) / wavelength * 2 * Double.pi + phase
            let y: Double = surface + height * sin(angle)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 1
        }
        let endAngle: Double = rect.width / wavelength * 2 * Double.pi + phase
        path.addLine(to: CGPoint(x: rect.maxX, y: surface + height * sin(endAngle)))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension Color {
    /// "#RRGGBB". 형식이 틀리면 nil(카탈로그 검증 밖의 값이 와도 썸네일만 기본색으로 바뀐다).
    init?(liquidHex hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Drink {
    var liquid: Color {
        liquidColor.flatMap(Color.init(liquidHex:)) ?? LiquidBadge.fallback
    }
}
