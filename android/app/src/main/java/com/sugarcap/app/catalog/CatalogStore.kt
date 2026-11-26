package com.sugarcap.app.catalog

import com.sugarcap.app.model.MenuCountry
import kotlinx.serialization.json.Json
import java.io.InputStream

sealed class CatalogException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class ResourceMissing(val name: String) : CatalogException("번들에 ${name}이 없습니다.")

    class UnsupportedSchemaVersion(val found: Int, val supported: Int) :
        CatalogException("지원하지 않는 schema_version $found (지원: $supported).")

    class DecodingFailed(cause: Throwable) : CatalogException("카탈로그 디코딩 실패: $cause", cause)

    class DuplicateIdentifier(val kind: String, val id: String) : CatalogException("$kind id가 중복입니다: $id")
}

object CatalogStore {
    /** 앱이 읽을 수 있는 스키마 버전. 깨는 변경이 오면 data/SCHEMA.md와 함께 올린다. */
    val supportedSchemaVersions: IntRange = 1..3
    val supportedSchemaVersion: Int get() = supportedSchemaVersions.last

    const val RESOURCE_EXTENSION = "json"

    private val json = Json { ignoreUnknownKeys = true }

    fun load(text: String): Catalog {
        val catalog = try {
            json.decodeFromString<Catalog>(text)
        } catch (error: IllegalArgumentException) {
            throw CatalogException.DecodingFailed(error)
        }
        if (catalog.schemaVersion !in supportedSchemaVersions) {
            throw CatalogException.UnsupportedSchemaVersion(catalog.schemaVersion, supportedSchemaVersion)
        }
        assertUniqueIdentifiers(catalog)
        return catalog
    }

    /** CatalogIndex가 사전을 만들기 전에 잡는다. 원격 갱신(§2.3)은 손상된 파일을 줄 수 있다. */
    private fun assertUniqueIdentifiers(catalog: Catalog) {
        val brandIds = HashSet<String>()
        for (brand in catalog.brands) {
            if (!brandIds.add(brand.id)) throw CatalogException.DuplicateIdentifier("brand", brand.id)
        }
        val drinkIds = HashSet<String>()
        val servingIds = HashSet<String>()
        for (drink in catalog.drinks) {
            if (!drinkIds.add(drink.id)) throw CatalogException.DuplicateIdentifier("drink", drink.id)
            for (serving in drink.servings) {
                if (!servingIds.add(serving.id)) throw CatalogException.DuplicateIdentifier("serving", serving.id)
            }
        }
    }

    /** `open`은 파일 이름("catalog.json")으로 번들 스트림을 연다. 없으면 null. */
    fun loadBundled(country: MenuCountry, open: (String) -> InputStream?): Catalog {
        val fileName = "${country.catalogResourceName}.$RESOURCE_EXTENSION"
        val stream = open(fileName) ?: throw CatalogException.ResourceMissing(fileName)
        return load(stream.use { it.readBytes().decodeToString() })
    }
}
