-- ============================================================
-- 0006 — منطق اللعبة على الخادم (المرجع النهائي)
-- الأدوار توزَّع هنا، والاغتيال/الحماية/الطلقة/التفجير والتصويت تُحسم هنا.
-- ترتيب حسم الليل: التفجير (يتجاوز الحماية) ← الاغتيال (أغلبية المافيا، التعادل = لا اغتيال)
-- ← الطلقة. الحماية تُبطل الاغتيال والطلقة ولا تُبطل التفجير. المحقق يرى نتيجته سرًا.
-- ============================================================

create or replace function private.build_role_deck(p_n integer)
returns public.game_role[] language plpgsql immutable set search_path = '' as $$
declare
  v_deck public.game_role[] := '{}';
  v_mafia integer := greatest(1, p_n / 4);
  i integer;
begin
  for i in 1..v_mafia loop v_deck := v_deck || 'mafia'::public.game_role; end loop;
  v_deck := v_deck || 'doctor'::public.game_role || 'detective'::public.game_role;
  if p_n >= 7 then v_deck := v_deck || 'gunner'::public.game_role; end if;
  if p_n >= 9 then v_deck := v_deck || 'bomber'::public.game_role; end if;
  while coalesce(array_length(v_deck, 1), 0) < p_n loop v_deck := v_deck || 'citizen'::public.game_role; end loop;
  return v_deck;
end $$;

create or replace function private.check_winner(p_game_id uuid)
returns public.game_winner language sql stable set search_path = '' as $$
  select (case when x.m = 0 then 'citizens' when x.m >= x.o then 'mafia' end)::public.game_winner
  from (
    select count(*) filter (where s.role = 'mafia') as m,
           count(*) filter (where s.role <> 'mafia') as o
    from public.game_players p
    join public.game_secrets s on s.game_id = p.game_id and s.user_id = p.user_id
    where p.game_id = p_game_id and p.is_alive
  ) x;
$$;

create or replace function private.finish_game(p_game_id uuid, p_winner public.game_winner)
returns void language plpgsql security definer set search_path = '' as $$
declare v_room uuid; v_round integer;
begin
  update public.game_players p set revealed_role = s.role
    from public.game_secrets s
   where s.game_id = p.game_id and s.user_id = p.user_id and p.game_id = p_game_id;

  update public.games set status = 'finished', phase = 'ended', winner = p_winner,
         ended_at = now(), phase_ends_at = null
   where id = p_game_id
  returning room_id, round_no into v_room, v_round;

  update public.rooms set status = 'open' where id = v_room and status = 'in_game';

  insert into public.game_events (game_id, round_no, event_type, payload)
  values (p_game_id, v_round, 'game_ended', jsonb_build_object(
    'winner', p_winner,
    'roles', (select jsonb_agg(jsonb_build_object('user_id', s.user_id, 'role', s.role))
                from public.game_secrets s where s.game_id = p_game_id)));
end $$;

create or replace function private.night_all_submitted(p_game_id uuid, p_round integer)
returns boolean language sql stable set search_path = '' as $$
  select not exists (
    select 1
    from public.game_secrets s
    join public.game_players p on p.game_id = s.game_id and p.user_id = s.user_id
    where s.game_id = p_game_id and p.is_alive and s.role <> 'citizen'
      and not (s.role = 'gunner' and s.bullets_left = 0)
      and not (s.role = 'bomber' and s.bomb_used)
      and not exists (select 1 from public.night_actions a
                      where a.game_id = s.game_id and a.round_no = p_round and a.actor_id = s.user_id)
  );
$$;

create or replace function private.all_voted(p_game_id uuid, p_round integer)
returns boolean language sql stable set search_path = '' as $$
  select not exists (
    select 1 from public.game_players p
    where p.game_id = p_game_id and p.is_alive
      and not exists (select 1 from public.votes v
                      where v.game_id = p.game_id and v.round_no = p_round and v.voter_id = p.user_id)
  );
$$;

