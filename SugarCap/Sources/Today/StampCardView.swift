import SwiftUI

/// 2주 스탬프판(대표님 2026-11-05 확정 시안 `design/proto/stamp-card.html`). 카페 쿠폰처럼 14칸, 찍히기 전에는 칸 번호만 보인다.
/// 열릴 때 아직 연출을 안 본 칸(`seen` 다음부터)을 하나씩 찍는다. 14칸은 잔 세트 룰렛(다 가졌으면 병뚜껑 3개).
/// 바깥이나 X를 누르면 닫힌다. 에어브러시 없이 단색 면·선만.
struct StampCardView: View {
    /// `GiftKind.stamp` 행. 칸 번호 = `level`.
    let stamps: [GiftEvent]
    /// 찍는 연출까지 본 칸 수(`StampProgress.seenKey`).
    let seen: Int
    /// 룰렛에 돌릴 잔(기록하는 면의 상품). 멈추는 잔은 14칸 행에 이미 정해져 있다.
    let reel: [TradeItem]
    let onSeen: (Int) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var pressing: Int?
    /// 찍는 칸의 단계. 0 = 도장이 위에 떠 있음, 1 = 눌림, 2 = 상품이 튀어나옴.
    @State private var phase = 0
    @State private var finale: Finale?
    @State private var reelOffset: CGFloat = 0
    @State private var isSettled = false
    @State private var notchY: CGFloat = 76

    private enum Finale: Equatable {
        /// 받은 잔 세트 id.
        case cup(String)
        case caps
    }

    private static let windowSize = CGSize(width: 104, height: 136)

    private var stamped: Int {
        StampMath.stamped(cellNumbers: stamps.compactMap(\.level))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
                .accessibilityHidden(true)
            card
                .padding(.horizontal, 24)
        }
        .task { await play() }
        .sensoryFeedback(.impact(weight: .medium), trigger: shown) { old, new in new > old && old >= seen }
        .sensoryFeedback(.success, trigger: isSettled) { _, new in new }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("2주 스탬프")
                    .font(AppFont.pretendard(22, .bold, relativeTo: .title2))
                Spacer(minLength: 12)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(shown)")
                        .font(AppFont.pretendard(17, .bold, relativeTo: .headline))
                        .contentTransition(.numericText())
                    Text(verbatim: "/ \(StampMath.cells)")
                        .font(AppFont.pretendard(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Color(white: 0.63))
                }
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(shown) / \(StampMath.cells)"))
                .accessibilityIdentifier("stamp-count")
                .padding(.trailing, 34)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { notchY = $0 + 9 }

