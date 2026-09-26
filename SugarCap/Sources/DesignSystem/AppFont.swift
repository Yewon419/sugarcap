import SwiftUI

/// 앱 글꼴(2026-09-26 대표님 결정: Pretendard 번들). HTML 프로토타입에서 확정한 모양이 Pretendard라서 그대로 옮긴다.
/// 큰 숫자 일부(온보딩 릴·하루 기준 컵 숫자)는 Archivo Black. 둘 다 SIL OFL, 라이선스는 `Resources/Fonts`.
/// 등록은 Info.plist `UIAppFonts`(project.yml). 이름은 PostScript 이름이다.
enum AppFont {
    enum Weight: Sendable {
        case regular, medium, semibold, bold, extraBold, black

        var postScriptName: String {
            switch self {
            case .regular: return "Pretendard-Regular"
            case .medium: return "Pretendard-Medium"
            case .semibold: return "Pretendard-SemiBold"
            case .bold: return "Pretendard-Bold"
            case .extraBold: return "Pretendard-ExtraBold"
            case .black: return "Pretendard-Black"
            }
        }
    }

    static let numeralName = "ArchivoBlack-Regular"

    /// 큰 글자 설정을 따라 커지는 본문·제목용. `style`은 커지는 비율의 기준이다.
    static func pretendard(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: style)
    }

    /// 크기가 고정인 글자. 모션그래픽 무대처럼 배치가 픽셀로 짜인 곳에만 쓴다.
    static func pretendardFixed(_ size: CGFloat, _ weight: Weight) -> Font {
        .custom(weight.postScriptName, fixedSize: size)
    }

    static func numeral(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(numeralName, size: size, relativeTo: style)
    }

    static func numeralFixed(_ size: CGFloat) -> Font {
        .custom(numeralName, fixedSize: size)
    }

    /// 큰 한글 제목의 자간 하한(대표님 교정 2026-09-26): −0.02em보다 좁히면 받침·느낌표가 붙는다.
    static func displayTracking(for size: CGFloat) -> CGFloat {
        -0.02 * size
    }
}
