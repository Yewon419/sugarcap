import SwiftUI

/// 온보딩 영상(2026-10-28 대표님 확정): 매거진 12쪽을 카메라가 훑으며 앱 온보딩 7줄을 장면 문장으로 쓰는 22초 무음 영상.
/// 원본은 HyperFrames 프로젝트(`C:\hfwork\sugarcap-onboard`)이고, 앱용은 아이폰 비율(1080×2340)로 따로 렌더했다(`app_page.py`).
/// 가로 구도는 9:16판과 같고 위아래만 더 보인다. 한국어가 아니면 영어판을 쓴다(번체판 없음, 대표님 결정).
/// 마지막 빼꼼(로슈·카인)은 영상에서 빼고 앱이 화면 가장자리에 직접 그린다. 영상을 화면에 채우면 좌우가 잘려 가장자리 그림이 사라져서다.
enum OnboardingFilm {
    /// 장면 시작(영상의 BEAT). 화면을 누르면 다음 장면 시작으로 간다.
    static let chapters = ReelChapters(starts: [0, 2.6, 5.2, 7.8, 10.4, 13.0, 15.6, 18.2], end: 22)
    static let stage = CGSize(width: 1080, height: 2340)

    static var videoName: String {
        Bundle.main.preferredLocalizations.first == "ko" ? "onboarding-ko" : "onboarding-en"
    }

    /// 화면 위쪽이 어두운 방(지면 밖)인 구간. 진행 막대·건너뛰기를 흰색으로 바꾼다.
    static func isTopDark(at t: Double) -> Bool {
        t < 2.55 || (t > 18.35 && t < 19.55)
    }

    /// 빼꼼: 끝나기 0.7초 전에 둘이 동시에 0.2초 만에 나온다(영상 원본과 같은 값, 무대 좌표).
    static let peekStart = chapters.end - 0.7
    static let peekDuration = 0.2
}

/// 영상 위에 겹치는 빼꼼 층. 영상과 같은 화면 채우기(높이 맞춤, 좌우 잘림) 배율을 쓰되, 가로는 무대가 아니라 실제 화면 가장자리에 붙인다.
struct OnboardingPeekLayer: View {
    let t: Double

    // 무대 좌표(1080×2340). 9:16판(1920) 위치를 화면 가운데 기준으로 옮긴 값.
    private static let kainHeight = 242.0
    private static let kainWidth = kainHeight * 953 / 1962
    private static let kainLeft = -120.0
    private static let kainTop = 790.0
    private static let roshuHeight = 217.0
    private static let roshuWidth = roshuHeight * 669 / 1900
    private static let roshuTop = 1320.0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = max(size.width / OnboardingFilm.stage.width, size.height / OnboardingFilm.stage.height)
            let top = (size.height - OnboardingFilm.stage.height * scale) / 2
            let k = Motion.seg(t, OnboardingFilm.peekStart, OnboardingFilm.peekStart + OnboardingFilm.peekDuration, Ease.power2Out)
            ZStack(alignment: .topLeading) {
                Image("onboarding-peek-kain")
                    .resizable()
                    .frame(width: Self.kainWidth * scale, height: Self.kainHeight * scale)
                    .rotationEffect(.degrees(42), anchor: .bottom)
                    .offset(x: (Self.kainLeft + Motion.lerp(-260, 0, k)) * scale, y: top + Self.kainTop * scale)
                Image("onboarding-peek-roshu")
                    .resizable()
                    .frame(width: Self.roshuWidth * scale, height: Self.roshuHeight * scale)
                    .offset(x: size.width + (Motion.lerp(95, 6, k) - Self.roshuWidth) * scale, y: top + Self.roshuTop * scale)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .opacity(t >= OnboardingFilm.peekStart ? 1 : 0)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
