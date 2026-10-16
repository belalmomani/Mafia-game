-- ============================================================
-- 0008 — أدوار الأوراق الجديدة (شغّله وحده أولًا، ثم 0009)
-- القيم الجديدة للأنواع لا يمكن استعمالها إلا بعد اكتمال هذا الملف، لذلك هو منفصل.
-- ============================================================
alter type public.game_role add value if not exists 'red_mafia';
alter type public.game_role add value if not exists 'sheikh';
alter type public.game_role add value if not exists 'boy';
alter type public.game_role add value if not exists 'hunter';
alter type public.game_role add value if not exists 'girl';

alter type public.elimination_cause add value if not exists 'hunt';    -- طلقة الصياد
alter type public.elimination_cause add value if not exists 'pulled';  -- سحبه الولد معه
