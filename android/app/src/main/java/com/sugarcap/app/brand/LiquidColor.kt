package com.sugarcap.app.brand

/** 썸네일 액체 색 "#RRGGBB"(앞 #은 없어도 된다)를 0xRRGGBB로. 형식이 틀리면 null(iOS `Color(liquidHex:)`). */
fun liquidRgb(hex: String): Int? {
    val digits = hex.removePrefix("#")
    if (digits.length != 6 || !digits.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
    return digits.toInt(16)
}
