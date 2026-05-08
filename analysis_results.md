# 🔍 تحليل شامل لمشاكل الإشعارات

بعد مراجعة دقيقة جداً للأكواد والسيرفر الخاص بك (Supabase + Edge Functions + Flutter)، قمت بتحديد كافة المشاكل الموجودة التي تسبب الخلل العام في الإشعارات. المشاكل تنقسم إلى **3 أجزاء رئيسية**: مشكلة في إعدادات السيرفر تؤدي للرفض (401)، مشكلة في قاعدة البيانات (Triggers)، ومشكلة تعارض في التطبيق (Duplicates).

## 1️⃣ السيرفر: مشكلة الـ 401 المتكررة (Edge Function)
توجد مشكلة أمنية في إعداد الـ Edge Function الخاصة بـ `push-notifications`. 
- **السبب**: الدالة المرفوعة على Supabase معدلة للعمل بحماية جدار الحماية `verify_jwt: true`. وهذا يعني أنها تطلب توثيق `Authorization: Bearer <Token>` بجانب الـ `x-webhook-secret` من أي اتصال.
- المشغلات (Triggers) داخل Postgres مثل `handle_push_notification` تستخدم `net.http_post` وترسل فقط هيدر `x-webhook-secret` ولا ترسل `Authorization JWT`، لذلك يتم رفض جميع الطلبات مباشرة برمز الخطأ **401 Unauthorized** قبل أن يصل الكود لسطر التأكد من الـ Secret.

## 2️⃣ التطبيق: مشكلة التكرار والتداخل (FCM & AwesomeNotifications)
أنت تستخدم هيكلية **Hybrid Payload** (رسالة تحتوي على `notification` و `data` معاً) لضمان وصول الإشعارات حتى لو كان التطبيق مغلقاً.
- **التشخيص الخاطئ في التطبيق (`main.dart`)**: بداخل دالة الخلفية `_firebaseMessagingBackgroundHandler` أنت تقوم يدوياً بمناداة `AwesomeNotifications().createNotification(...)`.
- **النتيجة**: عند وصول إشعار والتطبيق في الخلفية، يقوم الـ Android (عن طريق FCM مباشرة) بعرض الإشعار من الـ Payload الخاص بـ `notification`. وفي نفس الثانية تعمل دالة `_firebaseMessagingBackgroundHandler` مما يقوم بإنشاء إشعار ثاني مطابق من الـ AwesomeNotifications. النتيجة إشعارين لكل تنبيه!
- **الحل**: طالما اعتمدنا هيكل الـ Hybrid، يجب أن نقوم بإلغاء سطر عرض الإشعار اليدوي بداخل الـ Background Handler ونتركه للـ FCM Native، أو نقوم بتحويل السيرفر ليرسل `data-only payload` (لكن الـ hybrid أفضل لضمان الوصول لأجهزة الأندرويد التي تقتل التطبيقات).

## 3️⃣ قاعدة البيانات: Trigger قديم وخاطئ
- في جدول `notifications`، هناك Trigger قديم اسمه `noite` يعتمد على `supabase_functions.http_request` ولا يرسل الـ `x-webhook-secret`. هذا الـ Trigger غير مفيد حالياً وكلما يتم حفظ إشعار، يرسل طلب خاطئ للـ Edge Function ويساهم في السجلات الخاطئة (401).

## 4️⃣ السيرفر: غياب الـ Channel ID لإشعارات التجار
- في الـ Edge Function بملف `index.ts`، وتحديداً في وظيفتي `notifyVendorOnConfirm` و `notifyVendorOnStatusConfirmed`.
- السيرفر يرسل الإشعارات للتاجر بدون `channelId` صحيح داخل الـ `data` مما قد يؤدي لإختفاء الإشعار أو عدم صدور الصوت القوي المخصص للـ Alerts عند تطبيق التاجر.

---

### 🛠️ خطة العمل المقترحة لحل المشاكل بشكل نهائي:
1. **تصحيح الـ Edge Function**:
   - تعديل دالة الإشعارات لإضافة الـ `channelId` لتنبيهات المتاجر.
   - إعادة رفع الـ Edge Function مع خاصية `--no-verify-jwt` لتتمكن الجداول من الإرسال عبر الـ Secret فقط.
2. **تنظيف قاعدة البيانات**:
   - حذف الـ Trigger القديم `noite` لأنه لم يعد مستخدماُ وبسبب الأخطاء.
3. **تعديل التطبيق (Flutter)**:
   - تنظيف الـ `_firebaseMessagingBackgroundHandler` لعدم عرض إشعار مكرر من `AwesomeNotifications` أثناء وجود `notification` أساسي من FCM.
   - تحديث كيفية قراءة الإجراء من الإشعارات بحيث يدعم الـ FCM Navigation Native بشكل صحيح بدون تضارب.

**ما رأيك يا صديقي؟ هل نبدأ في التنفيذ مباشرة لمعالجة كل هذه الثغرات خطوة بخطوة؟**
