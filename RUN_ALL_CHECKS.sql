-- فحص شامل: verify + 001 + 002 + 003 + 004 في تشغيل واحد (مشروع تجريبي فقط)
drop table if exists pg_temp.all_results;
create temp table all_results (suite text, result text, name text, detail text);

-- ============================================================
-- فحص سريع بعد تنفيذ الملفات 0001 → 0007. شغّله كاملًا؛ تظهر نتيجة واحدة.
-- كل صف يجب أن تكون حالته OK.
-- ============================================================
insert into pg_temp.all_results (suite, result, name, detail)
with tbl(name) as (values
  ('profiles'),('rooms'),('room_members'),('room_invites'),('games'),('game_players'),
  ('game_secrets'),('night_actions'),('votes'),('vote_results'),('game_events'),('reports'),('game_messages'),('player_stats'),('app_admins'),('push_tokens'),('push_outbox')),
checks as (
  select 1 as n, 'الجداول الـ17 موجودة' as check_name, '17' as expected,
    (select count(*)::text from pg_tables where schemaname='public' and tablename in (select name from tbl)) as actual
  union all
  select 2, 'RLS مفعّل على كل الجداول', '17',
    (select count(*)::text from pg_tables where schemaname='public' and rowsecurity and tablename in (select name from tbl))
  union all
  select 3, 'عدد سياسات RLS', '13',
    (select count(*)::text from pg_policies where schemaname='public')
  union all
  select 4, 'لا سياسات على الجداول السرية (game_secrets, night_actions, app_admins)', '0',
    (select count(*)::text from pg_policies where schemaname='public' and tablename in ('game_secrets','night_actions','app_admins','push_tokens','push_outbox'))
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
  select 8, 'دوال RPC الـ41 موجودة', '41',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in ('create_room','join_room','leave_room','kick_member',
      'set_member_role','update_room_settings','invite_player','respond_invite','submit_report','start_game',
      'abort_game','get_my_role','submit_night_action','cast_vote','advance_phase','ping','hunter_shoot','set_boy_target','set_display_name','end_speech','boy_pull','send_message','set_room_voice_link','leave_game','add_bots','remove_bots','set_avatar','is_admin','admin_list_reports','admin_set_report_status','register_push_token','unregister_push_token','claim_admin','lab_start','lab_state','lab_act','lab_advance','lab_autofill','lab_list','lab_remove','delete_room'))
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
  select 20, 'أعمدة المختبر (bot_mode, is_lab)', '2',
    ((select count(*) from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='bot_mode')
    + (select count(*) from information_schema.columns where table_schema='public' and table_name='rooms' and column_name='is_lab'))::text
  union all
  select 14, 'اتصال الخادم (ping)', 'true', (public.ping() ->> 'ok')
)
select 'verify', case when expected = actual then 'PASS' else 'FAIL' end, check_name, 'المتوقع ' || expected || ' / الفعلي ' || actual from checks order by n;

-- ============================================================
-- اختبارات الصلاحيات ومنع التصويت المكرر وسرية الأدوار.
-- للمشروع التجريبي فقط. ينشئ مستخدمين وهميين (@test.mafia.invalid) ويحذفهم في النهاية.
-- شغّله كاملًا؛ النتيجة الأخيرة جدول PASS/FAIL (الإخفاقات تظهر أولًا).
-- ============================================================

-- نحذف الغرف أولًا (تحذف ألعابها ونتائجها بالتتابع)، ثم المستخدمين؛ لتفادي تعارض ترتيب الحذف داخل نفس المعاملة
delete from public.rooms where owner_id in (select id from auth.users where email like '%@test.mafia.invalid');
delete from auth.users where email like '%@test.mafia.invalid';

drop table if exists pg_temp.t_results;
drop table if exists pg_temp.t_ctx;
create temp table t_results (n serial primary key, name text, ok boolean, detail text);
create temp table t_ctx (k text primary key, v text);

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
select ('00000000-0000-4000-8000-0000000000a' || i)::uuid,
       '00000000-0000-0000-0000-000000000000'::uuid,
       'authenticated', 'authenticated', 'p' || i || '@test.mafia.invalid', now(), now()
from generate_series(1, 7) i;

-- ---------- أدوات الاختبار ----------
create or replace function pg_temp.u(i int) returns text language sql immutable as
$$ select '00000000-0000-4000-8000-0000000000a' || i $$;

create or replace function pg_temp.run_as(p_uid text, p_sql text, p_role text default 'authenticated')
returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
    reset role;
    return 'OK:' || coalesce(v, 'null');
  exception when others then
    reset role;
    return 'ERR:' || sqlstate || ':' || sqlerrm;
  end;
end $$;

create or replace function pg_temp.expect(p_name text, p_actual text, p_like text)
returns void language plpgsql as $$
begin
  insert into t_results (name, ok, detail) values (p_name, p_actual like p_like, p_actual);
end $$;

create or replace function pg_temp.setctx(p_k text, p_v text) returns void language plpgsql as $$
begin
  insert into t_ctx values (p_k, replace(p_v, 'OK:', '')) on conflict (k) do update set v = excluded.v;
end $$;

create or replace function pg_temp.ctx(p_k text) returns text language sql stable as
$$ select v from t_ctx where k = p_k $$;

-- ---------- 1) الأساسيات: profiles و anon ----------
select pg_temp.expect('trigger أنشأ 7 ملفات شخصية',
  (select count(*)::text from public.profiles where id::text like '00000000-0000-4000-8000-0000000000a%'), '7');
select pg_temp.expect('anon لا يقرأ profiles',
  pg_temp.run_as(null, 'select count(*)::text from public.profiles', 'anon'), 'ERR:42501:%');
select pg_temp.expect('anon لا ينفّذ create_room',
  pg_temp.run_as(null, $q$select (public.create_room('xx')).id::text$q$, 'anon'), 'ERR:42501:%');
select pg_temp.expect('anon ينفّذ ping',
  pg_temp.run_as(null, 'select public.ping()::text', 'anon'), 'OK:%"ok": true%');
select pg_temp.expect('اسم مستخدم غير صالح مرفوض',
  pg_temp.run_as(pg_temp.u(1), format($q$with u as (update public.profiles set username='x' where id=%L returning 1) select count(*)::text from u$q$, pg_temp.u(1))), 'ERR:23514:%');
select pg_temp.expect('لا يعدّل ملف لاعب آخر',
  pg_temp.run_as(pg_temp.u(1), format($q$with u as (update public.profiles set display_name='hack' where id=%L returning 1) select count(*)::text from u$q$, pg_temp.u(2))), 'OK:0');
select pg_temp.expect('لا يعدّل created_at',
  pg_temp.run_as(pg_temp.u(1), format($q$with u as (update public.profiles set created_at=now() where id=%L returning 1) select count(*)::text from u$q$, pg_temp.u(1))), 'ERR:42501:%');
select pg_temp.expect('يعدّل اسمه المعروض',
  pg_temp.run_as(pg_temp.u(1), format($q$with u as (update public.profiles set display_name='اختبار' where id=%L returning 1) select count(*)::text from u$q$, pg_temp.u(1))), 'OK:1');

-- ---------- 2) الغرف والعضوية ----------
select pg_temp.setctx('room', pg_temp.run_as(pg_temp.u(1), $q$select (public.create_room('غرفة اختبار','private',5,false)).id::text$q$));
select pg_temp.setctx('code', (select invite_code from public.rooms where id = pg_temp.ctx('room')::uuid));

select pg_temp.expect('المنشئ صار owner نشطًا',
  (select count(*)::text from public.room_members where room_id = pg_temp.ctx('room')::uuid and role = 'owner' and status = 'active'), '1');
select pg_temp.expect('غير العضو لا يرى الغرفة الخاصة',
  pg_temp.run_as(pg_temp.u(7), format('select count(*)::text from public.rooms where id=%L', pg_temp.ctx('room'))), 'OK:0');
select pg_temp.expect('رمز خاطئ مرفوض',
  pg_temp.run_as(pg_temp.u(7), $q$select (public.join_room(null,'WRONGCODE1')).id::text$q$), 'ERR:%room_not_found');
select pg_temp.expect('الدخول بمعرّف الغرفة الخاصة بلا رمز مرفوض',
  pg_temp.run_as(pg_temp.u(7), format('select (public.join_room(%L)).id::text', pg_temp.ctx('room'))), 'ERR:%room_not_found');
select pg_temp.expect('انضمام اللاعب ' || i || ' برمز الدعوة',
  pg_temp.run_as(pg_temp.u(i), format('select (public.join_room(null,%L)).id::text', pg_temp.ctx('code'))), 'OK:%')
from generate_series(2, 5) i;
select pg_temp.expect('الغرفة الممتلئة ترفض لاعبًا سادسًا',
  pg_temp.run_as(pg_temp.u(6), format('select (public.join_room(null,%L)).id::text', pg_temp.ctx('code'))), 'ERR:%room_full');
select pg_temp.expect('العضو يرى 5 أعضاء',
  pg_temp.run_as(pg_temp.u(2), format('select count(*)::text from public.room_members where room_id=%L', pg_temp.ctx('room'))), 'OK:5');
select pg_temp.expect('غير العضو لا يرى الأعضاء',
  pg_temp.run_as(pg_temp.u(7), format('select count(*)::text from public.room_members where room_id=%L', pg_temp.ctx('room'))), 'OK:0');
select pg_temp.expect('منع تكرار العضوية (قيد قاعدة البيانات)',
  pg_temp.run_as(null, format($q$with i as (insert into public.room_members(room_id,user_id) values (%L,%L) returning 1) select count(*)::text from i$q$, pg_temp.ctx('room'), pg_temp.u(2)), 'postgres'), 'ERR:23505:%');
