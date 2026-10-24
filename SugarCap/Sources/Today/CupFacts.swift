import Foundation

/// 오늘 화면 날짜 아래 회색 한 줄(2026-10-24 대표님 "당이나 카페인에 대한 잡다 짤막한 상식").
/// 쓸데없는 잡지식·찔리는 숫자·웃고 넘길 말을 섞는다. 하루에 하나, 면마다 따로 고른다.
enum CupFacts {
    static func line(for side: CupSide, day: DayKey) -> String {
        let lines = side == .sugar ? sugar : caffeine
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        let date = Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
        let ordinal = Int(date.timeIntervalSince1970 / 86_400)
        let index = ((ordinal % lines.count) + lines.count) % lines.count
        return lines[index]
    }

    private static let sugar: [String] = [
        String(localized: "각설탕 한 개는\n3~4 g 정도예요."),
        String(localized: "적당한 당은 기분에도 좋아요.\n물론 생존에도 필요하고요."),
        String(localized: "WHO는 첨가당을\n하루 열량의 10% 아래로 권해요."),
        String(localized: "미지근해지면 같은 음료도\n더 달게 느껴져요."),
        String(localized: "당 50 g은\n각설탕 열두 개 반쯤이에요."),
        String(localized: "'혀 지도'는 사실이 아니에요.\n단맛은 혀 어디서든 느껴요."),
        String(localized: "뇌는 하루에\n포도당을 100 g 넘게 써요."),
        String(localized: "콜라 한 캔(355 ml)엔\n당이 40 g 가까이 있어요."),
        String(localized: "사람은 태어날 때부터\n단맛을 좋아해요."),
        String(localized: "과일 주스의 당도\nWHO는 첨가당과 같이 쳐요."),
        String(localized: "꿀과 시럽도\n당은 당이에요."),
        String(localized: "'디저트 배는 따로 있다'는 말,\n조금은 근거가 있어요."),
        String(localized: "달콤한 음료 한 잔이면\n하루 기준의 절반을 넘기기 쉬워요."),
        String(localized: "꿀은 잘 보관하면\n거의 상하지 않아요."),
        String(localized: "우유 한 컵(200 ml)엔\n유당이 10 g쯤 있어요."),
        String(localized: "단 걸 먹으면 뇌의 보상 회로가 반응해요.\n기분 탓만은 아니에요."),
        String(localized: "사과 한 개에도\n당이 20 g쯤 들어 있어요."),
        String(localized: "버블티 한 잔의 당은\n각설탕 열 개를 넘기도 해요."),
        String(localized: "설탕은\n사탕수수나 사탕무에서 나와요."),
        String(localized: "영양성분표 '당류'엔\n재료에 원래 든 당도 포함돼요."),
        String(localized: "단맛은 다섯 가지 기본 맛 중 하나예요.\n나머지 넷도 맛있긴 해요."),
    ]

    private static let caffeine: [String] = [
        String(localized: "에스프레소 한 샷엔\n카페인이 60 mg 안팎 있어요."),
        String(localized: "전설에 따르면\n커피 열매는 염소가 먼저 맛봤어요."),
        String(localized: "카페인이 몸에서 반으로 줄기까지\n평균 5시간쯤 걸려요."),
        String(localized: "커피가 맛있는 건 죄가 아니에요.\n숫자만 지켜 주세요."),
        String(localized: "카페인은 식물이\n벌레를 쫓으려고 만든 물질이에요."),
        String(localized: "진하게 볶은 원두라고\n카페인이 더 많은 건 아니에요."),
        String(localized: "오후 늦게 마신 커피는\n잠들 때까지 꽤 남아 있어요."),
        String(localized: "꿀벌도 카페인이 든 꽃꿀을\n더 잘 기억해요."),
        String(localized: "카페인은 마신 뒤 45분 안에\n대부분 흡수돼요."),
        String(localized: "카페인은 졸음 신호를 잠깐 막을 뿐,\n피로를 없애진 않아요."),
        String(localized: "디카페인 커피에도\n카페인이 조금 남아 있어요."),
        String(localized: "커피 마시고 바로 20분 자는\n'커피 낮잠'이란 게 있어요."),
        String(localized: "큰 사이즈 아메리카노 두 잔이면\n하루 기준에 금방 닿아요."),
        String(localized: "홍차 잎은 무게로 치면\n커피콩보다 카페인이 많아요."),
        String(localized: "커피 열매는 빨갛게 익어서\n'커피 체리'라고 불러요."),
        String(localized: "녹차와 초콜릿에도\n카페인이 들어 있어요."),
        String(localized: "카페인이 듣는 정도는\n유전자 영향도 받아요."),
        String(localized: "'커피는 석유 다음가는 교역품'이라는 말은\n사실이 아니에요."),
        String(localized: "성인 카페인 하루 권고량은\n400 mg 이하예요."),
    ]
}
