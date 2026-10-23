import SwiftUI

/// 오늘 화면 큰 숫자(2026-10-13 대표님 시안). 바닥을 잔 앞쪽 입구 선에 맞춰 잔 뒤에 세운다. 숫자는 유리 너머로 그대로
/// 비치고 유리 선(입구 앞·뒤 호, 벽, `rimline-*`)만 숫자를 끊는다(대표님 "컵 경계만 지워져 있거든"). 처음엔 오린 잔
/// 모양 전체로 지웠다. 잔 그림을 위에 덮지 않아 얼음 루프(`CupIdleOverlay`)는 그대로 움직인다.
/// 사진 칸(`CupView`) 안에서 사진과 캐릭터 사이에 그린다. 보이스오버·누르기는 `TodayView`의 숫자 요소가 맡는다.
struct CupHero: View {
    let side: CupSide
    let remaining: Double
    let limit: Double
    let overflow: Double
    /// 켜진 면 숫자 중 가장 넓은 글자. 두 면 숫자 크기를 맞춘다.
    let widest: String
    let rimLine: String
    /// 라벨 바로 위에 잠깐 뜨는 한 줄 안내("지난밤 먹인 음료가 반영됐어요" 등). 언제 지울지는 `TodayView`가 정한다.
    var notice: String?
    /// 날짜 머리기사(요일 · 날짜 · 상식 한 줄 · 선)의 날. nil이면 그리지 않는다.
    var day: DayKey?
    /// 화면 위 안전 영역. 머리기사는 오른쪽 위 버튼 줄 바로 아래에서 시작한다.
    var topInset: Double = 0
    /// 라벨 위끝 ~ 숫자 바닥(입구 위로 보이는 부분)의 화면 자리. 숫자를 누르면 하루 기록이 열린다(`TodayView.tapCup`).
    var onFrame: (CGRect) -> Void = { _ in }

    static let fontName = "Anton-Regular"
    /// 숫자 바닥(사진 비율). 시안처럼 잔 앞쪽 입구 선(사진 10장 0.318~0.328)보다 살짝 아래까지 내려 선 너머로 글자 조각이
    /// 보이게 한다. 음료 윗면은 가장 높아야 0.331이다.
    static let baselineRatio = 0.328
    /// Anton 글자 비율(unitsPerEm 2048): 숫자 폭 1012, 쉼표 484, 대문자 높이 1760, 위 여백(hhea ascent) 2409.
    static let digitAdvance = 1012.0 / 2048
    static let commaAdvance = 484.0 / 2048
    static let capRatio = 1760.0 / 2048
    static let ascentRatio = 2409.0 / 2048
    /// 아래 여백(hhea descent 674).
    static let descentRatio = 674.0 / 2048
    /// 단위 글자 크기(숫자 대비).
    static let unitScale = 0.3
    /// 단위·기준의 바닥(사진 비율). 뒤쪽 입구 위끝(0.254)보다 위라 유리 선에 안 끊긴다(대표님 2026-10-13 "단위를 위로").
    /// 처음엔 숫자 크기 비례(대문자 높이의 0.36)였는데, 숫자를 줄이자 단위가 입구 선에 걸렸다.
    static let unitBaselineRatio = 0.243
    /// 라벨 바닥과 숫자 머리 사이.
    static let labelGap = 4.0
    /// "오늘 남은 당" 한 줄 높이(넉넉히).
    static let labelHeight = 16.0
    /// 머리기사 위끝 = 안전 영역 + 버튼 줄(위 2 + 44) 아래 조금.
    static let mastheadInset = 50.0
    /// 머리기사 선과 라벨 사이 최소 간격.
    static let mastheadGap = 10.0
    /// 머리기사 높이: 상식 두 줄까지 / 요일·날짜·선만. 자리가 모자라면 상식부터, 그다음 통째로 뺀다(작은 화면).
    static let mastheadHeight = 104.0
    static let mastheadShortHeight = 64.0

