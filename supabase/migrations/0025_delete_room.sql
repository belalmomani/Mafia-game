-- ============================================================
-- 0025 — حذف الغرفة (للمالك، وللمشرف على أي غرفة)
-- لا يُسمح أثناء لعبة جارية (على المالك إلغاء اللعبة أولًا). يحذف الغرفة وألعابها وأعضاءها
-- والحسابات الوهمية (البوتات) التي أُضيفت إليها. شغّله بعد 0024.
-- ============================================================
create or replace function public.delete_room(p_room_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v_room public.rooms;
  v_bots uuid[];
begin
  select * into v_room from public.rooms where id = p_room_id for update;
  if not found then raise exception 'room_not_found'; end if;
  if v_room.owner_id <> v_uid and not private.is_admin() then raise exception 'not_room_owner'; end if;
  if exists (select 1 from public.games g where g.room_id = p_room_id and g.status = 'in_progress') then
    raise exception 'game_in_progress';
  end if;

  select coalesce(array_agg(m.user_id), '{}') into v_bots
    from public.room_members m join public.profiles p on p.id = m.user_id
   where m.room_id = p_room_id and p.is_bot;

  delete from public.rooms where id = p_room_id;
  delete from auth.users where id = any(v_bots);
  return true;
end $$;

revoke all on function public.delete_room(uuid) from public, anon, authenticated;
grant execute on function public.delete_room(uuid) to authenticated;
