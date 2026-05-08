-- إنشاء جدول الأقسام الفرعية
CREATE TABLE public.sub_categories (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    name TEXT NOT NULL,
    category_id UUID REFERENCES public.categories(id) ON DELETE CASCADE,
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true
);

-- تعديل جدول المنتجات لربطه بالقسم الفرعي (بدلاً من النص)
ALTER TABLE public.products 
ADD COLUMN sub_category_id UUID REFERENCES public.sub_categories(id) ON DELETE SET NULL;

-- (اختياري) حذف العمود النصي القديم إذا لم يعد له لزوم
-- ALTER TABLE public.products DROP COLUMN sub_category;

-- بيانات تجريبية (Seed Data)
-- افترضنا وجود category_id معين، سنقوم بإضافة أقسام فرعية له
-- ملاحظة: ستحتاج لمعرفة IDs الفئات الحقيقية لتشغيل هذا الجزء بدقة، 
-- لكن هذا الكود يعتمد على الاستعلام الفرعي لإضافة بيانات لأول فئة يجدها.

DO $$
DECLARE
    first_cat_id UUID;
    sub_1_id UUID;
    sub_2_id UUID;
BEGIN
    -- جلب آيدي لأي فئة موجودة
    SELECT id INTO first_cat_id FROM public.categories LIMIT 1;

    IF first_cat_id IS NOT NULL THEN
        -- إضافة قسمين فرعيين
        INSERT INTO public.sub_categories (name, category_id, sort_order)
        VALUES ('أقسام فرعية 1', first_cat_id, 1) RETURNING id INTO sub_1_id;

        INSERT INTO public.sub_categories (name, category_id, sort_order)
        VALUES ('أقسام فرعية 2', first_cat_id, 2) RETURNING id INTO sub_2_id;

        -- تحديث بعض المنتجات لتتبع هذه الأقسام
        UPDATE public.products 
        SET sub_category_id = sub_1_id 
        WHERE category_id = first_cat_id AND (id::text LIKE '%0%' OR id::text LIKE '%1%');

        UPDATE public.products 
        SET sub_category_id = sub_2_id 
        WHERE category_id = first_cat_id AND (id::text LIKE '%2%' OR id::text LIKE '%3%');
    END IF;
END $$;