select pg_temp.expect('عضو عادي لا يطرد',
  pg_temp.run_as(pg_temp.u(2), format('select public.kick_member(%L,%L)::text', pg_temp.ctx('room'), pg_temp.u(3))), 'ERR:%not_room_manager');
select pg_temp.expect('لا حذف مباشر من room_members',
  pg_temp.run_as(pg_temp.u(2), format($q$with d as (delete from public.room_members where room_id=%L returning 1) select count(*)::text from d$q$, pg_temp.ctx('room'))), 'ERR:42501:%');
select pg_temp.expect('عضو عادي لا يبدأ اللعبة',
  pg_temp.run_as(pg_temp.u(2), format('select public.start_game(%L)::text', pg_temp.ctx('room'))), 'ERR:%not_room_owner');
select pg_temp.expect('عضو عادي لا يعدّل الإعدادات',
  pg_temp.run_as(pg_temp.u(2), format($q$select (public.update_room_settings(%L,'x2'))::text$q$, pg_temp.ctx('room'))), 'ERR:%not_room_owner');

create or replace function pg_temp.to_voting(p_game text, p_user text) returns text language plpgsql as $$
declare i int := 0; v_phase text;
begin
  loop
    select phase::text into v_phase from public.games where id = p_game::uuid;
    exit when v_phase = 'voting' or i > 40;
    update public.games set phase_ends_at = now() - interval '1 second' where id = p_game::uuid;
    perform pg_temp.run_as(p_user, format('select public.advance_phase(%L)', p_game));
    i := i + 1;
  end loop;
  return v_phase;
end $$;

create or replace function pg_temp.vote_all(p_game text, p_target text, p_alt text) returns int language plpgsql as $$
declare r record; n int := 0;
begin
  for r in select user_id::text as u from public.game_players where game_id = p_game::uuid and is_alive loop
    perform pg_temp.run_as(r.u, format('select public.cast_vote(%L,%L)::text', p_game, case when r.u = p_target then p_alt else p_target end));
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------- 3) بدء اللعبة وسرية الأدوار ----------
-- رموز الإشعارات لكل اللاعبين قبل البدء
select pg_temp.expect('تسجيل رمز إشعار للاعب ' || i,
  pg_temp.run_as(pg_temp.u(i), format($q$select public.register_push_token(%L)::text$q$, 'test-push-token-padding-' || i)), 'OK:true')
from generate_series(1, 5) i;
select pg_temp.expect('رمز قصير مرفوض',
  pg_temp.run_as(pg_temp.u(1), $q$select public.register_push_token('short')::text$q$), 'ERR:%invalid_token');
select pg_temp.expect('anon لا يسجّل رمزًا',
  has_function_privilege('anon', 'public.register_push_token(text)', 'execute')::text, 'false');
select pg_temp.expect('العميل لا يقرأ push_tokens',
  pg_temp.run_as(pg_temp.u(1), 'select count(*)::text from public.push_tokens'), 'ERR:42501:%');
select pg_temp.expect('العميل لا يقرأ push_outbox',
  pg_temp.run_as(pg_temp.u(1), 'select count(*)::text from public.push_outbox'), 'ERR:42501:%');
select pg_temp.setctx('game', pg_temp.run_as(pg_temp.u(1), format('select public.start_game(%L, 30, 30, 30, true)::text', pg_temp.ctx('room'))));
select pg_temp.setctx('mafia', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'red_mafia'));
select pg_temp.setctx('girl',  (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'girl'));
select pg_temp.setctx('c1', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'citizen' order by user_id limit 1));
select pg_temp.setctx('c2', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'citizen' order by user_id desc limit 1));
select pg_temp.setctx('c3', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'citizen' and user_id::text not in (pg_temp.ctx('c1'), pg_temp.ctx('c2')) limit 1));

select pg_temp.expect('بدء اللعبة أضاف إشعار «دورك في الكلام» لصندوق الإرسال',
  (select (count(*) >= 1)::text from public.push_outbox where title = 'دورك في الكلام' and user_ids && array(select id from public.profiles where id::text like '00000000-0000-4000-8000-0000000000a%')), 'true');
select pg_temp.expect('وُزّعت 5 أدوار (مافيا أحمر واحد + بنت + 3 مواطنين)',
  (select count(*)::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid), '5');
select pg_temp.expect('اللعبة تبدأ بمرحلة التبرير',
  pg_temp.run_as(pg_temp.u(1), format('select phase::text from public.games where id=%L', pg_temp.ctx('game'))), 'OK:day');
select pg_temp.expect('المالك لا يقرأ game_secrets',
  pg_temp.run_as(pg_temp.u(1), 'select count(*)::text from public.game_secrets'), 'ERR:42501:%');
select pg_temp.expect('لاعب لا يقرأ game_secrets',
  pg_temp.run_as(pg_temp.u(2), 'select count(*)::text from public.game_secrets'), 'ERR:42501:%');
select pg_temp.expect('لاعب لا يقرأ night_actions',
  pg_temp.run_as(pg_temp.u(2), 'select count(*)::text from public.night_actions'), 'ERR:42501:%');
select pg_temp.expect('لا تعديل مباشر في games',
  pg_temp.run_as(pg_temp.u(1), format($q$with u as (update public.games set winner='mafia' where id=%L returning 1) select count(*)::text from u$q$, pg_temp.ctx('game'))), 'ERR:42501:%');
select pg_temp.expect('لا تعديل مباشر في game_players',
  pg_temp.run_as(pg_temp.u(1), format($q$with u as (update public.game_players set is_alive=false where game_id=%L returning 1) select count(*)::text from u$q$, pg_temp.ctx('game'))), 'ERR:42501:%');
select pg_temp.expect('لا إدخال مباشر في votes',
  pg_temp.run_as(pg_temp.u(2), format($q$with i as (insert into public.votes(game_id,round_no,voter_id) values (%L,1,%L) returning 1) select count(*)::text from i$q$, pg_temp.ctx('game'), pg_temp.u(2))), 'ERR:42501:%');
select pg_temp.expect('لا إدخال مباشر في vote_results',
  pg_temp.run_as(pg_temp.u(1), format($q$with i as (insert into public.vote_results(game_id,round_no) values (%L,9) returning 1) select count(*)::text from i$q$, pg_temp.ctx('game'))), 'ERR:42501:%');
select pg_temp.expect('لا إدخال مباشر في game_events',
  pg_temp.run_as(pg_temp.u(1), format($q$with i as (insert into public.game_events(game_id,event_type) values (%L,'x') returning 1) select count(*)::text from i$q$, pg_temp.ctx('game'))), 'ERR:42501:%');
select pg_temp.expect('لا حذف مباشر لـ games',
  pg_temp.run_as(pg_temp.u(1), format($q$with d as (delete from public.games where id=%L returning 1) select count(*)::text from d$q$, pg_temp.ctx('game'))), 'ERR:42501:%');
select pg_temp.expect('الغريب لا يرى اللعبة',
  pg_temp.run_as(pg_temp.u(7), 'select count(*)::text from public.games'), 'OK:0');
select pg_temp.expect('get_my_role: اللاعب يرى دوره فقط (صف واحد)',
  pg_temp.run_as(pg_temp.u(1), format('select count(*)::text from public.get_my_role(%L)', pg_temp.ctx('game'))), 'OK:1');
select pg_temp.expect('get_my_role: الغريب لا يحصل على شيء',
  pg_temp.run_as(pg_temp.u(7), format('select count(*)::text from public.get_my_role(%L)', pg_temp.ctx('game'))), 'OK:0');
select pg_temp.expect('دور المافيا الأحمر يطابق الخادم',
  pg_temp.run_as(pg_temp.ctx('mafia'), format('select my_role::text from public.get_my_role(%L)', pg_temp.ctx('game'))), 'OK:red_mafia');
