# تفعيل تسجيل الدخول بحساب Google (اختياري)

الكود جاهز في التطبيق، ويظهر زر «الدخول بحساب Google» في شاشة «حسابي» **فقط** إن وضعت معرّف عميل الويب. الخطوات (من المتصفح على الهاتف):

## 1) بصمة التوقيع الثابتة
Google تربط الدخول ببصمة SHA-1 لمفتاح التوقيع. بدون مفتاح ثابت تتغير البصمة مع كل بناء.
1. GitHub ← Actions ← **Generate Keystore (one time)** ← Run، ثم نزّل `keystore-secrets` (فيه القيم وبصمة **SHA1**).
2. أضف الأسرار الأربعة (`KEYSTORE_BASE64` و`KEYSTORE_PASSWORD` و`KEY_ALIAS` و`KEY_PASSWORD`) في Settings ← Secrets and variables ← Actions، واحفظ نسخة خارج GitHub.
3. أعد تشغيل **Android Debug Build**: صار يُوقَّع بالمفتاح نفسه، فتثبت البصمة.

## 2) Google Cloud Console (console.cloud.google.com)
1. أنشئ مشروعًا، ثم **APIs & Services ← OAuth consent screen**: اختر External، واسم التطبيق وبريدك. (للتجربة اترك الحالة Testing وأضف بريدك ضمن Test users.)
2. **Credentials ← Create credentials ← OAuth client ID**:
   - نوع **Web application**: احفظ **Client ID** و**Client secret**.
   - نوع **Android**: اسم الحزمة `com.mafia.game` وبصمة **SHA-1** من الخطوة 1.

## 3) Supabase
Authentication ← Sign In / Providers ← **Google**: فعّله، وضع **Client ID** و**Client secret** من نوع Web. احفظ.

## 4) التطبيق
افتح `supabase.properties` على GitHub وضع:
```
GOOGLE_WEB_CLIENT_ID=<الـ Client ID من نوع Web>
```
ثم أعد البناء. يظهر الزر في «حسابي».

**ملاحظة:** الدخول بـ Google يفتح حسابك المرتبط بـ Google (أو ينشئه). حسابك المجهول الحالي لا يُدمج معه تلقائيًا؛ إن أردت الاحتفاظ بغرفك الحالية فاربط بريدًا أولًا بدل Google.
