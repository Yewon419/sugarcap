import SwiftUI

/// 최소 버전보다 낮을 때 앱 전체를 대신하는 화면(대표님 2026-11-22). 닫거나 넘길 길이 없다.
/// 루트가 오늘·온보딩 대신 이것만 그려서, 열려 있던 시트도 같이 내려간다.
struct UpdateGateView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text("업데이트").kicker()
            Text("중요한 업데이트가 있어요")
                .font(AppFont.pretendard(30, .extraBold, relativeTo: .largeTitle))
                .tracking(AppFont.displayTracking(for: 30))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text("업데이트해야 계속 쓸 수 있어요. 기록은 그대로 남아 있어요.")
                .font(AppFont.pretendard(15, .regular, relativeTo: .body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Spacer(minLength: 24)
            Button {
                openURL(UpdateSource.appStoreURL)
            } label: {
                Text("App Store에서 업데이트")
                    .font(AppFont.pretendard(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.ink, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("update-required-open")
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .accessibilityIdentifier("update-required")
    }
}

/// 새 버전이 있을 때 오늘 화면 왼쪽 위에 늘 떠 있는 안내(닫기 없음, 대표님 2026-11-22). 누르면 App Store.
struct UpdateBadge: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(UpdateSource.appStoreURL)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("새로운 업데이트가 있습니다")
                    .font(AppFont.pretendard(13, .semibold, relativeTo: .footnote))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        // 오른쪽 모서리 버튼은 글자 크기를 안 따라 커진다. 안내만 커지면 날짜 줄을 덮었다(2026-11-22 AX-XL 스크린샷).
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityIdentifier("update-available")
    }
}
