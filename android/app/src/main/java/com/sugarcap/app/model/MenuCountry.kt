package com.sugarcap.app.model

enum class MenuCountry(val code: String) {
    KR("kr"),
    US("us"),
    TW("tw"),
    ;

    /** 번들 에셋 이름(data/catalog.json, catalog-us.json, catalog-tw.json). 한국은 기존 이름 그대로. */
    val catalogResourceName: String
        get() = when (this) {
            KR -> "catalog"
            US -> "catalog-us"
            TW -> "catalog-tw"
        }

    /** 카페인 하루 권고량. 한국 식약처·미국 FDA 400mg, 대만 식약서 300mg. */
    val caffeineAdviceMg: Double
        get() = when (this) {
            KR, US -> 400.0
            TW -> 300.0
        }

    companion object {
        /** 사용자가 고른 적이 없으면 기기 지역(ISO 3166 코드)을 따른다. 카탈로그가 없는 지역은 한국이다. */
        fun resolve(storedCode: String?, regionCode: String?): MenuCountry {
            entries.firstOrNull { it.code == storedCode }?.let { return it }
            return when (regionCode?.uppercase()) {
                "US" -> US
                "TW" -> TW
                else -> KR
            }
        }
    }
}