    /// 당 = 왼쪽, 카페인 = 오른쪽 정렬(대표님 베타 피드백 2026-10-13 "카페인은 우측정렬해볼까").
    static func edge(_ side: CupSide) -> HorizontalAlignment {
        switch side {
        case .sugar: .leading
        case .caffeine: .trailing
        }
    }

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
            let baseline: Double = photo.top + Self.baselineRatio * photo.height
            let capTop: Double = baseline - cap
            let rowTop: Double = baseline - Self.ascentRatio * size
            let edge = Self.edge(side)
            let mastheadTop: Double = topInset + Self.mastheadInset
            let room: Double = capTop - Self.labelGap - Self.labelHeight - Self.mastheadGap - mastheadTop
            ZStack(alignment: .topLeading) {
                Color.clear
                if let day, room >= Self.mastheadShortHeight {
                    masthead(day: day, showsFact: notice == nil && room >= Self.mastheadHeight)
                        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: edge, vertical: .top))
                        .padding(.horizontal, 24)
                        .offset(y: mastheadTop)
                }
                label
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: edge, vertical: .center))
                    .frame(height: max(capTop - Self.labelGap, 0), alignment: Alignment(horizontal: edge, vertical: .bottom))
                    .padding(.horizontal, 24)
                numberRow(size: size, rise: baseline - (photo.top + Self.unitBaselineRatio * photo.height))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { row in
                        let top: Double = row.minY + (Self.ascentRatio - Self.capRatio) * size - Self.labelGap - 20
                        let bottom: Double = row.minY + Self.ascentRatio * size
                        onFrame(CGRect(x: row.minX, y: top, width: row.width, height: bottom - top))
                    }
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: edge, vertical: .top))
                    .padding(.horizontal, 24)
                    .offset(y: rowTop)
            }
        }
        .mask {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                context.blendMode = .destinationOut
                context.draw(Image(rimLine), in: IdlePhoto(slot: size).rect)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 매거진 머리기사(2026-10-24 대표님 시안 A + 상식 줄 + 선). 요일 · 날짜 · 회색 상식 한 줄 · 가는 선.
    /// 큰 글자 설정에서도 자리를 넘지 않게 고정 크기 글자를 쓴다. 안내 한 줄이 뜨는 동안엔 상식을 접어 자리를 비운다.
    private func masthead(day: DayKey, showsFact: Bool) -> some View {
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        let date = Calendar.current.date(from: components) ?? Date()
        let edge = Self.edge(side)
        let textAlignment: TextAlignment = side == .sugar ? .leading : .trailing
        return VStack(alignment: edge, spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.wide)))
                .font(AppFont.pretendardFixed(12, .semibold))
                .tracking(1.3)
                .foregroundStyle(Self.color(side))
            Text(date.formatted(.dateTime.month(.wide).day()))
                .font(AppFont.pretendardFixed(28, .extraBold))
                .tracking(-0.4)
                .foregroundStyle(Color.ink)
                .padding(.top, 2)
            if showsFact {
                Text(CupFacts.line(for: side, day: day))
                    .font(AppFont.pretendardFixed(12.5, .regular))
                    .lineSpacing(3)
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: 260, alignment: Alignment(horizontal: edge, vertical: .top))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
            Rectangle()
                .fill(Color.ink.opacity(0.5))
                .frame(width: 132, height: 1)
                .padding(.top, 11)
        }
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.3), value: showsFact)
    }

    /// "오늘 남은 당" (+ 넘긴 양). 숫자 머리 바로 위에 붙는다. 안내 한 줄은 그 위로 쌓여 라벨·숫자를 밀지 않는다.
    /// 카드·X 없이 면 색 점 + 작은 글자(2026-10-23 대표님, 시안 `summary-v3.html`).
    private var label: some View {
        VStack(alignment: Self.edge(side), spacing: 8) {
            if let notice {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Self.color(side))
                        .frame(width: 5, height: 5)
                    Text(notice)
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            }
            valueLabel
        }
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.3), value: notice)
    }

    private var valueLabel: some View {
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

    /// 행 위끝 = 숫자의 Anton 위 여백 위끝(바닥에서 `ascentRatio × size`).
    /// 당: 숫자 + 오른쪽 위로 올라간 단위·기준. 카페인: 오른쪽 정렬로 숫자 아래에 단위, 그 아래 기준(대표님 시안 2026-10-13).
    @ViewBuilder
    private func numberRow(size: Double, rise: Double) -> some View {
        switch side {
        case .sugar:
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                digits(size: size)
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    unit(size: size)
                    limitText
                        .padding(.leading, 6)
                }
                .padding(.leading, 6)
                .alignmentGuide(.lastTextBaseline) { $0[.lastTextBaseline] + rise }
            }
            .fixedSize()
            .animation(.spring(response: 0.4), value: remaining)
        case .caffeine:
            // 숫자 글자 칸의 아래 여백(descent)과 단위 글자 칸의 위 여백을 빼서 단위를 숫자 바닥 바로 아래에 붙인다.
            let unitGap: Double = 0.15 * Self.capRatio * size
            let pull: Double = Self.descentRatio * size + (Self.ascentRatio - Self.capRatio) * Self.unitScale * size
            VStack(alignment: .trailing, spacing: 0) {
                digits(size: size)
                unit(size: size)
                    .padding(.top, unitGap - pull)
                limitText
                    .padding(.top, 2)
            }
            .fixedSize()
            .animation(.spring(response: 0.4), value: remaining)
        }
    }

    private func digits(size: Double) -> some View {
        Text(Amount.number(remaining))
            .font(.custom(Self.fontName, fixedSize: size))
            .foregroundStyle(Self.color(side))
            .contentTransition(.numericText())
    }

    private func unit(size: Double) -> some View {
        Text(side.unit)
            .font(.custom(Self.fontName, fixedSize: size * Self.unitScale))
            .foregroundStyle(Self.color(side))
    }

    private var limitText: some View {
        Text("/\(Amount.number(limit)) \(side.unit)")
            .font(.footnote)
            .tracking(0.3)
            .foregroundStyle(.secondary)
    }
}