-- ---------- حسم الليل ----------
create or replace function private.resolve_night(p_game public.games)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_round integer := p_game.round_no;
  v_protect uuid; v_kill uuid; v_bomber uuid; v_bomb_target uuid;
  v_dead uuid[] := '{}';
  v_deaths jsonb := '[]'::jsonb;
  v_explosion jsonb := null;
  v_role public.game_role;
  v_cause public.elimination_cause;
  v_winner public.game_winner;
  r record;
begin
  select a.target_id into v_protect from public.night_actions a
   where a.game_id = p_game.id and a.round_no = v_round and a.action = 'protect' limit 1;

  update public.game_secrets s
     set last_protected_id = (select a.target_id from public.night_actions a
                              where a.game_id = s.game_id and a.round_no = v_round
                                and a.actor_id = s.user_id and a.action = 'protect')
   where s.game_id = p_game.id and s.role = 'doctor';

  -- التفجير
  select a.actor_id, a.target_id into v_bomber, v_bomb_target from public.night_actions a
   where a.game_id = p_game.id and a.round_no = v_round and a.action = 'bomb' limit 1;
  if v_bomber is not null then
    update public.game_secrets set bomb_used = true where game_id = p_game.id and user_id = v_bomber;
    v_dead := array[v_bomber, v_bomb_target];
    v_explosion := jsonb_build_object('bomber_id', v_bomber, 'target_id', v_bomb_target);
  end if;

  -- اغتيال المافيا (أغلبية؛ التعادل = لا اغتيال)
  with c as (
    select a.target_id, count(*) as n from public.night_actions a
     where a.game_id = p_game.id and a.round_no = v_round and a.action = 'kill'
     group by a.target_id)
  select case when (select count(*) from c where c.n = (select max(c2.n) from c c2)) = 1
              then (select c3.target_id from c c3 order by c3.n desc limit 1) end
    into v_kill;
  if v_kill is not null and v_kill is distinct from v_protect then v_dead := v_dead || v_kill; end if;

  -- الطلقات
  for r in select a.actor_id, a.target_id from public.night_actions a
            where a.game_id = p_game.id and a.round_no = v_round and a.action = 'shoot' loop
    update public.game_secrets set bullets_left = bullets_left - 1
     where game_id = p_game.id and user_id = r.actor_id and bullets_left > 0;
    if r.target_id is distinct from v_protect then v_dead := v_dead || r.target_id; end if;
  end loop;

  -- نتيجة المحقق (خاصة به)
  for r in select a.actor_id, a.target_id from public.night_actions a
            where a.game_id = p_game.id and a.round_no = v_round and a.action = 'investigate' loop
    insert into public.game_events (game_id, round_no, event_type, visibility, recipient_id, payload)
    values (p_game.id, v_round, 'investigation_result', 'private', r.actor_id, jsonb_build_object(
      'target_id', r.target_id,
      'is_mafia', (select s.role = 'mafia' from public.game_secrets s
                    where s.game_id = p_game.id and s.user_id = r.target_id)));
  end loop;

  -- تطبيق الوفيات
  select coalesce(array_agg(distinct d), '{}') into v_dead from unnest(v_dead) d;
  for r in select d as uid from unnest(v_dead) d loop
    select s.role into v_role from public.game_secrets s where s.game_id = p_game.id and s.user_id = r.uid;
    v_cause := (case when v_explosion is not null and (r.uid = v_bomber or r.uid = v_bomb_target)
                     then 'explosion' else 'night' end)::public.elimination_cause;
    update public.game_players
       set is_alive = false, eliminated_round = v_round, eliminated_by = v_cause,
           revealed_role = case when p_game.reveal_role_on_death then v_role end
     where game_id = p_game.id and user_id = r.uid and is_alive;
    v_deaths := v_deaths || jsonb_build_array(jsonb_build_object(
      'user_id', r.uid, 'cause', v_cause,
      'role', case when p_game.reveal_role_on_death then v_role end));
  end loop;

  insert into public.game_events (game_id, round_no, event_type, payload)
  values (p_game.id, v_round, 'night_result', jsonb_build_object('deaths', v_deaths, 'explosion', v_explosion));

  v_winner := private.check_winner(p_game.id);
  if v_winner is not null then
    perform private.finish_game(p_game.id, v_winner);
  else
    update public.games set phase = 'day', phase_started_at = now(),
           phase_ends_at = now() + make_interval(secs => p_game.day_seconds)
     where id = p_game.id;
    insert into public.game_events (game_id, round_no, event_type, payload)
    values (p_game.id, v_round, 'day_started', '{}'::jsonb);
  end if;
