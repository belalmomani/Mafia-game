-- ============================================================
-- 0013 — قيم جديدة: دور «مافيا الإسكات» وقدرة الإسكات (شغّله وحده أولًا)
-- ============================================================
alter type public.game_role add value if not exists 'silencer';
alter type public.night_action_type add value if not exists 'silence';
