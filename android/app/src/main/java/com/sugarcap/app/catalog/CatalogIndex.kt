package com.sugarcap.app.catalog

import com.sugarcap.app.brand.DrinkQuery
import com.sugarcap.app.brand.DrinkSearchName
import com.sugarcap.app.brand.DrinkSearchRank
import com.sugarcap.app.brand.searchNames

/** 기록 시트 검색에 걸린 브랜드. `menuQuery`는 브랜드 이름 뒤에 이어 친 말이다. */
data class BrandMatch(val brand: Brand, val menuQuery: String) {
    val id: String get() = brand.id
}

/** 화면이 쓰는 조회용 색인. 카탈로그는 불변이라 한 번만 만든다. iOS CatalogStore.swift의 CatalogIndex와 같다. */
class CatalogIndex(val catalog: Catalog) {
    private val brandsById: Map<String, Brand> = catalog.brands.associateBy { it.id }
    private val drinksByBrandId: Map<String, List<Drink>> = catalog.drinks.groupBy { it.brandId }
    private val servingsById: Map<String, Serving> = catalog.drinks.flatMap { it.servings }.associateBy { it.id }
    private val drinksByServingId: Map<String, Drink> =
        catalog.drinks.flatMap { drink -> drink.servings.map { it.id to drink } }.toMap()
    private val searchNamesByDrinkId: Map<String, List<DrinkSearchName>> =
        catalog.drinks.associate { it.id to it.searchNames }
    private val flagshipDrinkIds: Set<String> =
        catalog.drinks.filter { flagshipMenus[it.brandId]?.contains(it.name) == true }.map { it.id }.toSet()

    fun brand(id: String): Brand? = brandsById[id]

    fun drinks(brandId: String): List<Drink> = drinksByBrandId[brandId].orEmpty()

    fun serving(id: String): Serving? = servingsById[id]

    fun drink(servingId: String): Drink? = drinksByServingId[servingId]

    /** 기록 시트 검색(브랜드 전체), 최대 `limit`개. 같은 순위 안에서는 카페 → 편의점, 그다음 브랜드 격자 순서. */
    fun search(text: String, limit: Int = 60): List<Drink> {
        val query = DrinkQuery(text)
        if (query.isEmpty) return emptyList()
        return ranked(catalog.brands.flatMap { drinks(it.id) }, query).take(limit)
    }

    /**
     * 기록 시트 검색어에 걸린 브랜드. 띄어쓰기·대소문자는 무시하고 브랜드 격자 순서다.
     * 한 글자는 이름 앞부분만 잡는다.
     */
    fun brandMatches(text: String): List<BrandMatch> {
        val needle = DrinkQuery.fold(text)
        if (needle.isEmpty()) return emptyList()
        return catalog.brands.mapNotNull { brand -> brandMatch(brand, text, needle) }
    }

    private fun brandMatch(brand: Brand, text: String, needle: String): BrandMatch? {
        val name = DrinkQuery.fold(brand.name)
        if (name.startsWith(needle) || (needle.length >= 2 && name.contains(needle))) return BrandMatch(brand, "")
        val aliases = brandAliases[brand.id].orEmpty()
        if (needle.length >= 2 && aliases.any { it.startsWith(needle) }) return BrandMatch(brand, "")
        for (prefix in listOf(name) + aliases) {
            if (!needle.startsWith(prefix)) continue
            remainder(text, prefix)?.let { return BrandMatch(brand, it) }
        }
        return null
    }

    /** 브랜드 안 검색. 빈 검색어면 브랜드 메뉴 전체. 같은 순위 안에서는 카탈로그 순서다. */
    fun drinks(brandId: String, matching: DrinkQuery): List<Drink> {
        if (matching.isEmpty) return drinks(brandId)
        return ranked(drinks(brandId), matching)
    }

    private fun searchNames(drink: Drink): List<DrinkSearchName> = searchNamesByDrinkId[drink.id] ?: drink.searchNames

    /** 글자로 하나도 안 걸리면 자음만 친 검색어는 초성으로, 나머지는 자판 키로 다시 찾는다. */
    private fun ranked(drinks: List<Drink>, query: DrinkQuery): List<Drink> {
        val found = rankedByText(drinks, query)
        if (found.isNotEmpty()) return found
        return if (query.firstSounds == null) rankedByKeys(drinks, query) else rankedByFirstSounds(drinks, query)
    }

    private class FirstSoundRow(
        val isFlagship: Boolean,
        val isPrefix: Boolean,
        val isStore: Boolean,
        val length: Int,
        val offset: Int,
        val drink: Drink,
    )

    /** 대표 메뉴 → 첫소리가 검색어로 시작 → 카페 → 짧은 이름 순. */
    private fun rankedByFirstSounds(drinks: List<Drink>, query: DrinkQuery): List<Drink> =
        drinks.withIndex()
            .mapNotNull { (offset, drink) ->
                query.firstSoundMatch(searchNames(drink))?.let {
                    FirstSoundRow(drink.id in flagshipDrinkIds, it.isPrefix, drink.brandId == CONVENIENCE_STORE_ID, it.length, offset, drink)
                }
            }
            .sortedWith(compareBy({ !it.isFlagship }, { !it.isPrefix }, { it.isStore }, { it.length }, { it.offset }))
            .map { it.drink }

    private class TextRow(
        val rank: DrinkSearchRank,
        val isFlagship: Boolean,
        val isStore: Boolean,
        val offset: Int,
        val drink: Drink,
    )

