-- ============================================================
-- فحص سريع بعد تنفيذ الملفات 0001 → 0007. شغّله كاملًا؛ تظهر نتيجة واحدة.
-- كل صف يجب أن تكون حالته OK.
-- ============================================================
with tbl(name) as (values
  ('profiles'),('rooms'),('room_members'),('room_invites'),('games'),('game_players'),
  ('game_secrets'),('night_actions'),('votes'),('vote_results'),('game_events'),('reports'),('game_messages')),
checks as (
  select 1 as n, 'الجداول الـ13 موجودة' as check_name, '13' as expected,
    (select count(*)::text from pg_tables where schemaname='public' and tablename in (select name from tbl)) as actual
  union all
  select 2, 'RLS مفعّل على كل الجداول', '13',
    (select count(*)::text from pg_tables where schemaname='public' and rowsecurity and tablename in (select name from tbl))
  union all
  select 3, 'عدد سياسات RLS', '12',
    (select count(*)::text from pg_policies where schemaname='public')
  union all
  select 4, 'لا سياسات على الجداول السرية (game_secrets, night_actions)', '0',
    (select count(*)::text from pg_policies where schemaname='public' and tablename in ('game_secrets','night_actions'))
  union all
  select 5, 'العميل المسجّل لا يقرأ game_secrets', 'false',
    has_table_privilege('authenticated','public.game_secrets','select')::text
  union all
  select 6, 'العميل المسجّل لا يقرأ night_actions', 'false',
    has_table_privilege('authenticated','public.night_actions','select')::text
  union all
  select 7, 'الزائر (anon) بلا صلاحية select على أي جدول', '0',
    (select count(*)::text from tbl where has_table_privilege('anon','public.'||name,'select'))
  union all
  select 8, 'دوال RPC الـ26 موجودة', '26',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in ('create_room','join_room','leave_room','kick_member',
      'set_member_role','update_room_settings','invite_player','respond_invite','submit_report','start_game',
      'abort_game','get_my_role','submit_night_action','cast_vote','advance_phase','ping','hunter_shoot','set_boy_target','set_display_name','end_speech','boy_pull','send_message','set_room_voice_link','leave_game','add_bots','remove_bots'))
  union all
  select 9, 'الزائر لا ينفّذ cast_vote', 'false',
    has_function_privilege('anon','public.cast_vote(uuid,uuid)','execute')::text
  union all
  select 10, 'المسجّل ينفّذ cast_vote', 'true',
    has_function_privilege('authenticated','public.cast_vote(uuid,uuid)','execute')::text
  union all
  select 11, 'Trigger إنشاء الملف الشخصي موجود', '1',
    (select count(*)::text from pg_trigger where tgname='on_auth_user_created' and not tgisinternal)
  union all
  select 12, 'Realtime يشمل 7 جداول آمنة', '7',
    (select count(*)::text from pg_publication_tables where pubname='supabase_realtime' and schemaname='public'
      and tablename in ('rooms','room_members','games','game_players','vote_results','game_events','game_messages'))
  union all
  select 13, 'Realtime لا يشمل جداولًا سرية', '0',
    (select count(*)::text from pg_publication_tables where pubname='supabase_realtime' and schemaname='public'
      and tablename in ('game_secrets','night_actions','votes','reports'))
  union all
  select 15, 'الأدوار الجديدة موجودة (red_mafia, sheikh, boy, hunter, girl)', '5',
    (select count(*)::text from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='game_role' and e.enumlabel in ('red_mafia','sheikh','boy','hunter','girl'))
  union all
  select 16, 'الصياد والولد يملكان صلاحية التنفيذ', 'true',
    (has_function_privilege('authenticated','public.hunter_shoot(uuid,uuid)','execute') and has_function_privilege('authenticated','public.set_boy_target(uuid,uuid)','execute'))::text
  union all
  select 17, 'دور الإسكات وقدرته موجودان', '2',
    ((select count(*) from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='game_role' and e.enumlabel='silencer') + (select count(*) from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='night_action_type' and e.enumlabel='silence'))::text
  union all
  select 18, 'أعمدة الدورة الجديدة في games', '4',
    (select count(*)::text from information_schema.columns where table_schema='public' and table_name='games' and column_name in ('speech_order','speech_idx','silenced_id','vote_cycle'))
  union all
  select 19, 'عمود البوتات والغياب والصوت', '3',
    ((select count(*) from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='is_bot')
    + (select count(*) from information_schema.columns where table_schema='public' and table_name='game_players' and column_name='missed')
    + (select count(*) from information_schema.columns where table_schema='public' and table_name='rooms' and column_name='voice_link'))::text
  union all
  select 14, 'اتصال الخادم (ping)', 'true', (public.ping() ->> 'ok')
)
select n, check_name, expected, actual,
       case when expected = actual then 'OK' else 'CHECK' end as status
from checks order by n;
