-- ============================================================
-- 0023 — مختبر التجربة للمشرف + صلاحية المشرف بالبريد
--  • المشرف (بريدك المؤكد) ينشئ لعبة تجريبية بلاعبين وهميين «يدوي التحكم» يتصرف بدلهم،
--    ويرى كل الأدوار والإجراءات (عرض المشرف) في ألعاب المختبر فقط، لا في الألعاب الحقيقية.
--  • claim_admin: أول من يؤكد بريد bilalalmomani90@gmail.com يصبح مشرفًا (مرة واحدة فقط).
-- شغّله بعد 0022. لا تُعد تشغيل 0014 بعد 0017.
-- ============================================================

alter table public.profiles add column if not exists bot_mode text not null default 'auto'
  check (bot_mode in ('auto', 'manual'));
alter table public.rooms add column if not exists is_lab boolean not null default false;

-- صلاحية المشرف: تُمنح لصاحب البريد المخصص بعد تأكيده، ولمرة واحدة (لا تُمنح إن وُجد مشرف آخر)
create or replace function public.claim_admin()
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_user(); v_email text; v_conf timestamptz;
begin
  select u.email, u.email_confirmed_at into v_email, v_conf from auth.users u where u.id = v_uid;
  if lower(coalesce(v_email, '')) <> 'bilalalmomani90@gmail.com' or v_conf is null then
    raise exception 'not_allowed';
  end if;
  if exists (select 1 from public.app_admins) and not exists (select 1 from public.app_admins where user_id = v_uid) then
    raise exception 'admin_exists';
  end if;
  insert into public.app_admins (user_id) values (v_uid) on conflict do nothing;
  return true;
end $$;

-- البوتات اليدوية (لاعبو المختبر) لا تُتخطّى أدوارها ولا تتصرف وحدها
create or replace function private.skippable(p_game_id uuid, p_uid uuid)
returns boolean language sql stable set search_path = '' as $$
  select coalesce((
    select (not p.is_alive) or p.missed >= 2 or (pr.is_bot and pr.bot_mode = 'auto')
      from public.game_players p join public.profiles pr on pr.id = p.user_id
     where p.game_id = p_game_id and p.user_id = p_uid), true);
$$;

drop function if exists private.bots_act(uuid);
-- البوتات: تتصرف على الخادم بقرارات عشوائية صالحة
create or replace function private.bots_act(p_game_id uuid, p_include_manual boolean default false)
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
       where p.game_id = p_game_id and p.is_alive and pr.is_bot and (pr.bot_mode = 'auto' or p_include_manual)
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
       where p.game_id = p_game_id and p.is_alive and pr.is_bot and (pr.bot_mode = 'auto' or p_include_manual)
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
     and exists (select 1 from public.profiles pr where pr.id = s.user_id and pr.is_bot and (pr.bot_mode = 'auto' or p_include_manual));
end $$;


-- ============================ دوال المختبر (للمشرف فقط) ============================