    private fun rankedByText(drinks: List<Drink>, query: DrinkQuery): List<Drink> =
        drinks.withIndex()
            .mapNotNull { (offset, drink) ->
                query.rank(searchNames(drink), drink.temperature)?.let {
                    TextRow(it, drink.id in flagshipDrinkIds, drink.brandId == CONVENIENCE_STORE_ID, offset, drink)
                }
            }
            .sortedWith(
                compareBy(
                    { it.rank.isScattered },
                    { !it.rank.isExact },
                    { !it.isFlagship },
                    { it.isStore },
                    { it.rank },
                    { it.offset },
                ),
            )
            .map { it.drink }

    private class KeyRow(
        val typos: Int,
        val isFlagship: Boolean,
        val isStore: Boolean,
        val length: Int,
        val offset: Int,
        val drink: Drink,
    )

    /** 틀린 키가 적은 것 → 대표 메뉴 → 카페 → 짧은 이름 순. */
    private fun rankedByKeys(drinks: List<Drink>, query: DrinkQuery): List<Drink> =
        drinks.withIndex()
            .mapNotNull { (offset, drink) ->
                val names = searchNames(drink)
                query.typos(names)?.let { typos ->
                    val length = names.minOfOrNull { it.keys.size } ?: 0
                    KeyRow(typos, drink.id in flagshipDrinkIds, drink.brandId == CONVENIENCE_STORE_ID, length, offset, drink)
                }
            }
            .sortedWith(compareBy({ it.typos }, { !it.isFlagship }, { it.isStore }, { it.length }, { it.offset }))
            .map { it.drink }

    /** 브랜드 메뉴 분류 칩: 메뉴가 많은 분류부터. 같은 수면 이름순. */
    fun categories(brandId: String): List<String> {
        val counts = drinks(brandId).groupingBy { it.category }.eachCount()
        return counts.keys.sortedWith(compareByDescending<String> { counts.getValue(it) }.thenBy { it })
    }

    companion object {
        /** 편의점은 같은 순위 안에서 카페 뒤에 둔다. 제품이 만 개가 넘어 카페 메뉴를 밀어낸다. */
        const val CONVENIENCE_STORE_ID = "cvs"

        /** 대표 메뉴. 이름이 검색어와 같은 메뉴 다음, 나머지보다 먼저다. 한국 카탈로그만. */
        val flagshipMenus: Map<String, Set<String>> = mapOf(
            "cvs" to setOf(
                "코카콜라", "펩시", "펩시제로슈거", "칠성사이다", "칠성사이다제로", "스프라이트", "환타 오렌지", "밀키스",
                "포카리스웨트 이온워터", "바나나맛우유", "초코에몽", "박카스에이", "몬스터에너지", "핫식스", "솔의눈",
                "갈아만든배", "아침햇살", "옥수수수염차", "하늘보리", "닥터페퍼", "마운틴듀", "미에로화이바", "서울우유",
                "토레타!",
            ),
            "starbucks" to setOf(
                "카페 아메리카노", "아이스 카페 아메리카노", "카페 라떼", "아이스 카페 라떼", "자몽 허니 블랙 티",
                "아이스 자몽 허니 블랙 티", "스타벅스 돌체 라떼", "아이스 스타벅스 돌체 라떼", "자바 칩 프라푸치노",
                "바닐라 크림 콜드 브루", "쿨 라임 피지오",
            ),
            "mega" to setOf("메가리카노", "왕메가카페라떼", "플레인퐁크러쉬", "쿠키프라페"),
            "compose" to setOf("딥라떼"),
            "ediya" to setOf("카페 아메리카노", "토피넛 라떼"),
            "paik" to setOf("원조커피", "원조빽스치노(BASIC)", "달달연유라떼"),
            "twosome" to setOf("아메리카노", "로얄 밀크티"),
            "hollys" to setOf("아메리카노"),
            "theventi" to setOf("아이스 아메리카노", "아인슈페너"),
            "gongcha" to setOf("블랙 밀크티 + 펄", "브라운슈가 시그니처 밀크티 +펄", "타로 밀크티 + 펄"),
            "paulbassett" to setOf("룽고", "아이스 룽고", "바닐라빈 카페라떼", "아이스 바닐라빈 카페라떼"),
            "coffeebean" to setOf("바닐라 라떼", "아이스 바닐라 라떼", "헤이즐넛 아이스 블렌디드", "캐러멜 아이스 블렌디드"),
            "bluebottle" to setOf("뉴올리언스", "지브롤터"),
            "amasvin" to setOf("흑당 버블티"),
        )

        /** 브랜드 줄임말·흔한 오타. 접은 값으로 적는다. 이름 앞부분·가운데로 이미 잡히는 말은 넣지 않는다. */
        val brandAliases: Map<String, List<String>> = mapOf(
            "starbucks" to listOf("스벅"),
            "mega" to listOf("메가커피"),
            "paik" to listOf("백다방"),
            "baskin" to listOf("배라", "베라", "베스킨라빈스"),
            "coffeebean" to listOf("커빈"),
            "parisbaguette" to listOf("파바", "파리바게트"),
        )

        /** 원래 글에서 접은 브랜드 이름만큼 걷어 낸 나머지. 메뉴 검색어의 띄어쓰기를 그대로 둔다. */
        private fun remainder(text: String, foldedName: String): String? {
            val consumed = StringBuilder()
            var index = 0
            while (index < text.length && consumed.length < foldedName.length) {
                val codePoint = text.codePointAt(index)
                val end = index + Character.charCount(codePoint)
                consumed.append(DrinkQuery.fold(text.substring(index, end)))
                index = end
            }
            if (consumed.toString() != foldedName) return null
            return text.substring(index).trim().ifEmpty { null }
        }
    }
}
