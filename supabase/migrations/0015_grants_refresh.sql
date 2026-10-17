-- ============================================================
-- 0015 — إعادة ضبط صلاحيات الدوال بعد 0014 (آمن لإعادة التشغيل)
-- ============================================================
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.proowner = (select oid from pg_roles where rolname = current_user)
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;

  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'create_room','join_room','leave_room','kick_member','set_member_role','update_room_settings',
      'invite_player','respond_invite','submit_report','start_game','abort_game',
      'get_my_role','submit_night_action','cast_vote','advance_phase','ping',
      'hunter_shoot','set_boy_target','set_display_name','end_speech')
  loop
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;

  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'ping'
  loop
    execute format('grant execute on function %s to anon', r.sig);
  end loop;

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