create or replace function private.lab_check(p_game_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() then raise exception 'not_admin'; end if;
  if not exists (select 1 from public.games g join public.rooms r on r.id = g.room_id
                  where g.id = p_game_id and r.is_lab) then
    raise exception 'not_lab_game';
  end if;
end $$;

create or replace function public.lab_start(
  p_players integer default 4, p_silencer boolean default false,
  p_speech_seconds integer default 20, p_night_seconds integer default 20, p_vote_seconds integer default 20)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_user(); v_room uuid; v_id uuid; i integer;
begin
  if not private.is_admin() then raise exception 'not_admin'; end if;
  if p_players is null or p_players < 4 or p_players > 20 then raise exception 'invalid_max_players'; end if;
  insert into public.rooms (owner_id, name, visibility, invite_code, max_players, public_votes, is_lab)
  values (v_uid, 'مختبر تجربة', 'private', private.generate_invite_code(), p_players, true, true)
  returning id into v_room;
  for i in 1..p_players loop
    v_id := gen_random_uuid();
    insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
    values (v_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
            'lab_' || replace(v_id::text, '-', '') || '@bots.mafia.invalid', now(), now());
    update public.profiles set is_bot = true, bot_mode = 'manual', display_name = 'لاعب ' || i where id = v_id;
    insert into public.room_members (room_id, user_id) values (v_room, v_id);
  end loop;
  return public.start_game(v_room, p_night_seconds, p_speech_seconds, p_vote_seconds, true, coalesce(p_silencer, false));
end $$;

create or replace function public.lab_state(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_game public.games;
begin
  perform private.lab_check(p_game_id);
  select * into v_game from public.games where id = p_game_id;
  return jsonb_build_object(
    'game', to_jsonb(v_game),
    'players', (select coalesce(jsonb_agg(jsonb_build_object(
          'user_id', p.user_id, 'name', coalesce(nullif(pr.display_name, ''), pr.username), 'seat', p.seat_no,
          'alive', p.is_alive, 'role', s.role, 'bullets', s.bullets_left, 'pull', s.pull_target_id,
          'last_protected', s.last_protected_id, 'missed', p.missed, 'by', p.eliminated_by) order by p.seat_no), '[]'::jsonb)
        from public.game_players p
        join public.game_secrets s on s.game_id = p.game_id and s.user_id = p.user_id
        join public.profiles pr on pr.id = p.user_id
       where p.game_id = p_game_id),
    'night_actions', (select coalesce(jsonb_agg(jsonb_build_object('actor', a.actor_id, 'action', a.action, 'target', a.target_id)), '[]'::jsonb)
        from public.night_actions a where a.game_id = p_game_id and a.round_no = v_game.round_no),
    'votes', (select coalesce(jsonb_agg(jsonb_build_object('voter', v.voter_id, 'target', v.target_id)), '[]'::jsonb)
        from public.votes v where v.game_id = p_game_id and v.round_no = v_game.vote_cycle),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'type', e.event_type, 'vis', e.visibility,
          'round', e.round_no, 'payload', e.payload) order by e.id), '[]'::jsonb)
        from (select * from public.game_events where game_id = p_game_id order by id desc limit 60) e),
    'messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'user', m.user_id, 'channel', m.channel, 'body', m.body) order by m.id), '[]'::jsonb)
        from (select * from public.game_messages where game_id = p_game_id order by id desc limit 40) m)
  );
end $$;

-- تنفيذ إجراء بدل لاعب وهمي: نبدّل هوية الجلسة مؤقتًا إلى اللاعب ثم نستدعي نفس دوال اللعبة الحقيقية (فتبقى كل القواعد مطبّقة)
create or replace function public.lab_act(
  p_game_id uuid, p_actor uuid, p_action text, p_target uuid default null,
  p_text text default null, p_channel text default 'public')
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_old_claims text := coalesce(current_setting('request.jwt.claims', true), '');
  v_old_sub text := coalesce(current_setting('request.jwt.claim.sub', true), '');
begin
  perform private.lab_check(p_game_id);
  if not exists (select 1 from public.game_players gp join public.profiles pr on pr.id = gp.user_id
                  where gp.game_id = p_game_id and gp.user_id = p_actor and pr.is_bot) then
    raise exception 'not_lab_player';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', p_actor, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  begin
    case p_action
      when 'kill' then perform public.submit_night_action(p_game_id, 'kill', p_target);
      when 'protect' then perform public.submit_night_action(p_game_id, 'protect', p_target);
      when 'bomb' then perform public.submit_night_action(p_game_id, 'bomb', p_target);
      when 'silence' then perform public.submit_night_action(p_game_id, 'silence', p_target);
      when 'skip' then perform public.submit_night_action(p_game_id, 'skip', null);
      when 'vote' then perform public.cast_vote(p_game_id, p_target);
      when 'end_speech' then perform public.end_speech(p_game_id);
      when 'say' then perform public.send_message(p_game_id, p_text, p_channel);
      when 'hunter' then perform public.hunter_shoot(p_game_id, p_target);
      when 'boy_target' then perform public.set_boy_target(p_game_id, p_target);
      when 'boy_pull' then perform public.boy_pull(p_game_id, p_target);
      when 'leave' then perform public.leave_game(p_game_id);
      else raise exception 'invalid_action';
    end case;
  exception when others then
    perform set_config('request.jwt.claims', v_old_claims, true);
    perform set_config('request.jwt.claim.sub', v_old_sub, true);
    raise;
  end;
  perform set_config('request.jwt.claims', v_old_claims, true);
  perform set_config('request.jwt.claim.sub', v_old_sub, true);
  return 'ok';
