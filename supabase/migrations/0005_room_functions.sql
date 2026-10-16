-- ============================================================
-- 0005 — دوال RPC للغرف والدعوات والبلاغات (تُنفَّذ على الخادم)
-- كلها SECURITY DEFINER مع search_path فارغ، وتتحقق من auth.uid() بنفسها.
-- ============================================================

create or replace function private.require_user()
returns uuid language plpgsql stable set search_path = '' as $$
declare v uuid := (select auth.uid());
begin
  if v is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  return v;
end $$;

create or replace function private.generate_invite_code()
returns text language sql volatile set search_path = '' as $$
  select upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
$$;

create or replace function public.ping()
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('ok', true, 'server_time', now());
$$;

-- ---------- إنشاء غرفة ----------
create or replace function public.create_room(
  p_name text,
  p_visibility public.room_visibility default 'public',
  p_max_players integer default 10,
  p_public_votes boolean default false)
returns public.rooms language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_room public.rooms;
  v_try integer := 0;
begin
  p_name := btrim(coalesce(p_name, ''));
  if char_length(p_name) < 2 or char_length(p_name) > 40 then raise exception 'invalid_room_name'; end if;
  if p_max_players is null or p_max_players < 4 or p_max_players > 20 then raise exception 'invalid_max_players'; end if;
  if (select count(*) from public.rooms r where r.owner_id = v_uid and r.status <> 'closed') >= 3 then
    raise exception 'too_many_rooms';
  end if;

  loop
    begin
      insert into public.rooms (owner_id, name, visibility, invite_code, max_players, public_votes)
      values (v_uid, p_name, p_visibility,
              case when p_visibility = 'private' then private.generate_invite_code() end,
              p_max_players, coalesce(p_public_votes, false))
      returning * into v_room;
      exit;
    exception when unique_violation then
      v_try := v_try + 1;
      if v_try > 5 then raise; end if;
    end;
  end loop;

  insert into public.room_members (room_id, user_id, role) values (v_room.id, v_uid, 'owner');
  select * into v_room from public.rooms where id = v_room.id;
  return v_room;
end $$;

-- ---------- الانضمام (بمعرّف الغرفة العامة أو برمز الدعوة أو بدعوة مباشرة) ----------
create or replace function public.join_room(p_room_id uuid default null, p_invite_code text default null)
returns public.rooms language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_room public.rooms;
  v_member public.room_members;
  v_code text := upper(btrim(coalesce(p_invite_code, '')));
begin
  if p_room_id is null and v_code = '' then raise exception 'room_required'; end if;

  if v_code <> '' then
    select * into v_room from public.rooms r where r.invite_code = v_code for update;
  else
    select * into v_room from public.rooms r where r.id = p_room_id for update;
  end if;
  if not found then raise exception 'room_not_found'; end if;

  if v_room.visibility = 'private'
     and v_code is distinct from v_room.invite_code
     and not exists (select 1 from public.room_invites i
                     where i.room_id = v_room.id and i.invitee_id = v_uid
                       and i.status = 'pending' and i.expires_at > now())
  then
    raise exception 'room_not_found';   -- لا نكشف وجود الغرف الخاصة
  end if;

  select * into v_member from public.room_members m where m.room_id = v_room.id and m.user_id = v_uid for update;
  if found and v_member.status = 'kicked' then raise exception 'kicked_from_room'; end if;
  if found and v_member.status = 'active' then return v_room; end if;

  if v_room.status <> 'open' then raise exception 'room_not_joinable'; end if;
  if (select count(*) from public.room_members m where m.room_id = v_room.id and m.status = 'active') >= v_room.max_players then
    raise exception 'room_full';
  end if;

  if found then
    update public.room_members set status = 'active', role = 'member', left_at = null, joined_at = now()
     where room_id = v_room.id and user_id = v_uid;
  else
    insert into public.room_members (room_id, user_id) values (v_room.id, v_uid);
  end if;

  update public.room_invites set status = 'accepted', responded_at = now()
   where room_id = v_room.id and invitee_id = v_uid and status = 'pending';

  select * into v_room from public.rooms where id = v_room.id;
  return v_room;
