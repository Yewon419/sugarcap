import OSLog
import SwiftData
import SwiftUI

/// 설정(SPEC §4.4). 오늘 화면 모서리 버튼으로 여는 시트다(2026-10-05 하단 탭 제거).
/// 2026-10-05 프로토타입 v4 확정 = 네이티브 목록 하나. 하루 기준·조금씩 줄이기는 추이 화면으로 옮겼다(대표님 "설정 탭에 안 어울리는 기능").
/// 시간 → Pro·복원·소개·개인정보 → 테스트(TestFlight·Debug만).
struct SettingsView: View {
    let catalog: Catalog
    /// 테스트 카드에서 고른 일. 오늘 화면이 시트를 닫은 뒤 실행한다.
    let onTestAction: (SettingsTestAction) -> Void

    @Query private var settingsRows: [AppSettings]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                // 설정 행은 루트가 첫 프레임에 만든다(`RootView.ensureSettings`).
                if let settings = settingsRows.first {
                    SettingsContent(settings: settings, catalog: catalog, onTestAction: onTestAction)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("settings-close")
                }
            }
        }
    }
}

/// 시각 선택지. 하루 경계는 새벽, 마감 가능 시각은 저녁으로만 연다.
/// 경계를 낮으로 옮기면 "하루"의 뜻이 무너지고, 마감을 낮에 열면 이른 마감 방지(§4.7)가 무의미해진다.
enum HourChoices {
    static let dayBoundary = Array(0...6)
    static let closeFrom = Array(18...23)

