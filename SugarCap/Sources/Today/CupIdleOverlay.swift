import AVFoundation
import SwiftUI
import UIKit

/// 가만히 있는 컵의 대기 루프(SPEC §9-10). 단계 사진 위, 얼음이 움직이는 윗부분에만 영상을 겹친다.
/// 번들에 `<에셋>-idle.mp4`·`<에셋>-idle.json`(캔버스 좌표 사각형)·`<에셋>-idle-mask` 이미지가 있는 단계만 돈다.
/// 만드는 법은 `design/assets/cups/make_idle_patch.py`.
///
/// 단계 사진(`resizable().scaledToFill()`)의 overlay로 붙인다. 그 틀이 937×1666 캔버스를 그대로 비례 확대한 크기다.
struct CupIdleOverlay: View {
    private let loop: CupIdleLoop?

    init(assetName: String) {
        loop = CupIdleLoop(assetName: assetName)
    }

    var body: some View {
        if let loop {
            GeometryReader { proxy in
                let scale = proxy.size.width / CupIdleLoop.canvasWidth
                LoopingVideo(url: loop.videoURL)
                    .frame(width: loop.rect.width * scale, height: loop.rect.height * scale)
                    .mask(Image(loop.maskAsset).resizable())
                    .offset(x: loop.rect.minX * scale, y: loop.rect.minY * scale)
            }
            .allowsHitTesting(false)
        }
    }
}

private struct CupIdleLoop {
    static let canvasWidth: CGFloat = 937
    /// 꺼 둠(2026-09-28 대표님): 100% 잔 사진을 다시 뽑는 중이라 지금 영상(옛 사진 기준)이 새 사진과 안 맞는다.
    /// 새 사진으로 대기 루프 영상을 다시 만든 뒤 true로 켠다.
    static let isEnabled = false

    let videoURL: URL
    let maskAsset: String
    let rect: CGRect

    private struct Placement: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    init?(assetName: String) {
        let base = "\(assetName)-idle"
        guard
            Self.isEnabled,
            let video = Self.resource(base, "mp4"),
            let json = Self.resource(base, "json"),
            let data = try? Data(contentsOf: json),
            let placement = try? JSONDecoder().decode(Placement.self, from: data)
        else { return nil }
        videoURL = video
        maskAsset = "\(base)-mask"
        rect = CGRect(x: placement.x, y: placement.y, width: placement.width, height: placement.height)
    }

    /// XcodeGen은 Resources 하위 폴더를 그룹으로 넣어 번들 루트에 풀어 놓는다. 폴더 참조일 때를 대비해 둘 다 찾는다.
    private static func resource(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "CupIdle")
    }
}

private struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerView {
        LoopingPlayerView(url: url)
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {}
}

/// 소리 없는 영상을 끝없이 돌린다. 첫 프레임이 뜨기 전엔 투명해서 밑의 정지 사진이 그대로 보인다.
final class LoopingPlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        player.isMuted = true
        // 화면 꺼짐을 막지 않는다(장식 영상이다).
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        if let playerLayer = layer as? AVPlayerLayer {
            playerLayer.player = player
            playerLayer.videoGravity = .resize
        }
        // 백그라운드에 다녀오면 멈춰 있으니 다시 튼다.
        NotificationCenter.default.addObserver(
            self, selector: #selector(resume),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
        player.play()
    }

    required init?(coder: NSCoder) { nil }

    @objc private func resume() {
        player.play()
    }
}
