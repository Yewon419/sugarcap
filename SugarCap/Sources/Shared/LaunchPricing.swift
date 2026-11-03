/// 출시 가격 정책. 켜져 있으면 결제 없이 Pro 기능이 전부 열린다(대표님 2026-11-03 "유저 좀 모일 때까지는 기능 다 풀어둘거야").
/// 앱(`ProStore`)과 위젯(`SharedDefaults.isPro`)이 같이 본다. 끄면 원래 Pro 잠금·페이월로 돌아간다(SPEC §6).
/// CI 스크린샷·UI 테스트의 `-mockPro`·`-mockProOwned` 목 상태는 이 값과 상관없이 흉내 낸 대로 그린다.
enum LaunchPricing {
    static let everythingFree = true
}