            Line()
                .stroke(Color(white: 0.83), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(height: 1.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 8.25)

            VStack(spacing: 14) {
                row(1 ... 7)
                row(8 ... 14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 6)

            Text("밤에 돌아와서 마감 시 스탬프를 적립!")
                .font(AppFont.pretendard(14, .medium, relativeTo: .footnote))
                .foregroundStyle(Color(white: 0.44))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 22)
        }
        .background(CouponShape(notchY: notchY).fill(.white))
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 30, height: 30)
                    .background(Color.wall, in: Circle())
                    .tapTarget()
            }
            .accessibilityLabel("닫기")
            .accessibilityIdentifier("stamp-close")
            .padding(.top, 9)
            .padding(.trailing, 7)
        }
        .overlay { finaleView }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stamp-card")
    }

    private func row(_ numbers: ClosedRange<Int>) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(numbers), id: \.self) { number in
                cell(number)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 칸

    @ViewBuilder
    private func cell(_ number: Int) -> some View {
        let isLast = number == StampMath.cells
        let isDone = number <= shown
        let isPressing = pressing == number
        let gift = stamps.first { $0.level == number }
        ZStack {
            if isLast {
                lastCell(isDone: isDone, gift: gift)
            } else {
                Circle()
                    .strokeBorder(
                        isDone || number == shown + 1 ? Color.ink : Color(white: 0.83),
                        lineWidth: number == shown + 1 && !isDone && !isPressing ? 2 : 1.5
                    )
                    .background(Circle().fill(isDone ? Color.ink : .clear))
                if isPressing {
                    Circle()
                        .fill(Color.ink)
                        .padding(-1.5)
                        .scaleEffect(reduceMotion ? 1 : (phase >= 1 ? 1 : 1.7))
                        .rotationEffect(.degrees(reduceMotion || phase >= 1 ? 0 : -10))
                        .opacity(phase >= 1 ? 1 : 0)
                }
                if isDone || (isPressing && phase >= 2), let gift {
                    PrizeGlyph(gift: gift, size: 20)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else if !isPressing {
                    Text(verbatim: "\(number)")
                        .font(AppFont.pretendardFixed(12, .semibold))
                        .foregroundStyle(number == shown + 1 ? Color.ink : Color(white: 0.63))
                        .monospacedDigit()
                }
            }
        }
        .frame(width: 38, height: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cellLabel(number, isDone: isDone, gift: gift))
    }

    @ViewBuilder
    private func lastCell(isDone: Bool, gift: GiftEvent?) -> some View {
        if isDone, let gift {
            Circle().fill(.white)
            Circle().strokeBorder(Color.ink, lineWidth: 2)
            if let set = StampCardView.setID(of: gift) {
                CupCutout(setID: set, cupHeight: 28)
            } else {
                PrizeGlyph(gift: gift, size: 20)
            }
        } else {
            Circle().strokeBorder(Color.ink, style: StrokeStyle(lineWidth: shown == StampMath.cells - 1 ? 2 : 1.5, dash: shown == StampMath.cells - 1 ? [] : [3, 2.5]))
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ink)
        }
    }

    private func cellLabel(_ number: Int, isDone: Bool, gift: GiftEvent?) -> String {
        guard isDone, let gift else { return String(localized: "\(number)번째 칸") }
        if let set = StampCardView.setID(of: gift), let item = TradeCatalog.item(set) { return item.name }
        return gift.isCap ? String(localized: "병뚜껑") : String(localized: "마음")
    }

    private static func setID(of gift: GiftEvent) -> String? {
        guard let payload = gift.payload, payload.hasPrefix(GiftContent.setPrefix) else { return nil }
        return String(payload.dropFirst(GiftContent.setPrefix.count))
    }

    // MARK: - 14칸

    @ViewBuilder
    private var finaleView: some View {
        if let finale {
            HStack(spacing: 22) {
                ZStack(alignment: .top) {
                    switch finale {
                    case .cup:
                        VStack(spacing: 0) {
                            ForEach(Array(reelSequence.enumerated()), id: \.offset) { _, item in
                                CupCutout(setID: item.id, cupHeight: 116)
                                    .frame(width: Self.windowSize.width, height: Self.windowSize.height)
                            }
                        }
                        .offset(y: reelOffset)
                    case .caps:
                        VStack(spacing: 6) {
                            ForEach(capGifts, id: \.id) { gift in
                                PrizeGlyph(gift: gift, size: 30)
                                    .scaleEffect(isSettled || reduceMotion ? 1 : 0.3)
                                    .opacity(isSettled || reduceMotion ? 1 : 0)
                            }
                        }
                        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
                    }
                }
                .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .top)
                .clipped()
                .background(Color.wall, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(finale == .caps ? "14일 선물" : "14일 룰렛")
                        .font(AppFont.pretendard(22, .bold, relativeTo: .title2))
                        .foregroundStyle(Color.ink)
                    Text(isSettled ? finaleName : " ")
                        .font(AppFont.pretendard(17, .semibold, relativeTo: .headline))
                        .foregroundStyle(Color(white: 0.25))
                        .padding(.top, 8)
                        .accessibilityIdentifier("stamp-pick")
                    Button(action: takeFinale) {
                        Text("받기")
                            .font(AppFont.pretendard(16, .semibold, relativeTo: .body))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .frame(minHeight: 44)
                            .background(Color.ink, in: Capsule())
                    }
                    .opacity(isSettled ? 1 : 0)
                    .disabled(!isSettled)
                    .padding(.top, 18)
                    .accessibilityIdentifier("stamp-take")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transition(.opacity)
        }
    }

    private var capGifts: [GiftEvent] {
        stamps.filter { $0.level == StampMath.cells }
    }

    private var finaleName: String {
        switch finale {
        case .cup(let id): return TradeCatalog.item(id)?.name ?? id
        case .caps: return String(localized: "병뚜껑 \(StampMath.finalCaps)개")
        case nil: return ""
        }
    }

    /// 4바퀴 돈 뒤 받은 잔에서 멈춘다.
    private var reelSequence: [TradeItem] {
        guard case .cup(let id) = finale, let won = TradeCatalog.item(id) else { return [] }
        let loop = reel.isEmpty ? [won] : reel
        return Array(repeating: loop, count: 4).flatMap { $0 } + [won]
    }

    private func takeFinale() {
        withAnimation(.easeOut(duration: 0.2)) {
            finale = nil
            shown = StampMath.cells
        }
        onSeen(StampMath.cells)
    }

    // MARK: - 순서

    private func play() async {
        shown = min(seen, stamped)
        guard shown < stamped else { return }
        try? await Task.sleep(for: .seconds(0.45))
        while shown < stamped, !Task.isCancelled {
            let number = shown + 1
            if number == StampMath.cells {
                await playFinale()
                return
            }
            phase = 0
            pressing = number
            withAnimation(.easeIn(duration: 0.22)) { phase = 1 }
            try? await Task.sleep(for: .seconds(0.27))
            withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { phase = 2 }
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                shown = number
                pressing = nil
            }
            onSeen(number)
        }
    }

    /// CI 스크린샷(Debug `-screenshotStampInstant YES`): 룰렛을 돌리지 않고 멈춘 자리부터 보인다.
    private static var isScreenshotInstant: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "screenshotStampInstant")
        #else
        return false
        #endif
    }

    private func playFinale() async {
        guard let first = capGifts.first else { return }
        if let set = Self.setID(of: first), TradeCatalog.item(set) != nil {
            withAnimation(.easeOut(duration: 0.25)) { finale = .cup(set) }
            guard !reduceMotion, !Self.isScreenshotInstant else {
                reelOffset = -CGFloat(reelSequence.count - 1) * Self.windowSize.height
                isSettled = true
                return
            }
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 3.2)) {
                reelOffset = -CGFloat(reelSequence.count - 1) * Self.windowSize.height
            }
            try? await Task.sleep(for: .seconds(3.2))
        } else {
            withAnimation(.easeOut(duration: 0.25)) { finale = .caps }
            try? await Task.sleep(for: .seconds(0.35))
        }
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { isSettled = true }
    }
}

