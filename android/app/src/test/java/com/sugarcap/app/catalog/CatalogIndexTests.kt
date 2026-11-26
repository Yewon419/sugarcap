package com.sugarcap.app.catalog

import com.sugarcap.app.brand.DrinkQuery
import com.sugarcap.app.brand.DrinkSearchName
import com.sugarcap.app.brand.HangulKeys
import com.sugarcap.app.brand.searchNames
import com.sugarcap.app.model.MenuCountry
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS SugarCap/Tests/CatalogTests.swift의 CatalogIndexTests. 검색 결과가 iOS와 같아야 한다. */
class CatalogIndexTests {
    private val catalog: Catalog get() = BundledCatalogs.catalog(MenuCountry.KR)
    private val index: CatalogIndex get() = BundledCatalogs.index(MenuCountry.KR)

    private fun first(text: String): String = DrinkQuery.normalize(index.search(text).firstOrNull()?.name ?: "(없음)")

    @Test
    fun lookupsResolveAgainstTheRealCatalog() {
        for (brand in catalog.brands) {
            assertEquals(brand.id, index.brand(brand.id)?.id)
            assertFalse("${brand.id} 메뉴가 비었음", index.drinks(brand.id).isEmpty())
        }
        val anyServing = catalog.drinks.first().servings.first()
        assertEquals(anyServing.id, index.serving(anyServing.id)?.id)
        assertNull(index.serving("없는:아이디:regular"))
    }

    @Test
    fun latteSearchPutsCafeLatteAboveFlavoredLattes() {
        // 2026-10-04: "라떼"에 딸기 콜드폼 딸기 라떼·편의점 "라떼는 말이야…"가 카페 라떼보다 먼저 왔다.
        val hits = index.search("라떼")
        val top = hits.first()
        assertNotEquals(CatalogIndex.CONVENIENCE_STORE_ID, top.brandId)
        assertTrue("맨 위가 카페 라떼가 아님: ${top.name}", DrinkQuery.fold(top.name).endsWith("카페라떼"))
        assertFalse("딸기라떼가 카페 라떼 묶음에 섞임", hits.take(10).any { it.name.contains("딸기") })

        val starbucks = index.drinks("starbucks", DrinkQuery("라떼"))
        assertTrue("브랜드 안 검색 맨 위: ${starbucks.firstOrNull()?.name}", starbucks.firstOrNull()?.name in setOf("카페 라떼", "아이스 카페 라떼"))
    }

    @Test
    fun searchOrderFollowsRankThenCafeBeforeStoreThenBrandGrid() {
        val order = catalog.brands.withIndex().associate { (offset, brand) -> brand.id to offset }
        val lexicographic = Comparator<List<Int>> { a, b ->
            a.zip(b).map { (x, y) -> x.compareTo(y) }.firstOrNull { it != 0 } ?: a.size.compareTo(b.size)
        }

        for (text in listOf("라떼", "아메리카노", "콜라", "커피", "허니자몽", "바닐라라떼")) {
            val query = DrinkQuery(text)
            val hits = index.search(text, limit = 5_000)
            assertFalse(text, hits.isEmpty())
            val keys = hits.map { drink ->
                val rank = query.rank(drink.searchNames, drink.temperature) ?: error("$text: ${drink.name} 순위 없음")
                listOf(
                    if (rank.isScattered) 1 else 0,
                    if (rank.isExact) 0 else 1,
                    if (CatalogIndex.flagshipMenus[drink.brandId]?.contains(drink.name) == true) 0 else 1,
                    if (drink.brandId == CatalogIndex.CONVENIENCE_STORE_ID) 1 else 0,
                    rank.extraLength,
                    if (rank.isPrefix) 0 else 1,
                    order[drink.brandId] ?: -1,
                )
            }
            assertEquals("$text 검색 순서가 규칙과 다름", keys.sortedWith(lexicographic), keys)
        }
    }

