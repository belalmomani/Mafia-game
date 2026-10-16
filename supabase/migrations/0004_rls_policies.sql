-- ============================================================
-- 0004 — Row Level Security + صلاحيات الجداول
-- المبدأ: العميل يقرأ فقط ما تسمح به السياسات، ولا يكتب مباشرة إلا في
-- profiles (حقول محدودة). كل كتابة أخرى تمر عبر دوال RPC الخادمية.
-- ============================================================

alter table public.profiles      enable row level security;
alter table public.rooms         enable row level security;
alter table public.room_members  enable row level security;
alter table public.room_invites  enable row level security;
alter table public.games         enable row level security;
alter table public.game_players  enable row level security;
alter table public.game_secrets  enable row level security;   -- بلا سياسات = ممنوع على العميل
alter table public.night_actions enable row level security;   -- بلا سياسات = ممنوع على العميل
alter table public.votes         enable row level security;
alter table public.vote_results  enable row level security;
alter table public.game_events   enable row level security;
alter table public.reports       enable row level security;

-- إلغاء كل الصلاحيات الافتراضية ثم منح الحد الأدنى
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on tables    from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;

grant select on public.profiles, public.rooms, public.room_members, public.room_invites,
                public.games, public.game_players, public.votes, public.vote_results,
                public.game_events, public.reports
  to authenticated;
-- لا صلاحيات على game_secrets و night_actions إطلاقًا.
grant update (username, display_name, avatar_url) on public.profiles to authenticated;

-- ---------- profiles ----------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (true);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ---------- rooms ----------
drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms for select to authenticated using (
  (visibility = 'public' and status <> 'closed')
  or owner_id = (select auth.uid())
  or private.is_room_member(id)
);

-- ---------- room_members ----------
drop policy if exists room_members_select on public.room_members;
create policy room_members_select on public.room_members for select to authenticated using (
  user_id = (select auth.uid()) or private.is_room_member(room_id)
);

-- ---------- room_invites ----------
drop policy if exists room_invites_select on public.room_invites;
create policy room_invites_select on public.room_invites for select to authenticated using (
  inviter_id = (select auth.uid()) or invitee_id = (select auth.uid())
);

-- ---------- games / game_players / vote_results ----------
drop policy if exists games_select on public.games;
create policy games_select on public.games for select to authenticated using (private.is_room_member(room_id));

drop policy if exists game_players_select on public.game_players;
create policy game_players_select on public.game_players for select to authenticated using (private.is_game_room_member(game_id));

drop policy if exists vote_results_select on public.vote_results;
create policy vote_results_select on public.vote_results for select to authenticated using (private.is_game_room_member(game_id));

-- ---------- votes ----------
drop policy if exists votes_select on public.votes;
create policy votes_select on public.votes for select to authenticated using (private.can_view_vote(game_id, round_no, voter_id));

-- ---------- game_events ----------
drop policy if exists game_events_select on public.game_events;
create policy game_events_select on public.game_events for select to authenticated using (
  (visibility = 'public'  and private.is_game_room_member(game_id))
  or (visibility = 'private' and recipient_id = (select auth.uid()))
  or (visibility = 'mafia'   and private.is_mafia_in_game(game_id))
);

-- ---------- reports ----------
drop policy if exists reports_select_own on public.reports;
create policy reports_select_own on public.reports for select to authenticated using (reporter_id = (select auth.uid()));
