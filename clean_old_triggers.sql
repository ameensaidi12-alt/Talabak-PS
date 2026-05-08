-- ============================================
-- 🧹 سكربت تنظيف التريجرات القديمة المتكررة (HatStar CleanUp)
-- ============================================

-- هذا الكود سيقوم بالبحث عن أي تريجر قديم على جدول الطلبات (orders)
-- وظيفته كانت إعطاء نقاط/نجوم، وسيقوم بحذفه لتبقى النسخة الجديدة فقط 
-- (tr_award_order_stars) هي التي تعمل وتمنع تكرار النقاط.

DO $$ 
DECLARE
  trig record;
BEGIN
  FOR trig IN 
    SELECT DISTINCT trigger_name 
    FROM information_schema.triggers 
    WHERE event_object_table = 'orders' 
      AND trigger_schema = 'public'
      AND (
          trigger_name ILIKE '%star%' 
       OR trigger_name ILIKE '%point%' 
       OR trigger_name ILIKE '%award%' 
       OR trigger_name ILIKE '%reward%'
      )
      AND trigger_name != 'tr_award_order_stars'
  LOOP
    EXECUTE 'DROP TRIGGER IF EXISTS ' || trig.trigger_name || ' ON public.orders CASCADE;';
    RAISE NOTICE 'تم حذف التريجر القديم: %', trig.trigger_name;
  END LOOP;
END $$;
