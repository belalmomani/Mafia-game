-- ============================================================
-- 0002 — الجداول والعلاقات والقيود والفهارس
-- ملاحظة: create table if not exists لا يعدّل جدولًا موجودًا؛
-- لو غيّرنا تعريف جدول لاحقًا سنضيف ملف ترحيل جديدًا.
-- ============================================================

-- profiles: ملفات اللاعبين (صف لكل مستخدم في auth.users)
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text not null,
  display_name text not null default '',
  avatar_url   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[A-Za-z0-9_\u0600-\u06FF]{3,20}$'),
  constraint profiles_display_name_len check (char_length(display_name) <= 30),
  constraint profiles_avatar_url_check check (avatar_url is null or (char_length(avatar_url) <= 500 and avatar_url ~ '^https://'))
);
create unique index if not exists profiles_username_lower_uidx on public.profiles (lower(username));

-- rooms: الغرف العامة والخاصة
create table if not exists public.rooms (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  name         text not null,
  visibility   public.room_visibility not null default 'public',
  invite_code  text,                                  -- للغرف الخاصة فقط
  max_players  smallint not null default 10,
  status       public.room_status not null default 'open',
  public_votes boolean not null default false,        -- هل يرى كل الأعضاء تفاصيل الأصوات بعد حسم الجولة
  member_count smallint not null default 0,           -- يحدّثه trigger
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint rooms_name_len check (char_length(name) between 2 and 40 and name = btrim(name)),
  constraint rooms_max_players_range check (max_players between 4 and 20),
  constraint rooms_code_matches_visibility check ((visibility = 'private') = (invite_code is not null)),
  constraint rooms_code_format check (invite_code is null or invite_code ~ '^[A-Z0-9]{8,12}$')
);
create unique index if not exists rooms_invite_code_uidx on public.rooms (invite_code) where invite_code is not null;
create index if not exists rooms_public_list_idx on public.rooms (created_at desc) where visibility = 'public' and status <> 'closed';
create index if not exists rooms_owner_idx on public.rooms (owner_id);