    @Test
    fun brandMatchesNameAndCarriesMenuQuery() {
        assertEquals(listOf("starbucks"), index.brandMatches("스타벅").map { it.brand.id })
        assertEquals("", index.brandMatches("스타 벅스").firstOrNull()?.menuQuery)
        assertTrue("메뉴 검색어가 브랜드에 걸림", index.brandMatches("라떼").isEmpty())
        assertTrue(index.brandMatches(" ").isEmpty())

        // 브랜드 이름 뒤에 친 말은 띄어쓰기를 살려 메뉴 검색어로 넘긴다.
        val scoped = index.brandMatches("스타벅스 카페 라떼").first()
        assertEquals("starbucks", scoped.brand.id)
        assertEquals("카페 라떼", scoped.menuQuery)
        assertEquals("라떼", index.brandMatches("스타벅스라떼").firstOrNull()?.menuQuery)
        assertFalse(index.drinks("starbucks", DrinkQuery(scoped.menuQuery)).isEmpty())
    }

    @Test
    fun brandAliasesMatchAndCarryMenuQuery() {
        val brandIds = catalog.brands.map { it.id }.toSet()
        assertTrue("없는 브랜드에 줄임말이 걸림", brandIds.containsAll(CatalogIndex.brandAliases.keys))

        assertEquals(listOf("starbucks"), index.brandMatches("스벅").map { it.brand.id })
        assertEquals(listOf("baskin"), index.brandMatches("배라").map { it.brand.id })
        assertEquals(listOf("mega"), index.brandMatches("메가커피").map { it.brand.id })
        val scoped = index.brandMatches("스벅 아이스 라떼").first()
        assertEquals("starbucks", scoped.brand.id)
        assertEquals("아이스 라떼", scoped.menuQuery)
    }

    @Test
    fun temperatureWordScopesSearchToThatTemperature() {
        // 2026-11-12: 이름에 "아이스"를 안 붙이는 브랜드가 많아 "아이스 라떼"가 아무것도 안 잡았다.
        val starbucks = index.drinks("starbucks", DrinkQuery("아이스 라떼"))
        assertEquals("아이스 카페 라떼", starbucks.firstOrNull()?.name)
        assertFalse("아이스 검색에 뜨거운 메뉴가 섞임", starbucks.any { it.temperature == Drink.Temperature.HOT })
        for (brandId in listOf("mega", "compose", "ediya")) {
            val hits = index.drinks(brandId, DrinkQuery("아이스 라떼"))
            assertFalse(brandId, hits.isEmpty())
            assertFalse(brandId, hits.any { it.temperature == Drink.Temperature.HOT })
        }
        assertFalse(index.search("아이스 라떼").isEmpty())

        // 붙여 쓴 이름의 앞말은 온도 말이 아니다.
        assertNull(DrinkQuery("아이스크림").temperatureScope)
        assertNull(DrinkQuery("핫식스 제로").temperatureScope)
        assertNull(DrinkQuery("아이스").temperatureScope)
    }

    @Test
    fun icedAmericanoSlangFindsIcedAmericano() {
        val starbucks = index.drinks("starbucks", DrinkQuery("아아"))
        assertEquals("아이스 카페 아메리카노", starbucks.firstOrNull()?.name)
        assertFalse("아아에 뜨거운 메뉴가 섞임", starbucks.any { it.temperature == Drink.Temperature.HOT })
        assertFalse(index.search("아아").isEmpty())
        assertEquals("아아", index.brandMatches("스벅 아아").first().menuQuery)

        assertEquals("아이스 바닐라 라떼", index.drinks("starbucks", DrinkQuery("아바라")).firstOrNull()?.name)
        assertEquals("아이스 자몽 허니 블랙 티", index.drinks("starbucks", DrinkQuery("자허블")).firstOrNull()?.name)
        assertFalse(index.drinks("starbucks", DrinkQuery("뜨아")).any { it.temperature == Drink.Temperature.ICED })
        for (slang in DrinkQuery.menuAliases.keys) {
            assertFalse("${slang}로 아무것도 안 잡힘", index.search(slang).isEmpty())
        }
    }

