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

select * from (
  select case when ok then 'PASS' else 'FAIL' end as result, name, left(detail, 140) as detail from t_results
  union all
  select '— الملخص —', count(*) filter (where ok)::text || ' نجح / ' || count(*) filter (where not ok)::text || ' فشل', null from t_results
) x
order by case when result like '—%' then 0 when result = 'FAIL' then 1 else 2 end, name;
