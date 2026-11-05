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
    /// 얼리버드 대상(`EarlyBird.known() == true`). 7칸을 찍기 전에도 유리 방울을 옅게 보여 준다.
    let isEarlyBird: Bool
    /// 얼리버드 무대를 본 적 있는지(`EarlyBird.seenKey`). 7칸을 지나 소급해 받았으면 판을 열 때 한 번 보여 준다.
    let earlyBirdSeen: Bool
    let onSeen: (Int) -> Void
    let onEarlyBirdSeen: () -> Void
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
    /// 얼리버드 무대 단계. 0 = 없음, 1 = 판이 어두워짐, 2 = 방울이 떠오름, 3 = 빛줄기가 지나감, 4 = 이름과 받기.
    @State private var earlyStage = 0
    /// 빛줄기 위치(0 = 방울 왼쪽 밖, 1 = 오른쪽 밖).
    @State private var streak: CGFloat = 0
    /// 이 판에서 무대를 받았다(스크린샷처럼 바깥 기록이 안 바뀌어도 다시 틀지 않는다).
    @State private var earlyBirdDone = false
    /// 무대를 받은 뒤 남은 칸을 이어 찍으려고 `play`를 다시 돌린다.
    @State private var playRun = 0
    /// 찍는 연출·룰렛·얼리버드 무대가 도는 중. 끝날 때까지 X·바깥 탭으로 닫지 못한다.
    @State private var isPlaying = false
    /// 작은 폭죽이 터지는 칸과 다시 터뜨리는 열쇠.
    @State private var burstCell: Int?
    @State private var burstID = 0
    /// 잔·병뚜껑·얼리버드를 받을 때 판 전체에 터지는 큰 폭죽(0 = 아직 없음).
    @State private var bigBurst = 0

    private enum Finale: Equatable {
        /// 받은 잔 세트 id.
        case cup(String)
        case caps
    }

    private static let windowSize = CGSize(width: 104, height: 104)

    private var stamped: Int {
        StampMath.stamped(cellNumbers: stamps.compactMap(\.level))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if !isPlaying { onClose() } }
                .accessibilityHidden(true)
            card
                .padding(.horizontal, 24)
        }
        .task(id: playRun) { await play() }
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

            // 폭죽이 옆·아래 칸에 가리지 않게 터지는 칸의 줄을 위로 올린다.
            VStack(spacing: 14) {
                row(1 ... 7)
                    .zIndex(burstCell.map { $0 <= 7 } == true ? 1 : 0)
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
            // 찍는 연출이 끝나야 닫을 수 있다(대표님 2026-11-06 "애니메이션 종료 후 엑스버튼 활성화").
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 30, height: 30)
                    .background(Color.wall, in: Circle())
                    .tapTarget()
            }
            .disabled(isPlaying)
            .opacity(isPlaying ? 0.3 : 1)
            .animation(.easeOut(duration: 0.2), value: isPlaying)
            .accessibilityLabel("닫기")
            .accessibilityIdentifier("stamp-close")
            .padding(.top, 9)
            .padding(.trailing, 7)
        }
        .overlay { finaleView }
        .overlay { earlyBirdView }
        .overlay {
            if bigBurst > 0 {
                ConfettiBurst(size: .big)
                    .id(bigBurst)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stamp-card")
    }

    private func row(_ numbers: ClosedRange<Int>) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(numbers), id: \.self) { number in
                cell(number)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if burstCell == number {
                            ConfettiBurst(size: .small)
                                .id(burstID)
                        }
                    }
                    .zIndex(burstCell == number ? 1 : 0)
            }
        }
    }

    // MARK: - 칸

    @ViewBuilder
    private func cell(_ number: Int) -> some View {
        let isLast = number == StampMath.cells
        let isDone = number <= shown
        let isPressing = pressing == number
        let gift = stampGift(at: number)
        ZStack {
            if isLast {
                lastCell(isDone: isDone, gift: gift)
            } else if number == StampMath.earlyBirdCell, isDone ? !perkItems.isEmpty : (isEarlyBird && !isPressing) {
                earlyBirdCell(isDone: isDone)
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
            if let set = StampCardView.setID(of: gift), let item = TradeCatalog.item(set) {
                Image(item.dropAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            } else {
                PrizeGlyph(gift: gift, size: 20)
            }
        } else {
            Circle().strokeBorder(Self.gold, style: StrokeStyle(lineWidth: shown == StampMath.cells - 1 ? 2 : 1.5, dash: shown == StampMath.cells - 1 ? [] : [3, 2.5]))
            GoldFoilGlyph(systemName: "cup.and.saucer.fill", size: 15)
        }
    }

    static let gold = Color(red: 0.80, green: 0.60, blue: 0.18)

    /// 7칸 얼리버드 자리. 받았으면 유리 방울 두 개, 대상인데 아직이면 무지개 물음표(빌드 407 대표님, 무엇인지 숨긴다).
    @ViewBuilder
    private func earlyBirdCell(isDone: Bool) -> some View {
        let isNext = shown == StampMath.earlyBirdCell - 1
        if isDone {
            Circle().fill(.white)
            Circle().strokeBorder(Color.ink, lineWidth: 2)
            HStack(spacing: -7) {
                ForEach(perkItems) { item in
                    Image(item.dropAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 19, height: 19)
                }
            }
            .accessibilityHidden(true)
        } else {
            Circle().strokeBorder(Color.ink, style: StrokeStyle(lineWidth: isNext ? 2 : 1.5, dash: isNext ? [] : [3, 2.5]))
            RainbowQuestionMark(size: 20)
        }
    }

    private func cellLabel(_ number: Int, isDone: Bool, gift: GiftEvent?) -> String {
        if number == StampMath.earlyBirdCell, isDone ? !perkItems.isEmpty : isEarlyBird {
            let title = String(localized: "얼리버드 선물")
            let place = String(localized: "\(number)번째 칸")
            guard isDone else { return "\(place), \(title)" }
            return "\(title): \(perkItems.map(\.name).joined(separator: ", "))"
        }
        guard isDone, let gift else { return String(localized: "\(number)번째 칸") }
        if let set = StampCardView.setID(of: gift), let item = TradeCatalog.item(set) { return item.name }
        return gift.isCap ? String(localized: "병뚜껑") : String(localized: "마음")
    }

    private static func setID(of gift: GiftEvent) -> String? {
        guard let payload = gift.payload, payload.hasPrefix(GiftContent.setPrefix) else { return nil }
        return String(payload.dropFirst(GiftContent.setPrefix.count))
    }

    private static func isPerk(_ gift: GiftEvent) -> Bool {
        guard let id = setID(of: gift) else { return false }
        return TradeCatalog.perks.contains { $0.id == id }
    }

    /// 칸에 찍힌 상품. 7칸은 얼리버드 잔 행이 더 있어도 마음 행이 도장이다.
    private func stampGift(at number: Int) -> GiftEvent? {
        let rows = stamps.filter { $0.level == number }
        return rows.first { !Self.isPerk($0) } ?? rows.first
    }

    /// 7칸에서 받은 유리 공예 잔(`TradeCatalog.perks` 순서).
    private var perkItems: [TradeItem] {
        let won = Set(stamps.filter { $0.level == StampMath.earlyBirdCell && Self.isPerk($0) }.compactMap(Self.setID(of:)))
        return TradeCatalog.perks.filter { won.contains($0.id) }
    }

    private var needsEarlyBirdStage: Bool {
        !perkItems.isEmpty && !earlyBirdSeen && !earlyBirdDone
    }

    // MARK: - 얼리버드 무대

    /// 판을 어둡게 덮고 뒤로 빛살이 돌며 유리 방울 두 개가 차례로 튀어 오른다. 폭죽이 터지고 빛줄기가 두 번 지나간 뒤
    /// 이름표가 튀어나온다(빌드 407 대표님 "좀 더 화려하게"). 단색 면·또렷한 선만(에어브러시 금지).
    @ViewBuilder
    private var earlyBirdView: some View {
        if earlyStage > 0 {
            ZStack {
                CouponShape(notchY: notchY)
                    .fill(Color.ink.opacity(0.92))
                VStack(spacing: 0) {
                    HStack(spacing: 20) {
                        ForEach(Array(perkItems.enumerated()), id: \.element.id) { index, item in
                            Image(item.dropAsset)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 92, height: 92)
                                .overlay { streakBand(item) }
                                .scaleEffect(earlyStage >= 2 ? 1 : 0.2)
                                .rotationEffect(.degrees(earlyStage >= 2 ? 0 : (index == 0 ? -30 : 30)))
                                .offset(y: earlyStage >= 2 ? 0 : 40)
                                .opacity(earlyStage >= 2 ? 1 : 0)
                                .animation(
                                    reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.48).delay(Double(index) * 0.14),
                                    value: earlyStage
                                )
                        }
                    }
                    .background {
                        SpinningRays(isOn: earlyStage >= 2)
                            .frame(width: 420, height: 420)
                    }
                    .accessibilityHidden(true)

                    Text("얼리버드 선물")
                        .font(AppFont.pretendard(22, .bold, relativeTo: .title2))
                        .foregroundStyle(.white)
                        .padding(.top, 22)
                        .scaleEffect(earlyStage >= 4 ? 1 : 0.6)
                        .opacity(earlyStage >= 4 ? 1 : 0)
                    Text(verbatim: perkItems.map(\.name).joined(separator: " · "))
                        .font(AppFont.pretendard(17, .semibold, relativeTo: .headline))
                        .foregroundStyle(Color(white: 0.85))
                        .padding(.top, 8)
                        .opacity(earlyStage >= 4 ? 1 : 0)
                        .accessibilityIdentifier("stamp-early-names")
                    Button(action: takeEarlyBird) {
                        Text("받기")
                            .font(AppFont.pretendard(16, .semibold, relativeTo: .body))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 28)
                            .frame(minHeight: 44)
                            .background(.white, in: Capsule())
                    }
                    .opacity(earlyStage >= 4 ? 1 : 0)
                    .disabled(earlyStage < 4)
                    .padding(.top, 20)
                    .accessibilityIdentifier("stamp-early-take")
                }
                .padding(.horizontal, 24)
            }
            .clipShape(CouponShape(notchY: notchY))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stamp-early")
            .transition(.opacity)
        }
    }

    /// 방울 모양 안에서만 보이는 비스듬한 흰 띠.
    private func streakBand(_ item: TradeItem) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let travel: CGFloat = width * 2
            let x: CGFloat = -width * 0.5 + travel * streak
            Rectangle()
                .fill(Color.white.opacity(0.75))
                .frame(width: 14, height: proxy.size.height * 1.6)
                .rotationEffect(.degrees(20))
                .position(x: x, y: proxy.size.height / 2)
        }
        .opacity(earlyStage == 3 ? 1 : 0)
        .mask {
            Image(item.dropAsset)
                .resizable()
                .scaledToFit()
        }
        .allowsHitTesting(false)
    }

    private func playEarlyBird() async {
        streak = 0
        withAnimation(.easeOut(duration: 0.25)) { earlyStage = 1 }
        guard !reduceMotion, !Self.isScreenshotInstant else {
            earlyStage = 4
            return
        }
        try? await Task.sleep(for: .seconds(0.3))
        earlyStage = 2
        try? await Task.sleep(for: .seconds(0.25))
        bigBurst += 1
        try? await Task.sleep(for: .seconds(0.6))
        guard !Task.isCancelled else { return }
        earlyStage = 3
        for _ in 0 ..< 2 {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { streak = 0 }
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(.easeInOut(duration: 0.55)) { streak = 1 }
            try? await Task.sleep(for: .seconds(0.65))
            guard !Task.isCancelled else { return }
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { earlyStage = 4 }
        bigBurst += 1
    }

    private func takeEarlyBird() {
        withAnimation(.easeOut(duration: 0.2)) { earlyStage = 0 }
        earlyBirdDone = true
        onEarlyBirdSeen()
        playRun += 1
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
                                // 룰렛은 잔이 아니라 그 잔의 먹이기 방울로 돈다(대표님 2026-11-05).
                                Image(item.dropAsset)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .frame(width: Self.windowSize.width, height: Self.windowSize.height)
                            }
                        }
                        .offset(y: reelOffset)
                    case .caps:
                        // 세 줄로 쌓으면 창(104pt)을 넘어 위아래가 잘린다. 둘·하나 삼각형으로 놓는다.
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                ForEach(capGifts.prefix(2), id: \.id) { gift in capGlyph(gift) }
                            }
                            HStack(spacing: 4) {
                                ForEach(capGifts.dropFirst(2), id: \.id) { gift in capGlyph(gift) }
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

    private func capGlyph(_ gift: GiftEvent) -> some View {
        PrizeGlyph(gift: gift, size: 28)
            .scaleEffect(isSettled || reduceMotion ? 1 : 0.3)
            .opacity(isSettled || reduceMotion ? 1 : 0)
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

    /// 찍을 칸·무대가 남았으면 그동안 닫기를 막는다. 무대·룰렛은 받기 버튼이 뜨는 순간 풀린다.
    private func play() async {
        shown = max(shown, min(seen, stamped))
        let isRetroEarlyBird = shown >= StampMath.earlyBirdCell && needsEarlyBirdStage
        guard isRetroEarlyBird || shown < stamped else { return }
        isPlaying = true
        await playSteps(isRetroEarlyBird: isRetroEarlyBird)
        isPlaying = false
    }

    private func playSteps(isRetroEarlyBird: Bool) async {
        // 판정이 늦게 와서 이미 찍은 7칸에 잔이 들어왔다. 판을 열자마자 무대부터.
        if isRetroEarlyBird {
            try? await Task.sleep(for: .seconds(0.45))
            guard !Task.isCancelled else { return }
            await playEarlyBird()
            return
        }
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
            // 상품이 튀어나오는 순간 그 칸에서 작은 폭죽(대표님 2026-11-06 "매 칸 도장마다").
            burstCell = number
            burstID += 1
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                shown = number
                pressing = nil
            }
            onSeen(number)
            if number == StampMath.earlyBirdCell, needsEarlyBirdStage {
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }
                await playEarlyBird()
                return
            }
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
                bigBurst += 1
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
        bigBurst += 1
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

/// 7칸 얼리버드 미리보기(빌드 407 대표님 "무지개빛 일렁이는 물음표"). 경계가 또렷한 무지개 띠가 글자 안을 흘러가고
/// 글자가 살짝 기울었다 돌아온다. 부드러운 그라데이션은 쓰지 않는다. 동작 줄이기면 멈춘다.
private struct RainbowQuestionMark: View {
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bands: [Color] = [
        Color(red: 0.93, green: 0.27, blue: 0.33),
        Color(red: 0.98, green: 0.58, blue: 0.20),
        Color(red: 0.98, green: 0.82, blue: 0.20),
        Color(red: 0.35, green: 0.78, blue: 0.42),
        Color(red: 0.25, green: 0.58, blue: 0.95),
        Color(red: 0.55, green: 0.38, blue: 0.90),
    ]

    /// 띠 한 바퀴를 두 번 이어 붙인 딱딱한 경계 그라데이션. 한 바퀴만큼 밀면 처음과 같아진다.
    private static let gradient: Gradient = {
        var stops: [Gradient.Stop] = []
        let count = Double(bands.count)
        for cycle in 0 ..< 2 {
            for (index, color) in bands.enumerated() {
                let start: Double = (Double(cycle) + Double(index) / count) / 2
                let end: Double = (Double(cycle) + Double(index + 1) / count) / 2
                stops.append(Gradient.Stop(color: color, location: start))
                stops.append(Gradient.Stop(color: color, location: end))
            }
        }
        return Gradient(stops: stops)
    }()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            let flow: Double = reduceMotion ? 0 : (t / 2.2).truncatingRemainder(dividingBy: 1)
            let tilt: Double = reduceMotion ? 0 : sin(t * 2.4) * 7
            let swell: Double = reduceMotion ? 1 : 1 + sin(t * 3.1) * 0.05
            // 그라데이션 길이 = 글자 폭 4배(띠 두 바퀴), 한 바퀴(2배)만큼 왼쪽으로 흘린다.
            let startX: Double = -2 * flow
            let shape = LinearGradient(
                gradient: Self.gradient,
                startPoint: UnitPoint(x: startX, y: 0),
                endPoint: UnitPoint(x: startX + 4, y: 1.2)
            )
            Text(verbatim: "?")
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundStyle(shape)
                .rotationEffect(.degrees(tilt))
                .scaleEffect(swell)
        }
        .accessibilityHidden(true)
    }
}

