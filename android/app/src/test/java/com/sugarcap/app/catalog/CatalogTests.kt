package com.sugarcap.app.catalog

import com.sugarcap.app.brand.liquidRgb
import com.sugarcap.app.model.MenuCountry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS SugarCap/Tests/CatalogTests.swift의 CatalogTests. 여기서 깨지면 수집 파이프라인이 계약을 어긴 것이다. */
class CatalogTests {
    private val brandsWithSizeChoice = setOf("compose", "ediya", "twosome", "gongcha", "paulbassett", "baskin", "cvs")

    private fun loadCatalog(): Catalog = BundledCatalogs.catalog(MenuCountry.KR)

    @Test
    fun bundledCatalogLoadsWithSupportedSchema() {
        val catalog = loadCatalog()

        assertTrue("schema_version ${catalog.schemaVersion}", catalog.schemaVersion in CatalogStore.supportedSchemaVersions)
        assertNotNull("built_at이 ISO 8601이 아님: ${catalog.builtAt}", catalog.builtAtDate)
        assertEquals(18, catalog.brands.size)
        assertEquals("기본 메뉴가 격자 맨 앞이 아님", "basic", catalog.brands.first().id)
        assertFalse(catalog.drinks.isEmpty())
    }

    @Test
    fun everyDrinkPointsAtAKnownBrand() {
        val catalog = loadCatalog()
        val brandIds = catalog.brands.map { it.id }.toSet()

        for (drink in catalog.drinks) {
            assertTrue("${drink.id}의 brand_id ${drink.brandId}가 brands에 없음", drink.brandId in brandIds)
        }
    }

    @Test
    fun identifiersAreUnique() {
        val catalog = loadCatalog()

        val drinkIds = catalog.drinks.map { it.id }
        assertEquals("drink.id 중복", drinkIds.size, drinkIds.toSet().size)
        val servingIds = catalog.drinks.flatMap { it.servings }.map { it.id }
        assertEquals("serving.id 중복", servingIds.size, servingIds.toSet().size)
    }

    @Test
    fun servingIdentifiersAreNamespacedByDrink() {
        for (drink in loadCatalog().drinks) {
            for (serving in drink.servings) {
                assertTrue("${serving.id}가 ${drink.id} 접두사를 따르지 않음", serving.id.startsWith(drink.id + ":"))
            }
        }
    }

    @Test
    fun onlySizeChoiceBrandsHaveMultipleServings() {
        val catalog = loadCatalog()
        val sizeChoice = catalog.brands.filter { it.hasSizeChoice }.map { it.id }.toSet()

        assertEquals(brandsWithSizeChoice, sizeChoice)
        for (drink in catalog.drinks.filter { it.brandId !in sizeChoice }) {
            assertEquals("${drink.id}는 사이즈 선택이 없는 브랜드인데 serving이 ${drink.servings.size}개", 1, drink.servings.size)
        }
    }

    /** 추정치는 영양정보를 아예 공개하지 않는 브랜드와 기본 메뉴에만 있다(SPEC §2 예외). */
    @Test
    fun estimatesStayInBrandsThatPublishNothing() {
        val catalog = loadCatalog()
        val estimatedBrands = catalog.drinks.filter { drink -> drink.servings.any { it.isEstimated } }.map { it.brandId }.toSet()
        assertEquals(setOf("basic", "bluebottle", "amasvin", "oozy"), estimatedBrands)

        val latte = catalog.drinks.first { it.brandId == "bluebottle" && it.name == "카페라떼" }
        val cup = latte.servings.first()
        assertTrue(cup.isEstimated)
        assertNotNull(cup.sugarG)
    }

    @Test
    fun everyDrinkHasAtLeastOneServing() {
        for (drink in loadCatalog().drinks) {
            assertFalse("${drink.id}에 serving이 없음", drink.servings.isEmpty())
        }
    }