end $$;

-- ---------- حسم التصويت ----------
create or replace function private.resolve_votes(p_game public.games)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_round integer := p_game.round_no;
  v_tally jsonb; v_max integer; v_top_count integer; v_total integer;
  v_top uuid; v_role public.game_role; v_winner public.game_winner;
begin
  select coalesce(jsonb_object_agg(c.target_id::text, c.n), '{}'::jsonb), coalesce(max(c.n), 0)
    into v_tally, v_max
    from (select v.target_id, count(*)::integer as n from public.votes v
           where v.game_id = p_game.id and v.round_no = v_round and v.target_id is not null
           group by v.target_id) c;

  select count(*) into v_top_count from (
    select v.target_id from public.votes v
     where v.game_id = p_game.id and v.round_no = v_round and v.target_id is not null
     group by v.target_id having count(*) = v_max) t where v_max > 0;

  select count(*) into v_total from public.votes v where v.game_id = p_game.id and v.round_no = v_round;

  if v_max > 0 and v_top_count = 1 then
    select v.target_id into v_top from public.votes v
     where v.game_id = p_game.id and v.round_no = v_round and v.target_id is not null
     group by v.target_id having count(*) = v_max;
  end if;

  insert into public.vote_results (game_id, round_no, eliminated_user_id, tally, total_votes, is_tie)
  values (p_game.id, v_round, v_top, v_tally, v_total, (v_max > 0 and v_top is null));

  if v_top is not null then
    select s.role into v_role from public.game_secrets s where s.game_id = p_game.id and s.user_id = v_top;
    update public.game_players
       set is_alive = false, eliminated_round = v_round, eliminated_by = 'vote',
           revealed_role = case when p_game.reveal_role_on_death then v_role end
     where game_id = p_game.id and user_id = v_top;
    insert into public.game_events (game_id, round_no, event_type, payload)
    values (p_game.id, v_round, 'player_eliminated', jsonb_build_object(
      'user_id', v_top, 'role', case when p_game.reveal_role_on_death then v_role end));
  else
    insert into public.game_events (game_id, round_no, event_type, payload)
    values (p_game.id, v_round, 'no_elimination', jsonb_build_object('tie', v_max > 0));
  end if;

  v_winner := private.check_winner(p_game.id);
  if v_winner is not null then
    perform private.finish_game(p_game.id, v_winner);
  else
    update public.games set round_no = v_round + 1, phase = 'night', phase_started_at = now(),
           phase_ends_at = now() + make_interval(secs => p_game.night_seconds)
     where id = p_game.id;
    insert into public.game_events (game_id, round_no, event_type, payload)
    values (p_game.id, v_round + 1, 'night_started', '{}'::jsonb);
  end if;
end $$;

-- ============================ واجهة العميل (RPC) ============================

create or replace function public.start_game(
  p_room_id uuid,
  p_night_seconds integer default 60,
  p_day_seconds integer default 120,
  p_vote_seconds integer default 60,
  p_reveal_role_on_death boolean default true)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_room public.rooms;
  v_users uuid[];
  v_roles public.game_role[];
  v_n integer;
  v_game uuid;
  i integer;
