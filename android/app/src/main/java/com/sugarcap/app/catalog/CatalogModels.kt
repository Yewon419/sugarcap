package com.sugarcap.app.catalog

import com.sugarcap.app.today.Amount
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException

// data/catalog*.json 디코딩 모델. 필드 정의와 불변식의 계약서는 data/SCHEMA.md다.
// iOS(SugarCap/Sources/Catalog/CatalogModels.swift)와 같은 모양이다. 옵셔널 키는 없으면 null.

@Serializable
data class Catalog(
    @SerialName("schema_version") val schemaVersion: Int,
    @SerialName("built_at") val builtAt: String,
    val brands: List<Brand>,
    val drinks: List<Drink>,
) {
    val builtAtDate: OffsetDateTime?
        get() = try {
            OffsetDateTime.parse(builtAt)
        } catch (_: DateTimeParseException) {
            null
        }
}

@Serializable
data class Brand(
    val id: String,
    val name: String,
    @SerialName("serving_note") val servingNote: String,
    /** false면 그 브랜드의 drink는 serving이 정확히 1개다(수집 단계 검증이 강제). */
    @SerialName("has_size_choice") val hasSizeChoice: Boolean,
)

@Serializable
data class Drink(
    val id: String,
    @SerialName("brand_id") val brandId: String,
    val name: String,
    @SerialName("name_en") val nameEn: String? = null,
    val category: String,
    val temperature: Temperature,
    /** 썸네일 액체 색 "#RRGGBB"(SPEC §9.7). */
    @SerialName("liquid_color") val liquidColor: String? = null,
    val servings: List<Serving>,
) {
    @Serializable
    enum class Temperature {
        @SerialName("hot") HOT,
        @SerialName("iced") ICED,

        /** 브랜드가 온도를 구분해 게시하지 않았다는 뜻이다. "둘 다 가능"이 아니다. */
        @SerialName("both") BOTH,
    }
}

@Serializable
data class Serving(
    val id: String,
    @SerialName("size_label") val sizeLabel: String,
    @SerialName("volume_ml") val volumeMl: Int? = null,
    /** null은 0이 아니라 "브랜드 미공개"다(SCHEMA.md "null 값 처리"). */
    @SerialName("sugar_g") val sugarG: Double? = null,
    @SerialName("caffeine_mg") val caffeineMg: Double? = null,
    @SerialName("caffeine_variants") val caffeineVariants: List<CaffeineVariant>,
    /** 숫자 대신 구간으로 게시한 카페인(대만, schema 2). caffeineMg는 위 끝, 위가 열렸으면 아래 끝. */
    @SerialName("caffeine_range") val caffeineRange: CaffeineRange? = null,
    /** 참이면 당·카페인은 게시값이 아니라 추정치다(schema 3, SPEC §2 예외). */
    val estimated: Boolean? = null,
) {
    val isEstimated: Boolean get() = estimated == true
}

@Serializable
data class CaffeineRange(
    @SerialName("min_mg") val minMg: Double,
    /** null이면 위가 열린 구간("201mg 이상"). */
    @SerialName("max_mg") val maxMg: Double? = null,
) {
    /** "101–200", "≤100", "≥201". 대만 표기를 기호로 그대로 쓴다. */
    val numbers: String
        get() {
            val max = maxMg ?: return "≥${Amount.number(minMg)}"
            return if (minMg == 0.0) "≤${Amount.number(max)}" else "${Amount.number(minMg)}–${Amount.number(max)}"
        }
}

@Serializable
data class CaffeineVariant(
    val label: String,
    @SerialName("caffeine_mg") val caffeineMg: Double,
)
