package com.sugarcap.app.brand

import com.sugarcap.app.catalog.Drink

// 메뉴 검색. iOS SugarCap/Sources/Brand/ServingSelection.swift의 DrinkQuery·DrinkSearchName·HangulKeys·
// DrinkSearchRank를 그대로 옮겼다. 규칙을 바꾸면 양쪽을 같이 바꾸고 양쪽 테스트를 같이 고친다.

val Drink.searchNames: List<DrinkSearchName>
    get() = listOfNotNull(name, nameEn).map(::DrinkSearchName)

/** 띄어 쓴 낱말들. 빈 조각은 버린다(Swift `split(whereSeparator: \.isWhitespace)`). */
internal fun splitWords(text: String): List<String> {
    val words = mutableListOf<String>()
    val current = StringBuilder()
    for (char in text) {
        if (char.isWhitespace()) {
            if (current.isNotEmpty()) {
                words += current.toString()
                current.clear()
            }
        } else {
            current.append(char)
        }
    }
    if (current.isNotEmpty()) words += current.toString()
    return words
}

/** 메뉴 검색어. 이름과 영문명에서 부분 일치, 대소문자·띄어쓰기 무시. 검색어는 한 번만 접는다. */
class DrinkQuery(typed: String) {
    val needle: String

    /** "아이스 라떼"처럼 첫 낱말이 온도 말이고 뒤에 말이 더 있으면, 그 온도와 나머지 검색어. */
    val temperatureScope: TemperatureScope?

    /** 띄어 쓴 낱말들(표기 묶기 후). 통째로 안 걸릴 때 순서 상관없이 낱말마다 견준다. */
    val words: List<String>

    /** 두벌식 자판 키 순서(HangulKeys). 영문 자판으로 친 글자는 키 그대로라 대소문자를 살린다. */
    val keys: ByteArray

    /** 검색어가 자음 낱자로만 돼 있으면 그 자음들("ㅋㅋㅋㄹ"). */
    val firstSounds: String?

    data class TemperatureScope(val temperature: Drink.Temperature, val needle: String)

    data class FirstSoundMatch(val isPrefix: Boolean, val length: Int)

    init {
        val text = menuAliases[fold(typed)] ?: typed
        needle = normalize(text)
        val spaced = text.filterNot { it.isWhitespace() }
        keys = HangulKeys.typed(spellings.fold(spaced) { acc, (variant, canonical) -> acc.replace(variant, canonical) })
        firstSounds = spaced.takeIf { it.isNotEmpty() && it.all { char -> char.code in 0x3131..0x314E } }
        val rawWords = splitWords(text.lowercase())
        words = rawWords.map(::normalize)
        val temperature = if (rawWords.size > 1) temperatureWords[rawWords[0]] else null
        temperatureScope = temperature?.let { TemperatureScope(it, normalize(rawWords.drop(1).joinToString(""))) }
    }

    val isEmpty: Boolean get() = needle.isEmpty()

    /** 자판 키 순서로 견준 틀린 키 수. 4키 이하 0, 8키 이하 1, 그 위 2까지 봐준다. 못 잡으면 null. */
    fun typos(names: List<DrinkSearchName>): Int? {
        if (keys.size < 2) return null
        val allowed = if (keys.size <= 4) 0 else if (keys.size <= 8) 1 else 2
        return names.mapNotNull { HangulKeys.substringDistance(keys, it.keys, allowed) }.minOrNull()
    }

    /** 초성 검색. 자음 하나는 이름 맨 앞만 본다(가운데까지 보면 "ㅋ" 하나에 수천 개가 걸린다). */
    fun firstSoundMatch(names: List<DrinkSearchName>): FirstSoundMatch? {
        val sounds = firstSounds ?: return null
        val hits = names.filter {
            if (sounds.length == 1) it.firstSounds.startsWith(sounds) else it.firstSounds.contains(sounds)
        }
        val shortest = hits.minOfOrNull { it.firstSounds.length } ?: return null
        return FirstSoundMatch(hits.any { it.firstSounds.startsWith(sounds) }, shortest)
    }

