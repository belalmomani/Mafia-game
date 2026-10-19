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

delete from public.rooms where owner_id in (select id from auth.users where email like '%@test.mafia.invalid');
delete from auth.users where email like '%@test.mafia.invalid';

select * from (
  select case when ok then 'PASS' else 'FAIL' end as result, name, left(detail, 140) as detail from t_results
  union all
  select '— الملخص —', count(*) filter (where ok)::text || ' نجح / ' || count(*) filter (where not ok)::text || ' فشل', null from t_results
) x
order by case when result like '—%' then 0 when result = 'FAIL' then 1 else 2 end, name;
