-- ============================================================
-- بيانات اختبار وهمية فقط (لا أسماء ولا بريد حقيقي). للمشروع التجريبي فقط.
-- المستخدمون هنا لا يملكون كلمة مرور ولا يمكنهم تسجيل الدخول؛ هم للفحص في Table Editor.
-- آمن لإعادة التشغيل. للحذف: شغّل seed_cleanup.sql
-- ============================================================

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
select ('11111111-1111-4111-8111-11111111110' || i)::uuid,
       '00000000-0000-0000-0000-000000000000'::uuid,
       'authenticated', 'authenticated',
       'seed' || i || '@seed.mafia.invalid', now(), now()
from generate_series(1, 6) i
on conflict (id) do nothing;

update public.profiles set username = 'لاعب_تجريبي' || right(id::text, 1), display_name = 'لاعب تجريبي ' || right(id::text, 1)
where id::text like '11111111-1111-4111-8111-11111111110%';

insert into public.rooms (id, owner_id, name, visibility, invite_code, max_players, public_votes)
values
  ('22222222-2222-4222-8222-222222222201', '11111111-1111-4111-8111-111111111101', 'غرفة عامة تجريبية', 'public', null, 10, false),
  ('22222222-2222-4222-8222-222222222202', '11111111-1111-4111-8111-111111111102', 'غرفة خاصة تجريبية', 'private', 'TESTCODE01', 6, true)
on conflict (id) do nothing;

insert into public.room_members (room_id, user_id, role)
values
  ('22222222-2222-4222-8222-222222222201', '11111111-1111-4111-8111-111111111101', 'owner'),
  ('22222222-2222-4222-8222-222222222201', '11111111-1111-4111-8111-111111111103', 'member'),
  ('22222222-2222-4222-8222-222222222201', '11111111-1111-4111-8111-111111111104', 'member'),
  ('22222222-2222-4222-8222-222222222202', '11111111-1111-4111-8111-111111111102', 'owner'),
  ('22222222-2222-4222-8222-222222222202', '11111111-1111-4111-8111-111111111105', 'moderator')
on conflict (room_id, user_id) do nothing;

insert into public.room_invites (room_id, inviter_id, invitee_id, room_name)
values ('22222222-2222-4222-8222-222222222202', '11111111-1111-4111-8111-111111111102',
        '11111111-1111-4111-8111-111111111106', 'غرفة خاصة تجريبية')
on conflict do nothing;