    /**
     * 검색 순위. 이름과 영문명 중 더 나은 쪽, 온도 말 검색이면 그쪽 일치까지 견줘 더 나은 쪽. 일치하지 않으면 null.
     * 통째 일치가 하나도 없을 때만 조각 일치를 본다.
     */
    fun rank(names: List<DrinkSearchName>, temperature: Drink.Temperature): DrinkSearchRank? {
        if (needle.isEmpty()) return null
        val isGuess = temperature == Drink.Temperature.BOTH
        val whole = names.mapNotNull { rank(it, needle) }.minOrNull()
        val scope = temperatureScope
        val inScope = scope != null && (temperature == scope.temperature || isGuess)
        val scoped = if (scope != null && inScope) {
            names.mapNotNull { rank(it, scope.needle) }.minOrNull()
                ?.let { DrinkSearchRank(isExact = it.isExact, extraLength = it.extraLength, isPrefix = it.isPrefix, isTemperatureGuess = isGuess) }
        } else {
            null
        }
        listOfNotNull(whole, scoped).minOrNull()?.let { return it }
        val scattered = names.mapNotNull { scatteredRank(it, words, needle) }.minOrNull()
        val scopedScattered = if (inScope) {
            names.mapNotNull { scatteredRank(it, words.drop(1), needle) }.minOrNull()
                ?.let {
                    DrinkSearchRank(
                        isExact = false,
                        extraLength = it.extraLength,
                        isPrefix = false,
                        isTemperatureGuess = isGuess,
                        isScattered = true,
                    )
                }
        } else {
            null
        }
        return listOfNotNull(scattered, scopedScattered).minOrNull()
    }

