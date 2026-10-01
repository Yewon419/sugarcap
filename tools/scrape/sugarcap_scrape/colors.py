"""Liquid colour for the drink thumbnail (SPEC §9.7, 2026-10-01).

No brand publishes a drink colour and 18k drinks cannot be checked one by one,
so the colour is read from the name: the first rule whose keyword appears in
the drink name wins, then the same rules run on the brand's category, then a
neutral default. Rule order is the whole design: flavours that dye the drink
(딸기, 말차, 초코) come before the bases they are mixed into (우유, 라떼, 커피),
and the more specific word comes before the word it contains (청포도 before
포도, 밀크티 before 홍차).

This is a display hint, not nutrition data, so a wrong guess costs only a
slightly off thumbnail.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


@dataclass(frozen=True)
class ColorRule:
    """Keywords are regular expressions, matched case-insensitively anywhere in the text."""

    keywords: tuple[str, ...]
    color: str
    pattern: re.Pattern[str] = field(init=False, repr=False, compare=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "pattern", re.compile("|".join(self.keywords), re.IGNORECASE))


COFFEE = "#4A2C1D"
ESPRESSO = "#2E1B12"
LATTE = "#C49A6C"
MILK = "#F4EFE6"
MILK_TEA = "#C8A27C"
TEA = "#B5651D"
GREEN_TEA = "#8DB255"
CHOCO = "#6B3E26"
CLEAR = "#DCE8EE"
FRUIT = "#F2A541"
CREAM = "#EADBC8"
DEFAULT = "#D9C2A0"

RULES: tuple[ColorRule, ...] = (
    # Coloured flavours first: they dye milk, latte and tea bases.
    ColorRule(("청포도", "샤인머스캣", "머스캣", "그린애플", "청사과"), "#B8D86B"),
    ColorRule(("블루베리",), "#4B3B7A"),
    ColorRule(("블루레몬", "블루 레몬", "블루하와이", "블루큐라소", "블루"), "#3E8EDE"),
    ColorRule(("딸기", "스트로베리", "strawberry"), "#E8587A"),
    ColorRule(("라즈베리", "크랜베리", "석류", "체리", "베리", "오미자", "히비스커스"), "#C0283E"),
    ColorRule(("수박", "토마토"), "#E5413A"),
    ColorRule(("자몽", "그레이프프루트"), "#F06B5B"),
    ColorRule(("비트", "자색", "용과"), "#9C2A6B"),
    ColorRule(("포도", "그레이프", "grape", "와인"), "#6A2C70"),
    ColorRule(("복숭아", "피치", "peach", "살구"), "#F7A57A"),
    ColorRule(("망고", "패션후르츠", "패션프루트", "파인애플", "트로피컬"), "#F7B32B"),
    ColorRule(("오렌지", "한라봉", "천혜향", "감귤", "귤", "당근", "orange"), "#F5871F"),
    ColorRule(("유자", "레몬", "lemon", "라임", "생강", "진저"), "#F3D34A"),
    ColorRule(("바나나", "banana"), "#F6E08A"),
    ColorRule(("키위", "케일", "녹즙", "알로에", "오이"), "#9CC63B"),
    ColorRule(("민트", "mint"), "#9ED9C3"),
    ColorRule(("코코넛 ?워터", "coconut water"), CLEAR),
    ColorRule(("말차", "녹차", "그린티", "matcha", "green tea"), GREEN_TEA),
    ColorRule(("흑임자", "쿠키", "오레오", "쿠앤크"), "#8C8580"),
    ColorRule(
        ("초코", "초콜릿", "초콜렛", "쇼콜라", "코코아", "모카", "chocolate", "choco", "mocha"),
        CHOCO,
    ),
    ColorRule(("흑당", "카라멜", "캐러멜", "caramel", "달고나", "토피"), "#B07A3B"),
    ColorRule(("고구마",), "#C9A07A"),
    ColorRule(("보리차", "옥수수차", "옥수수수염", "헛개", "결명자", "둥굴레"), "#C98B3A"),
    ColorRule(
        ("미숫가루", "곡물", "corn", "오곡", "검은콩", "옥수수", "보리", "누룽지", "인절미"), CREAM
    ),
    ColorRule(("홍삼", "인삼", "쌍화", "대추"), "#7A3B1E"),
    ColorRule(("식혜", "수정과"), "#E8D9B0"),
    ColorRule(("매실", "사과", "애플", "apple", "모과"), "#E2B65A"),
    ColorRule(("밀크티", "milk tea", "로얄밀크", "타로", "버블티"), MILK_TEA),
    # Coffee: milky coffee before black coffee, both after every flavour above.
    ColorRule(
        (
            "라떼",
            "latte",
            "카푸치노",
            "cappuccino",
            "마키아또",
            "macchiato",
            "플랫화이트",
            "flat white",
            "아인슈페너",
            "카페오레",
            "프라푸치노",
            "frappuccino",
            "커피우유",
            "커피 우유",
            "밀크커피",
            "맥심",
            "조지아",
            "칸타타",
            "바리스타",
        ),
        LATTE,
    ),
    ColorRule(("에스프레소", "espresso", "리스트레토", "도피오"), ESPRESSO),
    ColorRule(
        (
            "아메리카노",
            "americano",
            "콜드브루",
            "cold brew",
            "브루",
            "블랙",
            "black",
            "커피",
            "coffee",
        ),
        COFFEE,
    ),
    ColorRule(("콜라(?!겐)", "cola", "펩시", "pepsi", "코크", "닥터페퍼", "루트비어"), "#3B1F14"),
    ColorRule(
        ("얼그레이", "홍차", "아쌈", "다즐링", "black tea", "earl grey", "우롱", "보이차"), TEA
    ),
    ColorRule(("캐모마일", "카모마일", "루이보스", "허브", "자스민", "재스민"), "#D9A441"),
    ColorRule(("두유", "soy", "아몬드", "오트", "귀리", "호두", "땅콩"), "#E6D3B3"),
    ColorRule(
        ("요거트", "요구르트", "yogurt", "플레인", "요플레", "야쿠르트", "유산균"), "#F7F3EA"
    ),
    ColorRule(("바닐라", "vanilla", "크림", "cream", "쉐이크", "shake", "코코넛"), "#F1E6CF"),
    ColorRule(("우유", "milk", "밀크", "밀키스"), MILK),
    ColorRule(
        (
            "사이다",
            "탄산수",
            "스파클링",
            "sparkling",
            "토닉",
            "소다",
            "soda",
            "이온",
            "포카리",
            "게토레이",
            "파워에이드",
            "토레타",
            "생수",
            "워터",
            "water",
            "제로",
        ),
        CLEAR,
    ),
    ColorRule(("에너지", "몬스터", "핫식스", "레드불", "박카스", "비타", "energy"), "#E3C93C"),
)

# Broad words that also hide inside unrelated names (티 in 에티오피아). They run on
# the category before the name, so a café's own 커피/티 category decides first.
GENERIC_RULES: tuple[ColorRule, ...] = (
    ColorRule(("에이드", "ade", "주스", "juice", "과일", "피지오", "리프레셔", "fruit"), FRUIT),
    ColorRule(
        ("스무디", "smoothie", "프라페", "블렌디드", "플랫치노", "빽스치노", "할리치노"), CREAM
    ),
    ColorRule(("티", "tea", "차"), TEA),
)

# K-FIND 대표식품명 for convenience-store drinks whose names hit no rule.
CATEGORY_COLORS: dict[str, str] = {
    "액상커피": LATTE,
    "액상차": TEA,
    "과·채주스": FRUIT,
    "과·채음료": FRUIT,
    "탄산음료": CLEAR,
    "탄산수": CLEAR,
    "인삼/홍삼음료": "#7A3B1E",
    "두유": "#E6D3B3",
    "발효음료": "#F7F3EA",
    "유산균음료": "#F7F3EA",
    "효모음료": "#F1E6CF",
    "발효유": "#F7F3EA",
    "우유": MILK,
    "우유(멸균)": MILK,
    "가공우유": MILK,
    "가공우유(멸균)": MILK,
    "강화우유": MILK,
    "유당분해우유": MILK,
}


def _match(text: str, rules: tuple[ColorRule, ...]) -> str | None:
    for rule in rules:
        if rule.pattern.search(text):
            return rule.color
    return None


def liquid_color(name: str, category: str) -> str:
    """'#RRGGBB' for the drink thumbnail.

    Specific words in the name, then the K-FIND category table, then every rule
    on the category, then broad words in the name, then a neutral default.
    """
    return (
        _match(name, RULES)
        or CATEGORY_COLORS.get(category)
        or _match(category, RULES + GENERIC_RULES)
        or _match(name, GENERIC_RULES)
        or DEFAULT
    )
