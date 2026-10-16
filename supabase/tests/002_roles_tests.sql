-- ============================================================
-- اختبارات الأدوار الجديدة: الشيخ والبنت والصياد والولد (لعبة من 8 لاعبين).
-- للمشروع التجريبي فقط. ينشئ مستخدمين وهميين (@test.mafia.invalid) ويحذفهم في النهاية.
-- ============================================================

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

-- غرفة عامة من 8 لاعبين
select pg_temp.setctx('room', pg_temp.run_as(pg_temp.v(1), $q$select (public.create_room('غرفة الأدوار','public',8,false)).id::text$q$));
select pg_temp.expect('لاعب ' || i || ' ينضم',
  pg_temp.run_as(pg_temp.v(i), format('select (public.join_room(%L)).id::text', pg_temp.ctx('room'))), 'OK:%')
from generate_series(2, 8) i;
select pg_temp.setctx('game', pg_temp.run_as(pg_temp.v(1), format('select public.start_game(%L, 30, 30, 30, true)::text', pg_temp.ctx('room'))));

-- توزيع 8 لاعبين: أحمر + مافيا + بنت + شيخ + صياد + ولد + مواطنان
select pg_temp.expect('توزيع الأدوار لـ 8 لاعبين',
  (select string_agg(role::text || '=' || c, ',' order by role::text) from (
     select role, count(*) c from public.game_secrets where game_id = pg_temp.ctx('game')::uuid group by role) x),
  'boy=1,citizen=2,girl=1,hunter=1,mafia=1,red_mafia=1,sheikh=1');

select pg_temp.setctx('red',    pg_temp.role_user('red_mafia'));
select pg_temp.setctx('mafia',  pg_temp.role_user('mafia'));
select pg_temp.setctx('girl',   pg_temp.role_user('girl'));
select pg_temp.setctx('sheikh', pg_temp.role_user('sheikh'));
select pg_temp.setctx('hunter', pg_temp.role_user('hunter'));
select pg_temp.setctx('boy',    pg_temp.role_user('boy'));
select pg_temp.setctx('c1', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'citizen' order by user_id limit 1));
select pg_temp.setctx('c2', (select user_id::text from public.game_secrets where game_id = pg_temp.ctx('game')::uuid and role = 'citizen' order by user_id desc limit 1));

-- سرية الأدوار
select pg_temp.expect('المالك لا يقرأ game_secrets',
  pg_temp.run_as(pg_temp.v(1), 'select count(*)::text from public.game_secrets'), 'ERR:42501:%');
select pg_temp.expect('المافيا العادي يرى زميله الأحمر فقط',
  pg_temp.run_as(pg_temp.ctx('mafia'), format('select teammates::text from public.get_my_role(%L)', pg_temp.ctx('game'))),
  'OK:{' || pg_temp.ctx('red') || '}');
