-- 1. تنظيف الجداول القديمة الزائدة
DROP TABLE IF EXISTS public.vendor_multi_types CASCADE;
DROP TABLE IF EXISTS public.vendor_global_category_links CASCADE;

-- 2. التأكد من وجود عمود الربط في جدول المتاجر
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='vendors' AND column_name='global_category_id') THEN
        ALTER TABLE public.vendors ADD COLUMN global_category_id UUID REFERENCES public.global_categories(id) ON DELETE SET NULL;
    END IF;
END $$;

-- 3. تحديث نوع المحل ليكون نص بسيط (اختياري لسهولة الاستخدام)
ALTER TABLE public.vendors ALTER COLUMN type TYPE TEXT;

-- 4. ربط المتاجر الحالية بالكاتلوجات (بناءً على النوع كبداية)
UPDATE public.vendors v
SET global_category_id = (SELECT id FROM public.global_categories gc WHERE gc.vendor_type = v.type LIMIT 1)
WHERE v.global_category_id IS NULL;

-- 5. إنشاء الـ View الاحترافي لجلب الكاتلوجات مع متاجرها
CREATE OR REPLACE VIEW categories_with_vendors AS
SELECT 
    c.id AS category_id,
    c.name AS category_name,
    c.image_url AS category_image,
    c.vendor_type,
    c.sort_order,
    v.id AS vendor_id,
    v.name AS vendor_name,
    v.logo_url,
    v.rating_avg,
    v.delivery_fee,
    v.estimated_delivery_time,
    v.is_open,
    v.area_id -- مهم للفلترة حسب المنطقة
FROM public.global_categories c
LEFT JOIN public.vendors v ON v.global_category_id = c.id
ORDER BY c.sort_order ASC, v.is_open DESC;

-- 6. تفعيل الصلاحيات (RLS) للـ View
-- ملاحظة: الـ Views في بوستغرس تأخذ صلاحيات الجداول الأساسية عادةً
-- ولكن يفضل التأكد من أن الجداول الأصلية لديها RLS مفعل