end $$;

-- ---------- المغادرة ----------
create or replace function public.leave_room(p_room_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_member public.room_members;
  v_next uuid;
begin
  perform 1 from public.rooms where id = p_room_id for update;
  if not found then raise exception 'room_not_found'; end if;

  select * into v_member from public.room_members m
   where m.room_id = p_room_id and m.user_id = v_uid and m.status = 'active' for update;
  if not found then raise exception 'not_a_member'; end if;

  if exists (select 1 from public.games g join public.game_players gp on gp.game_id = g.id
             where g.room_id = p_room_id and g.status = 'in_progress' and gp.user_id = v_uid) then
    raise exception 'game_in_progress';
  end if;

  update public.room_members set status = 'left', left_at = now(), role = 'member'
   where room_id = p_room_id and user_id = v_uid;

  if v_member.role = 'owner' then
    select m.user_id into v_next from public.room_members m
     where m.room_id = p_room_id and m.status = 'active'
     order by (m.role = 'moderator') desc, m.joined_at asc limit 1;
    if v_next is null then
      update public.rooms set status = 'closed' where id = p_room_id;
    else
      update public.room_members set role = 'owner' where room_id = p_room_id and user_id = v_next;
      update public.rooms set owner_id = v_next where id = p_room_id;
    end if;
  end if;
  return true;
end $$;

-- ---------- الطرد ----------
create or replace function public.kick_member(p_room_id uuid, p_user_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_me public.room_members;
  v_target public.room_members;
begin
  perform 1 from public.rooms where id = p_room_id for update;
  if not found then raise exception 'room_not_found'; end if;

  select * into v_me from public.room_members m
   where m.room_id = p_room_id and m.user_id = v_uid and m.status = 'active';
  if not found or v_me.role not in ('owner', 'moderator') then raise exception 'not_room_manager'; end if;
  if p_user_id = v_uid then raise exception 'cannot_kick_self'; end if;

  select * into v_target from public.room_members m
   where m.room_id = p_room_id and m.user_id = p_user_id and m.status = 'active';
  if not found then raise exception 'target_not_member'; end if;
  if v_target.role = 'owner' or (v_target.role = 'moderator' and v_me.role <> 'owner') then
    raise exception 'insufficient_role';
  end if;
  if exists (select 1 from public.games g join public.game_players gp on gp.game_id = g.id
             where g.room_id = p_room_id and g.status = 'in_progress' and gp.user_id = p_user_id) then
    raise exception 'game_in_progress';
  end if;

  update public.room_members set status = 'kicked', left_at = now(), role = 'member'
   where room_id = p_room_id and user_id = p_user_id;
  return true;
end $$;

-- ---------- تعيين مشرف ----------
create or replace function public.set_member_role(p_room_id uuid, p_user_id uuid, p_role public.member_role)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_user();
begin
  if p_role not in ('moderator', 'member') then raise exception 'invalid_role'; end if;
  if not exists (select 1 from public.rooms r where r.id = p_room_id and r.owner_id = v_uid) then
    raise exception 'not_room_owner';
  end if;
  update public.room_members set role = p_role
   where room_id = p_room_id and user_id = p_user_id and status = 'active' and role <> 'owner';
  if not found then raise exception 'target_not_member'; end if;
  return true;
end $$;

-- ---------- تعديل إعدادات الغرفة (المالك فقط، والغرفة مفتوحة) ----------
create or replace function public.update_room_settings(
  p_room_id uuid, p_name text default null, p_max_players integer default null, p_public_votes boolean default null)
returns public.rooms language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_room public.rooms;
begin
  select * into v_room from public.rooms where id = p_room_id for update;
  if not found then raise exception 'room_not_found'; end if;
  if v_room.owner_id <> v_uid then raise exception 'not_room_owner'; end if;
  if v_room.status <> 'open' then raise exception 'room_not_open'; end if;
  if p_name is not null and (char_length(btrim(p_name)) < 2 or char_length(btrim(p_name)) > 40) then
    raise exception 'invalid_room_name';
  end if;
  if p_max_players is not null and (p_max_players < 4 or p_max_players > 20 or p_max_players < v_room.member_count) then
    raise exception 'invalid_max_players';
  end if;

  update public.rooms
     set name = coalesce(btrim(p_name), name),
         max_players = coalesce(p_max_players, max_players),
         public_votes = coalesce(p_public_votes, public_votes)
   where id = p_room_id
  returning * into v_room;
  return v_room;
end $$;

-- ---------- الدعوات ----------
create or replace function public.invite_player(p_room_id uuid, p_invitee_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_room public.rooms;
  v_id uuid;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if not found then raise exception 'room_not_found'; end if;
  if not exists (select 1 from public.room_members m where m.room_id = p_room_id and m.user_id = v_uid
                 and m.status = 'active' and m.role in ('owner', 'moderator')) then
    raise exception 'not_room_manager';
  end if;
  if v_room.status <> 'open' then raise exception 'room_not_open'; end if;
  if p_invitee_id = v_uid then raise exception 'cannot_invite_self'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_invitee_id) then raise exception 'user_not_found'; end if;
  if exists (select 1 from public.room_members m where m.room_id = p_room_id and m.user_id = p_invitee_id
             and m.status in ('active', 'kicked')) then
    raise exception 'invitee_not_eligible';
  end if;
  if (select count(*) from public.room_invites i where i.room_id = p_room_id and i.status = 'pending') >= 20 then
    raise exception 'too_many_pending_invites';
  end if;

  update public.room_invites set status = 'revoked', responded_at = now()
   where room_id = p_room_id and invitee_id = p_invitee_id and status = 'pending' and expires_at <= now();

  insert into public.room_invites (room_id, inviter_id, invitee_id, room_name)
  values (p_room_id, v_uid, p_invitee_id, v_room.name)
  on conflict (room_id, invitee_id) where status = 'pending'
  do update set expires_at = now() + interval '1 day', inviter_id = excluded.inviter_id
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.respond_invite(p_invite_id uuid, p_accept boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_inv public.room_invites;
begin
  select * into v_inv from public.room_invites where id = p_invite_id and invitee_id = v_uid for update;
  if not found then raise exception 'invite_not_found'; end if;
  if v_inv.status <> 'pending' or v_inv.expires_at <= now() then raise exception 'invite_not_pending'; end if;

  if p_accept then
    perform public.join_room(v_inv.room_id, null);
    update public.room_invites set status = 'accepted', responded_at = now() where id = p_invite_id;
  else
    update public.room_invites set status = 'declined', responded_at = now() where id = p_invite_id;
  end if;
  return true;
end $$;

-- ---------- البلاغات ----------
create or replace function public.submit_report(
  p_reported_id uuid, p_reason public.report_reason, p_details text default '',
  p_room_id uuid default null, p_game_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_room uuid := p_room_id;
  v_id uuid;
begin
  if p_reported_id = v_uid then raise exception 'cannot_report_self'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_reported_id) then raise exception 'user_not_found'; end if;
  p_details := left(btrim(coalesce(p_details, '')), 1000);

  if p_game_id is not null then
    if not (exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.user_id = v_uid)
        and exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.user_id = p_reported_id)) then
      raise exception 'invalid_context';
    end if;
    select g.room_id into v_room from public.games g where g.id = p_game_id;
  elsif p_room_id is not null then
    if not (exists (select 1 from public.room_members m where m.room_id = p_room_id and m.user_id = v_uid)
        and exists (select 1 from public.room_members m where m.room_id = p_room_id and m.user_id = p_reported_id)) then
      raise exception 'invalid_context';
    end if;
  else
    raise exception 'invalid_context';
  end if;

  if (select count(*) from public.reports r where r.reporter_id = v_uid and r.created_at > now() - interval '1 day') >= 10 then
    raise exception 'too_many_reports';
  end if;

  begin
    insert into public.reports (reporter_id, reported_id, room_id, game_id, reason, details)
    values (v_uid, p_reported_id, v_room, p_game_id, p_reason, p_details)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'already_reported';
  end;
  return v_id;
end $$;