    @Test
    fun shorterNamesBeatPrefixMatches() {
        // 앞부분 일치를 길이보다 앞에 두면 콜라겐 제품이 코카콜라를 덮는다.
        val hits = index.search("콜라", limit = 100).map { it.name }
        val cola = hits.indexOf("코카콜라")
        assertTrue("코카콜라가 상위 100개에 없음", cola >= 0)
        assertTrue("코카콜라가 너무 아래: ${hits.take(cola + 1)}", cola < 10)

        // 떼어 내는 앞말은 띄어 쓴 낱말만: "아이스크림"의 본체는 "크림"이 아니다.
        assertEquals("아이스크림카페라떼", DrinkSearchName("아이스크림 카페라떼").core)
        assertEquals("라떼", DrinkSearchName("아이스 카페 라떼").core)
        assertEquals("latte", DrinkSearchName("Caffe Latte").core)
        assertEquals("이름 전체를 떼지는 않는다", "카페", DrinkSearchName("카페").core)
    }

    @Test
    fun flagshipDrinksComeFirst() {
        // 카탈로그를 다시 빌드해 메뉴 이름이 바뀌면 목록이 조용히 무력해진다.
        for ((brandId, names) in CatalogIndex.flagshipMenus) {
            val menu = index.drinks(brandId).map { it.name }.toSet()
            assertEquals("$brandId 카탈로그에 없는 대표 메뉴", emptySet<String>(), names - menu)
        }

        // 2026-11-19 대표님 "콜라 치면 코카콜라가 제일 위에".
        assertEquals("코카콜라", index.search("콜라").firstOrNull()?.name)
        assertEquals("칠성사이다", index.search("사이다").firstOrNull()?.name)
        assertEquals("바나나맛우유", index.search("바나나").firstOrNull()?.name)
        // 온도별로 실린 대표 메뉴는 둘 다 올라온다.
        assertEquals(listOf("아이스 자몽 허니 블랙 티", "자몽 허니 블랙 티"), index.search("자몽").take(2).map { it.name }.sorted())
        val pearl = index.search("펄").first()
        assertTrue("펄: ${pearl.name}", CatalogIndex.flagshipMenus["gongcha"]?.contains(pearl.name) == true)
        // 이름이 검색어와 같은 메뉴가 대표 메뉴보다 먼저다: "라떼"는 카페 라떼, 그다음 돌체 라떼.
        val lattes = index.search("라떼", limit = 200).map { it.name }
        val plain = lattes.indexOf("카페 라떼")
        val dolce = lattes.indexOf("스타벅스 돌체 라떼")
        val strawberry = lattes.indexOf("딸기라떼")
        assertTrue(plain >= 0 && dolce >= 0)
        assertTrue("메가 딸기라떼가 상위 200개에 없음", strawberry >= 0)
        assertTrue(plain < dolce)
        assertTrue(dolce < strawberry)
    }

    @Test
    fun typedKeysFindMenusDespiteTyposAndKeyboardMode() {
        // 두벌식 키 순서: 겹모음·겹받침은 두 키, 된소리·ㅖ는 Shift 키, 조합 중인 낱자도 같은 키.
        assertArrayEquals("EP".toByteArray(), HangulKeys.typed("뗴"))
        assertArrayEquals("ekfrrhk".toByteArray(), HangulKeys.typed("닭과"))
        assertArrayEquals("zhff".toByteArray(), HangulKeys.typed("콜ㄹ"))
        assertArrayEquals("Shift가 없는 대문자는 소문자 키", "zhffk".toByteArray(), HangulKeys.typed("ZHFFK"))

        // 오타(2026-11-19 대표님 "검색 알고리즘이 별로면 금방 알아채").
        assertEquals("아메리카노", first("아메리카도"))
        assertEquals("카페라떼", first("카페라뗴"))
        assertEquals("바닐라라떼", first("바닐리라떼"))
        // 조합 중인 글자: "콜라"를 치는 사이 "콜ㄹ"에서 결과가 비지 않는다.
        assertEquals("코카콜라", first("콜ㄹ"))
        assertEquals("카페라떼", first("카페라ㄸ"))
        // 한/영 자판 실수: 영문 자판으로 친 "콜라"·"딸기라떼".
        assertEquals("코카콜라", first("zhffk"))
        assertTrue(first("Ekfrlfkep").contains("딸기라떼"))
        // 글자로 걸리는 검색은 키 셈을 쓰지 않는다.
        assertTrue(first("라떼"), first("라떼").endsWith("카페라떼"))
    }

