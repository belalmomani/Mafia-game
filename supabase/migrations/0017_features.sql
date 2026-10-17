-- ============================================================
-- 0017 — ميزات جديدة
--   دردشة اللعبة (للمتحدث نهارًا، وللمافيا ليلًا) + رابط غرفة صوتية خارجية
--   لاعبون وهميون (بوتات) للتجربة يديرها الخادم
--   الغياب: من يتغيب عن دورين متتاليين لا ننتظره (لا تخطّي ولا طرد)
--   الانسحاب من اللعبة
--   الولد يختار من يسحبه لحظة موته (مهلة 20 ثانية، وإلا يُنفَّذ اختياره المسبق)
-- ============================================================

alter table public.profiles    add column if not exists is_bot boolean not null default false;
alter table public.game_players add column if not exists missed integer not null default 0;
alter table public.games add column if not exists pending_pull uuid;
alter table public.games add column if not exists pending_pull_until timestamptz;
alter table public.rooms add column if not exists voice_link text
  check (voice_link is null or (char_length(voice_link) <= 300 and voice_link ~ '^https://'));

-- ---------- الدردشة ----------
create table if not exists public.game_messages (
  id         bigint generated always as identity primary key,
  game_id    uuid not null references public.games(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  channel    text not null default 'public' check (channel in ('public', 'mafia')),
  round_no   integer not null default 1,
  body       text not null check (char_length(body) between 1 and 300),
  created_at timestamptz not null default now()
);
create index if not exists game_messages_game_idx on public.game_messages (game_id, id);
alter table public.game_messages enable row level security;
revoke all on public.game_messages from anon, authenticated;
grant select on public.game_messages to authenticated;

drop policy if exists game_messages_select on public.game_messages;
create policy game_messages_select on public.game_messages for select to authenticated using (
  (channel = 'public' and private.is_game_room_member(game_id))
  or (channel = 'mafia' and private.is_mafia_in_game(game_id))
);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'game_messages') then
    alter publication supabase_realtime add table public.game_messages;
  end if;
end $$;

-- ---------- تصفير عداد الغياب عند أي إجراء ----------
create or replace function private.reset_missed()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := coalesce((to_jsonb(new) ->> 'actor_id')::uuid, (to_jsonb(new) ->> 'voter_id')::uuid);
begin
  update public.game_players set missed = 0 where game_id = new.game_id and user_id = v_uid;
  return null;
end $$;
drop trigger if exists night_actions_reset_missed on public.night_actions;
create trigger night_actions_reset_missed after insert on public.night_actions
  for each row execute function private.reset_missed();
drop trigger if exists votes_reset_missed on public.votes;
create trigger votes_reset_missed after insert on public.votes
  for each row execute function private.reset_missed();

-- ---------- دوال داخلية ----------
create or replace function private.skippable(p_game_id uuid, p_uid uuid)
returns boolean language sql stable set search_path = '' as $$
  select coalesce((
    select (not p.is_alive) or p.missed >= 2 or pr.is_bot
      from public.game_players p join public.profiles pr on pr.id = p.user_id
     where p.game_id = p_game_id and p.user_id = p_uid), true);
$$;

create or replace function private.night_all_submitted(p_game_id uuid, p_round integer)
returns boolean language sql stable set search_path = '' as $$
  select not exists (
    select 1
    from public.game_secrets s
    join public.game_players p on p.game_id = s.game_id and p.user_id = s.user_id
    where s.game_id = p_game_id and p.is_alive and p.missed < 2
      and s.role in ('mafia', 'red_mafia', 'silencer', 'girl', 'sheikh')
      and not exists (select 1 from public.night_actions a
                      where a.game_id = s.game_id and a.round_no = p_round and a.actor_id = s.user_id)
  );
$$;

create or replace function private.all_voted(p_game_id uuid, p_round integer)
returns boolean language sql stable set search_path = '' as $$
  select not exists (
    select 1 from public.game_players p
    where p.game_id = p_game_id and p.is_alive and p.missed < 2
      and not exists (select 1 from public.votes v
                      where v.game_id = p.game_id and v.round_no = p_round and v.voter_id = p.user_id)
  );
$$;

