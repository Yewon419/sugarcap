import Foundation

/// `data/catalog.json`의 디코딩 모델. 필드 정의와 불변식의 계약서는 `data/SCHEMA.md`다.
/// snake_case는 디코더의 `.convertFromSnakeCase`가 처리한다.
struct Catalog: Decodable {
    let schemaVersion: Int
    let builtAt: String
    let brands: [Brand]
    let drinks: [Drink]

    /// `built_at`은 UTC ISO 8601. 설정 화면의 "데이터 갱신 날짜"와
    /// 원격 갱신 비교(§2.3)가 이 값을 쓴다.
    var builtAtDate: Date? {
        ISO8601DateFormatter().date(from: builtAt)
    }
}

struct Brand: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    /// 이 브랜드 수치가 어느 잔 기준인지. 상세 화면에 그대로 노출한다.
    let servingNote: String
    /// false면 해당 브랜드의 drink는 serving이 정확히 1개다(수집 단계 검증이 강제).
    let hasSizeChoice: Bool
}

struct Drink: Decodable, Identifiable, Hashable {
    let id: String
    let brandId: String
    let name: String
    let nameEn: String?
    /// 브랜드의 자체 분류명. 표준화하지 않는다.
    let category: String
    let temperature: Temperature
    let servings: [Serving]

    enum Temperature: String, Decodable {
        case hot
        case iced
        /// 브랜드가 온도를 구분해 게시하지 않았다는 뜻이다. "둘 다 가능"이 아니다.
        case both
    }
}

struct Serving: Decodable, Identifiable, Hashable {
    let id: String
    let sizeLabel: String
    /// 브랜드가 게시한 컵용량. 미게시는 nil — ml 환산·추정은 하지 않는다.
    let volumeMl: Int?
    /// nil은 0이 아니라 "브랜드 미공개"다(SCHEMA.md "null 값 처리").
    let sugarG: Double?
    /// nil은 "브랜드 미공개". 변형이 있으면 첫 변형 값과 같다.
    let caffeineMg: Double?
    /// 원두 선택에 따라 카페인이 갈리는 경우만. 현재 더벤티뿐이다.
    let caffeineVariants: [CaffeineVariant]
}

struct CaffeineVariant: Decodable, Hashable {
    let label: String
    let caffeineMg: Double
}
