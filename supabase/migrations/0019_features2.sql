-- ============================================================
-- 0019 — إحصاءات اللاعبين وترتيبهم، الصور الرمزية، لوحة إدارة البلاغات، تنظيف البيانات القديمة
-- شغّله بعد 0018. (لا تُعد تشغيل 0014 بعده أبدًا؛ إن احتجت فأعد 0017 ثم 0018 ثم 0019 ثم 0020.)
-- ============================================================

alter table public.profiles add column if not exists avatar text
  check (avatar is null or char_length(avatar) <= 8);

-- ---------- الإحصاءات ----------
create table if not exists public.player_stats (
  user_id      uuid primary key references public.profiles(id) on delete cascade,
  games_played integer not null default 0,
  wins         integer not null default 0,
  mafia_games  integer not null default 0,
  mafia_wins   integer not null default 0,
  updated_at   timestamptz not null default now()
);
alter table public.player_stats enable row level security;
revoke all on public.player_stats from anon, authenticated;
grant select on public.player_stats to authenticated;
drop policy if exists player_stats_select on public.player_stats;
create policy player_stats_select on public.player_stats for select to authenticated using (true);

-- ---------- المشرفون على التطبيق (لا قراءة ولا كتابة من العميل) ----------
create table if not exists public.app_admins (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.app_admins enable row level security;
revoke all on public.app_admins from anon, authenticated;

create or replace function private.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.app_admins a where a.user_id = (select auth.uid()));
$$;

-- ---------- إنهاء اللعبة + تحديث الإحصاءات ----------
create or replace function private.finish_game(p_game_id uuid, p_winner public.game_winner)
returns void language plpgsql security definer set search_path = '' as $$
declare v_room uuid; v_round integer;
begin
  update public.game_players p set revealed_role = s.role
    from public.game_secrets s
   where s.game_id = p.game_id and s.user_id = p.user_id and p.game_id = p_game_id;

  update public.games set status = 'finished', phase = 'ended', winner = p_winner,
         ended_at = now(), phase_ends_at = null, pending_pull = null, pending_pull_until = null
   where id = p_game_id
  returning room_id, round_no into v_room, v_round;

  update public.rooms set status = 'open' where id = v_room and status = 'in_game';

  insert into public.player_stats (user_id, games_played, wins, mafia_games, mafia_wins)
  select s.user_id, 1,
         case when (s.role in ('mafia', 'red_mafia', 'silencer')) = (p_winner = 'mafia')
                   and gp.eliminated_by is distinct from 'left' then 1 else 0 end,
         case when s.role in ('mafia', 'red_mafia', 'silencer') then 1 else 0 end,
         case when s.role in ('mafia', 'red_mafia', 'silencer') and p_winner = 'mafia'
                   and gp.eliminated_by is distinct from 'left' then 1 else 0 end
    from public.game_secrets s
    join public.game_players gp on gp.game_id = s.game_id and gp.user_id = s.user_id
    join public.profiles pr on pr.id = s.user_id
   where s.game_id = p_game_id and not pr.is_bot
  on conflict (user_id) do update
     set games_played = public.player_stats.games_played + excluded.games_played,
         wins         = public.player_stats.wins + excluded.wins,
         mafia_games  = public.player_stats.mafia_games + excluded.mafia_games,
         mafia_wins   = public.player_stats.mafia_wins + excluded.mafia_wins,
         updated_at   = now();

  insert into public.game_events (game_id, round_no, event_type, payload)
  values (p_game_id, v_round, 'game_ended', jsonb_build_object(
    'winner', p_winner,
    'roles', (select jsonb_agg(jsonb_build_object('user_id', s.user_id, 'role', s.role))
                from public.game_secrets s where s.game_id = p_game_id)));
end $$;

-- ---------- واجهات العميل ----------
create or replace function public.set_avatar(p_avatar text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_user(); v text := nullif(btrim(coalesce(p_avatar, '')), '');
begin
  if v is not null and char_length(v) > 8 then raise exception 'invalid_avatar'; end if;
  update public.profiles set avatar = v where id = v_uid;
  return v;
end $$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_admin();
$$;

create or replace function public.admin_list_reports(p_status text default 'open', p_limit integer default 50)
returns table (rp_id uuid, rp_reason public.report_reason, rp_details text, rp_status public.report_status,
               rp_created_at timestamptz, rp_reporter text, rp_reported text, rp_reported_id uuid, rp_game_id uuid)
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() then raise exception 'not_admin'; end if;
  return query
    select r.id, r.reason, r.details, r.status, r.created_at,
           coalesce(nullif(pr.display_name, ''), pr.username),
           coalesce(nullif(pd.display_name, ''), pd.username),
           r.reported_id, r.game_id
      from public.reports r
      join public.profiles pr on pr.id = r.reporter_id
      join public.profiles pd on pd.id = r.reported_id
     where p_status = 'all' or r.status::text = p_status
     order by r.created_at desc
     limit least(greatest(coalesce(p_limit, 50), 1), 200);
end $$;

create or replace function public.admin_set_report_status(p_id uuid, p_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() then raise exception 'not_admin'; end if;
  if p_status not in ('open', 'reviewing', 'resolved', 'dismissed') then raise exception 'invalid_status'; end if;
  update public.reports set status = p_status::public.report_status,
         reviewed_at = case when p_status in ('resolved', 'dismissed') then now() else null end
   where id = p_id;
  return found;
end $$;

-- ---------- تنظيف دوري ----------
create or replace function private.cleanup_old_data()
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- ألعاب متروكة أكثر من يومين: تُلغى وتُفتح غرفها
  update public.rooms set status = 'open'
   where id in (select g.room_id from public.games g
                 where g.status = 'in_progress' and g.phase_started_at < now() - interval '2 days')
     and status = 'in_game';
  update public.games set status = 'aborted', phase = 'ended', phase_ends_at = null, ended_at = now(),
         pending_pull = null, pending_pull_until = null
   where status = 'in_progress' and phase_started_at < now() - interval '2 days';
  -- ألعاب منتهية قديمة (تُحذف معها أصواتها وأحداثها ورسائلها)
  delete from public.games where status <> 'in_progress' and coalesce(ended_at, started_at) < now() - interval '30 days';
  -- غرف مغلقة قديمة ودعوات منتهية
  delete from public.rooms where status = 'closed' and updated_at < now() - interval '7 days';
  delete from public.room_invites where expires_at < now() - interval '7 days';
end $$;

-- جدولة يومية 03:17 إن كان pg_cron مفعّلًا (Database ← Extensions ← pg_cron). لا يفشل الملف إن لم يكن.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mafia-cleanup', '17 3 * * *', 'select private.cleanup_old_data()');
  end if;
exception when others then
  raise notice 'تخطّي جدولة pg_cron: %', sqlerrm;
end $$;