create or replace function private.count_missed_night(p_game_id uuid, p_round integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.game_players p
     set missed = case when exists (select 1 from public.night_actions a
                                    where a.game_id = p.game_id and a.round_no = p_round and a.actor_id = p.user_id)
                       then 0 else p.missed + 1 end
    from public.game_secrets s, public.profiles pr
   where s.game_id = p.game_id and s.user_id = p.user_id and pr.id = p.user_id
     and p.game_id = p_game_id and p.is_alive and not pr.is_bot
     and s.role in ('mafia', 'red_mafia', 'silencer', 'girl', 'sheikh');
end $$;

create or replace function private.count_missed_votes(p_game_id uuid, p_cycle integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.game_players p
     set missed = case when exists (select 1 from public.votes v
                                    where v.game_id = p.game_id and v.round_no = p_cycle and v.voter_id = p.user_id)
                       then 0 else p.missed + 1 end
    from public.profiles pr
   where pr.id = p.user_id and p.game_id = p_game_id and p.is_alive and not pr.is_bot;
end $$;

-- الغائبون (دورين متتاليين) لا يُمنحون دور كلام
create or replace function private.begin_day(p_game_id uuid, p_round integer)
returns void language plpgsql security definer set search_path = '' as $$
declare v_game public.games; v_order uuid[];
begin
  select * into v_game from public.games where id = p_game_id;
  select coalesce(array_agg(p.user_id order by p.seat_no), '{}'::uuid[]) into v_order
    from public.game_players p
   where p.game_id = p_game_id and p.is_alive and p.missed < 2
     and p.user_id is distinct from v_game.silenced_id;

  if coalesce(array_length(v_order, 1), 0) = 0 then
    update public.games set round_no = p_round where id = p_game_id;
    perform private.begin_voting(p_game_id);
    return;
  end if;

  update public.games
     set phase = 'day', round_no = p_round, speech_order = v_order, speech_idx = 0,
         phase_started_at = now(), phase_ends_at = now() + make_interval(secs => v_game.speech_seconds)
   where id = p_game_id;
  insert into public.game_events (game_id, round_no, event_type, payload)
  values (p_game_id, p_round, 'day_started', jsonb_build_object('speakers', to_jsonb(v_order)));
end $$;

-- الولد: عند موته تُفتح مهلة 20 ثانية ليختار من يسحبه
create or replace function private.kill_player(p_game public.games, p_uid uuid, p_cause public.elimination_cause)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_role public.game_role; v_round integer; v_out jsonb := '[]'::jsonb;
begin
  select g.round_no into v_round from public.games g where g.id = p_game.id;
  select s.role into v_role from public.game_secrets s where s.game_id = p_game.id and s.user_id = p_uid;

  update public.game_players
     set is_alive = false, eliminated_round = v_round, eliminated_by = p_cause,
         revealed_role = case when p_game.reveal_role_on_death then v_role end
   where game_id = p_game.id and user_id = p_uid and is_alive;
  if not found then return v_out; end if;

  v_out := jsonb_build_array(jsonb_build_object(
    'user_id', p_uid, 'cause', p_cause, 'role', case when p_game.reveal_role_on_death then v_role end));
  if v_role = 'boy' and p_cause <> 'left' then
    update public.games set pending_pull = p_uid, pending_pull_until = now() + interval '20 seconds'
     where id = p_game.id and pending_pull is null;
  end if;
  return v_out;
end $$;

create or replace function private.settle_pull(p_game_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_game public.games; v_def uuid; v_deaths jsonb; v_winner public.game_winner;
begin
  select * into v_game from public.games where id = p_game_id;
  if v_game.pending_pull is null or v_game.status <> 'in_progress' or now() < v_game.pending_pull_until then return; end if;
  select s.pull_target_id into v_def from public.game_secrets s
   where s.game_id = p_game_id and s.user_id = v_game.pending_pull;
  update public.games set pending_pull = null, pending_pull_until = null where id = p_game_id;
  if v_def is not null then
    v_deaths := private.kill_player(v_game, v_def, 'pulled');
    insert into public.game_events (game_id, round_no, event_type, payload)
    values (p_game_id, v_game.round_no, 'boy_pulled', jsonb_build_object('boy_id', v_game.pending_pull, 'deaths', v_deaths));
    v_winner := private.check_winner(p_game_id);
    if v_winner is not null then perform private.finish_game(p_game_id, v_winner); end if;
  end if;
end $$;

-- البوتات: تتصرف على الخادم بقرارات عشوائية صالحة
create or replace function private.bots_act(p_game_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.games; r record; v_target uuid;
begin
  select * into g from public.games where id = p_game_id;
  if g.phase = 'night' then
    for r in
      select p.user_id, s.role, s.last_protected_id
        from public.game_players p
        join public.game_secrets s on s.game_id = p.game_id and s.user_id = p.user_id
        join public.profiles pr on pr.id = p.user_id
       where p.game_id = p_game_id and p.is_alive and pr.is_bot
         and s.role in ('mafia', 'red_mafia', 'silencer', 'girl', 'sheikh')
         and not exists (select 1 from public.night_actions a
                         where a.game_id = p_game_id and a.round_no = g.round_no and a.actor_id = p.user_id)
    loop
      v_target := null;
      if r.role in ('mafia', 'red_mafia', 'silencer') then
        select p2.user_id into v_target
          from public.game_players p2 join public.game_secrets s2 on s2.game_id = p2.game_id and s2.user_id = p2.user_id
         where p2.game_id = p_game_id and p2.is_alive and s2.role not in ('mafia', 'red_mafia', 'silencer')
         order by random() limit 1;
        insert into public.night_actions (game_id, round_no, actor_id, action, target_id)
        values (p_game_id, g.round_no, r.user_id,
                case when v_target is null then 'skip' when r.role = 'silencer' then 'silence' else 'kill' end::public.night_action_type,
                v_target);
      elsif r.role = 'girl' then
        select p2.user_id into v_target from public.game_players p2
         where p2.game_id = p_game_id and p2.is_alive and p2.user_id is distinct from r.last_protected_id
         order by random() limit 1;
        insert into public.night_actions (game_id, round_no, actor_id, action, target_id)
        values (p_game_id, g.round_no, r.user_id,
                case when v_target is null then 'skip' else 'protect' end::public.night_action_type, v_target);
      else  -- الشيخ: نصف الليالي يفجّر
        if random() < 0.5 then
          select p2.user_id into v_target from public.game_players p2
           where p2.game_id = p_game_id and p2.is_alive and p2.user_id <> r.user_id order by random() limit 1;
        end if;
        insert into public.night_actions (game_id, round_no, actor_id, action, target_id)
        values (p_game_id, g.round_no, r.user_id,
                case when v_target is null then 'skip' else 'bomb' end::public.night_action_type, v_target);
      end if;
    end loop;

  elsif g.phase = 'voting' then
    for r in
      select p.user_id from public.game_players p join public.profiles pr on pr.id = p.user_id
       where p.game_id = p_game_id and p.is_alive and pr.is_bot
         and not exists (select 1 from public.votes v
                         where v.game_id = p_game_id and v.round_no = g.vote_cycle and v.voter_id = p.user_id)
    loop
      select p2.user_id into v_target from public.game_players p2
       where p2.game_id = p_game_id and p2.is_alive and p2.user_id <> r.user_id order by random() limit 1;
      insert into public.votes (game_id, round_no, voter_id, target_id)
      values (p_game_id, g.vote_cycle, r.user_id, v_target);
    end loop;
  end if;

  -- الولد البوت يحدد هدف سحب مسبق
  update public.game_secrets s
     set pull_target_id = (select p2.user_id from public.game_players p2
                            where p2.game_id = p_game_id and p2.is_alive and p2.user_id <> s.user_id
                            order by random() limit 1)
   where s.game_id = p_game_id and s.role = 'boy' and s.pull_target_id is null
     and exists (select 1 from public.profiles pr where pr.id = s.user_id and pr.is_bot);
end $$;

-- ---------- advance_phase بالتحديثات ----------
create or replace function public.advance_phase(p_game_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_game public.games;
  v_phase text;
  v_idx integer; v_len integer; v_cur uuid;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found then raise exception 'game_not_found'; end if;
  if not exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.user_id = v_uid) then
    raise exception 'not_a_player';
  end if;
  if v_game.status <> 'in_progress' then return v_game.phase::text; end if;

  perform private.settle_pull(p_game_id);
  select * into v_game from public.games where id = p_game_id;
  if v_game.status <> 'in_progress' then return v_game.phase::text; end if;

  perform private.bots_act(p_game_id);

  if v_game.phase = 'night' then
    if now() >= v_game.phase_ends_at or private.night_all_submitted(p_game_id, v_game.round_no) then
      perform private.count_missed_night(p_game_id, v_game.round_no);
      perform private.resolve_night(v_game);
    end if;

  elsif v_game.phase = 'day' then
    v_idx := v_game.speech_idx;
    v_len := coalesce(array_length(v_game.speech_order, 1), 0);
    v_cur := case when v_idx < v_len then v_game.speech_order[v_idx + 1] end;
    if now() >= v_game.phase_ends_at or v_cur is null or private.skippable(p_game_id, v_cur) then
      v_idx := v_idx + 1;
      while v_idx < v_len and private.skippable(p_game_id, v_game.speech_order[v_idx + 1]) loop
        v_idx := v_idx + 1;
      end loop;
      if v_idx >= v_len then
        perform private.begin_voting(p_game_id);
      else
        update public.games set speech_idx = v_idx, phase_started_at = now(),
               phase_ends_at = now() + make_interval(secs => v_game.speech_seconds)
         where id = p_game_id;
      end if;
    end if;

  elsif v_game.phase = 'voting' then
    if now() >= v_game.phase_ends_at or private.all_voted(p_game_id, v_game.vote_cycle) then
      perform private.count_missed_votes(p_game_id, v_game.vote_cycle);
      perform private.resolve_votes(v_game);
    end if;
  end if;

  select g.phase::text into v_phase from public.games g where g.id = p_game_id;
  return v_phase;
end $$;

-- ============================ واجهة العميل ============================

create or replace function public.boy_pull(p_game_id uuid, p_target_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_game public.games;
  v_target public.game_players;
  v_deaths jsonb; v_winner public.game_winner;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found or v_game.status <> 'in_progress' then raise exception 'game_not_active'; end if;
  if v_game.pending_pull is distinct from v_uid then raise exception 'no_pending_pull'; end if;
  if now() >= v_game.pending_pull_until then raise exception 'phase_expired'; end if;
  if p_target_id = v_uid then raise exception 'cannot_target_self'; end if;
  select * into v_target from public.game_players where game_id = p_game_id and user_id = p_target_id;
  if not found then raise exception 'invalid_target'; end if;
  if not v_target.is_alive then raise exception 'target_dead'; end if;

  update public.games set pending_pull = null, pending_pull_until = null where id = p_game_id;
  v_deaths := private.kill_player(v_game, p_target_id, 'pulled');
  insert into public.game_events (game_id, round_no, event_type, payload)
  values (p_game_id, v_game.round_no, 'boy_pulled', jsonb_build_object('boy_id', v_uid, 'deaths', v_deaths));
  v_winner := private.check_winner(p_game_id);
  if v_winner is not null then perform private.finish_game(p_game_id, v_winner); end if;
  return true;
end $$;

create or replace function public.send_message(p_game_id uuid, p_body text, p_channel text default 'public')
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_game public.games;
  v_me public.game_players;
  v_role public.game_role;
  v_cur uuid;
  v_id bigint;
begin
  p_body := btrim(coalesce(p_body, ''));
  if char_length(p_body) < 1 or char_length(p_body) > 300 then raise exception 'invalid_message'; end if;
  select * into v_game from public.games where id = p_game_id;
  if not found or v_game.status <> 'in_progress' then raise exception 'game_not_active'; end if;
  select * into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if not found then raise exception 'not_a_player'; end if;
  if not v_me.is_alive then raise exception 'player_dead'; end if;

  if p_channel = 'public' then
    if v_game.phase <> 'day' then raise exception 'not_day_phase'; end if;
    v_cur := case when v_game.speech_idx < coalesce(array_length(v_game.speech_order, 1), 0)
                  then v_game.speech_order[v_game.speech_idx + 1] end;
    if v_cur is distinct from v_uid then raise exception 'not_your_turn'; end if;
  elsif p_channel = 'mafia' then
    select s.role into v_role from public.game_secrets s where s.game_id = p_game_id and s.user_id = v_uid;
    if v_role not in ('mafia', 'red_mafia', 'silencer') then raise exception 'not_mafia'; end if;
    if v_game.phase <> 'night' then raise exception 'not_night_phase'; end if;
  else
    raise exception 'invalid_channel';
  end if;

  if (select count(*) from public.game_messages m
       where m.user_id = v_uid and m.game_id = p_game_id and m.created_at > now() - interval '10 seconds') >= 5 then
    raise exception 'too_fast';
  end if;
  insert into public.game_messages (game_id, user_id, channel, round_no, body)
  values (p_game_id, v_uid, p_channel, v_game.round_no, p_body) returning id into v_id;
  return v_id;
end $$;

create or replace function public.set_room_voice_link(p_room_id uuid, p_link text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_user(); v text := nullif(btrim(coalesce(p_link, '')), '');
begin
  if not exists (select 1 from public.rooms r where r.id = p_room_id and r.owner_id = v_uid) then
    raise exception 'not_room_owner';
  end if;
  if v is not null and (char_length(v) > 300 or v !~ '^https://') then raise exception 'invalid_link'; end if;
  update public.rooms set voice_link = v where id = p_room_id;
  return v;
end $$;

create or replace function public.leave_game(p_game_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_game public.games;
  v_me public.game_players;
  v_deaths jsonb; v_winner public.game_winner;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found or v_game.status <> 'in_progress' then raise exception 'game_not_active'; end if;
  select * into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if not found then raise exception 'not_a_player'; end if;
  if not v_me.is_alive then raise exception 'player_dead'; end if;

  v_deaths := private.kill_player(v_game, v_uid, 'left');
  insert into public.game_events (game_id, round_no, event_type, payload)
  values (p_game_id, v_game.round_no, 'player_left', jsonb_build_object('user_id', v_uid, 'deaths', v_deaths));
  v_winner := private.check_winner(p_game_id);
  if v_winner is not null then perform private.finish_game(p_game_id, v_winner); end if;
  return true;
end $$;

-- ---------- البوتات ----------
create or replace function public.add_bots(p_room_id uuid, p_count integer)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_room public.rooms;
  v_active integer; v_existing integer; v_id uuid; i integer;
begin
  select * into v_room from public.rooms where id = p_room_id for update;
  if not found then raise exception 'room_not_found'; end if;
  if v_room.owner_id <> v_uid then raise exception 'not_room_owner'; end if;
  if v_room.status <> 'open' then raise exception 'room_not_open'; end if;
  if p_count is null or p_count < 1 or p_count > 15 then raise exception 'invalid_count'; end if;
  select count(*) into v_active from public.room_members m where m.room_id = p_room_id and m.status = 'active';
  if v_active + p_count > v_room.max_players then raise exception 'room_full'; end if;
  select count(*) into v_existing from public.room_members m join public.profiles p on p.id = m.user_id
   where m.room_id = p_room_id and p.is_bot;

  for i in 1..p_count loop
    v_id := gen_random_uuid();
    insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
    values (v_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
            'bot_' || replace(v_id::text, '-', '') || '@bots.mafia.invalid', now(), now());
    update public.profiles set is_bot = true, display_name = 'بوت ' || (v_existing + i) where id = v_id;
    insert into public.room_members (room_id, user_id) values (p_room_id, v_id);
  end loop;
  return p_count;
end $$;

create or replace function public.remove_bots(p_room_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_ids uuid[]; v_n integer;
begin
  if not exists (select 1 from public.rooms r where r.id = p_room_id and r.owner_id = v_uid) then
    raise exception 'not_room_owner';
  end if;
  if exists (select 1 from public.games g where g.room_id = p_room_id and g.status = 'in_progress') then
    raise exception 'game_in_progress';
  end if;
  select coalesce(array_agg(m.user_id), '{}') into v_ids
    from public.room_members m join public.profiles p on p.id = m.user_id
   where m.room_id = p_room_id and p.is_bot;
  v_n := coalesce(array_length(v_ids, 1), 0);
  delete from auth.users where id = any(v_ids);
  return v_n;
end $$;