-- room_members: عضوية اللاعبين وصلاحياتهم (المفتاح الأساسي يمنع تكرار العضوية)
create table if not exists public.room_members (
  room_id   uuid not null references public.rooms(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  role      public.member_role not null default 'member',
  status    public.member_status not null default 'active',
  joined_at timestamptz not null default now(),
  left_at   timestamptz,
  primary key (room_id, user_id)
);
create unique index if not exists room_members_one_owner_uidx on public.room_members (room_id) where role = 'owner' and status = 'active';
create index if not exists room_members_user_idx on public.room_members (user_id) where status = 'active';

-- room_invites: دعوات مباشرة لغرفة (اللاعب المدعو يدخل حتى لو الغرفة خاصة)
create table if not exists public.room_invites (
  id           uuid primary key default gen_random_uuid(),
  room_id      uuid not null references public.rooms(id) on delete cascade,
  inviter_id   uuid not null references public.profiles(id) on delete cascade,
  invitee_id   uuid not null references public.profiles(id) on delete cascade,
  room_name    text not null,                         -- نسخة من الاسم كي لا نكشف الغرفة الخاصة
  status       public.invite_status not null default 'pending',
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default (now() + interval '1 day'),
  responded_at timestamptz,
  constraint room_invites_not_self check (inviter_id <> invitee_id)
);
create unique index if not exists room_invites_one_pending_uidx on public.room_invites (room_id, invitee_id) where status = 'pending';
create index if not exists room_invites_invitee_idx on public.room_invites (invitee_id, status);

-- games: جلسات اللعب وحالة الجولة
create table if not exists public.games (
  id                  uuid primary key default gen_random_uuid(),
  room_id             uuid not null references public.rooms(id) on delete cascade,
  status              public.game_status not null default 'in_progress',
  phase               public.game_phase not null default 'night',
  round_no            integer not null default 1 check (round_no >= 1),
  phase_started_at    timestamptz not null default now(),
  phase_ends_at       timestamptz,
  night_seconds       integer not null default 60  check (night_seconds between 20 and 300),
  day_seconds         integer not null default 120 check (day_seconds between 20 and 600),
  vote_seconds        integer not null default 60  check (vote_seconds between 20 and 300),
  reveal_role_on_death boolean not null default true,
  winner              public.game_winner,
  started_by          uuid references public.profiles(id) on delete set null,
  started_at          timestamptz not null default now(),
  ended_at            timestamptz,
  constraint games_phase_matches_status check ((status = 'in_progress') = (phase <> 'ended')),
  constraint games_deadline_when_active check (status <> 'in_progress' or phase_ends_at is not null),
  constraint games_winner_only_finished check (winner is null or status = 'finished')
);
create unique index if not exists games_one_active_per_room_uidx on public.games (room_id) where status = 'in_progress';
create index if not exists games_room_idx on public.games (room_id, started_at desc);

-- game_players: اللاعبون المشاركون وحالاتهم (لا يحتوي الدور السري)
create table if not exists public.game_players (
  game_id          uuid not null references public.games(id) on delete cascade,
  user_id          uuid not null references public.profiles(id) on delete cascade,
  seat_no          smallint not null check (seat_no >= 1),
  is_alive         boolean not null default true,
  eliminated_round integer,
  eliminated_by    public.elimination_cause,
  revealed_role    public.game_role,                  -- يملؤه الخادم عند الإقصاء/نهاية اللعبة فقط
  primary key (game_id, user_id),
  unique (game_id, seat_no),
  constraint game_players_alive_consistency check (
    (is_alive and eliminated_round is null and eliminated_by is null)
    or (not is_alive and eliminated_round is not null and eliminated_by is not null)
  )
);
create index if not exists game_players_user_idx on public.game_players (user_id);

-- game_secrets: الأدوار السرية وحالة القدرات (سري: لا صلاحيات ولا سياسات للعميل)
create table if not exists public.game_secrets (
  game_id           uuid not null,
  user_id           uuid not null,
  role              public.game_role not null,
  bullets_left      smallint not null default 0 check (bullets_left >= 0),
  bomb_used         boolean not null default false,
  last_protected_id uuid,
  primary key (game_id, user_id),
  foreign key (game_id, user_id) references public.game_players (game_id, user_id) on delete cascade
);
create index if not exists game_secrets_role_idx on public.game_secrets (game_id, role);

-- night_actions: اختيارات القدرات الليلية (سري: للخادم فقط)
create table if not exists public.night_actions (
  id         bigint generated always as identity primary key,
  game_id    uuid not null,
  round_no   integer not null check (round_no >= 1),
  actor_id   uuid not null,
  action     public.night_action_type not null,
  target_id  uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (game_id, actor_id)  references public.game_players (game_id, user_id) on delete cascade,
  foreign key (game_id, target_id) references public.game_players (game_id, user_id) on delete cascade,
  unique (game_id, round_no, actor_id),
  constraint night_actions_skip_has_no_target check ((action = 'skip') = (target_id is null)),
  constraint night_actions_no_self_target check (action = 'protect' or target_id is distinct from actor_id)
);

-- votes: الأصوات. UNIQUE يمنع التصويت أكثر من مرة في نفس مرحلة التصويت (جولة واحدة = مرحلة تصويت واحدة)
create table if not exists public.votes (
  id         bigint generated always as identity primary key,
  game_id    uuid not null,
  round_no   integer not null check (round_no >= 1),
  voter_id   uuid not null,
  target_id  uuid,                                    -- null = امتناع
  created_at timestamptz not null default now(),
  foreign key (game_id, voter_id)  references public.game_players (game_id, user_id) on delete cascade,
  foreign key (game_id, target_id) references public.game_players (game_id, user_id) on delete cascade,
  constraint votes_one_per_voter_per_round unique (game_id, round_no, voter_id),
  constraint votes_no_self_vote check (target_id is distinct from voter_id)
);
create index if not exists votes_round_idx on public.votes (game_id, round_no);

-- vote_results: نتيجة التصويت النهائية لكل جولة (يكتبها الخادم فقط)
create table if not exists public.vote_results (
  game_id            uuid not null references public.games(id) on delete cascade,
  round_no           integer not null,
  eliminated_user_id uuid references public.profiles(id) on delete set null,
  tally              jsonb not null default '{}'::jsonb,
  total_votes        smallint not null default 0,
  is_tie             boolean not null default false,
  resolved_at        timestamptz not null default now(),
  primary key (game_id, round_no)
);

-- game_events: سجل أحداث اللعبة (عام / للمافيا / خاص بلاعب)
create table if not exists public.game_events (
  id           bigint generated always as identity primary key,
  game_id      uuid not null references public.games(id) on delete cascade,
  round_no     integer not null default 0,
  event_type   text not null check (char_length(event_type) between 1 and 40),
  visibility   public.event_visibility not null default 'public',
  recipient_id uuid references public.profiles(id) on delete cascade,
  payload      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  constraint game_events_private_has_recipient check (visibility <> 'private' or recipient_id is not null)
);
create index if not exists game_events_game_idx on public.game_events (game_id, id);
create index if not exists game_events_recipient_idx on public.game_events (recipient_id) where visibility = 'private';

-- reports: بلاغات عن اللاعبين
create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_id uuid not null references public.profiles(id) on delete cascade,
  room_id     uuid references public.rooms(id) on delete set null,
  game_id     uuid references public.games(id) on delete set null,
  reason      public.report_reason not null,
  details     text not null default '' check (char_length(details) <= 1000),
  status      public.report_status not null default 'open',
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz,
  constraint reports_not_self check (reporter_id <> reported_id)
);
create unique index if not exists reports_no_duplicate_open_uidx
  on public.reports (reporter_id, reported_id, coalesce(game_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where status in ('open', 'reviewing');
create index if not exists reports_reported_idx on public.reports (reported_id, created_at desc);
