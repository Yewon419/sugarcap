import SwiftUI

/// Phase 1a 플레이스홀더. 빌드·서명·TestFlight 업로드 경로를 확인하는 용도다.
/// Phase 1c에서 오늘 화면으로 교체한다.
struct RootView: View {
    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            Text("슈가캡")
                .font(.largeTitle.bold())
            Text(versionLine)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    RootView()
}