begin
  select * into v_room from public.rooms where id = p_room_id for update;
  if not found then raise exception 'room_not_found'; end if;
  if v_room.owner_id <> v_uid then raise exception 'not_room_owner'; end if;
  if v_room.status <> 'open' then raise exception 'room_not_open'; end if;

  select array_agg(m.user_id order by gen_random_uuid()) into v_users
    from public.room_members m where m.room_id = p_room_id and m.status = 'active';
  v_n := coalesce(array_length(v_users, 1), 0);
  if v_n < 4 then raise exception 'not_enough_players'; end if;
  v_roles := private.build_role_deck(v_n);

  insert into public.games (room_id, started_by, night_seconds, day_seconds, vote_seconds,
                            reveal_role_on_death, phase_ends_at)
  values (p_room_id, v_uid, p_night_seconds, p_day_seconds, p_vote_seconds,
          coalesce(p_reveal_role_on_death, true), now() + make_interval(secs => p_night_seconds))
  returning id into v_game;

  for i in 1..v_n loop
    insert into public.game_players (game_id, user_id, seat_no) values (v_game, v_users[i], i);
    insert into public.game_secrets (game_id, user_id, role, bullets_left)
    values (v_game, v_users[i], v_roles[i], case when v_roles[i] = 'gunner' then 1 else 0 end);
  end loop;

  update public.rooms set status = 'in_game' where id = p_room_id;
  insert into public.game_events (game_id, round_no, event_type, payload)
  values (v_game, 1, 'game_started', jsonb_build_object('players', v_n));
  return v_game;
end $$;

