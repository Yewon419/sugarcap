import SwiftUI

/// 홈 화면 위젯 잔(SPEC §4.6, 시안 `design/proto/widget.html` v7 대표님 2026-11-07 확정).
/// 잔을 남은 수면 쪽으로 바짝 당긴 사진(`Widget.xcassets`, `make_widget_crops.py`) 위에 남은 양을 Anton 큰 숫자로 얹는다.
/// 숫자는 음료·유리보다 앞 레이어, 잔 가운데 아래. 단위는 숫자 오른쪽 위에 매달려 가운데 맞춤에서 빠진다. 라벨은 없다.
/// 위젯 확장과 앱(Debug 위젯 스크린샷 `-screenshotWidget`)이 함께 컴파일한다.
enum WidgetCupFamily: String, Sendable {
    /// Small 한 잔.
    case small
    /// Medium 두 잔 중 한 칸. 이음새를 섞으려고 가운데 쪽으로 `seam`만큼 더 넓다.
    case half
    /// Medium 한 면만 켠 사용자(잔 왼쪽, "하루 기준" 오른쪽 아래).
    case wide

    /// 기준 칸(pt, 6.1인치 아이폰). `make_widget_crops.py`의 Family와 같아야 한다.
    var referenceSize: CGSize {
        switch self {
        case .small: CGSize(width: 158, height: 158)
        case .half: CGSize(width: 169 + Self.seam, height: 158)
        case .wide: CGSize(width: 338, height: 158)
        }
    }

    /// 잔 가운데(숫자 가운데)가 칸 왼쪽에서 몇 pt인지. Medium 두 잔은 당이 왼쪽, 카페인이 오른쪽 칸이다.
    func axis(_ side: CupSide) -> Double {
        switch self {
        case .small: 79
        case .half: side == .sugar ? 84.5 : Self.seam + 84.5
        case .wide: 0.35 * 338
        }
    }

    var numberSize: Double {
        switch self {
        case .small, .half: 52
        case .wide: 60
        }
    }

    /// Medium 두 칸이 겹쳐 섞이는 폭의 절반. 두 잔 사진의 벽 톤이 달라 맞대면 세로 줄이 보였다(시안 v1).
    static let seam = 12.0

    func imageName(setID: String, step: Int) -> String {
        "widget-\(rawValue)-\(setID)-\(step)"
    }

    func hasPhoto(_ name: String) -> Bool {
        switch self {
        case .half: WidgetCupCrops.halfCropY[name] != nil
        case .small, .wide: WidgetCupCrops.numberBottom[name] != nil
        }
    }
}

/// 잔마다 숫자 색(시안 v6 대표님 "당도 무조건 파랑 하지 말고 음료별로"). 밝은 음료는 그 음료의 진한 색,
/// 진한 음료는 그 음료의 밝은 색(크림·우유). `zero` = 빈 잔(0%)일 때 흰 배경 위 색. `steps`는 그 단계만 다른 색.
struct WidgetCupInk: Sendable {
    let ink: UInt32
    let zero: UInt32
    var steps: [Int: UInt32] = [:]

    func color(step: Int) -> Color {
        Self.color(hex(step: step))
    }

    /// 숫자 외곽선 색: 숫자 색의 반대. 밝은 숫자는 그 잔의 빈 잔 색, 진한 숫자는 흰색(대표님 2026-11-09).
    func outline(step: Int) -> Color {
        let hex = hex(step: step)
        let luminance: Double = 0.2126 * Double((hex >> 16) & 0xFF) + 0.7152 * Double((hex >> 8) & 0xFF)
            + 0.0722 * Double(hex & 0xFF)
        return Self.color(luminance / 255 > 0.5 ? zero : 0xFFFFFF)
    }

    private func hex(step: Int) -> UInt32 {
        step == 0 ? zero : (steps[step] ?? ink)
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func of(_ setID: String) -> WidgetCupInk {
        table[setID] ?? WidgetCupInk(ink: 0x1D1D1F, zero: 0x1D1D1F)
    }

    private static let table: [String: WidgetCupInk] = [
        "strawberry-latte": WidgetCupInk(ink: 0xB8394A, zero: 0xB8394A),
        "iced-americano": WidgetCupInk(ink: 0xFFFFFF, zero: 0x4A3226),
        "cafe-latte": WidgetCupInk(ink: 0x5A3B26, zero: 0x5A3B26),
        "choco-frappe": WidgetCupInk(ink: 0xFFF4E8, zero: 0x4B2A1D),
        // 말차 30%는 숫자 자리가 아래 우유 층이라 진한 초록.
        "matcha": WidgetCupInk(ink: 0xFBFAF2, zero: 0x2F5A2B, steps: [30: 0x1F3F1D]),
        "mango": WidgetCupInk(ink: 0xC0561B, zero: 0xC0561B),
        "einspanner": WidgetCupInk(ink: 0xFFF6E6, zero: 0x4A3226),
        "grape": WidgetCupInk(ink: 0x3E6A1C, zero: 0x3E6A1C),
        // 대표님 2026-11-07 "유리과일 글자색 흰색 해봐"로 흰색 확정.
        "glass-soda": WidgetCupInk(ink: 0xFFFFFF, zero: 0x2C6430),
        "glass-beans": WidgetCupInk(ink: 0xFFF1DC, zero: 0x5A3B26),
    ]
}

/// 위젯 칸 한 개에 그릴 잔 한 면.
struct WidgetCupModel: Equatable, Sendable {
    let side: CupSide
    let setID: String
    let remaining: Double
    let limit: Double

