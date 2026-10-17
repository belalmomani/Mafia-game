# النشر على Google Play (من الهاتف)

1. **إنشاء مفتاح التوقيع (مرة واحدة):** GitHub ← Actions ← **Generate Keystore (one time)** ← Run. ثم نزّل `keystore-secrets` من نتيجة التشغيل.
2. أضف 4 أسرار في Settings ← Secrets and variables ← Actions بنفس الأسماء: `KEYSTORE_BASE64` و`KEYSTORE_PASSWORD` و`KEY_ALIAS` و`KEY_PASSWORD` (القيم من الملف). **احتفظ بنسخة خارج GitHub** ثم احذف الـ Artifact. ضياع المفتاح = استحالة تحديث التطبيق.
3. **بناء النسخة الموقعة:** Actions ← **Android Release (signed)** ← Run. ينتج `.aab` (يُرفع لـ Google Play) و`.apk`.
4. **قبل الرفع:** انشر `docs/privacy_policy_ar.md` كصفحة عامة (GitHub Pages) وضع رابطها في Play Console، واملأ نموذج «أمان البيانات» (معرّف الإعلان، البريد، بيانات اللعب)، وفعّل موافقة الإعلانات (GDPR) في لوحة Start.io.
5. شرط Google الحالي لـ `targetSdk` يتغير سنويًا؛ التطبيق مضبوط على 35، تحقق من المطلوب وقت النشر.
6. إعلانات Start.io في النسخ الحقيقية حقيقية: لا تضغط عليها بنفسك.
