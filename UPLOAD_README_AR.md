# رفع المشروع وبناؤه (طريقة بلا رفع مجلدات)

> إن كان رفع Git يُرفض عندك، استعمل هذه الطريقة: ملف واحد فقط يُرفع من المتصفح.

## مرة واحدة: إنشاء ملف البناء
1. GitHub ← المستودع ← **Add file ← Create new file**.
2. في خانة الاسم اكتب: `.github/workflows/build-from-zip.yml`
3. الصق محتوى الملف `build-from-zip.yml` (موجود في هذا المشروع داخل `ci-workflows/`)، ثم **Commit changes**.

## في كل تحديث
1. **Add file ← Upload files** ← اختر ملف ZIP المشروع (واحد فقط) ← **Commit changes**.
   (احذف ملفات zip القديمة من المستودع إن وُجدت؛ يُستعمل الأحدث رفعًا.)
2. **Actions ← Build APK from ZIP ← Run workflow**.
3. بعد النجاح: نزّل `mafia-apk` من Artifacts وثبّته.

## قاعدة البيانات
نفّذ `APPLY_ALL_PENDING.sql` في Supabase SQL Editor (مرة واحدة)، ثم شغّل `RUN_ALL_CHECKS.sql` للتحقق.

## ملاحظات
- لا حاجة لأي أسرار للبناء.
- إن فشل البناء فأرسل أول سطرين فيهما `e:` أو `FAILURE` من خطوة **Build debug APK**.
