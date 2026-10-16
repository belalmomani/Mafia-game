-- ============================================================
-- 0011 — تعيين الاسم المعروض (يستعمله التطبيق). شغّله بعد 0010.
-- ============================================================
create or replace function public.set_display_name(p_name text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_user();
  v text := btrim(coalesce(p_name, ''));
begin
  if char_length(v) < 2 or char_length(v) > 30 then raise exception 'invalid_display_name'; end if;
  update public.profiles set display_name = v where id = v_uid;
  return v;
end $$;

revoke all on function public.set_display_name(text) from public, anon, authenticated;
grant execute on function public.set_display_name(text) to authenticated;
