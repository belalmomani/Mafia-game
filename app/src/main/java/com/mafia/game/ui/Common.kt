package com.mafia.game.ui

import com.mafia.game.R
import org.json.JSONArray
import org.json.JSONObject

fun JSONObject.strOrNull(key: String): String? = if (!has(key) || isNull(key)) null else getString(key)
fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }

object Roles {
    fun nameAr(role: String?): String = when (role) {
        "mafia" -> "مافيا"
        "red_mafia" -> "مافيا أحمر"
        "silencer" -> "مافيا الإسكات"
        "sheikh" -> "الشيخ"
        "boy" -> "الولد"
        "hunter" -> "الصياد"
        "girl" -> "البنت"
        "citizen" -> "مواطن"
        else -> role ?: "؟"
    }

    fun cardRes(role: String): Int = when (role) {
        "mafia", "silencer" -> R.drawable.card_mafia
        "red_mafia" -> R.drawable.card_red_mafia
        "sheikh" -> R.drawable.card_sheikh
        "boy" -> R.drawable.card_boy
        "hunter" -> R.drawable.card_hunter
        "girl" -> R.drawable.card_girl
        else -> R.drawable.card_citizen
    }

    fun isMafia(role: String?): Boolean = role == "mafia" || role == "red_mafia" || role == "silencer"
}
