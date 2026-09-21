import SwiftUI

/// 캐릭터 정지 스프라이트 한 장(SPEC §9.4 — v1은 프레임 애니메이션 없음).
/// 탭 반응과 기준 초과 반응은 이미지 교체가 아니라 변형으로 낸다.
struct CharacterView: View {
    let side: CupSide
    /// 기준 초과 시 가볍게 아쉬워한다(§4.1). 호감도는 깎지 않고 죄책감 문구도 없다.
    let isOverLimit: Bool

    @State private var isPoked = false

    var body: some View {
        Image(side.characterAsset)
            .resizable()
            .scaledToFit()
            .scaleEffect(isPoked ? 1.12 : (isOverLimit ? 0.94 : 1))
            .rotationEffect(.degrees(isOverLimit ? -8 : 0), anchor: .bottom)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isOverLimit)
            .contentShape(Rectangle())
            .onTapGesture(perform: poke)
            .accessibilityElement()
            .accessibilityLabel(side.characterName)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "쓰다듬기", poke)
    }

    private func poke() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
            isPoked = true
        }
        Task {
            // 취소는 화면을 벗어났다는 뜻이라 되돌릴 필요도 없다.
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                isPoked = false
            }
        }
    }
}

#Preview {
    HStack {
        CharacterView(side: .sugar, isOverLimit: false)
        CharacterView(side: .caffeine, isOverLimit: true)
    }
    .frame(height: 160)
    .padding()
}
