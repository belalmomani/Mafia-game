# تفعيل الإشعارات الفورية والصوت (من المتصفح)

## 0) في قاعدة البيانات
شغّل في SQL Editor، كل ملف وحده: `0021_push.sql` ثم `0022_grants_refresh.sql` (أو ملف `APPLY_0021_0022.sql` المجمّع).

## 1) نشر دالة الإشعارات `send-push`
1. Supabase ← **Edge Functions ← Deploy a new function ← Via Editor**.
2. الاسم: `send-push`. احذف الكود الافتراضي والصق محتوى `supabase/functions/send-push/index.ts`. اضغط **Deploy**.
3. اترك خيار **Verify JWT** مفعّلًا (الدالة نفسها ترفض أي نداء غير `service_role`).

## 2) ربط الدالة بجدول الإرسال (Webhook)
1. Supabase ← **Database ← Webhooks ← Create a new hook** (فعّل Webhooks إن طُلب).
2. Name: `push_outbox_hook` · Table: `public.push_outbox` · Events: **Insert فقط**.
3. Type: **Supabase Edge Functions** · Function: `send-push` · Method: POST. احفظ.

## 3) نشر دالة الصوت `voice-token`
كما في الخطوة 1: الاسم `voice-token`، والصق `supabase/functions/voice-token/index.ts`، ثم Deploy (Verify JWT مفعّل).

## 4) الأسرار (أضفتها سابقًا)
`FCM_SERVICE_ACCOUNT` و`LIVEKIT_URL` و`LIVEKIT_API_KEY` و`LIVEKIT_API_SECRET` في Edge Functions ← Secrets.

## 5) التطبيق
- ملف `app/google-services.json` يجب أن يبقى في المستودع (لا يوجد في الـ ZIP، فلا تحذفه عند رفع الملفات).
- أعد البناء وثبّت الـ APK، وافتح التطبيق مرة ليسجّل رمز جهازك.

## الاختبار
- **إشعار تجريبي:** بعد فتح التطبيق مرة، شغّل في SQL Editor (ضع معرّف حسابك من شاشة «حسابي»):
```sql
insert into public.push_outbox (user_ids, title, body)
values (array['معرّفك-هنا'::uuid], 'تجربة', 'إشعار تجريبي');
```
أغلق التطبيق (اسحبه من الشاشة الأخيرة) وانتظر ثوانٍ. إن لم يصل: Edge Functions ← send-push ← **Logs**.
- **الصوت:** في لعبة حقيقية اضغط «انضم إلى الصوت». المتحدث وحده يُفتح ميكروفونه نهارًا، والمافيا ليلًا في قناتهم.

## قيود الصوت (اقرأها)
- الخادم يحدد من يحق له الميكروفون عند إصدار التصريح، ويتجدد التصريح تلقائيًا عند كل تغيّر دور. لكن **تعديلًا خبيثًا على التطبيق** قد يُبقي ميكروفون لاعب مفتوحًا بعد انتهاء دوره حتى يعيد الاتصال. إنفاذ أقوى (إسكات من الخادم لحظة تبدّل الدور) ممكن لاحقًا.
- الصوت يعمل ما دام التطبيق مفتوحًا؛ لا خدمة خلفية بعد.
- ملف FCM السري لا يُرفع إلى GitHub أبدًا.
