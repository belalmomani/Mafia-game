-- ============================================================
-- 0012 — منع تعارض اسم المستخدم التلقائي عند إنشاء الملف الشخصي
-- كان الاسم يُبنى من أول 8 خانات من المعرّف، فيتعارض مع معرّفات الاختبار المتشابهة البداية.
-- الآن: آخر 8 خانات، وعند أي تعارض نادر نستعمل اسمًا عشوائيًا بديلًا.
-- ============================================================
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_dn text := left(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), 30);
begin
  begin
    insert into public.profiles (id, username, display_name)
    values (new.id, 'player_' || right(replace(new.id::text, '-', ''), 8), v_dn)
    on conflict (id) do nothing;
  exception when unique_violation then
    insert into public.profiles (id, username, display_name)
    values (new.id, 'player_' || substr(md5(new.id::text || clock_timestamp()::text), 1, 12), v_dn)
    on conflict (id) do nothing;
  end;
  return new;
end $$;