    companion object {
        /** 띄어 쓴 첫 낱말일 때만 온도 말로 본다. 붙여 쓰면 "아이스크림"·"핫식스"가 갈라진다. */
        val temperatureWords: Map<String, Drink.Temperature> = mapOf(
            "아이스" to Drink.Temperature.ICED,
            "iced" to Drink.Temperature.ICED,
            "핫" to Drink.Temperature.HOT,
            "hot" to Drink.Temperature.HOT,
        )

        /** 메뉴 줄임말. 검색어 전체가 이 말이면 풀어 쓴 말로 찾는다. */
        val menuAliases: Map<String, String> = mapOf(
            "아아" to "아이스 아메리카노",
            "뜨아" to "핫 아메리카노",
            "따아" to "핫 아메리카노",
            "아라" to "아이스 라떼",
            "뜨라" to "핫 라떼",
            "아바라" to "아이스 바닐라 라떼",
            "뜨바라" to "핫 바닐라 라떼",
            "카마" to "카라멜 마키아또",
            "캐마" to "카라멜 마키아또",
            "아캐마" to "아이스 카라멜 마키아또",
            "콜브" to "콜드 브루",
            "바콜" to "바닐라 크림 콜드 브루",
            "자허블" to "자몽 허니 블랙 티",
            "민초" to "민트 초코",
            "딸라" to "딸기 라떼",
            "밀티" to "밀크티",
            "블글라" to "블랙 글레이즈드 라떼",
            "화모" to "화이트 초콜릿 모카",
            "제말크프" to "제주 말차 크림 프라푸치노",
        )

        /** 같은 말의 다른 표기. 검색어와 이름 양쪽을 뒤 표기로 바꿔 견준다. 접은 값, 긴 말부터. */
        val spellings: List<Pair<String, String>> = listOf(
            "쵸콜릿" to "초코", "쵸콜렛" to "초코", "초콜릿" to "초코", "초콜렛" to "초코", "쵸코" to "초코",
            "그린티" to "녹차",
            "캬라멜" to "카라멜", "캐러멜" to "카라멜", "캐라멜" to "카라멜",
            "마끼아또" to "마키아또", "마키야또" to "마키아또",
            "라테" to "라떼",
            "쥬스" to "주스",
            "콜드브류" to "콜드브루",
            "티라미슈" to "티라미수",
            "애이드" to "에이드",
            "요구르트" to "요거트",
        )

        /** 조각 일치. 낱말마다 통째로 이름에 있거나 2글자 이상 조각으로 나눠 조각마다 이름에 있으면 걸린다. */
        private fun scatteredRank(name: DrinkSearchName, pieces: List<String>, needle: String): DrinkSearchRank? {
            if (pieces.isEmpty()) return null
            val joined = pieces.joinToString("")
            if (!joined.all { it in name.characters }) return null
            if (!pieces.all { name.folded.contains(it) || covers(name.folded, it) }) return null
            return DrinkSearchRank(
                isExact = false,
                extraLength = maxOf(0, name.folded.length - joined.length),
                isPrefix = false,
                isScattered = true,
            )
        }

        /** `piece`를 2글자 이상 조각들로 나눠 조각마다 `text` 안에 있게 할 수 있는가. */
        private fun covers(text: String, piece: String): Boolean {
            if (piece.length < 4) return false
            val reachable = BooleanArray(piece.length + 1)
            reachable[0] = true
            for (start in piece.indices) {
                if (!reachable[start]) continue
                for (end in start + 2..piece.length) {
                    if (!reachable[end] && text.contains(piece.substring(start, end))) reachable[end] = true
                }
            }
            return reachable[piece.length]
        }

        private fun rank(name: DrinkSearchName, needle: String): DrinkSearchRank? {
            if (!name.folded.contains(needle)) return null
            val isExact = name.core == needle || name.core == "카페$needle"
            // 검색어가 떼어 낸 앞말에만 걸리면("아이스") 본체 대신 전체 이름 길이로 잰다.
            val body = if (name.core.contains(needle)) name.core else name.folded
            return DrinkSearchRank(
                isExact = isExact,
                extraLength = if (isExact) 0 else body.length - needle.length,
                isPrefix = name.core.startsWith(needle) || name.folded.startsWith(needle),
            )
        }

        fun fold(text: String): String = text.lowercase().filterNot { it.isWhitespace() }

        /** 접고 표기를 묶은 값. 메뉴 이름 견주기에만 쓴다(브랜드 이름은 fold). */
        fun normalize(text: String): String =
            spellings.fold(fold(text)) { acc, (variant, canonical) -> acc.replace(variant, canonical) }
    }
}

/** 검색 순위를 매길 이름 하나. 맨 앞의 온도·"카페" 낱말을 뗀 본체(core)를 같이 들고 있다. */
class DrinkSearchName(name: String) {
    val folded: String = DrinkQuery.normalize(name)
    val core: String
    val characters: Set<Char> = folded.toSet()
    val keys: ByteArray = HangulKeys.typed(folded)

    /** 글자마다 첫소리("코카콜라" → "ㅋㅋㅋㄹ"). 한글이 아닌 글자는 그대로. */
    val firstSounds: String = HangulKeys.firstSounds(folded)

    init {
        // 띄어 쓴 낱말 단위로만 뗀다. 붙여 쓴 이름까지 떼면 "아이스크림"이 "크림"이 된다.
        val words = splitWords(name.lowercase()).toMutableList()
        while (words.size > 1 && words.first() in leadingWords) words.removeAt(0)
        core = DrinkQuery.normalize(words.joinToString(""))
    }

    companion object {
        val leadingWords: Set<String> = setOf("아이스", "핫", "카페", "iced", "hot", "caffe", "cafe", "café")
    }
}

/** 한글을 두벌식 자판에서 누르는 키 순서로 푼다("콜라" → zhffk, "뗴" → EP). 겹받침·겹모음은 두 키. */
object HangulKeys {
    private val initials = listOf("r", "R", "s", "e", "E", "f", "a", "q", "Q", "t", "T", "d", "w", "W", "c", "z", "x", "v", "g")
    private val medials = listOf(
        "k", "o", "i", "O", "j", "p", "u", "P", "h", "hk", "ho", "hl", "y", "n", "nj", "np", "nl", "b", "m", "ml", "l",
    )
    private val finals = listOf(
        "", "r", "R", "rt", "s", "sw", "sg", "e", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg", "a", "q", "qt", "t", "T",
        "d", "w", "c", "z", "x", "v", "g",
    )

