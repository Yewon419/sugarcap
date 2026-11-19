import OSLog
import SwiftUI

/// 이용 기록 동의를 언제 묻고 답을 어떻게 남기는지(SPEC §9.10). 문구 SSOT = `docs/CONSENT.md`.
/// 새 사용자는 첫 마감 뒤, 기존 사용자는 업데이트 뒤 다음 마감 뒤에 한 번 묻는다(대표님 2026-11-19).
/// 고르지 않고 앱을 끄면 다음 실행 때 다시 묻는다.
enum ConsentPrompt {
    /// 이 버전에서 하루를 마감한 적이 있다. 마감할 때 켠다.
    static let dueKey = "usageConsentDue"

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "usage")

    static func isDue(consent: UsageConsent, closedDay: Bool) -> Bool {
        consent == .undecided && closedDay
    }

    /// 동의면 쌓아 둔 기록을 보내고, 거절이면 대기열을 지운다. 대기열을 못 연 실행이면 답만 저장한다.
    @MainActor
    static func answer(granted: Bool) async {
        guard let reporter = UsageReporter.shared else {
            UsageConsent.store(granted: granted, in: .standard)
            return
        }
        do {
            if granted {
                _ = try await reporter.grant()
            } else {
                try reporter.decline()
            }
        } catch {
            logger.error("동의 답 처리 실패(granted=\(granted)): \(String(describing: error), privacy: .public)")
        }
    }
}

/// 오늘 화면 가운데 뜨는 동의 카드(`design/proto/consent.html`, 대표님 2026-11-19 확정).
/// 닫기(X)·바깥 탭이 없다. 두 버튼은 같은 크기·같은 무게로 둔다.
struct ConsentCard: View {
    let onAnswer: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isExpanded: Bool

    init(expanded: Bool, onAnswer: @escaping (Bool) -> Void) {
        self.onAnswer = onAnswer
        _isExpanded = State(initialValue: expanded)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            card
                .padding(.horizontal, 20)
                .padding(.vertical, 40)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            if isExpanded {
                ScrollView { document }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: .infinity)
            } else {
                // 큰 글자에서 요약이 화면을 넘으면 그때만 스크롤.
                ViewThatFits(in: .vertical) {
                    document
                    ScrollView { document }
                        .scrollIndicators(.hidden)
                }
            }
            actions
        }
        .background(Color.wall, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var document: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConsentSummary()
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text(isExpanded ? LocalizedStringKey("전문 접기") : LocalizedStringKey("전문 보기"))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(AppFont.pretendard(14, .medium, relativeTo: .subheadline))
                .foregroundStyle(Color.ink.opacity(0.72))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("consent-more")
            if isExpanded {
                ConsentLaw()
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        // 큰 글자에서는 두 버튼을 위아래로 쌓아 문구가 낱글자로 끊기지 않게 한다.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            answerButton("동의하지 않습니다", granted: false, id: "consent-decline")
            answerButton("동의합니다", granted: true, id: "consent-accept")
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .overlay(alignment: .top) {
            if isExpanded { ConsentSummary.line.frame(height: 1) }
        }
    }

    private func answerButton(_ title: LocalizedStringKey, granted: Bool, id: String) -> some View {
        Button {
            onAnswer(granted)
        } label: {
            Text(title)
                .font(AppFont.pretendard(15, .semibold, relativeTo: .body))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 8)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.ink.opacity(0.12), lineWidth: 1.5)
                }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier(id)
    }
}

/// 설정 「전문 보기」. 카드와 같은 문서를 펼친 채로 보여 준다.
struct ConsentTextSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ConsentSummary()
                    ConsentLaw()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color.wall)
            .navigationTitle("동의 전문")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("consent-text-close")
                }
            }
        }
    }
}

