-- الخطوة 1: شغّل هذا السطر لوحده أولاً ثم اضغط Run
-- ALTER TYPE public.vendor_type ADD VALUE IF NOT EXISTS 'pharmacy';

-- الخطوة 2: بعد نجاح الخطوة 1، شغّل الكود التالي بالكامل:

-- 1. جدول ربط المتجر بأنواع متعددة (مطعم، ماركت، إلخ)
CREATE TABLE IF NOT EXISTS public.vendor_multi_types (
    vendor_id UUID REFERENCES public.vendors(id) ON DELETE CASCADE,
    type vendor_type NOT NULL,
    PRIMARY KEY (vendor_id, type)
);

-- 2. جدول ربط المتجر بكاتلوجات المتاجر (مجلدات بداخلها متاجر)
CREATE TABLE IF NOT EXISTS public.vendor_global_category_links (
    vendor_id UUID REFERENCES public.vendors(id) ON DELETE CASCADE,
    global_category_id UUID REFERENCES public.global_categories(id) ON DELETE CASCADE,
    PRIMARY KEY (vendor_id, global_category_id)
);

-- 3. تفعيل الحماية (RLS)
ALTER TABLE public.vendor_multi_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendor_global_category_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read types" ON public.vendor_multi_types;
CREATE POLICY "Public read types" ON public.vendor_multi_types FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read catalog links" ON public.vendor_global_category_links;
CREATE POLICY "Public read catalog links" ON public.vendor_global_category_links FOR SELECT USING (true);

-- 4. وظيفة لترحيل البيانات القديمة (Migration)
DO $$
BEGIN
    -- نقل الأنواع الحالية مع تصحيح القيم غير المتوافقة
    INSERT INTO public.vendor_multi_types (vendor_id, type)
    SELECT id, 
           CASE 
             WHEN type::text = 'rt' THEN 'restaurant'::vendor_type
             WHEN type::text IN ('restaurant', 'supermarket', 'retail', 'pharmacy') THEN type::vendor_type
             ELSE 'restaurant'::vendor_type 
           END
    FROM public.vendors
    ON CONFLICT DO NOTHING;

    -- نقل الكاتلوج الفردي القديم
    INSERT INTO public.vendor_global_category_links (vendor_id, global_category_id)
    SELECT id, global_category_id FROM public.vendors WHERE global_category_id IS NOT NULL
    ON CONFLICT DO NOTHING;
END $$;
