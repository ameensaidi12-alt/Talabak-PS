-- 1. إنشاء جدول الربط المتعدد
CREATE TABLE IF NOT EXISTS public.vendor_global_category_links (
    vendor_id UUID REFERENCES public.vendors(id) ON DELETE CASCADE,
    global_category_id UUID REFERENCES public.global_categories(id) ON DELETE CASCADE,
    PRIMARY KEY (vendor_id, global_category_id)
);

-- 2. تفعيل الحماية وتعريف سياسات الوصول (RLS)
ALTER TABLE public.vendor_global_category_links ENABLE ROW LEVEL SECURITY;

-- سياسة القراءة (للجميع)
DROP POLICY IF EXISTS "Public read links" ON public.vendor_global_category_links;
CREATE POLICY "Public read links" ON public.vendor_global_category_links 
FOR SELECT USING (true);

-- سياسة الإضافة (لوحة التحكم / الأدمن)
DROP POLICY IF EXISTS "Allow insert links" ON public.vendor_global_category_links;
CREATE POLICY "Allow insert links" ON public.vendor_global_category_links 
FOR INSERT WITH CHECK (true);

-- سياسة الحذف
DROP POLICY IF EXISTS "Allow delete links" ON public.vendor_global_category_links;
CREATE POLICY "Allow delete links" ON public.vendor_global_category_links 
FOR DELETE USING (true);

-- 3. ترحيل البيانات الحالية (نسخ أي ربط موجود حالياً قبل حذف العمود)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='vendors' AND column_name='global_category_id') THEN
        INSERT INTO public.vendor_global_category_links (vendor_id, global_category_id)
        SELECT id, global_category_id FROM public.vendors WHERE global_category_id IS NOT NULL
        ON CONFLICT DO NOTHING;
    END IF;
END $$;

-- 4. حذف الأعمدة الزائدة من جدول المتاجر
ALTER TABLE public.vendors DROP COLUMN IF EXISTS type CASCADE;
ALTER TABLE public.vendors DROP COLUMN IF EXISTS global_category_id CASCADE;

-- 5. إعادة بناء الـ View الاحترافي بنظام SECURITY INVOKER وترتيب متطور
-- ملاحظة: يجب حذف الـ View أولاً لتجنب تعارض أسماء الأعمدة عند التغيير
DROP VIEW IF EXISTS public.categories_with_vendors CASCADE;

CREATE OR REPLACE VIEW public.categories_with_vendors
WITH (security_invoker = true)
AS
SELECT 
    c.id AS category_id,
    c.name AS category_name,
    c.image_url,
    c.vendor_type,
    c.sort_order,
    v.id AS vendor_id,
    v.name AS vendor_name,
    v.logo_url,
    v.rating_avg,
    v.delivery_fee,
    v.estimated_delivery_time,
    v.is_open,
    v.area_id
FROM public.global_categories c
LEFT JOIN public.vendor_global_category_links l ON l.global_category_id = c.id
LEFT JOIN public.vendors v ON v.id = l.vendor_id
ORDER BY 
    c.sort_order ASC,
    v.is_open DESC NULLS LAST,
    v.rating_avg DESC NULLS LAST;