/// 제목과 요약 표(동의서 1절). 개인정보 보호법 제15조 제2항의 네 가지를 먼저 보인다.
struct ConsentSummary: View {
    static let line = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.18)
    static let sub = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.6)

    private static let rows: [(LocalizedStringResource, LocalizedStringResource)] = [
        ("수집·이용 목적", "앱 기능 개선, 음료 메뉴 데이터 보완, 이용 통계 분석"),
        ("수집 항목", "앱 이용 기록, 음료 기록(메뉴·잔 수·요일·시간대), 무작위 생성 식별값, 앱 버전·운영체제 버전·언어·지역 설정"),
        ("보유·이용 기간", "수집일로부터 2년, 기간이 끝나면 지체 없이 파기"),
        ("동의 거부 권리", "동의하지 않을 수 있으며, 동의하지 않아도 앱의 모든 기능을 똑같이 이용할 수 있습니다."),
    ]

    @ScaledMetric(relativeTo: .footnote) private var labelWidth: CGFloat = 92
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("선택")
                .font(AppFont.pretendard(11, .semibold, relativeTo: .caption2))
                .tracking(1.3)
                .foregroundStyle(Self.sub)
            Text("서비스 개선을 위한\n이용 기록 수집·이용 동의")
                .font(AppFont.pretendard(22, .extraBold, relativeTo: .title2))
                .tracking(AppFont.displayTracking(for: 22))
                .lineSpacing(4)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.rows.indices, id: \.self) { index in
                    let row = Self.rows[index]
                    ConsentRowLayout.of(typeSize) {
                        Text(row.0)
                            .font(AppFont.pretendard(13, .medium, relativeTo: .footnote))
                            .foregroundStyle(Self.sub)
                            .frame(width: typeSize.isAccessibilitySize ? nil : labelWidth, alignment: .leading)
                        Text(row.1)
                            .font(AppFont.pretendard(14, .regular, relativeTo: .subheadline))
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 11)
                    .overlay(alignment: .top) { Self.line.frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
            .overlay(alignment: .bottom) { Self.line.frame(height: 1) }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 동의서 전문(2절, 제1조~부칙).
struct ConsentLaw: View {
    /// 제8조 문의처. 동의서 원문(`docs/CONSENT.md`)과 같은 주소.
    private static let contact = "windgarden05@gmail.com"

    private static let purposes: [LocalizedStringResource] = [
        "앱 기능과 화면의 이용 흐름 분석 및 개선",
        "앱에 없는 음료 메뉴 파악과 메뉴 데이터 보완",
        "음료 종류·요일·시간대별 이용 통계 작성",
    ]

    private static let items: [(LocalizedStringResource, LocalizedStringResource)] = [
        ("앱 이용 기록:", "처음 사용 안내 완료 여부, 음료 기록 방법(검색·브랜드 메뉴·즐겨찾기·최근 기록·직접 입력의 구분), 하루 마감 진행 여부, 구독 안내 화면의 표시와 선택 결과, 줄이기 목표·마감 알림·위젯 사용 여부"),
        ("음료 기록:", "앱 메뉴 데이터의 음료 식별값, 잔 수, 기록한 요일과 시간대(정각 단위), 메뉴 국가, 하루 기준량의 범위, 하루 기준량 안에서 마쳤는지 여부, 직접 입력한 음료의 잔 수, 기록 항목(당·카페인) 설정"),
        ("무작위 생성 식별값:", "앱 설치 시 무작위로 만든 값과 앱을 실행할 때마다 새로 만드는 값으로, 이용 흐름을 잇는 데만 씁니다. 기기에서 변환(해시)한 뒤 보내며, 기기 고유번호나 광고 식별자가 아닙니다. 음료 기록(제2호)에는 이 값을 붙이지 않습니다."),
        ("기술 정보:", "앱 버전, 운영체제 버전, 언어·지역 설정"),
    ]

    private static let transfer: [(LocalizedStringResource, LocalizedStringResource)] = [
        ("이전받는 자", "TelemetryDeck GmbH (Von-der-Tann-Str. 54, 86159 Augsburg, Germany)"),
        ("이전되는 국가", "독일, 네덜란드(위탁사가 이용하는 Amazon Web Services·Hetzner의 독일 서버와 Microsoft Azure의 네덜란드 서버)"),
        ("이전 일시와 방법", "동의 후 앱 이용 시마다 암호화된 네트워크로 전송"),
        ("이전 항목", "제3조의 항목"),
        ("이용 목적", "이용 기록 저장과 통계 처리"),
        ("보유 기간", "제4조와 같음"),
        ("거부 방법", "동의하지 않거나 설정에서 \"이용 기록 제공\"을 끄면 이전되지 않습니다."),
    ]

    @ScaledMetric(relativeTo: .footnote) private var labelWidth: CGFloat = 92
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            purposeArticles
            dataArticles
            rightsArticles
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 제1조~제3조.
    @ViewBuilder
    private var purposeArticles: some View {
        heading("제1조 (목적)")
        paragraph("슈가캡(이하 \"앱\")의 운영자는 앱 기능을 개선하고 음료 메뉴 데이터를 보완하기 위하여, 이용자의 동의를 받아 아래와 같이 이용 기록을 수집·이용합니다. 이 동의는 선택 사항입니다.")

        heading("제2조 (수집·이용 목적)")
        ForEach(Self.purposes.indices, id: \.self) { index in
            numbered(index + 1, Text(Self.purposes[index]))
        }
        paragraph("수집한 정보는 위 목적 외의 용도로 이용하지 않으며, 광고·마케팅 목적으로 이용하거나 제3자에게 판매하지 않습니다.")
            .padding(.top, 6)

        heading("제3조 (수집 항목)")
        ForEach(Self.items.indices, id: \.self) { index in
            let item = Self.items[index]
            numbered(
                index + 1,
                Text(item.0).font(AppFont.pretendard(14, .bold, relativeTo: .subheadline)) + Text(verbatim: " ") + Text(item.1))
        }
        paragraph("다음 정보는 수집하지 않습니다: 이름, 연락처, 이메일, 위치, 사진, 광고 식별자, 직접 입력한 음료 이름, 음료를 기록한 정확한 시각, 기록 하나하나의 당·카페인 양.")
            .padding(.top, 6)
    }

    /// 제4조~제5조.
    @ViewBuilder
    private var dataArticles: some View {
        heading("제4조 (보유 및 이용 기간)")
        paragraph("수집한 정보는 수집일로부터 2년 동안 보유·이용하며, 기간이 끝나거나 이용자가 동의를 철회하면 지체 없이 파기합니다. 다만 이미 보낸 정보에는 이용자를 알아볼 수 있는 값이 없어 이용자별로 골라 지울 수 없으므로, 동의 철회 이후에는 새로 수집하지 않는 방식으로 처리합니다.")

        heading("제5조 (처리 위탁 및 국외 이전)")
        paragraph("운영자는 이용 기록의 저장과 분석을 아래 업체에 맡기며, 이에 따라 정보가 국외로 이전됩니다.")
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.transfer.indices, id: \.self) { index in
                let row = Self.transfer[index]
                ConsentRowLayout.of(typeSize) {
                    Text(row.0)
                        .font(AppFont.pretendard(13, .medium, relativeTo: .footnote))
                        .foregroundStyle(ConsentSummary.sub)
                        .frame(width: typeSize.isAccessibilitySize ? nil : labelWidth, alignment: .leading)
                    Text(row.1)
                        .font(AppFont.pretendard(13, .regular, relativeTo: .footnote))
                        .foregroundStyle(Color.ink.opacity(0.86))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .overlay(alignment: .top) { ConsentSummary.line.frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 8)
        paragraph("전송 과정에서 기기의 IP 주소가 위탁사 서버에 전달되지만, 위탁사는 이를 데이터베이스나 로그 파일 어디에도 저장하지 않는다고 밝히고 있습니다.")
            .padding(.top, 10)
    }

    /// 제6조~부칙.
    @ViewBuilder
    private var rightsArticles: some View {
        heading("제6조 (동의를 거부할 권리와 불이익)")
        paragraph("이용자는 이 동의를 거부할 권리가 있습니다. 동의하지 않아도 음료 기록, 마감, 캐릭터, 구독 등 앱의 모든 기능을 똑같이 이용할 수 있으며 어떠한 불이익도 없습니다.")

        heading("제7조 (동의 철회)")
        paragraph("이용자는 언제든지 앱의 설정 > 개인정보 > \"이용 기록 제공\"을 꺼서 동의를 철회할 수 있습니다. 철회하면 그 즉시 수집을 멈추고, 기기에 남아 있던 미전송 기록도 삭제합니다.")

        heading("제8조 (문의)")
        (Text("이용 기록 처리에 관한 문의:") + Text(verbatim: " \(Self.contact)"))
            .modifier(LawBody())

        heading("부칙")
        paragraph("이 동의서는 2026년 11월 19일부터 적용합니다.")
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.pretendard(15, .bold, relativeTo: .subheadline))
            .foregroundStyle(Color.ink)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text).modifier(LawBody())
    }

    private func numbered(_ number: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: "\(number).")
                .monospacedDigit()
            text
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(LawBody())
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }
}

/// 항목 이름·값 한 줄. 큰 글자에서는 이름 칸이 값을 낱말 단위로 밀어내니 이름을 값 위로 올린다.
private enum ConsentRowLayout {
    static func of(_ typeSize: DynamicTypeSize) -> AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    }
}

private struct LawBody: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppFont.pretendard(14, .regular, relativeTo: .subheadline))
            .foregroundStyle(Color.ink.opacity(0.86))
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }
}
