package com.sugarcap.app.catalog

import com.sugarcap.app.model.MenuCountry
import java.io.File

/** 목을 쓰지 않고 실제 data/catalog*.json을 읽는다(경로는 app/build.gradle.kts가 넘긴다). 나라마다 한 번만 읽는다. */
object BundledCatalogs {
    private val dir: File = File(
        System.getProperty("sugarcap.catalogDir") ?: error("sugarcap.catalogDir 시스템 속성이 없음(Gradle로 실행)"),
    )

    private val catalogs = mutableMapOf<MenuCountry, Catalog>()
    private val indexes = mutableMapOf<MenuCountry, CatalogIndex>()

    @Synchronized
    fun catalog(country: MenuCountry): Catalog = catalogs.getOrPut(country) {
        CatalogStore.loadBundled(country) { name -> File(dir, name).takeIf(File::isFile)?.inputStream() }
    }

    @Synchronized
    fun index(country: MenuCountry): CatalogIndex = indexes.getOrPut(country) { CatalogIndex(catalog(country)) }
}