select pg_temp.expect('غير المافيا لا يرى زملاء المافيا',
  pg_temp.run_as(pg_temp.ctx('girl'), format('select (teammates is null)::text from public.get_my_role(%L)', pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('لا دور مكشوف قبل الإقصاء',
  pg_temp.run_as(pg_temp.u(1), format('select count(revealed_role)::text from public.game_players where game_id=%L', pg_temp.ctx('game'))), 'OK:0');

-- ---------- 4) التبرير (دور لكل لاعب) ----------
select pg_temp.setctx('spk', (select speech_order[speech_idx + 1]::text from public.games where id = pg_temp.ctx('game')::uuid));
select pg_temp.setctx('nonspk', (select user_id::text from public.game_players where game_id = pg_temp.ctx('game')::uuid and user_id::text <> pg_temp.ctx('spk') limit 1));
select pg_temp.expect('عدد المتحدثين = 5',
  (select array_length(speech_order, 1)::text from public.games where id = pg_temp.ctx('game')::uuid), '5');
select pg_temp.expect('لا تصويت أثناء التبرير',
  pg_temp.run_as(pg_temp.ctx('c2'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('mafia'))), 'ERR:%not_voting_phase');
select pg_temp.expect('لا إجراء ليلي أثناء النهار',
  pg_temp.run_as(pg_temp.ctx('mafia'), format($q$select public.submit_night_action(%L,'skip')::text$q$, pg_temp.ctx('game'))), 'ERR:%not_night_phase');
select pg_temp.expect('غير المتحدث لا ينهي الدور',
  pg_temp.run_as(pg_temp.ctx('nonspk'), format('select public.end_speech(%L)::text', pg_temp.ctx('game'))), 'ERR:%not_your_turn');
select pg_temp.expect('المتحدث ينهي دوره',
  pg_temp.run_as(pg_temp.ctx('spk'), format('select public.end_speech(%L)::text', pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('انتقل الدور للمتحدث التالي',
  (select speech_idx::text from public.games where id = pg_temp.ctx('game')::uuid), '1');
select pg_temp.expect('بعد انتهاء كل الأدوار يبدأ التصويت',
  pg_temp.to_voting(pg_temp.ctx('game'), pg_temp.ctx('c2')), 'voting');

-- ---------- 5) التصويت الأول (يخرج مواطن فيأتي الليل) ----------
select pg_temp.expect('الغريب لا يصوّت',
  pg_temp.run_as(pg_temp.u(7), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('mafia'))), 'ERR:%not_a_player');
select pg_temp.expect('لا تصويت لنفسك',
  pg_temp.run_as(pg_temp.ctx('mafia'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('mafia'))), 'ERR:%cannot_vote_self');
select pg_temp.expect('التصويت الأول ينجح',
  pg_temp.run_as(pg_temp.ctx('mafia'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:true');
select pg_temp.expect('التصويت المكرر لنفس الهدف مرفوض',
  pg_temp.run_as(pg_temp.ctx('mafia'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'ERR:%already_voted');
select pg_temp.expect('تغيير الصوت مرفوض',
  pg_temp.run_as(pg_temp.ctx('mafia'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('girl'))), 'ERR:%already_voted');
select pg_temp.expect('منع التكرار على مستوى القاعدة (UNIQUE)',
  pg_temp.run_as(null, format($q$with i as (insert into public.votes(game_id,round_no,voter_id,target_id) values (%L,1,%L,%L) returning 1) select count(*)::text from i$q$, pg_temp.ctx('game'), pg_temp.ctx('mafia'), pg_temp.ctx('girl')), 'postgres'), 'ERR:23505:%');
select pg_temp.expect('البنت تصوّت',
  pg_temp.run_as(pg_temp.ctx('girl'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:true');
select pg_temp.expect('لا يرى اللاعب أصوات غيره أثناء التصويت',
  pg_temp.run_as(pg_temp.ctx('girl'), format('select count(*)::text from public.votes where game_id=%L and voter_id <> %L', pg_temp.ctx('game'), pg_temp.ctx('girl'))), 'OK:0');
select pg_temp.expect('المالك لا يرى أصوات غيره قبل الحسم',
  pg_temp.run_as(pg_temp.u(1), format('select count(*)::text from public.votes where game_id=%L and voter_id <> %L', pg_temp.ctx('game'), pg_temp.u(1))), 'OK:0');
select pg_temp.expect('advance_phase لا يتقدم قبل اكتمال الأصوات',
  pg_temp.run_as(pg_temp.ctx('girl'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:voting');
select pg_temp.expect('c2 يصوّت',
  pg_temp.run_as(pg_temp.ctx('c2'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:true');
select pg_temp.expect('c3 يصوّت',
  pg_temp.run_as(pg_temp.ctx('c3'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:true');
select pg_temp.expect('c1 يصوّت على الأحمر فيكتمل التصويت',
  pg_temp.run_as(pg_temp.ctx('c1'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('mafia'))), 'OK:true');
select pg_temp.expect('خرج مواطن (c1) فجاء الليل',
  pg_temp.run_as(pg_temp.ctx('girl'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:night');
select pg_temp.expect('c1 مات بالتصويت وكُشف دوره',
  pg_temp.run_as(pg_temp.u(1), format('select (is_alive::text || eliminated_by::text || coalesce(revealed_role::text, %L)) from public.game_players where game_id=%L and user_id=%L', '', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:falsevotecitizen');
select pg_temp.expect('المالك يرى سجل التصويت التفصيلي بعد الحسم (5 أصوات)',
  pg_temp.run_as(pg_temp.u(1), format('select count(*)::text from public.votes where game_id=%L', pg_temp.ctx('game'))), 'OK:5');
select pg_temp.setctx('other_voter', (select voter_id::text from public.votes where game_id = pg_temp.ctx('game')::uuid and voter_id::text <> pg_temp.u(1) limit 1));
select pg_temp.expect('العضو العادي يرى صوته فقط (public_votes=false)',
  pg_temp.run_as(pg_temp.ctx('other_voter'), format('select count(*)::text from public.votes where game_id=%L', pg_temp.ctx('game'))), 'OK:1');

-- ---------- الليل: اغتيال فاشل لأن البنت حمت نفسها ----------
select pg_temp.expect('لا تصويت أثناء الليل',
  pg_temp.run_as(pg_temp.ctx('c2'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('mafia'))), 'ERR:%not_voting_phase');
select pg_temp.expect('المواطن بلا قدرة ليلية',
  pg_temp.run_as(pg_temp.ctx('c2'), format($q$select public.submit_night_action(%L,'skip')::text$q$, pg_temp.ctx('game'))), 'ERR:%no_night_ability');
select pg_temp.expect('المواطن لا يغتال',
  pg_temp.run_as(pg_temp.ctx('c2'), format($q$select public.submit_night_action(%L,'kill',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('c3'))), 'ERR:%action_not_allowed');
select pg_temp.expect('المافيا لا تغتال نفسها',
  pg_temp.run_as(pg_temp.ctx('mafia'), format($q$select public.submit_night_action(%L,'kill',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('mafia'))), 'ERR:%cannot_target_self');
select pg_temp.expect('الميت لا يُستهدف',
  pg_temp.run_as(pg_temp.ctx('mafia'), format($q$select public.submit_night_action(%L,'kill',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'ERR:%target_dead');
select pg_temp.expect('المافيا الأحمر يغتال البنت',
  pg_temp.run_as(pg_temp.ctx('mafia'), format($q$select public.submit_night_action(%L,'kill',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('girl'))), 'OK:true');
select pg_temp.expect('البنت تحمي نفسها',
  pg_temp.run_as(pg_temp.ctx('girl'), format($q$select public.submit_night_action(%L,'protect',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('girl'))), 'OK:true');
select pg_temp.expect('اكتمال الإجراءات ينقل للنهار',
  pg_temp.run_as(pg_temp.ctx('c2'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:day');
select pg_temp.expect('عملية اغتيال فاشلة تُسجَّل في نتيجة الليل',
  pg_temp.run_as(pg_temp.ctx('c2'), format($q$select (payload ->> 'assassination_failed') from public.game_events where game_id=%L and event_type='night_result'$q$, pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('البنت نجت',
  pg_temp.run_as(pg_temp.u(1), format('select is_alive::text from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('girl'))), 'OK:true');

-- ---------- النهار 2: يخرج الأحمر (آخر مافيا) فتنتهي اللعبة ----------
select pg_temp.expect('تبرير النهار الثاني ثم التصويت',
  pg_temp.to_voting(pg_temp.ctx('game'), pg_temp.ctx('c2')), 'voting');
select pg_temp.expect('التصويت في دورة جديدة مسموح لمن صوّت سابقًا',
  pg_temp.run_as(pg_temp.ctx('c2'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('mafia'))), 'OK:true');
select pg_temp.expect('بقية الأحياء يصوّتون (4 أحياء)',
  pg_temp.vote_all(pg_temp.ctx('game'), pg_temp.ctx('mafia'), pg_temp.ctx('girl'))::text, '4');
select pg_temp.expect('اكتمال الأصوات يحسم اللعبة (يُستدعى advance_phase)',
  pg_temp.run_as(pg_temp.ctx('girl'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:ended');
select pg_temp.expect('اللعبة انتهت: فاز المواطنون',
  pg_temp.run_as(pg_temp.u(1), format('select (status::text || winner::text) from public.games where id=%L', pg_temp.ctx('game'))), 'OK:finishedcitizens');
select pg_temp.expect('نتيجتا تصويت (دورتان)',
  pg_temp.run_as(pg_temp.u(2), format('select count(*)::text from public.vote_results where game_id=%L', pg_temp.ctx('game'))), 'OK:2');
select pg_temp.expect('كُشفت كل الأدوار بعد النهاية',
  pg_temp.run_as(pg_temp.u(2), format('select count(revealed_role)::text from public.game_players where game_id=%L', pg_temp.ctx('game'))), 'OK:5');
select pg_temp.expect('لا تصويت بعد انتهاء اللعبة',
  pg_temp.run_as(pg_temp.ctx('girl'), format('select public.cast_vote(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('mafia'))), 'ERR:%game_not_active');
select pg_temp.expect('الغرفة عادت مفتوحة',
  pg_temp.run_as(pg_temp.u(1), format('select status::text from public.rooms where id=%L', pg_temp.ctx('room'))), 'OK:open');
select pg_temp.expect('game_secrets ما زال مغلقًا بعد النهاية',
  pg_temp.run_as(pg_temp.u(1), 'select count(*)::text from public.game_secrets'), 'ERR:42501:%');

-- ---------- 6) الدعوات والبلاغات والطرد ----------
select pg_temp.expect('عضو عادي لا يدعو',
  pg_temp.run_as(pg_temp.u(2), format('select public.invite_player(%L,%L)::text', pg_temp.ctx('room'), pg_temp.u(7))), 'ERR:%not_room_manager');
select pg_temp.setctx('invite', pg_temp.run_as(pg_temp.u(1), format('select public.invite_player(%L,%L)::text', pg_temp.ctx('room'), pg_temp.u(7))));
select pg_temp.expect('المدعو يرى دعوته',
  pg_temp.run_as(pg_temp.u(7), 'select count(*)::text from public.room_invites'), 'OK:1');
select pg_temp.expect('غير المدعو لا يرى الدعوة',
  pg_temp.run_as(pg_temp.u(6), 'select count(*)::text from public.room_invites'), 'OK:0');
select pg_temp.expect('قبول دعوة لغرفة ممتلئة مرفوض',
  pg_temp.run_as(pg_temp.u(7), format('select public.respond_invite(%L,true)::text', pg_temp.ctx('invite'))), 'ERR:%room_full');
select pg_temp.expect('رفض الدعوة',
  pg_temp.run_as(pg_temp.u(7), format('select public.respond_invite(%L,false)::text', pg_temp.ctx('invite'))), 'OK:true');

select pg_temp.expect('بلاغ صالح',
  pg_temp.run_as(pg_temp.u(2), format($q$select public.submit_report(%L,'cheating','اختبار',null,%L)::text$q$, pg_temp.u(3), pg_temp.ctx('game'))), 'OK:%');
select pg_temp.expect('لا بلاغ على النفس',
  pg_temp.run_as(pg_temp.u(2), format($q$select public.submit_report(%L,'spam','',null,%L)::text$q$, pg_temp.u(2), pg_temp.ctx('game'))), 'ERR:%cannot_report_self');
select pg_temp.expect('لا بلاغ بلا سياق مشترك',
  pg_temp.run_as(pg_temp.u(2), format($q$select public.submit_report(%L,'spam','',null,null)::text$q$, pg_temp.u(7))), 'ERR:%invalid_context');
select pg_temp.expect('بلاغ مكرر مرفوض',
  pg_temp.run_as(pg_temp.u(2), format($q$select public.submit_report(%L,'cheating','',null,%L)::text$q$, pg_temp.u(3), pg_temp.ctx('game'))), 'ERR:%already_reported');
select pg_temp.expect('المبلِّغ يرى بلاغه',
  pg_temp.run_as(pg_temp.u(2), 'select count(*)::text from public.reports'), 'OK:1');
select pg_temp.expect('غير المبلِّغ لا يرى البلاغ (ولا الملبَّغ عنه)',
  pg_temp.run_as(pg_temp.u(3), 'select count(*)::text from public.reports'), 'OK:0');
select pg_temp.expect('لا إدخال مباشر في reports',
  pg_temp.run_as(pg_temp.u(2), format($q$with i as (insert into public.reports(reporter_id,reported_id,reason) values (%L,%L,'spam') returning 1) select count(*)::text from i$q$, pg_temp.u(2), pg_temp.u(4))), 'ERR:42501:%');

select pg_temp.expect('المالك يطرد لاعبًا',
  pg_temp.run_as(pg_temp.u(1), format('select public.kick_member(%L,%L)::text', pg_temp.ctx('room'), pg_temp.u(5))), 'OK:true');
select pg_temp.expect('المطرود لا يعود',
  pg_temp.run_as(pg_temp.u(5), format('select (public.join_room(null,%L)).id::text', pg_temp.ctx('code'))), 'ERR:%kicked_from_room');
select pg_temp.expect('عدد الأعضاء تحدّث تلقائيًا إلى 4',
  pg_temp.run_as(pg_temp.u(1), format('select member_count::text from public.rooms where id=%L', pg_temp.ctx('room'))), 'OK:4');

-- ---------- 6ب) الإحصاءات والصور والإدارة ----------
select pg_temp.expect('الإحصاءات سُجّلت لـ 5 لاعبين',
  (select count(*)::text from public.player_stats where user_id::text like '00000000-0000-4000-8000-0000000000a%'), '5');
select pg_temp.expect('فاز 4 (المواطنون) وخسر الأحمر',
  (select sum(wins)::text from public.player_stats where user_id::text like '00000000-0000-4000-8000-0000000000a%'), '4');
select pg_temp.expect('اللاعب يقرأ الترتيب',
  pg_temp.run_as(pg_temp.u(2), 'select (count(*) >= 5)::text from public.player_stats'), 'OK:true');
select pg_temp.expect('لا كتابة مباشرة في الإحصاءات',
  pg_temp.run_as(pg_temp.u(2), format($q$with u as (update public.player_stats set wins = 99 where user_id=%L returning 1) select count(*)::text from u$q$, pg_temp.u(2))), 'ERR:42501:%');
select pg_temp.expect('رمز صورة طويل مرفوض',
  pg_temp.run_as(pg_temp.u(2), $q$select public.set_avatar('123456789')$q$), 'ERR:%invalid_avatar');
select pg_temp.expect('تعيين صورة رمزية',
  pg_temp.run_as(pg_temp.u(2), $q$select public.set_avatar('🦊')$q$), 'OK:%');
select pg_temp.expect('غير المشرف لا يرى البلاغات',
  pg_temp.run_as(pg_temp.u(2), $q$select count(*)::text from public.admin_list_reports()$q$), 'ERR:%not_admin');
select pg_temp.expect('is_admin = false للعادي',
  pg_temp.run_as(pg_temp.u(2), 'select public.is_admin()::text'), 'OK:false');
select pg_temp.expect('لا قراءة مباشرة لجدول المشرفين',
  pg_temp.run_as(pg_temp.u(1), 'select count(*)::text from public.app_admins'), 'ERR:42501:%');
insert into public.app_admins (user_id) values (pg_temp.u(1)::uuid);
select pg_temp.expect('المشرف يرى البلاغ المفتوح',
  pg_temp.run_as(pg_temp.u(1), 'select count(*)::text from public.admin_list_reports()'), 'OK:1');
select pg_temp.setctx('rep', (select id::text from public.reports order by created_at desc limit 1));
select pg_temp.expect('غير المشرف لا يغيّر حالة البلاغ',
  pg_temp.run_as(pg_temp.u(2), format($q$select public.admin_set_report_status(%L,'resolved')::text$q$, pg_temp.ctx('rep'))), 'ERR:%not_admin');
select pg_temp.expect('المشرف يحل البلاغ',
  pg_temp.run_as(pg_temp.u(1), format($q$select public.admin_set_report_status(%L,'resolved')::text$q$, pg_temp.ctx('rep'))), 'OK:true');
select pg_temp.expect('anon لا ينفّذ admin_list_reports',
  has_function_privilege('anon', 'public.admin_list_reports(text,integer)', 'execute')::text, 'false');
select pg_temp.expect('دالة التنظيف موجودة (لا تُشغَّل هنا كي لا تمسّ بياناتك الحقيقية)',
  (to_regprocedure('private.cleanup_old_data()') is not null)::text, 'true');

-- ---------- 7) فحوص بنيوية ----------
select pg_temp.expect('RLS مفعّل على كل جداول public',
  (select count(*)::text from pg_tables where schemaname = 'public' and not rowsecurity), '0');
select pg_temp.expect('لا سياسات على الجداول السرية',
  (select count(*)::text from pg_policies where schemaname = 'public' and tablename in ('game_secrets', 'night_actions')), '0');
select pg_temp.expect('anon لا يملك تنفيذ cast_vote',
  has_function_privilege('anon', 'public.cast_vote(uuid,uuid)', 'execute')::text, 'false');
select pg_temp.expect('authenticated لا يملك صلاحية على game_secrets',
  has_table_privilege('authenticated', 'public.game_secrets', 'select')::text, 'false');

-- ---------- تنظيف ثم النتيجة ----------
-- نحذف الغرف أولًا (تحذف ألعابها ونتائجها بالتتابع)، ثم المستخدمين؛ لتفادي تعارض ترتيب الحذف داخل نفس المعاملة
delete from public.rooms where owner_id in (select id from auth.users where email like '%@test.mafia.invalid');
delete from auth.users where email like '%@test.mafia.invalid';

insert into pg_temp.all_results (suite, result, name, detail)
select '001', case when ok then 'PASS' else 'FAIL' end, name, left(detail, 400) from t_results order by n;


-- ============================================================
-- اختبارات الأدوار الجديدة: الشيخ والبنت والصياد والولد (لعبة من 8 لاعبين).
-- للمشروع التجريبي فقط. ينشئ مستخدمين وهميين (@test.mafia.invalid) ويحذفهم في النهاية.
-- ============================================================

-- نحذف الغرف أولًا (تحذف ألعابها ونتائجها بالتتابع)، ثم المستخدمين؛ لتفادي تعارض ترتيب الحذف داخل نفس المعاملة
delete from public.rooms where owner_id in (select id from auth.users where email like '%@test.mafia.invalid');
delete from auth.users where email like '%@test.mafia.invalid';

drop table if exists pg_temp.t_results;
drop table if exists pg_temp.t_ctx;
create temp table t_results (n serial primary key, name text, ok boolean, detail text);
create temp table t_ctx (k text primary key, v text);

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
select ('00000000-0000-4000-8000-00000000b0' || lpad(i::text, 2, '0'))::uuid,
       '00000000-0000-0000-0000-000000000000'::uuid,
       'authenticated', 'authenticated', 'v' || i || '@test.mafia.invalid', now(), now()
from generate_series(1, 8) i;

-- ---------- أدوات الاختبار ----------
create or replace function pg_temp.u(i int) returns text language sql immutable as
$$ select '00000000-0000-4000-8000-0000000000a' || i $$;

create or replace function pg_temp.run_as(p_uid text, p_sql text, p_role text default 'authenticated')
returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
    reset role;
    return 'OK:' || coalesce(v, 'null');
  exception when others then
    reset role;
    return 'ERR:' || sqlstate || ':' || sqlerrm;
  end;
end $$;

create or replace function pg_temp.expect(p_name text, p_actual text, p_like text)
returns void language plpgsql as $$
begin
  insert into t_results (name, ok, detail) values (p_name, p_actual like p_like, p_actual);
end $$;

create or replace function pg_temp.setctx(p_k text, p_v text) returns void language plpgsql as $$
begin
  insert into t_ctx values (p_k, replace(p_v, 'OK:', '')) on conflict (k) do update set v = excluded.v;
end $$;

create or replace function pg_temp.ctx(p_k text) returns text language sql stable as
$$ select v from t_ctx where k = p_k $$;


create or replace function pg_temp.v(i int) returns text language sql immutable as
$$ select '00000000-0000-4000-8000-00000000b0' || lpad(i::text, 2, '0') $$;

create or replace function pg_temp.role_user(p_role text) returns text language sql stable as
$$ select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = p_role::public.game_role order by user_id limit 1 $$;

create or replace function pg_temp.to_voting(p_game text, p_user text) returns text language plpgsql as $$
declare i int := 0; v_phase text;
begin
  loop
    select phase::text into v_phase from public.games where id = p_game::uuid;
    exit when v_phase = 'voting' or i > 40;
    update public.games set phase_ends_at = now() - interval '1 second' where id = p_game::uuid;
    perform pg_temp.run_as(p_user, format('select public.advance_phase(%L)', p_game));
    i := i + 1;
  end loop;
  return v_phase;
end $$;

create or replace function pg_temp.vote_all(p_game text, p_target text, p_alt text) returns int language plpgsql as $$
declare r record; n int := 0;
begin
  for r in select user_id::text as u from public.game_players where game_id = p_game::uuid and is_alive loop
    perform pg_temp.run_as(r.u, format('select public.cast_vote(%L,%L)::text', p_game, case when r.u = p_target then p_alt else p_target end));
    n := n + 1;
  end loop;
  return n;
end $$;

-- غرفة عامة من 8 لاعبين
select pg_temp.setctx('room', pg_temp.run_as(pg_temp.v(1), $q$select (public.create_room('غرفة الأدوار','public',8,false)).id::text$q$));
select pg_temp.expect('لاعب ' || i || ' ينضم',
  pg_temp.run_as(pg_temp.v(i), format('select (public.join_room(%L)).id::text', pg_temp.ctx('room'))), 'OK:%')
from generate_series(2, 8) i;
-- مع تفعيل مافيا الإسكات
select pg_temp.setctx('game', pg_temp.run_as(pg_temp.v(1), format('select public.start_game(%L, 30, 30, 30, true, true)::text', pg_temp.ctx('room'))));

select pg_temp.expect('توزيع 8 لاعبين مع الإسكات',
  (select string_agg(role::text || '=' || c, ',' order by role::text) from (
     select role, count(*) c from public.game_secrets where game_id = pg_temp.ctx('game')::uuid group by role) x),
  'boy=1,citizen=2,girl=1,hunter=1,red_mafia=1,sheikh=1,silencer=1');

select pg_temp.setctx('red',    pg_temp.role_user('red_mafia'));
select pg_temp.setctx('sil',    pg_temp.role_user('silencer'));
select pg_temp.setctx('girl',   pg_temp.role_user('girl'));
select pg_temp.setctx('sheikh', pg_temp.role_user('sheikh'));
select pg_temp.setctx('hunter', pg_temp.role_user('hunter'));
select pg_temp.setctx('boy',    pg_temp.role_user('boy'));
select pg_temp.setctx('c1', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'citizen' order by user_id limit 1));
select pg_temp.setctx('c2', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'citizen' order by user_id desc limit 1));

-- سرية الأدوار
select pg_temp.expect('المالك لا يقرأ game_secrets',
  pg_temp.run_as(pg_temp.v(1), 'select count(*)::text from public.game_secrets'), 'ERR:42501:%');
select pg_temp.expect('الأحمر يرى زميله الإسكات فقط',
  pg_temp.run_as(pg_temp.ctx('red'), format('select teammates::text from public.get_my_role(%L)', pg_temp.ctx('game'))), 'OK:{' || pg_temp.ctx('sil') || '}');
select pg_temp.expect('الإسكات يرى زميله الأحمر فقط',
  pg_temp.run_as(pg_temp.ctx('sil'), format('select teammates::text from public.get_my_role(%L)', pg_temp.ctx('game'))), 'OK:{' || pg_temp.ctx('red') || '}');
select pg_temp.expect('البنت لا ترى زملاء مافيا',
  pg_temp.run_as(pg_temp.ctx('girl'), format('select (teammates is null)::text from public.get_my_role(%L)', pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('الصياد معه طلقة واحدة',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select bullets::text from public.get_my_role(%L)', pg_temp.ctx('game'))), 'OK:1');
select pg_temp.expect('اللعبة تبدأ بالتبرير',
  pg_temp.run_as(pg_temp.v(1), format('select phase::text from public.games where id=%L', pg_temp.ctx('game'))), 'OK:day');

-- الولد يحدد من يسحبه معه (c1)
select pg_temp.expect('غير الولد لا يحدد هدف سحب',
  pg_temp.run_as(pg_temp.ctx('c2'), format('select public.set_boy_target(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('red'))), 'ERR:%not_boy');
select pg_temp.expect('الولد يحدد هدفه c1',
  pg_temp.run_as(pg_temp.ctx('boy'), format('select public.set_boy_target(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:true');

-- النهار 1: الصياد يطلق على الولد فيسحب الولد c1 معه
select pg_temp.expect('غير الصياد لا يطلق',
  pg_temp.run_as(pg_temp.ctx('c2'), format('select public.hunter_shoot(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('red'))), 'ERR:%not_hunter');
select pg_temp.expect('الصياد لا يطلق على نفسه',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select public.hunter_shoot(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('hunter'))), 'ERR:%cannot_target_self');
select pg_temp.expect('الصياد يطلق على الولد',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select public.hunter_shoot(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('boy'))), 'OK:true');
select pg_temp.expect('الولد مات برصاصة',
  pg_temp.run_as(pg_temp.v(1), format('select (is_alive::text || eliminated_by::text) from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('boy'))), 'OK:falsehunt');
select pg_temp.expect('c1 ما زال حيًا حتى يختار الولد (مهلة 20 ثانية)',
  pg_temp.run_as(pg_temp.v(1), format('select is_alive::text from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:true');
select pg_temp.expect('غير الولد لا يسحب',
  pg_temp.run_as(pg_temp.ctx('c2'), format('select public.boy_pull(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'ERR:%no_pending_pull');
select pg_temp.expect('الولد الميت يسحب c1 بنفسه',
  pg_temp.run_as(pg_temp.ctx('boy'), format('select public.boy_pull(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:true');
select pg_temp.expect('الولد سحب c1 معه',
  pg_temp.run_as(pg_temp.v(1), format('select (is_alive::text || eliminated_by::text) from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:falsepulled');
select pg_temp.expect('لا طلقة ثانية للصياد',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select public.hunter_shoot(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('red'))), 'ERR:%no_bullets');
select pg_temp.expect('اللعبة مستمرة',
  pg_temp.run_as(pg_temp.v(1), format('select status::text from public.games where id=%L', pg_temp.ctx('game'))), 'OK:in_progress');

-- تبرير ثم تصويت 1: يخرج المواطن c2 (غير مافيا) فيأتي الليل
select pg_temp.expect('الانتقال إلى التصويت بعد التبرير',
  pg_temp.to_voting(pg_temp.ctx('game'), pg_temp.ctx('red')), 'voting');
select pg_temp.expect('الأحياء الستة يصوّتون',
  pg_temp.vote_all(pg_temp.ctx('game'), pg_temp.ctx('c2'), pg_temp.ctx('red'))::text, '6');
select pg_temp.expect('خرج مواطن فجاء الليل',
  pg_temp.run_as(pg_temp.ctx('red'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:night');
select pg_temp.expect('c2 مات بالتصويت',
  pg_temp.run_as(pg_temp.v(1), format('select (is_alive::text || eliminated_by::text) from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('c2'))), 'OK:falsevote');

-- الليل 1: اغتيال فاشل (البنت تحمي نفسها) + إسكات الشيخ
select pg_temp.expect('الإسكات لا يغتال',
  pg_temp.run_as(pg_temp.ctx('sil'), format($q$select public.submit_night_action(%L,'kill',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('girl'))), 'ERR:%action_not_allowed');
select pg_temp.expect('الإسكات لا يُسكت زميله',
  pg_temp.run_as(pg_temp.ctx('sil'), format($q$select public.submit_night_action(%L,'silence',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('red'))), 'ERR:%cannot_target_teammate');
select pg_temp.expect('الإسكات يُسكت الشيخ',
  pg_temp.run_as(pg_temp.ctx('sil'), format($q$select public.submit_night_action(%L,'silence',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('sheikh'))), 'OK:true');
select pg_temp.expect('الأحمر يغتال البنت',
  pg_temp.run_as(pg_temp.ctx('red'), format($q$select public.submit_night_action(%L,'kill',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('girl'))), 'OK:true');
select pg_temp.expect('الإسكات يرى اقتراح الأحمر (حدث مافيا)',
  pg_temp.run_as(pg_temp.ctx('sil'), format($q$select (count(*) >= 2)::text from public.game_events where game_id=%L and event_type='mafia_suggestion'$q$, pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('البنت لا ترى أحداث المافيا',
  pg_temp.run_as(pg_temp.ctx('girl'), format($q$select count(*)::text from public.game_events where game_id=%L and event_type='mafia_suggestion'$q$, pg_temp.ctx('game'))), 'OK:0');
select pg_temp.expect('البنت تحمي نفسها',
  pg_temp.run_as(pg_temp.ctx('girl'), format($q$select public.submit_night_action(%L,'protect',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('girl'))), 'OK:true');
select pg_temp.expect('لا ينتهي الليل قبل رد الشيخ',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:night');
select pg_temp.expect('الشيخ يتخطى',
  pg_temp.run_as(pg_temp.ctx('sheikh'), format($q$select public.submit_night_action(%L,'skip')::text$q$, pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('اكتمال الإجراءات ينقل للنهار',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:day');
select pg_temp.expect('عملية اغتيال فاشلة',
  pg_temp.run_as(pg_temp.ctx('hunter'), format($q$select (payload ->> 'assassination_failed') from public.game_events where game_id=%L and event_type='night_result'$q$, pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('البنت حية',
  pg_temp.run_as(pg_temp.v(1), format('select is_alive::text from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('girl'))), 'OK:true');
select pg_temp.expect('الجولة 2',
  (select round_no::text from public.games where id = pg_temp.ctx('game')::uuid), '2');
select pg_temp.expect('الشيخ مُسكَت (معلن)',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select (silenced_id = %L)::text from public.games where id=%L', pg_temp.ctx('sheikh'), pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('المُسكَت خارج قائمة المتحدثين',
  (select (not (speech_order @> array[pg_temp.ctx('sheikh')::uuid]))::text from public.games where id = pg_temp.ctx('game')::uuid), 'true');
select pg_temp.expect('عدد المتحدثين 4 (5 أحياء ناقص المُسكَت)',
  (select array_length(speech_order, 1)::text from public.games where id = pg_temp.ctx('game')::uuid), '4');

-- النهار 2: يخرج الإسكات (مافيا) والأحمر حي: تبرير جديد وتصويت جديد بلا ليل
select pg_temp.expect('التصويت الثاني',
  pg_temp.to_voting(pg_temp.ctx('game'), pg_temp.ctx('red')), 'voting');
select pg_temp.expect('الأحياء الخمسة يصوّتون ضد الإسكات',
  pg_temp.vote_all(pg_temp.ctx('game'), pg_temp.ctx('sil'), pg_temp.ctx('red'))::text, '5');
select pg_temp.expect('خرج مافيا: يبدأ تبرير جديد (لا ليل)',
  pg_temp.run_as(pg_temp.ctx('red'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:day');
select pg_temp.expect('نفس الجولة ودورة تصويت جديدة',
  (select round_no::text || '/' || vote_cycle::text from public.games where id = pg_temp.ctx('game')::uuid), '2/3');
select pg_temp.expect('الإسكات مات بالتصويت',
  pg_temp.run_as(pg_temp.v(1), format('select (is_alive::text || eliminated_by::text) from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('sil'))), 'OK:falsevote');

-- تبرير جديد ثم تصويت: يخرج الأحمر (آخر مافيا) فيفوز المواطنون
select pg_temp.expect('التصويت الثالث',
  pg_temp.to_voting(pg_temp.ctx('game'), pg_temp.ctx('red')), 'voting');
select pg_temp.expect('الأحياء الأربعة يصوّتون ضد الأحمر (يصوّتون مجددًا في دورة جديدة)',
  pg_temp.vote_all(pg_temp.ctx('game'), pg_temp.ctx('red'), pg_temp.ctx('girl'))::text, '4');
select pg_temp.expect('اكتمال الأصوات يحسم اللعبة (يُستدعى advance_phase)',
  pg_temp.run_as(pg_temp.ctx('girl'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:ended');
select pg_temp.expect('فاز المواطنون',
  pg_temp.run_as(pg_temp.v(1), format('select (status::text || winner::text) from public.games where id=%L', pg_temp.ctx('game'))), 'OK:finishedcitizens');
select pg_temp.expect('3 نتائج تصويت',
  pg_temp.run_as(pg_temp.v(2), format('select count(*)::text from public.vote_results where game_id=%L', pg_temp.ctx('game'))), 'OK:3');
select pg_temp.expect('كُشفت كل الأدوار',
  pg_temp.run_as(pg_temp.v(2), format('select count(revealed_role)::text from public.game_players where game_id=%L', pg_temp.ctx('game'))), 'OK:8');
select pg_temp.expect('game_secrets مغلق بعد النهاية',
  pg_temp.run_as(pg_temp.ctx('hunter'), 'select count(*)::text from public.game_secrets'), 'ERR:42501:%');
select pg_temp.expect('anon لا ينفّذ end_speech',
  has_function_privilege('anon', 'public.end_speech(uuid)', 'execute')::text, 'false');

-- توزيع الأدوار حسب ceil(n/5) (دالة داخلية، تُفحص من حساب الإدارة)
select pg_temp.expect('10 لاعبين = 2 مافيا',
  (select count(*)::text from unnest(private.build_role_deck(10, false)) r where r in ('red_mafia','mafia','silencer')), '2');
select pg_temp.expect('11 لاعبًا = 3 مافيا',
  (select count(*)::text from unnest(private.build_role_deck(11, false)) r where r in ('red_mafia','mafia','silencer')), '3');
select pg_temp.expect('5 لاعبين = مافيا واحد (الأحمر)',
  (select string_agg(r::text, ',') from unnest(private.build_role_deck(5, true)) r where r in ('red_mafia','mafia','silencer')), 'red_mafia');
select pg_temp.expect('6 لاعبين مع الإسكات = أحمر + إسكات',
  (select string_agg(r::text, ',' order by r::text) from unnest(private.build_role_deck(6, true)) r where r in ('red_mafia','mafia','silencer')), 'red_mafia,silencer');

delete from public.rooms where owner_id in (select id from auth.users where email like '%@test.mafia.invalid');
delete from auth.users where email like '%@test.mafia.invalid';

insert into pg_temp.all_results (suite, result, name, detail)
select '002', case when ok then 'PASS' else 'FAIL' end, name, left(detail, 400) from t_results order by n;


-- ============================================================
-- اختبارات الميزات: البوتات، الدردشة، الانسحاب، الغياب، رابط الصوت.
-- للمشروع التجريبي فقط. ينشئ مستخدمين وهميين (@test.mafia.invalid) ويحذفهم في النهاية.
-- ============================================================

-- نحذف الغرف أولًا (تحذف ألعابها ونتائجها بالتتابع)، ثم المستخدمين؛ لتفادي تعارض ترتيب الحذف داخل نفس المعاملة
delete from public.rooms where owner_id in (select id from auth.users where email like '%@test.mafia.invalid');
delete from auth.users where email like '%@test.mafia.invalid';

drop table if exists pg_temp.t_results;
drop table if exists pg_temp.t_ctx;
create temp table t_results (n serial primary key, name text, ok boolean, detail text);
create temp table t_ctx (k text primary key, v text);

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
select ('00000000-0000-4000-8000-00000000b0' || lpad(i::text, 2, '0'))::uuid,
       '00000000-0000-0000-0000-000000000000'::uuid,
       'authenticated', 'authenticated', 'v' || i || '@test.mafia.invalid', now(), now()
from generate_series(1, 8) i;

-- ---------- أدوات الاختبار ----------
create or replace function pg_temp.u(i int) returns text language sql immutable as
$$ select '00000000-0000-4000-8000-0000000000a' || i $$;

create or replace function pg_temp.run_as(p_uid text, p_sql text, p_role text default 'authenticated')
returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
    reset role;
    return 'OK:' || coalesce(v, 'null');
  exception when others then
    reset role;
    return 'ERR:' || sqlstate || ':' || sqlerrm;
  end;
end $$;

create or replace function pg_temp.expect(p_name text, p_actual text, p_like text)
returns void language plpgsql as $$
begin
  insert into t_results (name, ok, detail) values (p_name, p_actual like p_like, p_actual);
end $$;

create or replace function pg_temp.setctx(p_k text, p_v text) returns void language plpgsql as $$
begin
  insert into t_ctx values (p_k, replace(p_v, 'OK:', '')) on conflict (k) do update set v = excluded.v;
end $$;

create or replace function pg_temp.ctx(p_k text) returns text language sql stable as
$$ select v from t_ctx where k = p_k $$;


create or replace function pg_temp.v(i int) returns text language sql immutable as
$$ select '00000000-0000-4000-8000-00000000b0' || lpad(i::text, 2, '0') $$;

create or replace function pg_temp.to_voting(p_game text, p_user text) returns text language plpgsql as $$
declare i int := 0; v_phase text;
begin
  loop
    select phase::text into v_phase from public.games where id = p_game::uuid;
    exit when v_phase = 'voting' or i > 40;
    update public.games set phase_ends_at = now() - interval '1 second' where id = p_game::uuid;
    perform pg_temp.run_as(p_user, format('select public.advance_phase(%L)', p_game));
    i := i + 1;
  end loop;
  return v_phase;
end $$;

create or replace function pg_temp.vote_all(p_game text, p_target text, p_alt text) returns int language plpgsql as $$
declare r record; n int := 0;
begin
  for r in select user_id::text as u from public.game_players where game_id = p_game::uuid and is_alive loop
    perform pg_temp.run_as(r.u, format('select public.cast_vote(%L,%L)::text', p_game, case when r.u = p_target then p_alt else p_target end));
    n := n + 1;
  end loop;
  return n;
end $$;


-- غرفة صغيرة (4) يملكها اللاعب 1، ثم 3 بوتات
select pg_temp.setctx('room', pg_temp.run_as(pg_temp.v(1), $q$select (public.create_room('غرفة البوتات','public',4,false)).id::text$q$));
select pg_temp.expect('غير المالك لا يضيف بوتات',
  pg_temp.run_as(pg_temp.v(2), format('select public.add_bots(%L,3)::text', pg_temp.ctx('room'))), 'ERR:%not_room_owner');
select pg_temp.expect('المالك يضيف 3 بوتات',
  pg_temp.run_as(pg_temp.v(1), format('select public.add_bots(%L,3)::text', pg_temp.ctx('room'))), 'OK:3');
select pg_temp.expect('لا مكان لبوت رابع',
  pg_temp.run_as(pg_temp.v(1), format('select public.add_bots(%L,1)::text', pg_temp.ctx('room'))), 'ERR:%room_full');
select pg_temp.expect('البوتات موسومة',
  (select count(*)::text from public.room_members m join public.profiles p on p.id = m.user_id where m.room_id = pg_temp.ctx('room')::uuid and p.is_bot), '3');

-- رابط الصوت
select pg_temp.expect('رابط غير https مرفوض',
  pg_temp.run_as(pg_temp.v(1), format($q$select public.set_room_voice_link(%L,'http://x.com')$q$, pg_temp.ctx('room'))), 'ERR:%');
select pg_temp.expect('المالك يضبط رابط الصوت',
  pg_temp.run_as(pg_temp.v(1), format($q$select public.set_room_voice_link(%L,'https://meet.example.com/abc')$q$, pg_temp.ctx('room'))), 'OK:https://meet.example.com/abc');
select pg_temp.expect('غير المالك لا يضبط الرابط',
  pg_temp.run_as(pg_temp.v(2), format($q$select public.set_room_voice_link(%L,'https://x.com')$q$, pg_temp.ctx('room'))), 'ERR:%not_room_owner');

select pg_temp.setctx('game', pg_temp.run_as(pg_temp.v(1), format('select public.start_game(%L, 30, 30, 30, true)::text', pg_temp.ctx('room'))));
select pg_temp.expect('بدأت لعبة مع بوتات',
  (select status::text from public.games where id = pg_temp.ctx('game')::uuid), 'in_progress');

-- الدردشة: اللاعب 1 يتكلم فقط حين يكون دوره
update public.games set speech_idx = array_position(speech_order, pg_temp.v(1)::uuid) - 1, phase_ends_at = now() + interval '60 seconds'
 where id = pg_temp.ctx('game')::uuid;
select pg_temp.expect('المتحدث يرسل رسالة',
  pg_temp.run_as(pg_temp.v(1), format($q$select public.send_message(%L,'أنا بريء')::text$q$, pg_temp.ctx('game'))), 'OK:%');
select pg_temp.expect('رسالة فارغة مرفوضة',
  pg_temp.run_as(pg_temp.v(1), format($q$select public.send_message(%L,'   ')::text$q$, pg_temp.ctx('game'))), 'ERR:%invalid_message');
select pg_temp.expect('قناة المافيا نهارًا مرفوضة',
  pg_temp.run_as(pg_temp.v(1), format($q$select public.send_message(%L,'x','mafia')::text$q$, pg_temp.ctx('game'))), 'ERR:%');
select pg_temp.expect('الرسالة مرئية لأعضاء الغرفة',
  pg_temp.run_as(pg_temp.v(1), format('select count(*)::text from public.game_messages where game_id=%L', pg_temp.ctx('game'))), 'OK:1');
select pg_temp.expect('غريب لا يرى الرسائل',
  pg_temp.run_as(pg_temp.v(2), format('select count(*)::text from public.game_messages where game_id=%L', pg_temp.ctx('game'))), 'OK:0');
select pg_temp.expect('لا إدخال مباشر في game_messages',
  pg_temp.run_as(pg_temp.v(1), format($q$with i as (insert into public.game_messages(game_id,user_id,body) values (%L,%L,'x') returning 1) select count(*)::text from i$q$, pg_temp.ctx('game'), pg_temp.v(1))), 'ERR:42501:%');
select pg_temp.expect('anon لا ينفّذ add_bots',
  has_function_privilege('anon', 'public.add_bots(uuid,integer)', 'execute')::text, 'false');

-- البوتات تلعب والبشري لا يفعل شيئًا: اللعبة تنتهي (الغياب لا يعطّلها)
select pg_temp.expect('البشري ينسحب من اللعبة',
  pg_temp.run_as(pg_temp.v(1), format('select public.leave_game(%L)::text', pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('سبب إقصائه: انسحاب',
  (select eliminated_by::text from public.game_players where game_id = pg_temp.ctx('game')::uuid and user_id = pg_temp.v(1)::uuid), 'left');
select pg_temp.expect('لا يستطيع الانسحاب مرتين',
  pg_temp.run_as(pg_temp.v(1), format('select public.leave_game(%L)::text', pg_temp.ctx('game'))), 'ERR:%');

create or replace function pg_temp.drive(p_game text, p_user text) returns text language plpgsql as $$
declare i int := 0; v_status text; v_res text; v_err text := ''; v_diag text := '';
begin
  loop
    select status::text into v_status from public.games where id = p_game::uuid;
    exit when v_status <> 'in_progress' or i >= 200;
    update public.games set phase_ends_at = now() - interval '1 second' where id = p_game::uuid;
    update public.games set pending_pull_until = now() - interval '1 second' where id = p_game::uuid and pending_pull is not null;
    v_res := pg_temp.run_as(p_user, format('select public.advance_phase(%L)', p_game));
    if v_res like 'ERR:%' and v_err = '' then v_err := v_res; end if;
    i := i + 1;
  end loop;
  select g.phase::text || ' round=' || g.round_no || ' cycle=' || g.vote_cycle || ' status=' || g.status::text
         || ' alive=' || (select count(*) from public.game_players p where p.game_id = g.id and p.is_alive)
         || ' pending_pull=' || coalesce(g.pending_pull::text, '-') || ' last=' || coalesce(v_res, '-')
         || ' ; night_actions=' || (select count(*) from public.night_actions a where a.game_id = g.id)
         || ' votes=' || (select count(*) from public.votes v where v.game_id = g.id)
         || ' vote_results=' || (select count(*) from public.vote_results r where r.game_id = g.id)
         || ' ties=' || (select count(*) from public.vote_results r where r.game_id = g.id and r.is_tie)
         || ' elim=' || (select count(*) from public.vote_results r where r.game_id = g.id and r.eliminated_user_id is not null)
         || ' alive_roles=' || coalesce((select string_agg(s.role::text, ',') from public.game_players p
                                         join public.game_secrets s on s.game_id = p.game_id and s.user_id = p.user_id
                                         where p.game_id = g.id and p.is_alive), '-')
    into v_diag from public.games g where g.id = p_game::uuid;
  return i::text || '|' || v_err || '|' || v_diag;
end $$;

select pg_temp.setctx('drive', pg_temp.drive(pg_temp.ctx('game'), pg_temp.v(1)));
select pg_temp.expect('البوتات تُنهي اللعبة بدون تدخل بشري (أقل من 200 خطوة)',
  (split_part(pg_temp.ctx('drive'), '|', 1)::int < 200)::text, 'true');
select pg_temp.expect('تشخيص حالة اللعبة بعد التشغيل (للمطوّر)', split_part(pg_temp.ctx('drive'), '|', 3), '%');
select pg_temp.expect('لا أخطاء أثناء تشغيل البوتات (الخطأ يظهر في العمود detail إن وُجد)',
  split_part(pg_temp.ctx('drive'), '|', 2), '');
select pg_temp.expect('انتهت اللعبة بفائز',
  (select (status::text <> 'in_progress' and winner is not null)::text from public.games where id = pg_temp.ctx('game')::uuid), 'true');

select pg_temp.expect('إزالة البوتات بعد اللعبة',
  pg_temp.run_as(pg_temp.v(1), format('select public.remove_bots(%L)::text', pg_temp.ctx('room'))), 'OK:3');
select pg_temp.expect('لم يبقَ بوتات',
  (select count(*)::text from public.profiles where is_bot and display_name like 'بوت %' and id::text in (select user_id::text from public.room_members where room_id = pg_temp.ctx('room')::uuid)), '0');

-- حذف الغرفة
select pg_temp.setctx('droom', pg_temp.run_as(pg_temp.v(2), $q$select (public.create_room('غرفة للحذف','public',4,false)).id::text$q$));
select pg_temp.expect('غير المالك لا يحذف الغرفة',
  pg_temp.run_as(pg_temp.v(3), format('select public.delete_room(%L)::text', pg_temp.ctx('droom'))), 'ERR:%not_room_owner');
select pg_temp.expect('anon لا ينفّذ delete_room',
  has_function_privilege('anon', 'public.delete_room(uuid)', 'execute')::text, 'false');
select pg_temp.expect('المالك يحذف غرفته',
  pg_temp.run_as(pg_temp.v(2), format('select public.delete_room(%L)::text', pg_temp.ctx('droom'))), 'OK:true');
select pg_temp.expect('الغرفة اختفت',
  (select count(*)::text from public.rooms where id = pg_temp.ctx('droom')::uuid), '0');
select pg_temp.expect('حذف غرفة غير موجودة يفشل',
  pg_temp.run_as(pg_temp.v(2), format('select public.delete_room(%L)::text', pg_temp.ctx('droom'))), 'ERR:%room_not_found');

delete from public.rooms where owner_id in (select id from auth.users where email like '%@test.mafia.invalid');
delete from auth.users where email like '%@test.mafia.invalid';

insert into pg_temp.all_results (suite, result, name, detail)
select '003', case when ok then 'PASS' else 'FAIL' end, name, left(detail, 400) from t_results order by n;


-- ============================================================
-- اختبارات مختبر المشرف.
-- للمشروع التجريبي فقط. ينشئ مستخدمين وهميين (@test.mafia.invalid) ويحذفهم في النهاية.
-- ============================================================

-- نحذف الغرف أولًا (تحذف ألعابها ونتائجها بالتتابع)، ثم المستخدمين؛ لتفادي تعارض ترتيب الحذف داخل نفس المعاملة
delete from public.rooms where owner_id in (select id from auth.users where email like '%@test.mafia.invalid');
delete from auth.users where email like '%@test.mafia.invalid';

drop table if exists pg_temp.t_results;
drop table if exists pg_temp.t_ctx;
create temp table t_results (n serial primary key, name text, ok boolean, detail text);
create temp table t_ctx (k text primary key, v text);

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
select ('00000000-0000-4000-8000-00000000b0' || lpad(i::text, 2, '0'))::uuid,
       '00000000-0000-0000-0000-000000000000'::uuid,
       'authenticated', 'authenticated', 'v' || i || '@test.mafia.invalid', now(), now()
from generate_series(1, 8) i;

-- ---------- أدوات الاختبار ----------
create or replace function pg_temp.u(i int) returns text language sql immutable as
$$ select '00000000-0000-4000-8000-0000000000a' || i $$;

create or replace function pg_temp.run_as(p_uid text, p_sql text, p_role text default 'authenticated')
returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
    reset role;
    return 'OK:' || coalesce(v, 'null');
  exception when others then
    reset role;
    return 'ERR:' || sqlstate || ':' || sqlerrm;
  end;
end $$;

create or replace function pg_temp.expect(p_name text, p_actual text, p_like text)
returns void language plpgsql as $$
begin
  insert into t_results (name, ok, detail) values (p_name, p_actual like p_like, p_actual);
end $$;

create or replace function pg_temp.setctx(p_k text, p_v text) returns void language plpgsql as $$
begin
  insert into t_ctx values (p_k, replace(p_v, 'OK:', '')) on conflict (k) do update set v = excluded.v;
end $$;

create or replace function pg_temp.ctx(p_k text) returns text language sql stable as
$$ select v from t_ctx where k = p_k $$;


create or replace function pg_temp.v(i int) returns text language sql immutable as
$$ select '00000000-0000-4000-8000-00000000b0' || lpad(i::text, 2, '0') $$;

create or replace function pg_temp.lab_to_voting(p_game text, p_admin text) returns text language plpgsql as $$
declare i int := 0; v_phase text;
begin
  loop
    select phase::text into v_phase from public.games where id = p_game::uuid;
    exit when v_phase = 'voting' or v_phase = 'ended' or i > 60;
    perform pg_temp.run_as(p_admin, format('select public.lab_advance(%L, true)', p_game));
    i := i + 1;
  end loop;
  return v_phase;
end $$;

create or replace function pg_temp.lab_vote_all(p_game text, p_admin text, p_victim text, p_alt text) returns int language plpgsql as $$
declare r record; n int := 0;
begin
  for r in select user_id::text as u from public.game_players where game_id = p_game::uuid and is_alive loop
    perform pg_temp.run_as(p_admin, format('select public.lab_act(%L,%L,%L,%L)', p_game, r.u, 'vote', case when r.u = p_victim then p_alt else p_victim end));
    n := n + 1;
  end loop;
  return n;
end $$;

-- v1 مشرف، وv2 لاعب عادي
insert into public.app_admins (user_id) values (pg_temp.v(1)::uuid) on conflict do nothing;

select pg_temp.expect('غير المشرف لا ينشئ مختبرًا',
  pg_temp.run_as(pg_temp.v(2), 'select public.lab_start(4)::text'), 'ERR:%not_admin');
select pg_temp.expect('anon لا ينفّذ lab_start',
  has_function_privilege('anon', 'public.lab_start(integer,boolean,integer,integer,integer)', 'execute')::text, 'false');
select pg_temp.expect('بريد غير مخوّل لا يطالب بالإدارة',
  pg_temp.run_as(pg_temp.v(2), 'select public.claim_admin()::text'), 'ERR:%not_allowed');

select pg_temp.setctx('game', pg_temp.run_as(pg_temp.v(1), 'select public.lab_start(4, false, 30, 30, 30)::text'));
select pg_temp.expect('المشرف أنشأ لعبة مختبر',
  (select (g.status = 'in_progress' and r.is_lab)::text from public.games g join public.rooms r on r.id = g.room_id where g.id = pg_temp.ctx('game')::uuid), 'true');
select pg_temp.expect('عرض المشرف: 4 لاعبين بأدوارهم',
  pg_temp.run_as(pg_temp.v(1), format($q$select jsonb_array_length((public.lab_state(%L)) -> 'players')::text$q$, pg_temp.ctx('game'))), 'OK:4');
select pg_temp.expect('عرض المشرف يكشف الأدوار',
  pg_temp.run_as(pg_temp.v(1), format($q$select (count(*) filter (where p ->> 'role' is not null))::text from jsonb_array_elements((public.lab_state(%L)) -> 'players') p$q$, pg_temp.ctx('game'))), 'OK:4');
select pg_temp.expect('غير المشرف لا يرى عرض المشرف',
  pg_temp.run_as(pg_temp.v(2), format('select public.lab_state(%L)::text', pg_temp.ctx('game'))), 'ERR:%not_admin');

select pg_temp.setctx('spk', (select speech_order[speech_idx + 1]::text from public.games where id = pg_temp.ctx('game')::uuid));
select pg_temp.setctx('nonspk', (select user_id::text from public.game_players where game_id = pg_temp.ctx('game')::uuid and user_id::text <> pg_temp.ctx('spk') limit 1));
select pg_temp.expect('غير المشرف لا ينفّذ lab_act',
  pg_temp.run_as(pg_temp.v(2), format($q$select public.lab_act(%L,%L,'end_speech')$q$, pg_temp.ctx('game'), pg_temp.ctx('spk'))), 'ERR:%not_admin');
select pg_temp.expect('قواعد اللعبة تُطبَّق على الوهمي: غير المتحدث لا ينهي الدور',
  pg_temp.run_as(pg_temp.v(1), format($q$select public.lab_act(%L,%L,'end_speech')$q$, pg_temp.ctx('game'), pg_temp.ctx('nonspk'))), 'ERR:%not_your_turn');
select pg_temp.expect('المشرف ينهي دور المتحدث الوهمي',
  pg_temp.run_as(pg_temp.v(1), format($q$select public.lab_act(%L,%L,'end_speech')$q$, pg_temp.ctx('game'), pg_temp.ctx('spk'))), 'OK:ok');
select pg_temp.expect('تقدم الدور',
  (select speech_idx::text from public.games where id = pg_temp.ctx('game')::uuid), '1');
select pg_temp.expect('لاعب حقيقي ليس من المختبر مرفوض',
  pg_temp.run_as(pg_temp.v(1), format($q$select public.lab_act(%L,%L,'end_speech')$q$, pg_temp.ctx('game'), pg_temp.v(2))), 'ERR:%not_lab_player');

select pg_temp.expect('الانتقال السريع إلى التصويت',
  pg_temp.lab_to_voting(pg_temp.ctx('game'), pg_temp.v(1)), 'voting');
select pg_temp.setctx('victim', (select user_id::text from public.game_players where game_id = pg_temp.ctx('game')::uuid and is_alive order by seat_no limit 1));
select pg_temp.setctx('alt', (select user_id::text from public.game_players where game_id = pg_temp.ctx('game')::uuid and is_alive and user_id::text <> pg_temp.ctx('victim') order by seat_no limit 1));
select pg_temp.expect('المشرف يصوّت بدل 4 لاعبين',
  pg_temp.lab_vote_all(pg_temp.ctx('game'), pg_temp.v(1), pg_temp.ctx('victim'), pg_temp.ctx('alt'))::text, '4');
select pg_temp.expect('تسجيل 4 أصوات',
  (select count(*)::text from public.votes where game_id = pg_temp.ctx('game')::uuid), '4');
select pg_temp.expect('التقدم بعد التصويت (ليل أو نهاية)',
  pg_temp.run_as(pg_temp.v(1), format('select public.lab_advance(%L, false)', pg_temp.ctx('game'))), 'OK:%');
select pg_temp.expect('لم تعد المرحلة تصويتًا',
  (select (phase::text <> 'voting')::text from public.games where id = pg_temp.ctx('game')::uuid), 'true');
select pg_temp.expect('تعبئة عشوائية للباقين تعمل',
  pg_temp.run_as(pg_temp.v(1), format('select public.lab_autofill(%L)::text', pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('قائمة المختبر تعرض اللعبة',
  pg_temp.run_as(pg_temp.v(1), 'select (jsonb_array_length(public.lab_list()) >= 1)::text'), 'OK:true');

select pg_temp.setctx('room', (select room_id::text from public.games where id = pg_temp.ctx('game')::uuid));
select pg_temp.expect('حذف المختبر يحذف 4 وهميين',
  pg_temp.run_as(pg_temp.v(1), format('select public.lab_remove(%L)::text', pg_temp.ctx('room'))), 'OK:4');
select pg_temp.expect('لا بقايا للوهميين',
  (select count(*)::text from public.profiles where bot_mode = 'manual' and is_bot and display_name like 'لاعب %'), '0');

delete from public.app_admins where user_id = pg_temp.v(1)::uuid;
delete from public.rooms where owner_id in (select id from auth.users where email like '%@test.mafia.invalid');
delete from auth.users where email like '%@test.mafia.invalid';

insert into pg_temp.all_results (suite, result, name, detail)
select '004', case when ok then 'PASS' else 'FAIL' end, name, left(detail, 400) from t_results order by n;


select * from (
  select 'الملخص' as suite, case when count(*) filter (where result = 'FAIL') = 0 then 'كله ناجح' else 'يوجد إخفاق' end as result,
         count(*) filter (where result = 'PASS')::text || ' نجح / ' || count(*) filter (where result = 'FAIL')::text || ' فشل' as name, null as detail
    from pg_temp.all_results
  union all
  select suite, result, name, detail from pg_temp.all_results where result = 'FAIL' or name like 'تشخيص%'
) x
order by case when suite = 'الملخص' then 0 when result = 'FAIL' then 1 else 2 end, suite, name;