    static func label(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

private struct SettingsContent: View {
    @Bindable var settings: AppSettings
    let catalog: Catalog
    let onTestAction: (SettingsTestAction) -> Void

    @State private var showsPaywall = false
    @State private var showsOnboarding = false
    @State private var isRestoring = false
    @State private var alertMessage: String?
    @State private var isTestBuild = false
    @State private var confirmsFirstRun = false

    @Query private var affinities: [Affinity]
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var pro

    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "settings")

    var body: some View {
        List {
            Section {
                hourPicker("하루가 바뀌는 시각", selection: $settings.dayBoundaryHour, choices: HourChoices.dayBoundary)
                hourPicker("오늘 마감을 여는 시각", selection: $settings.closeFromHour, choices: HourChoices.closeFrom)
            } footer: {
                Text("하루가 바뀌는 시각 전에 마신 음료는 전날 몫으로 들어가요.")
            }

            Section {
                proRow
                Button {
                    restore()
                } label: {
                    HStack {
                        Text("구매 복원")
                        Spacer()
                        if isRestoring { ProgressView() }
                    }
                    .rowText()
                }
                .disabled(isRestoring)
                .accessibilityIdentifier("restore-purchases")
                Button {
                    showsOnboarding = true
                } label: {
                    linkRow("앱 소개 다시 보기", trailing: "chevron.right")
                }
                .accessibilityIdentifier("replay-onboarding")
                if let privacy = AppLinks.privacyPolicy {
                    Link(destination: privacy) {
                        linkRow("개인정보처리방침", trailing: "arrow.up.right")
                    }
                }
            } footer: {
                Text("기록은 이 기기에만 저장돼요. 수집하는 정보는 없어요.")
            }

            if isTestBuild { testSection }

            // 편의점 음료 출처 표기는 필수다(SPEC §2, 식약처 공공데이터).
            Section {
            } footer: {
                VStack(spacing: 4) {
                    Text("슈가캡 \(Self.appVersion) · 메뉴 데이터 \(catalog.builtAtDate?.formatted(date: .abbreviated, time: .omitted) ?? catalog.builtAt)")
                    Text("편의점 음료: 식품의약품안전처 식품영양성분 데이터베이스")
                }
                .font(AppFont.pretendard(11, .regular, relativeTo: .caption2))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.wall.ignoresSafeArea())
        .task { isTestBuild = await TestBuild.isActive() }
        .confirmationDialog("첫 실행으로 되돌릴까요?", isPresented: $confirmsFirstRun, titleVisibility: .visible) {
            Button("되돌리기", role: .destructive) { onTestAction(.firstRun) }
                .accessibilityIdentifier("confirm-first-run")
        } message: {
            Text("기록은 그대로 두고 앱 소개와 로슈·카인 소개를 처음부터 다시 봐요.")
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(feature: nil)
        }
        .alert(
            alertMessage ?? "",
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        }
        // 온보딩 화면을 그대로 전체 화면으로 띄운다. 완료 플래그는 건드리지 않는다.
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView(
                brands: catalog.brands,
                onStart: { showsOnboarding = false },
                onClose: { showsOnboarding = false }
            )
        }
    }

    /// 테스트 카드(2026-10-05 프로토 v4). 먹이기·정산은 저장 없이 열고, Pro 흉내는 앱을 다시 켜면 꺼진다.
    private var testSection: some View {
        Section {
            Button("먹이기 바로 보기") { onTestAction(.feeding) }
                .font(AppFont.pretendard(16, .regular, relativeTo: .body))
                .accessibilityIdentifier("test-feeding")
            Button("어제 정산 바로 보기") { onTestAction(.yesterdayGate) }
                .font(AppFont.pretendard(16, .regular, relativeTo: .body))
                .accessibilityIdentifier("test-yesterday")
            Toggle("Pro 켠 것처럼", isOn: Binding(get: { pro.isProSimulated }, set: { pro.simulatePro($0) }))
                .rowText()
                .accessibilityIdentifier("test-pro")
            affinityStepper(.sugar)
            affinityStepper(.caffeine)
            Button("첫 실행으로 되돌리기", role: .destructive) { confirmsFirstRun = true }
                .font(AppFont.pretendard(16, .regular, relativeTo: .body))
                .accessibilityIdentifier("test-first-run")
        } header: {
            Text("테스트 · TestFlight에서만 보여요")
        } footer: {
            Text("여기서 연 먹이기와 정산은 기록에 남지 않아요.")
        }
    }

    /// 호감도 단계를 바로 바꾼다. 그 단계의 시작 점수로 맞춘다.
    private func affinityStepper(_ side: CupSide) -> some View {
        let level = affinities.first { $0.character == side.characterID }?.level ?? 1
        return Stepper(
            value: Binding(get: { level }, set: { setAffinity(side, level: $0) }),
            in: 1...AffinityMath.maxLevel
        ) {
            HStack {
                Text("\(side.characterName) 호감도")
                Spacer()
                Text("\(level)단계").monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .rowText()
    }

    private func setAffinity(_ side: CupSide, level: Int) {
        do {
            let affinity = try SettlementStore.affinity(for: side, in: context)
            affinity.points = AffinityMath.threshold(level: level)
            try context.save()
        } catch {
            Self.logger.error("호감도 바꾸기 실패(\(side.rawValue, privacy: .public) \(level)): \(String(describing: error), privacy: .public)")
            context.rollback()
            alertMessage = "호감도를 바꾸지 못했어요."
        }
    }

    /// 시각 행. 값은 메뉴 피커라 한 번에 고른다.
    private func hourPicker(_ title: String, selection: Binding<Int>, choices: [Int]) -> some View {
        Picker(title, selection: selection) {
            ForEach(choices, id: \.self) { hour in
                Text(HourChoices.label(hour)).tag(hour)
            }
        }
        .pickerStyle(.menu)
        .rowText()
    }

    @ViewBuilder
    private var proRow: some View {
        if pro.isPro {
            HStack {
                Text("슈가캡 Pro")
                Spacer()
                Text("사용 중").foregroundStyle(.secondary)
            }
            .rowText()
            .accessibilityElement(children: .combine)
        } else {
            Button {
                showsPaywall = true
            } label: {
                HStack {
                    Text("슈가캡 Pro")
                    Spacer()
                    Text("알아보기").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .rowText()
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("open-paywall")
        }
    }

    private func linkRow(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: trailing)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .rowText()
        .contentShape(Rectangle())
    }

    /// 결과를 이 화면에서 바로 알린다. 페이월 밖에서는 `store.failure`가 그려지지 않는다.
    private func restore() {
        isRestoring = true
        Task {
            await pro.restore()
            isRestoring = false
            alertMessage = pro.isPro ? "구매를 복원했어요." : (pro.failure ?? "복원할 구매가 없어요.")
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

private extension View {
    /// 목록 행 글자. 버튼 행이 액센트 색으로 칠해지지 않게 잉크로 둔다.
    func rowText() -> some View {
        font(AppFont.pretendard(16, .regular, relativeTo: .body))
            .foregroundStyle(Color.ink)
    }
}
