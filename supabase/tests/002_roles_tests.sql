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

select * from (
  select case when ok then 'PASS' else 'FAIL' end as result, name, left(detail, 140) as detail from t_results
  union all
  select '— الملخص —', count(*) filter (where ok)::text || ' نجح / ' || count(*) filter (where not ok)::text || ' فشل', null from t_results
) x
order by case when result like '—%' then 0 when result = 'FAIL' then 1 else 2 end, name;