/// 마음·병뚜껑 기호. 로슈(흰색)는 흰 바탕에서도 보이게 바깥에 옅은 먹색을 한 겹 두른다.
struct PrizeGlyph: View {
    let gift: GiftEvent
    let size: CGFloat

    var body: some View {
        let symbol = gift.isCap ? "seal.fill" : "heart.fill"
        let isRoshu = gift.cupSide != .caffeine
        ZStack {
            if isRoshu {
                Image(systemName: symbol)
                    .font(.system(size: size + 2.5))
                    .foregroundStyle(Color(white: 0.33))
            }
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(isRoshu ? Color.roshuWhite : Color.caffeineAmber)
        }
        .accessibilityHidden(true)
    }
}

/// 잔 누끼(937×1666) 중 잔 부분만 잘라 `cupHeight` 높이로 그린다. 잔은 (199,430)~(735,1446)에 있다.
struct CupCutout: View {
    let setID: String
    let cupHeight: CGFloat

    var body: some View {
        let scale = cupHeight / 1016
        Image(CupLevel.cutoutName(setID: setID, step: 80))
            .resizable()
            .frame(width: 937 * scale, height: 1666 * scale)
            .offset(x: -199 * scale, y: -430 * scale)
            .frame(width: 536 * scale, height: 1016 * scale, alignment: .topLeading)
            .clipped()
            .accessibilityHidden(true)
    }
}

/// 둥근 카드에서 양옆 절취선 자리를 반원으로 파낸 쿠폰.
private struct CouponShape: Shape {
    var notchY: CGFloat
    var notchRadius: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var notches = Path()
        for x in [rect.minX, rect.maxX] {
            notches.addEllipse(in: CGRect(x: x - notchRadius, y: notchY - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        }
        return Path(roundedRect: rect, cornerRadius: 16, style: .continuous).subtracting(notches)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