    @Test
    fun caffeineMatchesTheFirstVariantWhenVariantsExist() {
        val withVariants = loadCatalog().drinks.flatMap { it.servings }.filter { it.caffeineVariants.isNotEmpty() }
        for (serving in withVariants) {
            assertEquals("${serving.id}의 caffeine_mg가 첫 변형과 다름", serving.caffeineVariants[0].caffeineMg, serving.caffeineMg)
        }
        // 현재 더벤티 원두별 값만 해당한다(SPEC §10).
        assertTrue(withVariants.isNotEmpty())
    }

    /** SPEC §9.2: 카페인 미공개를 이유로 행을 버리지 않는다. */
    @Test
    fun missingValuesAreKeptRatherThanDropped() {
        val caffeineMissing = loadCatalog().drinks.flatMap { it.servings }.filter { it.caffeineMg == null }
        assertTrue(caffeineMissing.isNotEmpty())
        assertTrue("카페인 미공개인데 당류는 있는 행이 하나도 없음", caffeineMissing.any { it.sugarG != null })
    }

    /** validate.py의 이상치 범위와 같다. 걸리면 신메뉴가 아니라 파싱 버그다. */
    @Test
    fun valuesStayInsideSanityBounds() {
        for (serving in loadCatalog().drinks.flatMap { it.servings }) {
            serving.sugarG?.let { assertTrue("${serving.id} 당류 ${it}g", it in 0.0..200.0) }
            serving.caffeineMg?.let { assertTrue("${serving.id} 카페인 ${it}mg", it in 0.0..800.0) }
            serving.volumeMl?.let { assertTrue("${serving.id} 용량 ${it}ml", it in 20..1200) }
        }
    }

    @Test
    fun everyDrinkHasAReadableLiquidColor() {
        for (drink in loadCatalog().drinks) {
            val hex = drink.liquidColor
            assertNotNull("${drink.id}에 liquid_color가 없음", hex)
            assertNotNull("${drink.id}의 liquid_color 형식이 틀림: $hex", liquidRgb(hex!!))
        }
    }

    @Test
    fun unsupportedSchemaVersionIsRejected() {
        val payload = """{"schema_version": 4, "built_at": "2026-09-16T04:06:26+00:00", "brands": [], "drinks": []}"""

        val error = assertThrows(CatalogException.UnsupportedSchemaVersion::class.java) { CatalogStore.load(payload) }
        assertEquals(4, error.found)
        assertEquals(3, error.supported)
    }

    @Test
    fun duplicateServingIdentifierIsRejected() {
        val payload = """
            {"schema_version": 1, "built_at": "2026-09-16T04:06:26+00:00", "brands": [],
             "drinks": [{"id": "x:a:hot", "brand_id": "x", "name": "A", "name_en": null,
              "category": "c", "temperature": "hot", "servings": [
               {"id": "x:a:hot:r", "size_label": "R", "volume_ml": null, "sugar_g": 1,
                "caffeine_mg": null, "caffeine_variants": []},
               {"id": "x:a:hot:r", "size_label": "L", "volume_ml": null, "sugar_g": 2,
                "caffeine_mg": null, "caffeine_variants": []}]}]}
        """.trimIndent()

        val error = assertThrows(CatalogException.DuplicateIdentifier::class.java) { CatalogStore.load(payload) }
        assertEquals("serving", error.kind)
        assertEquals("x:a:hot:r", error.id)
    }

    @Test
    fun duplicateBrandIdentifierIsRejected() {
        val payload = """
            {"schema_version": 1, "built_at": "2026-09-16T04:06:26+00:00", "drinks": [],
             "brands": [
              {"id": "x", "name": "X", "serving_note": "", "has_size_choice": false},
              {"id": "x", "name": "X2", "serving_note": "", "has_size_choice": false}]}
        """.trimIndent()

        val error = assertThrows(CatalogException.DuplicateIdentifier::class.java) { CatalogStore.load(payload) }
        assertEquals("brand", error.kind)
    }

    @Test
    fun malformedJsonIsRejected() {
        assertThrows(CatalogException.DecodingFailed::class.java) { CatalogStore.load("{ not json") }
    }

    @Test
    fun missingResourceIsReported() {
        val error = assertThrows(CatalogException.ResourceMissing::class.java) {
            CatalogStore.loadBundled(MenuCountry.US) { null }
        }
        assertEquals("catalog-us.json", error.name)
    }
}
