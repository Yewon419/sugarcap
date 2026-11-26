package com.sugarcap.app.catalog

import com.sugarcap.app.model.MenuCountry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 미국 카탈로그(data/catalog-us.json, SPEC §9.9). iOS USCatalogTests. */
class USCatalogTests {
    @Test
    fun usCatalogLoadsWithItsOwnBrands() {
        val catalog = BundledCatalogs.catalog(MenuCountry.US)

        assertTrue("schema_version ${catalog.schemaVersion}", catalog.schemaVersion in CatalogStore.supportedSchemaVersions)
        assertEquals(listOf("us-basic", "us-starbucks", "us-dutchbros"), catalog.brands.map { it.id })
        // Basic(기본 메뉴)만 사이즈 없이 1잔 1값이다.
        assertTrue(catalog.brands.filter { it.id != "us-basic" }.all { it.hasSizeChoice })
        val index = BundledCatalogs.index(MenuCountry.US)
        for (brand in catalog.brands) {
            assertFalse("${brand.id} 메뉴가 비었음", index.drinks(brand.id).isEmpty())
        }
    }

    @Test
    fun countryCatalogsShareNoIdentifiers() {
        val kr = BundledCatalogs.catalog(MenuCountry.KR)
        val us = BundledCatalogs.catalog(MenuCountry.US)
        val krServings = kr.drinks.flatMap { it.servings }.map { it.id }.toSet()
        val shared = us.drinks.flatMap { it.servings }.map { it.id }.filter { it in krServings }
        assertTrue("나라끼리 serving id가 겹침: ${shared.take(5)}", shared.isEmpty())
        assertTrue(kr.brands.map { it.id }.intersect(us.brands.map { it.id }.toSet()).isEmpty())
    }

    @Test
    fun englishSearchFindsLattes() {
        val first = BundledCatalogs.index(MenuCountry.US).search("latte").firstOrNull()
        assertNotNull("latte 검색 결과가 없음", first)
        assertTrue("맨 위가 라떼가 아님: ${first!!.name}", first.name.lowercase().contains("latte"))
    }
}

/** 대만 카탈로그(data/catalog-tw.json). 카페인 구간(caffeine_range)을 읽는다. iOS TWCatalogTests. */
class TWCatalogTests {
    @Test
    fun twCatalogLoadsWithItsOwnBrands() {
        val catalog = BundledCatalogs.catalog(MenuCountry.TW)

        assertEquals(3, catalog.schemaVersion)
        assertEquals(listOf("tw-basic", "tw-cama", "tw-kebuke"), catalog.brands.map { it.id })
        val index = BundledCatalogs.index(MenuCountry.TW)
        for (brand in catalog.brands) {
            assertFalse("${brand.id} 메뉴가 비었음", index.drinks(brand.id).isEmpty())
        }
    }

    @Test
    fun caffeineBandsCarryTheirBound() {
        val banded = BundledCatalogs.catalog(MenuCountry.TW).drinks.flatMap { it.servings }.filter { it.caffeineRange != null }
        assertFalse("구간으로 게시된 카페인이 하나도 없음", banded.isEmpty())
        for (serving in banded) {
            val range = serving.caffeineRange!!
            assertEquals(serving.id, range.maxMg ?: range.minMg, serving.caffeineMg)
        }
        val open = banded.firstOrNull { it.caffeineRange?.maxMg == null }
        assertNotNull("201mg 이상 구간이 없음", open)
        assertEquals("≥201", open!!.caffeineRange?.numbers)
    }

    @Test
    fun countryCatalogsShareNoIdentifiers() {
        val tw = BundledCatalogs.catalog(MenuCountry.TW)
        for (other in listOf(MenuCountry.KR, MenuCountry.US)) {
            val ids = BundledCatalogs.catalog(other).drinks.flatMap { it.servings }.map { it.id }.toSet()
            assertTrue(other.code, tw.drinks.flatMap { it.servings }.none { it.id in ids })
        }
    }
}

/** iOS MenuCountryTests. 지역은 ISO 3166 코드로 받는다(Android Locale.getCountry()). */
class MenuCountryTests {
    @Test
    fun deviceRegionPicksTheCatalogUntilTheUserChooses() {
        assertEquals(MenuCountry.US, MenuCountry.resolve(storedCode = null, regionCode = "US"))
        assertEquals(MenuCountry.TW, MenuCountry.resolve(storedCode = null, regionCode = "TW"))
        assertEquals(MenuCountry.KR, MenuCountry.resolve(storedCode = null, regionCode = "KR"))
        // 카탈로그가 없는 지역·지역 없음은 한국.
        assertEquals(MenuCountry.KR, MenuCountry.resolve(storedCode = null, regionCode = "JP"))
        assertEquals(MenuCountry.KR, MenuCountry.resolve(storedCode = null, regionCode = null))
    }

    @Test
    fun storedChoiceBeatsTheDeviceRegion() {
        assertEquals(MenuCountry.KR, MenuCountry.resolve(storedCode = "kr", regionCode = "US"))
        assertEquals(MenuCountry.US, MenuCountry.resolve(storedCode = "us", regionCode = "KR"))
        assertEquals(MenuCountry.TW, MenuCountry.resolve(storedCode = "tw", regionCode = "US"))
        // 모르는 값(다음 버전에서 내려온 나라 등)은 기기 지역으로 돌아간다.
        assertEquals(MenuCountry.KR, MenuCountry.resolve(storedCode = "jp", regionCode = "KR"))
    }

    @Test
    fun caffeineAdviceFollowsTheCountry() {
        assertEquals(400.0, MenuCountry.KR.caffeineAdviceMg, 0.0)
        assertEquals(400.0, MenuCountry.US.caffeineAdviceMg, 0.0)
        assertEquals(300.0, MenuCountry.TW.caffeineAdviceMg, 0.0)
    }

    @Test
    fun everyCountryHasABundledCatalog() {
        for (country in MenuCountry.entries) {
            assertNotNull(country.code, BundledCatalogs.catalog(country))
        }
    }
}
