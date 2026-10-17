package com.mafia.game.ui

/** يحوّل رموز أخطاء الخادم إلى رسائل عربية مفهومة. */
fun friendlyError(e: Exception): String {
    val m = e.message ?: return "خطأ غير معروف"
    val map = listOf(
        "room_full" to "الغرفة ممتلئة",
        "room_not_found" to "الغرفة أو الرمز غير صحيح",
        "kicked_from_room" to "تم طردك من هذه الغرفة",
        "room_not_joinable" to "الغرفة غير متاحة للانضمام الآن",
        "room_not_open" to "الغرفة ليست مفتوحة",
        "too_many_rooms" to "وصلت للحد الأقصى من الغرف (3)",
        "invalid_room_name" to "اسم الغرفة يجب أن يكون بين 2 و40 حرفًا",
        "invalid_max_players" to "عدد اللاعبين يجب أن يكون بين 4 و20",
        "invalid_display_name" to "الاسم يجب أن يكون بين 2 و30 حرفًا",
        "game_in_progress" to "لا يمكن ذلك أثناء لعبة جارية",
        "not_a_member" to "لست عضوًا في هذه الغرفة",
        "not_authenticated" to "سجّل الدخول أولًا",
        "not_room_owner" to "هذا الإجراء لمالك الغرفة فقط",
        "not_enough_players" to "يلزم 4 لاعبين على الأقل لبدء اللعبة",
        "already_voted" to "صوّتّ مسبقًا ولا يمكن تغيير الصوت",
        "phase_expired" to "انتهى وقت هذه المرحلة",
        "not_night_phase" to "ليس وقت الليل الآن",
        "not_day_phase" to "ليس وقت النهار الآن",
        "not_voting_phase" to "ليس وقت التصويت الآن",
        "player_dead" to "أنت خارج اللعبة",
        "target_dead" to "هذا اللاعب خارج اللعبة",
        "game_not_active" to "اللعبة غير نشطة",
        "action_not_allowed" to "دورك لا يسمح بهذا الإجراء",
        "no_night_ability" to "دورك بلا قدرة ليلية",
        "cannot_target_self" to "لا يمكنك اختيار نفسك",
        "cannot_target_teammate" to "لا يمكنك استهداف زميلك في المافيا",
        "cannot_protect_same_twice" to "لا تحمي نفس اللاعب ليلتين متتاليتين",
        "cannot_vote_self" to "لا يمكنك التصويت لنفسك",
        "no_bullets" to "استخدمت طلقتك",
        "not_hunter" to "هذه القدرة للصياد فقط",
        "not_your_turn" to "ليس دورك في الكلام الآن",
        "not_boy" to "هذه القدرة للولد فقط",
        "Anonymous sign-ins are disabled" to "فعّل Anonymous sign-ins في Supabase"
    )
    return map.firstOrNull { m.contains(it.first, ignoreCase = true) }?.second ?: m
}