end $$;

-- الانتقال للمرحلة التالية الآن (اختياريًا بتجاوز المؤقت)
create or replace function public.lab_advance(p_game_id uuid, p_force boolean default true)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_puppet uuid; v_res text;
  v_old_claims text := coalesce(current_setting('request.jwt.claims', true), '');
  v_old_sub text := coalesce(current_setting('request.jwt.claim.sub', true), '');
begin
  perform private.lab_check(p_game_id);
  select gp.user_id into v_puppet from public.game_players gp join public.profiles pr on pr.id = gp.user_id
   where gp.game_id = p_game_id and pr.is_bot limit 1;
  if v_puppet is null then raise exception 'not_lab_player'; end if;
  if p_force then
    update public.games
       set phase_ends_at = now(),
           pending_pull_until = case when pending_pull is not null then now() else pending_pull_until end
     where id = p_game_id and status = 'in_progress';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_puppet, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_puppet::text, true);
  begin
    v_res := public.advance_phase(p_game_id);
  exception when others then
    perform set_config('request.jwt.claims', v_old_claims, true);
    perform set_config('request.jwt.claim.sub', v_old_sub, true);
    raise;
  end;
  perform set_config('request.jwt.claims', v_old_claims, true);
  perform set_config('request.jwt.claim.sub', v_old_sub, true);
  return v_res;
end $$;

-- يجعل كل الوهميين اليدويين الذين لم يتصرفوا يتصرفون عشوائيًا (ليل/تصويت)
create or replace function public.lab_autofill(p_game_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  perform private.lab_check(p_game_id);
  perform private.bots_act(p_game_id, true);
  return true;
end $$;

create or replace function public.lab_list()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_user();
begin
  if not private.is_admin() then raise exception 'not_admin'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('game_id', g.id, 'room_id', r.id, 'status', g.status,
            'phase', g.phase, 'round', g.round_no, 'started_at', g.started_at) order by g.started_at desc), '[]'::jsonb)
            from (select * from public.games order by started_at desc limit 200) g
            join public.rooms r on r.id = g.room_id
           where r.is_lab and r.owner_id = v_uid limit 10);
end $$;

create or replace function public.lab_remove(p_room_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := private.require_user(); v_ids uuid[]; v_n integer;
begin
  if not private.is_admin() then raise exception 'not_admin'; end if;
  if not exists (select 1 from public.rooms r where r.id = p_room_id and r.is_lab and r.owner_id = v_uid) then
    raise exception 'not_lab_game';
  end if;
  select coalesce(array_agg(m.user_id), '{}') into v_ids from public.room_members m where m.room_id = p_room_id;
  v_n := coalesce(array_length(v_ids, 1), 0);
  delete from public.rooms where id = p_room_id;
  delete from auth.users where id = any(v_ids);
  return v_n;
end $$;

-- تنظيف: يضيف حذف الحسابات الوهمية اليتيمة (بوتات ومختبر بلا غرفة)
create or replace function private.cleanup_old_data()
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.rooms set status = 'open'
   where id in (select g.room_id from public.games g
                 where g.status = 'in_progress' and g.phase_started_at < now() - interval '2 days')
     and status = 'in_game';
  update public.games set status = 'aborted', phase = 'ended', phase_ends_at = null, ended_at = now(),
         pending_pull = null, pending_pull_until = null
   where status = 'in_progress' and phase_started_at < now() - interval '2 days';
  delete from public.games where status <> 'in_progress' and coalesce(ended_at, started_at) < now() - interval '30 days';
  delete from public.rooms where is_lab and created_at < now() - interval '2 days';
  delete from public.rooms where status = 'closed' and updated_at < now() - interval '7 days';
  delete from public.room_invites where expires_at < now() - interval '7 days';
  delete from auth.users u where u.email like '%@bots.mafia.invalid'
     and not exists (select 1 from public.room_members m where m.user_id = u.id);
end $$;
