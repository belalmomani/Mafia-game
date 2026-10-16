-- ============================================================
-- 0009 — منطق الأدوار الجديدة (يستبدل منطق طبيب/محقق/قناص/مفجّر)
--   مافيا + مافيا أحمر : يقترحون الضحية، والأحمر يقرر (إن مات أو غاب يُحسم بالأغلبية، التعادل = لا اغتيال)
--   الشيخ  : تفجير ضحية كل ليلة، لا تمنعه الحماية، يموت الهدف فورًا ولا يموت الشيخ
--   البنت  : تحمي لاعبًا من الاغتيال فقط (لا من التفجير)، ولا تحمي نفس الشخص ليلتين متتاليتين
--   الولد  : يحدد (في أي وقت) لاعبًا يسحبه معه، فإذا قُتل بأي سبب مات الهدف معه حتى لو بريئًا
--   الصياد : طلقة واحدة في النهار، يموت الهدف دائمًا حتى لو بريئًا
--   المواطن: بلا قدرة.   الفوز: المواطنون حين تنتهي المافيا (مافيا + أحمر)، والمافيا حين يتساوى عددها مع الباقين أو يزيد.
-- ============================================================

alter table public.game_secrets add column if not exists pull_target_id uuid;

-- المافيا (العاديون والأحمر) يشاهدون اقتراحات بعضهم
create or replace function private.is_mafia_in_game(p_game_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.game_secrets s
    where s.game_id = p_game_id and s.user_id = (select auth.uid()) and s.role in ('mafia', 'red_mafia'));
$$;

-- جدول التوزيع حسب عدد اللاعبين (قابل للتعديل بتغيير هذه الدالة فقط)
-- 4-5: أحمر + بنت | 6+: + شيخ | 7+: + صياد | 8+: + ولد
-- مافيا عاديون: 0 (حتى 5) · 1 (6-8) · 2 (9-13) · 3 (14+) ؛ والباقي مواطنون.
create or replace function private.build_role_deck(p_n integer)
returns public.game_role[] language plpgsql immutable set search_path = '' as $$
declare
  v_deck public.game_role[] := array['red_mafia']::public.game_role[];
  v_extra integer := case when p_n >= 14 then 3 when p_n >= 9 then 2 when p_n >= 6 then 1 else 0 end;
  i integer;
begin
  for i in 1..v_extra loop v_deck := v_deck || 'mafia'::public.game_role; end loop;
  v_deck := v_deck || 'girl'::public.game_role;
  if p_n >= 6 then v_deck := v_deck || 'sheikh'::public.game_role; end if;
  if p_n >= 7 then v_deck := v_deck || 'hunter'::public.game_role; end if;
  if p_n >= 8 then v_deck := v_deck || 'boy'::public.game_role; end if;
  while coalesce(array_length(v_deck, 1), 0) < p_n loop v_deck := v_deck || 'citizen'::public.game_role; end loop;
  return v_deck;
end $$;

create or replace function private.check_winner(p_game_id uuid)
returns public.game_winner language sql stable set search_path = '' as $$
  select (case when x.m = 0 then 'citizens' when x.m >= x.o then 'mafia' end)::public.game_winner
  from (
    select count(*) filter (where s.role in ('mafia', 'red_mafia')) as m,
           count(*) filter (where s.role not in ('mafia', 'red_mafia')) as o
    from public.game_players p
    join public.game_secrets s on s.game_id = p.game_id and s.user_id = p.user_id
    where p.game_id = p_game_id and p.is_alive
  ) x;
$$;

-- الأدوار المطلوب أن تُرسل إجراءً (أو تتخطى) قبل إنهاء الليل مبكرًا
create or replace function private.night_all_submitted(p_game_id uuid, p_round integer)
returns boolean language sql stable set search_path = '' as $$
  select not exists (
    select 1
    from public.game_secrets s
    join public.game_players p on p.game_id = s.game_id and p.user_id = s.user_id
    where s.game_id = p_game_id and p.is_alive and s.role in ('mafia', 'red_mafia', 'girl', 'sheikh')
      and not exists (select 1 from public.night_actions a
                      where a.game_id = s.game_id and a.round_no = p_round and a.actor_id = s.user_id)
  );
$$;

-- قتل لاعب (مع سحب الولد لهدفه). يعيد مصفوفة الوفيات الناتجة.
create or replace function private.kill_player(p_game public.games, p_uid uuid, p_cause public.elimination_cause)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_role public.game_role; v_pull uuid; v_round integer; v_out jsonb := '[]'::jsonb;
begin
  select g.round_no into v_round from public.games g where g.id = p_game.id;
  select s.role, s.pull_target_id into v_role, v_pull
    from public.game_secrets s where s.game_id = p_game.id and s.user_id = p_uid;

  update public.game_players
     set is_alive = false, eliminated_round = v_round, eliminated_by = p_cause,
         revealed_role = case when p_game.reveal_role_on_death then v_role end
   where game_id = p_game.id and user_id = p_uid and is_alive;
  if not found then return v_out; end if;

  v_out := jsonb_build_array(jsonb_build_object(
    'user_id', p_uid, 'cause', p_cause, 'role', case when p_game.reveal_role_on_death then v_role end));
  if v_role = 'boy' and v_pull is not null then
    v_out := v_out || private.kill_player(p_game, v_pull, 'pulled');
  end if;
  return v_out;
