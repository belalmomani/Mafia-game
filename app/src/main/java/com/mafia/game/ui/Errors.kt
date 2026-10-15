package com.mafia.game.ui

/** يحوّل رموز أخطاء الخادم إلى رسائل عربية مفهومة. */
fun friendlyError(e: Exception): String {
    val m = e.message ?: return "خطأ غير معروف"
    val map = listOf(
        "room_full" to "الغرفة ممتلئة",
        "room_not_found" to "الغرفة أو الرمز غير صحيح",
        "kicked_from_room" to "تم طردك من هذه الغرفة",
        "room_not_joinable" to "الغرفة غير متاحة للانضمام الآن",
        "too_many_rooms" to "وصلت للحد الأقصى من الغرف (3)",
        "invalid_room_name" to "اسم الغرفة يجب أن يكون بين 2 و40 حرفًا",
        "invalid_max_players" to "عدد اللاعبين يجب أن يكون بين 4 و20",
        "game_in_progress" to "لا يمكن المغادرة أثناء لعبة جارية",
        "not_a_member" to "لست عضوًا في هذه الغرفة",
        "not_authenticated" to "سجّل الدخول أولًا",
        "Anonymous sign-ins are disabled" to "فعّل Anonymous sign-ins في Supabase"
    )
    return map.firstOrNull { m.contains(it.first, ignoreCase = true) }?.second ?: m
}
