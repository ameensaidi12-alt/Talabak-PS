-- إضافة عمود is_trending لجدول categories
ALTER TABLE public.categories 
ADD COLUMN IF NOT EXISTS is_trending BOOLEAN DEFAULT false;

-- ═══════════════════════════════════════════════════════════════
-- أمثلة للاستخدام:
-- ═══════════════════════════════════════════════════════════════

-- 1️⃣ إنشاء فئة "الأكثر طلباً" يدوياً (مع تأثير لامع 🔥)
-- استبدل 'YOUR-VENDOR-UUID' بمعرف المتجر الفعلي
INSERT INTO public.categories (vendor_id, name, is_trending, sort_order)
VALUES ('YOUR-VENDOR-UUID', 'الأكثر طلباً', true, -1);

-- 2️⃣ تفعيل التأثير اللامع لفئات موجودة
UPDATE public.categories 
SET is_trending = true 
WHERE name IN ('بيتزا', 'برجر', 'مشروبات');

-- 3️⃣ إلغاء التأثير اللامع من فئة
UPDATE public.categories 
SET is_trending = false 
WHERE name = 'اسم الفئة';

-- إنشاء index للأداء (اختياري)
CREATE INDEX IF NOT EXISTS idx_categories_trending 
ON public.categories(is_trending) 
WHERE is_trending = true;
