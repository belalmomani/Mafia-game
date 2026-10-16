-- ============================================================
-- 0003 — Triggers + دوال مساعدة لسياسات RLS
-- ============================================================

create or replace function private.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();

drop trigger if exists rooms_touch on public.rooms;
create trigger rooms_touch before update on public.rooms
  for each row execute function private.touch_updated_at();

-- إنشاء profile تلقائيًا عند تسجيل مستخدم جديد
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    'player_' || substr(replace(new.id::text, '-', ''), 1, 8),
    left(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), 30)
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- مستخدمون موجودون قبل هذا الملف (إن وُجدوا)
insert into public.profiles (id, username, display_name)
select u.id, 'player_' || substr(replace(u.id::text, '-', ''), 1, 8), ''
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id);

-- تحديث عدد الأعضاء النشطين في الغرفة
create or replace function private.sync_room_member_count()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_room uuid := coalesce(new.room_id, old.room_id);
begin
  update public.rooms
     set member_count = (select count(*) from public.room_members m where m.room_id = v_room and m.status = 'active')
   where id = v_room;
  return null;
end $$;

drop trigger if exists room_members_count on public.room_members;
create trigger room_members_count after insert or update of status or delete on public.room_members
  for each row execute function private.sync_room_member_count();

-- ---------- دوال مساعدة تُستعمل داخل سياسات RLS ----------
create or replace function private.is_room_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.room_members m
    where m.room_id = p_room_id and m.user_id = (select auth.uid()) and m.status = 'active');
$$;

create or replace function private.is_room_manager(p_room_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.room_members m
    where m.room_id = p_room_id and m.user_id = (select auth.uid())
      and m.status = 'active' and m.role in ('owner', 'moderator'));
$$;

create or replace function private.is_game_room_member(p_game_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.games g
    join public.room_members m on m.room_id = g.room_id
    where g.id = p_game_id and m.user_id = (select auth.uid()) and m.status = 'active');
$$;

create or replace function private.is_game_room_manager(p_game_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.games g
    join public.room_members m on m.room_id = g.room_id
    where g.id = p_game_id and m.user_id = (select auth.uid())
      and m.status = 'active' and m.role in ('owner', 'moderator'));
$$;

create or replace function private.is_mafia_in_game(p_game_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.game_secrets s
    where s.game_id = p_game_id and s.user_id = (select auth.uid()) and s.role = 'mafia');
$$;

-- من يحق له رؤية صوت: صاحبه دائمًا؛ وغيره فقط بعد حسم الجولة
-- (مدير الغرفة دائمًا بعد الحسم، وبقية الأعضاء إن كانت rooms.public_votes مفعّلة)
create or replace function private.can_view_vote(p_game_id uuid, p_round_no integer, p_voter_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_voter_id = (select auth.uid())
    or (
      exists (select 1 from public.vote_results r where r.game_id = p_game_id and r.round_no = p_round_no)
      and (
        private.is_game_room_manager(p_game_id)
        or exists (
          select 1 from public.games g join public.rooms rm on rm.id = g.room_id
          where g.id = p_game_id and rm.public_votes and private.is_room_member(rm.id))
      )
    );
$$;
