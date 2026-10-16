-- ============================================================
-- 0001 — المخطط الخاص (private) والأنواع (Enums)
-- شغّل هذا الملف أولًا. آمن لإعادة التشغيل.
-- ============================================================

-- مخطط private: لا يُكشف عبر واجهة Supabase API؛ نضع فيه الدوال الداخلية.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;  -- مطلوب لدوال مساعدة سياسات RLS فقط

do $$
declare r record;
begin
  for r in select * from (values
    ('room_visibility',  $v$'public','private'$v$),
    ('room_status',      $v$'open','in_game','closed'$v$),
    ('member_role',      $v$'owner','moderator','member'$v$),
    ('member_status',    $v$'active','left','kicked'$v$),
    ('invite_status',    $v$'pending','accepted','declined','revoked'$v$),
    ('game_status',      $v$'in_progress','finished','aborted'$v$),
    ('game_phase',       $v$'night','day','voting','ended'$v$),
    ('game_role',        $v$'mafia','citizen','doctor','detective','gunner','bomber'$v$),
    ('game_winner',      $v$'mafia','citizens'$v$),
    ('elimination_cause',$v$'vote','night','explosion'$v$),
    ('night_action_type',$v$'kill','protect','investigate','shoot','bomb','skip'$v$),
    ('event_visibility', $v$'public','mafia','private'$v$),
    ('report_reason',    $v$'cheating','harassment','spam','offensive_name','leaving_game','other'$v$),
    ('report_status',    $v$'open','reviewing','resolved','dismissed'$v$)
  ) as x(name, vals)
  loop
    if not exists (
      select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
      where n.nspname = 'public' and t.typname = r.name
    ) then
      execute format('create type public.%I as enum (%s)', r.name, r.vals);
    end if;
  end loop;
end $$;