/// 14칸 잔(빌드 407 대표님 "금박 반짝이게"). 금색 면 위로 또렷한 흰 사선이 주기마다 한 번 지나간다. 동작 줄이기면 멈춘다.
private struct GoldFoilGlyph: View {
    let systemName: String
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: Double = 2.6
    private static let sweep: Double = 0.7

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            let local: Double = t.truncatingRemainder(dividingBy: Self.period)
            let progress: Double = reduceMotion ? 1 : min(local / Self.sweep, 1)
            glyph
                .foregroundStyle(StampCardView.gold)
                .overlay {
                    GeometryReader { proxy in
                        let width: Double = Double(proxy.size.width)
                        let x: Double = -4 + (width + 8) * progress
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 3.5, height: proxy.size.height * 2)
                            .rotationEffect(.degrees(22))
                            .position(x: x, y: proxy.size.height / 2)
                    }
                    .opacity(progress < 1 ? 1 : 0)
                    .mask { glyph }
                }
        }
        .accessibilityHidden(true)
    }

    private var glyph: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
    }
}

/// 얼리버드 무대 뒤에서 천천히 도는 빛살. 흰 쐐기 면(옅은 단색)만, 번짐 없음. 켜질 때 작게 시작해 펼쳐진다.
private struct SpinningRays: View {
    let isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !isOn)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            let angle: Double = reduceMotion ? 0 : (t * 18).truncatingRemainder(dividingBy: 360)
            RayWedges(count: 14)
                .fill(Color.white.opacity(0.09))
                .rotationEffect(.degrees(angle))
        }
        .scaleEffect(isOn ? 1 : 0.3)
        .opacity(isOn ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.7), value: isOn)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RayWedges: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius: Double = Double(max(rect.width, rect.height))
        let step: Double = 2 * Double.pi / Double(count)
        for index in 0 ..< count {
            let a0: Double = Double(index) * step
            let a1: Double = a0 + step / 2
            path.move(to: center)
            path.addLine(to: CGPoint(x: Double(center.x) + cos(a0) * radius, y: Double(center.y) + sin(a0) * radius))
            path.addLine(to: CGPoint(x: Double(center.x) + cos(a1) * radius, y: Double(center.y) + sin(a1) * radius))
            path.closeSubpath()
        }
        return path
    }
}
