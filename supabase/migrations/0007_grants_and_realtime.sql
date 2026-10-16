-- ============================================================
-- 0007 — صلاحيات الدوال + Realtime. شغّله أخيرًا (وآمن لإعادة التشغيل).
-- ============================================================

do $$
declare r record;
begin
  -- 1) سحب التنفيذ من الجميع عن كل دوال التطبيق (public + private)
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.proowner = (select oid from pg_roles where rolname = current_user)
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;

  -- 2) واجهة العميل: المستخدم المسجّل فقط
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'create_room','join_room','leave_room','kick_member','set_member_role','update_room_settings',
      'invite_player','respond_invite','submit_report','start_game','abort_game',
      'get_my_role','submit_night_action','cast_vote','advance_phase','ping')
  loop
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;

  -- ping آمنة وتُستعمل لاختبار الاتصال (تعمل بالمفتاح العام حتى بدون تسجيل دخول)
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'ping'
  loop
    execute format('grant execute on function %s to anon', r.sig);
  end loop;

  -- 3) دوال مساعدة تحتاجها سياسات RLS عند تقييمها بصلاحيات المستخدم
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname in (
      'is_room_member','is_room_manager','is_game_room_member','is_game_room_manager',
      'is_mafia_in_game','can_view_vote')
  loop
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;

-- Realtime: جداول آمنة فقط (لا game_secrets ولا night_actions ولا votes ولا reports)
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['rooms','room_members','games','game_players','vote_results','game_events']
    loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
