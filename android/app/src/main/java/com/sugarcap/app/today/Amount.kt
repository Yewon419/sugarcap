package com.sugarcap.app.today

import java.text.NumberFormat
import java.util.Locale

object Amount {
    /** 소수 0~1자리, 기기 언어의 숫자 표기(iOS `.number.precision(.fractionLength(0...1))`). */
    fun number(value: Double, locale: Locale = Locale.getDefault()): String {
        val format = NumberFormat.getNumberInstance(locale)
        format.minimumFractionDigits = 0
        format.maximumFractionDigits = 1
        return format.format(value)
    }
}