select pg_temp.expect('البنت لا ترى زملاء مافيا',
  pg_temp.run_as(pg_temp.ctx('girl'), format('select (teammates is null)::text from public.get_my_role(%L)', pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('الصياد معه طلقة واحدة',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select bullets::text from public.get_my_role(%L)', pg_temp.ctx('game'))), 'OK:1');

-- قدرات الليل: القيود
select pg_temp.expect('الصياد بلا قدرة ليلية',
  pg_temp.run_as(pg_temp.ctx('hunter'), format($q$select public.submit_night_action(%L,'skip')::text$q$, pg_temp.ctx('game'))), 'ERR:%no_night_ability');
select pg_temp.expect('الولد بلا قدرة ليلية',
  pg_temp.run_as(pg_temp.ctx('boy'), format($q$select public.submit_night_action(%L,'skip')::text$q$, pg_temp.ctx('game'))), 'ERR:%no_night_ability');
select pg_temp.expect('البنت لا تغتال',
  pg_temp.run_as(pg_temp.ctx('girl'), format($q$select public.submit_night_action(%L,'kill',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'ERR:%action_not_allowed');
select pg_temp.expect('المافيا لا تغتال الأحمر',
  pg_temp.run_as(pg_temp.ctx('mafia'), format($q$select public.submit_night_action(%L,'kill',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('red'))), 'ERR:%cannot_target_teammate');
select pg_temp.expect('الصياد لا يطلق ليلًا',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select public.hunter_shoot(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'ERR:%not_day_phase');

-- الولد يحدد من يسحبه معه (الأحمر)
select pg_temp.expect('غير الولد لا يحدد هدف سحب',
  pg_temp.run_as(pg_temp.ctx('c1'), format('select public.set_boy_target(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('red'))), 'ERR:%not_boy');
select pg_temp.expect('الولد يحدد هدفه',
  pg_temp.run_as(pg_temp.ctx('boy'), format('select public.set_boy_target(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('red'))), 'OK:true');

-- الليلة 1: الأحمر يغتال c1 والبنت تحمي c1 (ينجو)، والشيخ يفجّر c2 (يموت رغم أنه غير محمي)
select pg_temp.expect('الأحمر يغتال c1',
  pg_temp.run_as(pg_temp.ctx('red'), format($q$select public.submit_night_action(%L,'kill',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:true');
select pg_temp.expect('المافيا العادي يتخطى',
  pg_temp.run_as(pg_temp.ctx('mafia'), format($q$select public.submit_night_action(%L,'skip')::text$q$, pg_temp.ctx('game'))), 'OK:true');
select pg_temp.expect('البنت تحمي c1',
  pg_temp.run_as(pg_temp.ctx('girl'), format($q$select public.submit_night_action(%L,'protect',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:true');
select pg_temp.expect('المافيا العادي يرى اقتراح الأحمر (حدث مافيا)',
  pg_temp.run_as(pg_temp.ctx('mafia'), format($q$select count(*)::text from public.game_events where game_id=%L and event_type='mafia_suggestion'$q$, pg_temp.ctx('game'))), 'OK:%');
select pg_temp.expect('البنت لا ترى أحداث المافيا',
  pg_temp.run_as(pg_temp.ctx('girl'), format($q$select count(*)::text from public.game_events where game_id=%L and event_type='mafia_suggestion'$q$, pg_temp.ctx('game'))), 'OK:0');
select pg_temp.expect('لا ينتهي الليل قبل رد الشيخ',
  pg_temp.run_as(pg_temp.ctx('c1'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:night');
select pg_temp.expect('الشيخ يفجّر c2',
  pg_temp.run_as(pg_temp.ctx('sheikh'), format($q$select public.submit_night_action(%L,'bomb',%L)::text$q$, pg_temp.ctx('game'), pg_temp.ctx('c2'))), 'OK:true');
select pg_temp.expect('اكتمال الإجراءات ينقل للنهار',
  pg_temp.run_as(pg_temp.ctx('c1'), format('select public.advance_phase(%L)', pg_temp.ctx('game'))), 'OK:day');
select pg_temp.expect('c1 نجا بحماية البنت',
  pg_temp.run_as(pg_temp.v(1), format('select is_alive::text from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('c1'))), 'OK:true');
select pg_temp.expect('c2 مات بالتفجير',
  pg_temp.run_as(pg_temp.v(1), format('select (is_alive::text || eliminated_by::text) from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('c2'))), 'OK:falseexplosion');
select pg_temp.expect('الشيخ حي',
  pg_temp.run_as(pg_temp.v(1), format('select is_alive::text from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('sheikh'))), 'OK:true');

-- النهار: الصياد
select pg_temp.expect('غير الصياد لا يطلق',
  pg_temp.run_as(pg_temp.ctx('c1'), format('select public.hunter_shoot(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('mafia'))), 'ERR:%not_hunter');
select pg_temp.expect('الصياد لا يطلق على نفسه',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select public.hunter_shoot(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('hunter'))), 'ERR:%cannot_target_self');
select pg_temp.expect('الصياد يطلق على الولد',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select public.hunter_shoot(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('boy'))), 'OK:true');
select pg_temp.expect('الولد مات',
  pg_temp.run_as(pg_temp.v(1), format('select (is_alive::text || eliminated_by::text) from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('boy'))), 'OK:falsehunt');
select pg_temp.expect('الولد سحب الأحمر معه',
  pg_temp.run_as(pg_temp.v(1), format('select (is_alive::text || eliminated_by::text) from public.game_players where game_id=%L and user_id=%L', pg_temp.ctx('game'), pg_temp.ctx('red'))), 'OK:falsepulled');
select pg_temp.expect('لا طلقة ثانية للصياد',
  pg_temp.run_as(pg_temp.ctx('hunter'), format('select public.hunter_shoot(%L,%L)::text', pg_temp.ctx('game'), pg_temp.ctx('mafia'))), 'ERR:%no_bullets');
select pg_temp.expect('اللعبة مستمرة (مافيا واحد مقابل 4)',
  pg_temp.run_as(pg_temp.v(1), format('select status::text from public.games where id=%L', pg_temp.ctx('game'))), 'OK:in_progress');
select pg_temp.expect('الدور الجديد لا يكشف game_secrets',
  pg_temp.run_as(pg_temp.ctx('hunter'), 'select count(*)::text from public.game_secrets'), 'ERR:42501:%');
select pg_temp.expect('anon لا ينفّذ hunter_shoot',
  has_function_privilege('anon', 'public.hunter_shoot(uuid,uuid)', 'execute')::text, 'false');

delete from auth.users where email like '%@test.mafia.invalid';

select * from (
  select case when ok then 'PASS' else 'FAIL' end as result, name, left(detail, 140) as detail from t_results
  union all
  select '— الملخص —', count(*) filter (where ok)::text || ' نجح / ' || count(*) filter (where not ok)::text || ' فشل', null from t_results
) x
order by case when result like '—%' then 0 when result = 'FAIL' then 1 else 2 end, name;
