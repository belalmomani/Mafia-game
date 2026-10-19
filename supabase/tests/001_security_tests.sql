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
select pg_temp.setctx('game', pg_temp.run_as(pg_temp.u(1), format('select public.start_game(%L, 30, 30, 30, true)::text', pg_temp.ctx('room'))));
select pg_temp.setctx('mafia', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'red_mafia'));
select pg_temp.setctx('girl',  (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'girl'));
select pg_temp.setctx('c1', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'citizen' order by user_id limit 1));
select pg_temp.setctx('c2', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'citizen' order by user_id desc limit 1));
select pg_temp.setctx('c3', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'citizen' and user_id::text not in (pg_temp.ctx('c1'), pg_temp.ctx('c2')) limit 1));

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

select * from (
  select case when ok then 'PASS' else 'FAIL' end as result, name, left(detail, 140) as detail
  from t_results
  union all
  select '— الملخص —', count(*) filter (where ok)::text || ' نجح / ' || count(*) filter (where not ok)::text || ' فشل', null
  from t_results
) x
order by case when result like '—%' then 0 when result = 'FAIL' then 1 else 2 end, name;