end $$;

create or replace function private.resolve_night(p_game public.games)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_round integer := p_game.round_no;
  v_protect uuid; v_kill uuid;
  v_red_action public.night_action_type; v_red_target uuid;
  v_deaths jsonb := '[]'::jsonb;
  v_winner public.game_winner;
  r record;
begin
  select a.target_id into v_protect
    from public.night_actions a join public.game_secrets s on s.game_id = a.game_id and s.user_id = a.actor_id
   where a.game_id = p_game.id and a.round_no = v_round and a.action = 'protect' and s.role = 'girl' limit 1;

  update public.game_secrets s
     set last_protected_id = (select a.target_id from public.night_actions a
                              where a.game_id = s.game_id and a.round_no = v_round
                                and a.actor_id = s.user_id and a.action = 'protect')
   where s.game_id = p_game.id and s.role = 'girl';

  -- تفجير الشيخ: لا تمنعه الحماية
  for r in select a.target_id from public.night_actions a
            join public.game_secrets s on s.game_id = a.game_id and s.user_id = a.actor_id
           where a.game_id = p_game.id and a.round_no = v_round and a.action = 'bomb' and s.role = 'sheikh' loop
    v_deaths := v_deaths || private.kill_player(p_game, r.target_id, 'explosion');
  end loop;

  -- ضحية المافيا: قرار الأحمر إن وُجد، وإلا الأغلبية (التعادل = لا اغتيال)
  select a.action, a.target_id into v_red_action, v_red_target
    from public.night_actions a join public.game_secrets s on s.game_id = a.game_id and s.user_id = a.actor_id
   where a.game_id = p_game.id and a.round_no = v_round and s.role = 'red_mafia' limit 1;
  if v_red_action is not null then
    v_kill := case when v_red_action = 'kill' then v_red_target end;
  else
    with c as (
      select a.target_id, count(*) as n from public.night_actions a
       where a.game_id = p_game.id and a.round_no = v_round and a.action = 'kill'
       group by a.target_id)
    select case when (select count(*) from c where c.n = (select max(c2.n) from c c2)) = 1
                then (select c3.target_id from c c3 order by c3.n desc limit 1) end
      into v_kill;
  end if;
  if v_kill is not null and v_kill is distinct from v_protect then
    v_deaths := v_deaths || private.kill_player(p_game, v_kill, 'night');
  end if;

  insert into public.game_events (game_id, round_no, event_type, payload)
  values (p_game.id, v_round, 'night_result', jsonb_build_object('deaths', v_deaths));

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

create or replace function private.resolve_votes(p_game public.games)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_round integer := p_game.round_no;
  v_tally jsonb; v_max integer; v_top_count integer; v_total integer;
  v_top uuid; v_deaths jsonb := '[]'::jsonb; v_winner public.game_winner;
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
    v_deaths := private.kill_player(p_game, v_top, 'vote');
    insert into public.game_events (game_id, round_no, event_type, payload)
    values (p_game.id, v_round, 'player_eliminated', jsonb_build_object('user_id', v_top, 'deaths', v_deaths));
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
    values (v_game, v_users[i], v_roles[i], case when v_roles[i] = 'hunter' then 1 else 0 end);
  end loop;

  update public.rooms set status = 'in_game' where id = p_room_id;
  insert into public.game_events (game_id, round_no, event_type, payload)
  values (v_game, 1, 'game_started', jsonb_build_object('players', v_n));
  return v_game;
end $$;

-- الدور السري للمستدعي فقط. (تغيّر شكل المخرجات، لذلك نحذف الدالة القديمة؛ شغّل 0010 بعدها لإعادة الصلاحيات)
drop function if exists public.get_my_role(uuid);
create function public.get_my_role(p_game_id uuid)
returns table (my_role public.game_role, bullets smallint, last_protected_id uuid,
               pull_target_id uuid, teammates uuid[])