create or replace function public.abort_game(p_game_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_game public.games;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found then raise exception 'game_not_found'; end if;
  if not exists (select 1 from public.rooms r where r.id = v_game.room_id and r.owner_id = v_uid) then
    raise exception 'not_room_owner';
  end if;
  if v_game.status <> 'in_progress' then raise exception 'game_not_active'; end if;

  update public.games set status = 'aborted', phase = 'ended', ended_at = now(), phase_ends_at = null
   where id = p_game_id;
  update public.rooms set status = 'open' where id = v_game.room_id and status = 'in_game';
  insert into public.game_events (game_id, round_no, event_type, payload)
  values (p_game_id, v_game.round_no, 'game_aborted', '{}'::jsonb);
  return true;
end $$;

-- الدور السري للمستدعي فقط (ولا يرى زملاء المافيا إلا لاعب المافيا)
create or replace function public.get_my_role(p_game_id uuid)
returns table (my_role public.game_role, bullets smallint, bomb_used boolean,
               last_protected_id uuid, teammates uuid[])
language sql stable security definer set search_path = '' as $$
  select s.role, s.bullets_left, s.bomb_used, s.last_protected_id,
         case when s.role = 'mafia' then
           (select array_agg(t.user_id order by t.user_id) from public.game_secrets t
             where t.game_id = s.game_id and t.role = 'mafia' and t.user_id <> s.user_id)
         end
  from public.game_secrets s
  where s.game_id = p_game_id and s.user_id = (select auth.uid());
$$;

create or replace function public.submit_night_action(
  p_game_id uuid, p_action public.night_action_type, p_target_id uuid default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_game public.games;
  v_me public.game_players;
  v_sec public.game_secrets;
  v_target public.game_players;
  v_target_role public.game_role;
begin
  select * into v_game from public.games where id = p_game_id for share;
  if not found or v_game.status <> 'in_progress' then raise exception 'game_not_active'; end if;
  if v_game.phase <> 'night' then raise exception 'not_night_phase'; end if;
  if now() >= v_game.phase_ends_at then raise exception 'phase_expired'; end if;

  select * into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if not found then raise exception 'not_a_player'; end if;
  if not v_me.is_alive then raise exception 'player_dead'; end if;
  select * into v_sec from public.game_secrets where game_id = p_game_id and user_id = v_uid;

  if p_action = 'skip' then
    if v_sec.role = 'citizen' then raise exception 'no_night_ability'; end if;
    p_target_id := null;
  else
    if not ((v_sec.role = 'mafia' and p_action = 'kill')
         or (v_sec.role = 'doctor' and p_action = 'protect')
         or (v_sec.role = 'detective' and p_action = 'investigate')
         or (v_sec.role = 'gunner' and p_action = 'shoot')
         or (v_sec.role = 'bomber' and p_action = 'bomb')) then
      raise exception 'action_not_allowed';
    end if;
    if p_target_id is null then raise exception 'target_required'; end if;
    select * into v_target from public.game_players where game_id = p_game_id and user_id = p_target_id;
    if not found then raise exception 'invalid_target'; end if;
    if not v_target.is_alive then raise exception 'target_dead'; end if;
    if p_action <> 'protect' and p_target_id = v_uid then raise exception 'cannot_target_self'; end if;
    if p_action = 'kill' then
      select s.role into v_target_role from public.game_secrets s where s.game_id = p_game_id and s.user_id = p_target_id;
      if v_target_role = 'mafia' then raise exception 'cannot_target_teammate'; end if;
    end if;
    if p_action = 'shoot' and v_sec.bullets_left <= 0 then raise exception 'no_bullets'; end if;
    if p_action = 'bomb' and v_sec.bomb_used then raise exception 'bomb_used'; end if;
    if p_action = 'protect' and v_sec.last_protected_id is not distinct from p_target_id then
      raise exception 'cannot_protect_same_twice';
    end if;
  end if;

  insert into public.night_actions (game_id, round_no, actor_id, action, target_id)
  values (p_game_id, v_game.round_no, v_uid, p_action, p_target_id)
  on conflict (game_id, round_no, actor_id)
  do update set action = excluded.action, target_id = excluded.target_id, updated_at = now();
  return true;
end $$;

create or replace function public.cast_vote(p_game_id uuid, p_target_id uuid default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_game public.games;
  v_me public.game_players;
  v_target public.game_players;
begin
  select * into v_game from public.games where id = p_game_id for share;
  if not found or v_game.status <> 'in_progress' then raise exception 'game_not_active'; end if;
  if v_game.phase <> 'voting' then raise exception 'not_voting_phase'; end if;
  if now() >= v_game.phase_ends_at then raise exception 'phase_expired'; end if;

  select * into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if not found then raise exception 'not_a_player'; end if;
  if not v_me.is_alive then raise exception 'player_dead'; end if;

  if p_target_id is not null then
    if p_target_id = v_uid then raise exception 'cannot_vote_self'; end if;
    select * into v_target from public.game_players where game_id = p_game_id and user_id = p_target_id;
    if not found then raise exception 'invalid_target'; end if;
    if not v_target.is_alive then raise exception 'target_dead'; end if;
  end if;

  begin
    insert into public.votes (game_id, round_no, voter_id, target_id)
    values (p_game_id, v_game.round_no, v_uid, p_target_id);
  exception when unique_violation then
    raise exception 'already_voted';
  end;
  return true;
end $$;

-- ينقل اللعبة للمرحلة التالية فقط إذا انتهى الوقت أو اكتملت الإجراءات المطلوبة.
-- يستطيع أي لاعب في اللعبة استدعاءها؛ التحقق كله على الخادم، وتكرار الاستدعاء آمن.
create or replace function public.advance_phase(p_game_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_game public.games;
  v_phase text;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found then raise exception 'game_not_found'; end if;
  if not exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.user_id = v_uid) then
    raise exception 'not_a_player';
  end if;
  if v_game.status <> 'in_progress' then return v_game.phase::text; end if;

  if v_game.phase = 'night' then
    if now() >= v_game.phase_ends_at or private.night_all_submitted(p_game_id, v_game.round_no) then
      perform private.resolve_night(v_game);
    end if;
  elsif v_game.phase = 'day' then
    if now() >= v_game.phase_ends_at then
      update public.games set phase = 'voting', phase_started_at = now(),
             phase_ends_at = now() + make_interval(secs => v_game.vote_seconds)
       where id = p_game_id;
      insert into public.game_events (game_id, round_no, event_type, payload)
      values (p_game_id, v_game.round_no, 'voting_started', '{}'::jsonb);
    end if;
  elsif v_game.phase = 'voting' then
    if now() >= v_game.phase_ends_at or private.all_voted(p_game_id, v_game.round_no) then
      perform private.resolve_votes(v_game);
    end if;
  end if;

  select g.phase::text into v_phase from public.games g where g.id = p_game_id;
  return v_phase;
end $$;