    /** 호환 자모(ㄱ U+3131 ~ ㅣ U+3163). 조합 중인 글자가 낱자로 들어온다. */
    private val jamo = listOf(
        "r", "R", "rt", "s", "sw", "sg", "e", "E", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg", "a", "q", "Q", "qt", "t",
        "T", "d", "w", "W", "c", "z", "x", "v", "g",
    ) + medials

    /** Shift로 치는 키. 나머지 대문자는 소문자와 같은 키다. */
    private val shifted = setOf('Q', 'W', 'E', 'R', 'T', 'O', 'P')

    private const val FIRST_SOUND_JAMO = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"

    fun typed(text: String): ByteArray {
        val out = StringBuilder()
        text.codePoints().forEach { value ->
            when (value) {
                in 0xAC00..0xD7A3 -> {
                    val index = value - 0xAC00
                    out.append(initials[index / 588]).append(medials[(index % 588) / 28]).append(finals[index % 28])
                }
                in 0x3131..0x3163 -> out.append(jamo[value - 0x3131])
                in 'A'.code..'Z'.code -> {
                    val letter = value.toChar()
                    out.append(if (letter in shifted) letter else letter.lowercaseChar())
                }
                else -> out.appendCodePoint(value)
            }
        }
        return out.toString().toByteArray(Charsets.UTF_8)
    }

    fun firstSounds(text: String): String {
        val out = StringBuilder()
        text.codePoints().forEach { value ->
            if (value in 0xAC00..0xD7A3) out.append(FIRST_SOUND_JAMO[(value - 0xAC00) / 588]) else out.appendCodePoint(value)
        }
        return out.toString()
    }

    /** `needle`이 `text` 안 어딘가와 몇 키 다른가(삽입·삭제·바꿈 하나가 1). `allowed`보다 크면 null. */
    fun substringDistance(needle: ByteArray, text: ByteArray, allowed: Int): Int? {
        if (needle.isEmpty() || text.size + allowed < needle.size) return null
        var previous = IntArray(needle.size + 1) { it }
        var current = previous.copyOf()
        var best = previous[needle.size]
        for (byte in text) {
            current[0] = 0
            for (i in 1..needle.size) {
                val replace = previous[i - 1] + if (needle[i - 1] == byte) 0 else 1
                current[i] = minOf(replace, previous[i] + 1, current[i - 1] + 1)
            }
            best = minOf(best, current[needle.size])
            if (best == 0) return 0
            val swap = previous
            previous = current
            current = swap
        }
        return if (best <= allowed) best else null
    }
}

/**
 * 작을수록 위. 본체가 검색어와 같은 이름 → 검색어 밖 글자가 적은 이름 → 검색어로 시작하는 이름 순.
 * 앞부분 일치를 길이보다 앞에 두면 "콜라"에 콜라겐 제품이 코카콜라보다 먼저 온다.
 */
data class DrinkSearchRank(
    val isExact: Boolean,
    val extraLength: Int,
    val isPrefix: Boolean,
    /** 온도 말 검색에서 온도를 나눠 싣지 않은(BOTH) 메뉴로 잡혔다. */
    val isTemperatureGuess: Boolean = false,
    /** 검색어가 통째로가 아니라 조각으로 걸렸다. 통째 일치보다 늘 아래. */
    val isScattered: Boolean = false,
) : Comparable<DrinkSearchRank> {
    override fun compareTo(other: DrinkSearchRank): Int = order.compare(this, other)

    private companion object {
        val order: Comparator<DrinkSearchRank> = compareBy(
            { it.isScattered },
            { !it.isExact },
            { it.isTemperatureGuess },
            { it.extraLength },
            { !it.isPrefix },
        )
    }
}