    @Test
    fun firstSoundSearch() {
        assertEquals("ㅋㅋㅋㄹzero", HangulKeys.firstSounds("코카콜라zero"))
        assertNull("완성 글자가 섞이면 초성 검색이 아니다", DrinkQuery("ㅋㅋ콜라").firstSounds)

        // 2026-11-19 대표님 "초성 검색도".
        assertEquals("코카콜라", first("ㅋㅋㅋㄹ"))
        assertEquals("대표 메뉴가 앞부분 일치(코코리치)보다 먼저", "코카콜라", first("ㅋㅋㄹ"))
        assertEquals("아메리카노", first("ㅇㅁㄹㅋㄴ"))
        assertEquals("칠성사이다", first("ㅊㅅㅅㅇㄷ"))
        assertEquals("바나나맛우유", first("ㅂㄴㄴㅁㅇㅇ"))
        assertEquals("띄어 써도 된다", "자몽허니블랙티", first("ㅈㅁ ㅎㄴ ㅂㄹㅌ"))
        // 자음 하나는 이름 맨 앞만 본다.
        val single = index.search("ㅌ", limit = 500)
        assertFalse(single.isEmpty())
        assertTrue(single.all { drink -> drink.searchNames.any { it.firstSounds.startsWith("ㅌ") } })
    }

    @Test
    fun scatteredWordsAndSpellingsFindSameDrink() {
        // 2026-11-18 대표님: "허니자몽"으로 자몽 허니 블랙 티가 안 나왔다.
        for (text in listOf("허니자몽", "허니 자몽", "블랙티 자몽")) {
            val names = index.drinks("starbucks", DrinkQuery(text)).map { it.name }
            assertTrue("$text: ${names.take(5)}", "아이스 자몽 허니 블랙 티" in names)
        }
        // 통째로 걸리는 메뉴가 조각으로 걸린 메뉴보다 먼저다.
        val hits = index.search("허니자몽", limit = 500)
        val query = DrinkQuery("허니자몽")
        val firstScattered = hits.indexOfFirst { query.rank(it.searchNames, it.temperature)?.isScattered == true }
        val lastWhole = hits.indexOfLast { query.rank(it.searchNames, it.temperature)?.isScattered == false }
        if (firstScattered >= 0 && lastWhole >= 0) assertTrue(lastWhole < firstScattered)
        // 1글자 조각은 쓰지 않는다.
        assertTrue(
            index.search("라티").all {
                DrinkQuery.normalize(it.name).contains("라티") || DrinkQuery.normalize(it.nameEn ?: "").contains("라티")
            },
        )

        // 표기 묶기: 초콜릿↔초코, 그린티↔녹차, 마끼아또↔마키아또.
        assertEquals(DrinkQuery("초코라떼").needle, DrinkQuery("초콜릿 라떼").needle)
        assertTrue(
            index.drinks("compose", DrinkQuery("캬라멜마끼아또")).any { it.name.contains("마키아또") || it.name.contains("마끼아또") },
        )
        assertFalse(index.drinks("mega", DrinkQuery("그린티라떼")).isEmpty())
    }

    @Test
    fun convenienceStoreSearchIgnoresSpaces() {
        val spaced = index.drinks("cvs", DrinkQuery("바나나 맛 우유"))
        assertTrue("띄어 쓴 검색어로 바나나맛우유를 못 찾음", spaced.any { it.name == "바나나맛우유" })

        val all = index.drinks("cvs", DrinkQuery("  "))
        assertEquals("공백만 친 검색어는 전체여야 함", index.drinks("cvs").size, all.size)
    }
}