    var step: Int { CupLevel.step(remaining: remaining, limit: limit) }

    /// 이 잔의 위젯 사진이 없으면(위젯 사진을 아직 안 뽑은 새 잔) 기본 잔으로 그린다.
    func resolvedSetID(_ family: WidgetCupFamily) -> String {
        let name = family.imageName(setID: setID, step: step)
        return family.hasPhoto(name) ? setID : side.defaultCupSetID
    }

    /// Medium 두 잔 칸에서 이 잔을 혼자 그릴 때 칸 위끝(사진 단위).
    var halfCropY: Double {
        let name = WidgetCupFamily.half.imageName(setID: resolvedSetID(.half), step: step)
        return WidgetCupCrops.halfCropY[name] ?? WidgetCupCrops.halfTop
    }
}

/// 잔 사진 + 큰 숫자 한 칸. 기준 칸(`referenceSize`)을 `scale`배로 그린다.
/// `.half`는 두 잔 입구 높이를 맞추려고 두 칸이 같은 위끝(`cropY`, 사진 단위)으로 자른다.
struct WidgetCupArt: View {
    let family: WidgetCupFamily
    let cup: WidgetCupModel
    let scale: Double
    var cropY: Double = WidgetCupCrops.halfTop

    /// Anton 글자 비율(unitsPerEm 2048, `CupHero`와 같은 값): 위 여백 2409, 아래 여백 674.
    private static let ascentRatio = 2409.0 / 2048
    private static let descentRatio = 674.0 / 2048
    /// 시안은 줄 높이 1로 숫자 칸을 잡았다. 그 칸 아래 끝에서 글자 바닥선까지 = (1 - 위·아래 여백 합) / 2 + 아래 여백.
    private static let baselineLift = (1 - ascentRatio - descentRatio) / 2 + descentRatio
    private static let unitScale = 0.32
    /// 단위 칸 위끝이 숫자 칸 위끝보다 얼마나 아래인지(숫자 크기 비율, 시안 `sup { top: 0.08em }`을 옮긴 값).
    private static let unitDrop = 0.1975
    private static let unitGap = 0.02
    /// 두 잔 칸 숫자 외곽선 두께(기준 칸 pt).
    private static let outlineWidth = 1.5

    var body: some View {
        let setID = cup.resolvedSetID(family)
        let step = cup.step
        let name = family.imageName(setID: setID, step: step)
        let width: Double = family.referenceSize.width * scale
        let height: Double = family.referenceSize.height * scale
        let size: Double = family.numberSize * scale
        let photo = photoPlacement(setID: setID, name: name)
        let bottom: Double = photo.numberBottom * scale
        let baseline: Double = height - bottom - Self.baselineLift * size
        let top: Double = baseline - Self.ascentRatio * size
        let ink = WidgetCupInk.of(setID)
        let x: Double = family.axis(cup.side) * scale - 0.5
        ZStack(alignment: .topLeading) {
            Image(name)
                .resizable()
                .frame(width: width, height: photo.height * scale)
                .offset(y: photo.offset * scale)
            // 두 잔 칸은 덜 찬 잔에 맞춰 내려 자르니 숫자 뒤에 잔 바닥 건더기·우유 층이 들어온다.
            // 숫자를 8방향으로 밀어 그린 외곽선을 뒤에 깐다(대표님 2026-11-09, 그림자를 겹치면 두께가 누적된다).
            if family == .half {
                ForEach(0..<8, id: \.self) { index in
                    let angle: Double = Double(index) * Double.pi / 4
                    let radius: Double = Self.outlineWidth * scale
                    number(size: size, color: ink.outline(step: step))
                        .offset(x: x + radius * cos(angle), y: top + radius * sin(angle))
                }
            }
            number(size: size, color: ink.color(step: step))
                .offset(x: x, y: top)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("남은 \(cup.side.label) \(Amount.number(cup.remaining)) \(cup.side.unit)"))
    }

