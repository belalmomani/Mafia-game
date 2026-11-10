-- ============================================================
-- 0021 — الإشعارات الفورية: رموز الأجهزة + صندوق الإرسال + محفزات الأحداث
-- الإرسال الفعلي تقوم به دالة Edge اسمها send-push يستدعيها Webhook على جدول push_outbox
-- (راجع docs/PUSH_VOICE_AR.md). شغّله بعد 0020.
-- ============================================================

create table if not exists public.push_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;

create table if not exists public.push_outbox (
  id         bigint generated always as identity primary key,
  user_ids   uuid[] not null,
  title      text not null,
  body       text not null,
  data       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.push_outbox enable row level security;
revoke all on public.push_outbox from anon, authenticated;

create or replace function public.register_push_token(p_token text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_user();
begin
  if p_token is null or char_length(p_token) < 20 or char_length(p_token) > 4096 then raise exception 'invalid_token'; end if;
  insert into public.push_tokens (token, user_id) values (p_token, v_uid)
  on conflict (token) do update set user_id = excluded.user_id, updated_at = now();
  return true;
end $$;

create or replace function public.unregister_push_token(p_token text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_user();
begin
  delete from public.push_tokens where token = p_token and user_id = v_uid;
  return true;
end $$;

-- يضيف رسالة إلى صندوق الإرسال إن كان لأحد المستلمين (غير البوت) رمز جهاز
create or replace function private.enqueue_push(p_users uuid[], p_title text, p_body text, p_data jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_users uuid[];
begin
  if p_users is null then return; end if;
  select coalesce(array_agg(distinct t.user_id), '{}') into v_users
    from public.push_tokens t join public.profiles pr on pr.id = t.user_id
   where t.user_id = any(p_users) and not pr.is_bot;
  if coalesce(array_length(v_users, 1), 0) = 0 then return; end if;
  insert into public.push_outbox (user_ids, title, body, data) values (v_users, p_title, p_body, p_data);
end $$;

create or replace function private.push_on_event()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_users uuid[];
begin
  if new.event_type = 'voting_started' then
    select array_agg(p.user_id) into v_users from public.game_players p where p.game_id = new.game_id and p.is_alive;
    perform private.enqueue_push(v_users, 'بدأ التصويت', 'صوّت الآن على من تشك فيه', jsonb_build_object('game_id', new.game_id));
  elsif new.event_type = 'night_started' then
    select array_agg(p.user_id) into v_users
      from public.game_players p join public.game_secrets s on s.game_id = p.game_id and s.user_id = p.user_id
     where p.game_id = new.game_id and p.is_alive and s.role in ('mafia', 'red_mafia', 'silencer', 'girl', 'sheikh');
    perform private.enqueue_push(v_users, 'بدأ الليل', 'حان وقت قدرتك', jsonb_build_object('game_id', new.game_id));
  elsif new.event_type = 'game_ended' then
    select array_agg(p.user_id) into v_users from public.game_players p where p.game_id = new.game_id;
    perform private.enqueue_push(v_users, 'انتهت اللعبة', 'افتح التطبيق لمعرفة النتيجة', jsonb_build_object('game_id', new.game_id));
  end if;
  return null;
end $$;
drop trigger if exists game_events_push on public.game_events;
create trigger game_events_push after insert on public.game_events
  for each row execute function private.push_on_event();

create or replace function private.push_on_game()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_cur uuid;
begin
  if new.status = 'in_progress' and new.phase = 'day'
     and (old.phase is distinct from 'day' or new.speech_idx is distinct from old.speech_idx
          or new.speech_order is distinct from old.speech_order) then
    v_cur := new.speech_order[new.speech_idx + 1];
    if v_cur is not null then
      perform private.enqueue_push(array[v_cur], 'دورك في الكلام', 'تكلّم وبرّر الآن', jsonb_build_object('game_id', new.id));
    end if;
  end if;
  if new.pending_pull is not null and old.pending_pull is distinct from new.pending_pull then
    perform private.enqueue_push(array[new.pending_pull], 'اختر من تسحبه معك', 'لديك ثوانٍ قليلة', jsonb_build_object('game_id', new.id));
  end if;
  return null;
end $$;
drop trigger if exists games_push on public.games;
create trigger games_push after update on public.games
  for each row execute function private.push_on_game();
