import AVFoundation
import Combine
import OSLog
import SwiftUI

/// 로슈·카인 소개(SPEC §4.7). 첫 마감(먹이기) 직전에 한 번만 나온다. 온보딩 영상 마지막 문장 "오늘의 분량을 남기면 특별한 일이 생긴다던데..."의 답이다.
/// v3(2026-10-27 대표님 확정): 방 조명 아래 매거진 지면을 근접 촬영한 8.2초 무음 영상. 시선이 지면을 훑다가 로슈(손 흔들기)·카인(사진에서
/// 뛰어내려 뒤뚱 세 걸음)에서 멈춘다. 원본은 HyperFrames 프로젝트(`C:\hfwork\sugarcap-mag`)의 렌더(진행 막대·Skip은 빼고 렌더).
/// 끝나면 버튼 없이 바로 먹이기 화면으로 넘어가고, 건너뛰기도 같은 곳으로 간다. 두 캐릭터 이름은 첫 먹이기 튜토리얼이 알려 준다.
struct CompanionIntroView: View {
    let onFinish: () -> Void
    /// 스크린샷용(Debug 인자). 이 시각의 프레임에 멈춰 둔다.
    var frozenAt: Double?

    static let videoName = "companion-intro"
    private static let logger = Logger(subsystem: "com.sugarcap.app", category: "intro")

    @State private var player: AVPlayer?
    @State private var didFinish = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                IntroVideoLayer(player: player).ignoresSafeArea()
            }
        }
        .overlay(alignment: .topTrailing) { skipButton }
        .onAppear(perform: start)
        .onDisappear { player?.pause() }
        // 끝 알림은 재생 스레드에서 온다. 화면 상태를 바꾸니 메인에서 받는다.
        .onReceive(
            NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification).receive(on: DispatchQueue.main)
        ) { note in
            guard frozenAt == nil, let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            finish()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("로슈와 카인 소개. 남긴 당은 로슈가, 남긴 카페인은 카인이 먹어요. 많이 남길수록 더 가까워져요.")
    }

    /// 영상 위라 바탕이 밝은 지면·어두운 방을 오간다. 흰 글자에 그림자를 깔아 둘 다에서 읽힌다.
    private var skipButton: some View {
        Button("건너뛰기", action: finish)
            .font(AppFont.pretendard(14, .medium, relativeTo: .footnote))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
            .tapTarget()
            .padding(.trailing, 20)
            .padding(.top, 8)
            .accessibilityIdentifier("intro-skip")
    }

    private func start() {
        guard player == nil, !didFinish else { return }
        // 모션 줄이기: 카메라가 휙휙 움직이는 영상이라 통째로 건너뛴다. 이름은 튜토리얼이 알려 준다.
        if reduceMotion && frozenAt == nil {
            finish()
            return
        }
        guard let url = Bundle.main.url(forResource: Self.videoName, withExtension: "mp4") else {
            // 번들에 영상이 없으면 소개 없이 먹이기로 넘어간다. 빌드 설정 문제라 크게 남긴다.
            Self.logger.fault("소개 영상이 번들에 없음: \(Self.videoName, privacy: .public).mp4")
            finish()
            return
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player
        if let frozenAt {
            player.seek(to: CMTime(seconds: frozenAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.play()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        player?.pause()
        onFinish()
    }
}

/// 영상 한 장을 화면 가득(가로는 잘림) 그린다. 컨트롤 없는 `AVPlayerLayer`. 온보딩 영상도 같이 쓴다.
struct IntroVideoLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