    /// 숫자 + 오른쪽 위 단위. 폭 1pt 칸 가운데에 두면 글자 폭과 상관없이 숫자 가운데가 잔 축에 온다.
    private func number(size: Double, color: Color) -> some View {
        Text(Amount.number(cup.remaining))
            .font(.custom("Anton-Regular", fixedSize: size))
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .overlay(alignment: .topTrailing) {
                Text(cup.side.unit)
                    .font(.custom("Anton-Regular", fixedSize: size * Self.unitScale))
                    .foregroundStyle(color)
                    .fixedSize()
                    .alignmentGuide(.trailing) { $0[.leading] - Self.unitGap * size }
                    .offset(y: Self.unitDrop * size)
            }
            .fixedSize()
            .frame(width: 1)
    }

    /// 사진 높이·세로 밀기와 숫자 줄 아래 끝(전부 기준 칸 pt).
    private func photoPlacement(setID: String, name: String) -> (height: Double, offset: Double, numberBottom: Double) {
        let cell: Double = family.referenceSize.height
        guard family == .half else {
            return (cell, 0, (WidgetCupCrops.numberBottom[name] ?? 0.0253) * cell)
        }
        let k: Double = WidgetCupCrops.halfPointsPerUnit
        let photoHeight: Double = WidgetCupCrops.photoHeight
        let glass: Double = (WidgetCupCrops.glassBottom[setID] ?? 0.876) * photoHeight
        // 숫자는 잔 안에 선다: 잔 바닥이 칸 안으로 올라오면 숫자 아래 끝을 바닥 위 6pt로, 아니면 아래 4pt.
        let glassBottom: Double = (glass - cropY) * k
        let numberBottom: Double = max(4, cell - glassBottom + 6)
        return ((photoHeight - WidgetCupCrops.halfTop) * k, -(cropY - WidgetCupCrops.halfTop) * k, numberBottom)
    }
}

/// Small: 한 잔.
struct WidgetSmallFace: View {
    let cup: WidgetCupModel

    var body: some View {
        GeometryReader { proxy in
            let scale: Double = max(proxy.size.width, proxy.size.height) / WidgetCupFamily.small.referenceSize.width
            WidgetCupArt(family: .small, cup: cup, scale: scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
    }
}

/// Medium: 켠 면이 둘이면 당·카페인 잔 나란히, 하나면 그 잔 + "하루 기준".
struct WidgetMediumFace: View {
    let cups: [WidgetCupModel]

    var body: some View {
        GeometryReader { proxy in
            if cups.count >= 2 {
                pair(cups[0], cups[1], size: proxy.size)
            } else if let cup = cups.first {
                single(cup, size: proxy.size)
            }
        }
        .clipped()
    }

    private func pair(_ left: WidgetCupModel, _ right: WidgetCupModel, size: CGSize) -> some View {
        let half = WidgetCupFamily.half.referenceSize
        let scale: Double = max(size.height / half.height, size.width / 2 / (half.width - WidgetCupFamily.seam))
        let width: Double = half.width * scale
        let fade: Double = 2 * WidgetCupFamily.seam * scale
        // 두 잔 입구 높이를 맞춘다(대표님 2026-11-09): 덜 찬 잔(위끝이 더 아래)에 맞춰 같은 위끝으로 자른다.
        let cropY: Double = max(left.halfCropY, right.halfCropY)
        return ZStack(alignment: .leading) {
            WidgetCupArt(family: .half, cup: left, scale: scale, cropY: cropY)
            // 오른쪽 칸 왼쪽 날개를 투명 → 불투명으로 덮어 두 사진 벽 톤을 녹인다(오늘 화면 `CupView.seam`과 같은 방식).
            WidgetCupArt(family: .half, cup: right, scale: scale, cropY: cropY)
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: fade)
                        Color.black
                    }
                }
                .offset(x: size.width - width)
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
    }

    private func single(_ cup: WidgetCupModel, size: CGSize) -> some View {
        let wide = WidgetCupFamily.wide.referenceSize
        let scale: Double = max(size.height / wide.height, size.width / wide.width)
        return ZStack(alignment: .bottomTrailing) {
            WidgetCupArt(family: .wide, cup: cup, scale: scale)
                .frame(width: size.width, height: size.height)
            Text("하루 기준 \(Amount.number(cup.limit)) \(cup.side.unit)")
                .font(.custom("Pretendard-SemiBold", fixedSize: 10 * scale))
                .foregroundStyle(Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255).opacity(0.5))
                .padding(.trailing, 16 * scale)
                .padding(.bottom, 14 * scale)
        }
    }
}