language sql stable security definer set search_path = '' as $$
  select s.role, s.bullets_left, s.last_protected_id, s.pull_target_id,
         case when s.role in ('mafia', 'red_mafia') then
           (select array_agg(t.user_id order by t.user_id) from public.game_secrets t
             where t.game_id = s.game_id and t.role in ('mafia', 'red_mafia') and t.user_id <> s.user_id)
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
    if v_sec.role not in ('mafia', 'red_mafia', 'girl', 'sheikh') then raise exception 'no_night_ability'; end if;
    p_target_id := null;
  else
    if not ((v_sec.role in ('mafia', 'red_mafia') and p_action = 'kill')
         or (v_sec.role = 'girl' and p_action = 'protect')
         or (v_sec.role = 'sheikh' and p_action = 'bomb')) then
      raise exception 'action_not_allowed';
    end if;
    if p_target_id is null then raise exception 'target_required'; end if;
    select * into v_target from public.game_players where game_id = p_game_id and user_id = p_target_id;
    if not found then raise exception 'invalid_target'; end if;
    if not v_target.is_alive then raise exception 'target_dead'; end if;
    if p_action <> 'protect' and p_target_id = v_uid then raise exception 'cannot_target_self'; end if;
    if p_action = 'kill' then
      select s.role into v_target_role from public.game_secrets s where s.game_id = p_game_id and s.user_id = p_target_id;
      if v_target_role in ('mafia', 'red_mafia') then raise exception 'cannot_target_teammate'; end if;
    end if;
    if p_action = 'protect' and v_sec.last_protected_id is not distinct from p_target_id then
      raise exception 'cannot_protect_same_twice';
    end if;
  end if;

  insert into public.night_actions (game_id, round_no, actor_id, action, target_id)
  values (p_game_id, v_game.round_no, v_uid, p_action, p_target_id)
  on conflict (game_id, round_no, actor_id)
  do update set action = excluded.action, target_id = excluded.target_id, updated_at = now();

  if v_sec.role in ('mafia', 'red_mafia') then   -- يراها فريق المافيا فقط
    insert into public.game_events (game_id, round_no, event_type, visibility, payload)
    values (p_game_id, v_game.round_no, 'mafia_suggestion', 'mafia',
            jsonb_build_object('actor_id', v_uid, 'action', p_action, 'target_id', p_target_id));
  end if;
  return true;
end $$;

-- الصياد: طلقة واحدة في النهار، يموت الهدف دائمًا
create or replace function public.hunter_shoot(p_game_id uuid, p_target_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_game public.games;
  v_sec public.game_secrets;
  v_me public.game_players;
  v_target public.game_players;
  v_deaths jsonb;
  v_winner public.game_winner;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found or v_game.status <> 'in_progress' then raise exception 'game_not_active'; end if;
  if v_game.phase <> 'day' then raise exception 'not_day_phase'; end if;
  if now() >= v_game.phase_ends_at then raise exception 'phase_expired'; end if;

  select * into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if not found then raise exception 'not_a_player'; end if;
  if not v_me.is_alive then raise exception 'player_dead'; end if;
  select * into v_sec from public.game_secrets where game_id = p_game_id and user_id = v_uid;
  if v_sec.role <> 'hunter' then raise exception 'not_hunter'; end if;
  if v_sec.bullets_left <= 0 then raise exception 'no_bullets'; end if;
  if p_target_id = v_uid then raise exception 'cannot_target_self'; end if;
  select * into v_target from public.game_players where game_id = p_game_id and user_id = p_target_id;
  if not found then raise exception 'invalid_target'; end if;
  if not v_target.is_alive then raise exception 'target_dead'; end if;

  update public.game_secrets set bullets_left = 0 where game_id = p_game_id and user_id = v_uid;
  v_deaths := private.kill_player(v_game, p_target_id, 'hunt');
  insert into public.game_events (game_id, round_no, event_type, payload)
  values (p_game_id, v_game.round_no, 'hunter_shot', jsonb_build_object('hunter_id', v_uid, 'deaths', v_deaths));

  v_winner := private.check_winner(p_game_id);
  if v_winner is not null then perform private.finish_game(p_game_id, v_winner); end if;
  return true;
end $$;

-- الولد: يحدد (أو يلغي بـ null) اللاعب الذي يسحبه معه إن قُتل
create or replace function public.set_boy_target(p_game_id uuid, p_target_id uuid default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_game public.games;
  v_me public.game_players;
  v_role public.game_role;
  v_target public.game_players;
begin
  select * into v_game from public.games where id = p_game_id for share;
  if not found or v_game.status <> 'in_progress' then raise exception 'game_not_active'; end if;
  select * into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if not found then raise exception 'not_a_player'; end if;
  if not v_me.is_alive then raise exception 'player_dead'; end if;
  select s.role into v_role from public.game_secrets s where s.game_id = p_game_id and s.user_id = v_uid;
  if v_role <> 'boy' then raise exception 'not_boy'; end if;

  if p_target_id is not null then
    if p_target_id = v_uid then raise exception 'cannot_target_self'; end if;
    select * into v_target from public.game_players where game_id = p_game_id and user_id = p_target_id;
    if not found then raise exception 'invalid_target'; end if;
    if not v_target.is_alive then raise exception 'target_dead'; end if;
  end if;

  update public.game_secrets set pull_target_id = p_target_id where game_id = p_game_id and user_id = v_uid;
  return true;
end $$;
