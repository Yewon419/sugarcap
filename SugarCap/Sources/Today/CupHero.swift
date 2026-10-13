import SwiftUI

/// 오늘 화면 큰 숫자(2026-10-13 대표님 시안). 잔 입구에 걸쳐 두고, 입구 아래로 들어간 부분은 오린 잔(`cutout-*`)
/// 모양만큼 지워 잔 뒤에 있는 것처럼 보이게 한다. 잔 그림을 위에 덮지 않아 얼음 루프(`CupIdleOverlay`)는 그대로 움직인다.
/// 사진 칸(`CupView`) 안에서 사진과 캐릭터 사이에 그린다. 보이스오버·누르기는 `TodayView`의 숫자 요소가 맡는다.
struct CupHero: View {
    let side: CupSide
    let remaining: Double
    let limit: Double
    let overflow: Double
    /// 켜진 면 숫자 중 가장 넓은 글자. 두 면 숫자 크기를 맞춘다.
    let widest: String
    let cutout: String
    /// 라벨 위끝 ~ 숫자 바닥(입구 위로 보이는 부분)의 화면 자리. 숫자를 누르면 하루 기록이 열린다(`TodayView.tapCup`).
    var onFrame: (CGRect) -> Void = { _ in }

    static let fontName = "Anton-Regular"
    /// 잔 입구 높이(사진 비율). 오린 잔 10장 모두 위끝이 0.254~0.261이다.
    static let rim = 0.257
    /// Anton 글자 비율(unitsPerEm 2048): 숫자 폭 1012, 쉼표 484, 대문자 높이 1760, 위 여백(hhea ascent) 2409.
    static let digitAdvance = 1012.0 / 2048
    static let commaAdvance = 484.0 / 2048
    static let capRatio = 1760.0 / 2048
    static let ascentRatio = 2409.0 / 2048
    /// 숫자 바닥이 입구 아래로 들어가는 깊이(대문자 높이 대비, 시안).
    static let sink = 0.16
    /// 단위·기준이 숫자 바닥보다 올라간 높이(대문자 높이 대비, 시안). 입구 위에 있어야 잔에 안 가린다.
    static let unitRise = 0.36
    /// 라벨 바닥과 숫자 머리 사이.
    static let labelGap = 4.0

    /// 당 = 시안 회청색, 카페인 = 진갈색(대표님 2026-10-13).
    static func color(_ side: CupSide) -> Color {
        switch side {
        case .sugar: Color(red: 0x69 / 255, green: 0x83 / 255, blue: 0x94 / 255)
        case .caffeine: Color(red: 0x4A / 255, green: 0x32 / 255, blue: 0x26 / 255)
        }
    }

    /// 숫자 크기(pt). 두 자리 "50"이 화면 폭의 약 32%. 자리가 늘면 숫자 폭이 화면 폭 42%를 넘지 않게 줄인다.
    /// 처음엔 시안대로 45%였는데 대표님이 "숫자 너무 큰데"(2026-10-13)라고 해서 줄였다.
    static func size(width: Double, widest: String) -> Double {
        let ems: Double = widest.reduce(0) { $0 + ($1.isNumber ? digitAdvance : commaAdvance) }
        let base: Double = width * 0.32
        guard ems > 0 else { return base }
        return min(base, width * 0.42 / ems)
    }

    // 정렬 가이드(`alignmentGuide(.top) { $0[.lastTextBaseline] }`)는 ZStack 안에서 먹지 않아 숫자 윗변이 입구에 놓였다
    // (2026-10-13 CI, 숫자가 화면 가운데를 덮어 컵 누르기가 하루 기록으로 감). 자리는 글자 비율로 직접 계산한다.
    var body: some View {
        GeometryReader { proxy in
            let photo = IdlePhoto(slot: proxy.size)
            let size = Self.size(width: Double(proxy.size.width), widest: widest)
            let cap: Double = size * Self.capRatio
            let baseline: Double = photo.top + Self.rim * photo.height + Self.sink * cap
            let capTop: Double = baseline - cap
            let rowTop: Double = baseline - Self.ascentRatio * size
            ZStack(alignment: .topLeading) {
                Color.clear
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: max(capTop - Self.labelGap, 0), alignment: .bottomLeading)
                    .padding(.leading, 24)
                numberRow(size: size, cap: cap)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { row in
                        let top: Double = row.minY + (Self.ascentRatio - Self.capRatio) * size - Self.labelGap - 20
                        let bottom: Double = row.minY + Self.ascentRatio * size
                        onFrame(CGRect(x: row.minX, y: top, width: row.width, height: bottom - top))
                    }
                    .offset(x: 24, y: rowTop)
            }
        }
        .mask {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                context.blendMode = .destinationOut
                context.draw(Image(cutout), in: IdlePhoto(slot: size).rect)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// "오늘 남은 당" (+ 넘긴 양). 숫자 머리 바로 위에 붙는다.
    private var label: some View {
        HStack(spacing: 8) {
            Text("오늘 남은 \(side.label)")
                .font(.system(.caption2, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Self.color(side))
            if overflow > 0 {
                Text("+\(Amount.number(overflow)) \(side.unit) 넘김")
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 숫자 + 올라간 단위·기준. 행 위끝 = Anton 위 여백 위끝(바닥에서 `ascentRatio × size`).
    private func numberRow(size: Double, cap: Double) -> some View {
        let tint = Self.color(side)
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(Amount.number(remaining))
                .font(.custom(Self.fontName, fixedSize: size))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(side.unit)
                    .font(.custom(Self.fontName, fixedSize: size * 0.3))
                    .foregroundStyle(tint)
                Text("/\(Amount.number(limit)) \(side.unit)")
                    .font(.footnote)
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            .padding(.leading, 6)
            .alignmentGuide(.lastTextBaseline) { $0[.lastTextBaseline] + Self.unitRise * cap }
        }
        .fixedSize()
        .animation(.spring(response: 0.4), value: remaining)
    }
}
