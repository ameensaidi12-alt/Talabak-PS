-- هذا الملف لتعبئة بيانات تجريبية عشان تظهر الميزات الجديدة في التطبيق
-- (شغل هذا الكود في Supabase SQL Editor بعد ما تشغل كود إضافة الأعمدة)

-- 1. تحديث صور الكاتلوجات (أمثلة)
-- سنقوم بتحديث الفئات الموجودة بصور عشوائية من النت للتجربة
UPDATE public.categories
SET image_url = 'https://cdn-icons-png.flaticon.com/512/3081/3081559.png'
WHERE name LIKE '%ألبان%' OR name LIKE '%جبن%';

UPDATE public.categories
SET image_url = 'https://cdn-icons-png.flaticon.com/512/2954/2954808.png'
WHERE name LIKE '%لحوم%' OR name LIKE '%دجاج%';

UPDATE public.categories
SET image_url = 'https://cdn-icons-png.flaticon.com/512/3050/3050253.png'
WHERE name LIKE '%خضار%' OR name LIKE '%فواكه%';

-- تحديث الباقي بصورة عامة
UPDATE public.categories
SET image_url = 'https://cdn-icons-png.flaticon.com/512/3514/3514211.png'
WHERE image_url IS NULL;


-- 2. تحديث المنتجات وتوزيعها على فروع (Sub-Categories)
-- سنوزع المنتجات عشوائياً على فروع مثل: "محلي", "مستورد", "عرض خاص"

UPDATE public.products
SET sub_category = 'منتجات محلية'
WHERE (id::text) LIKE '%0%' OR (id::text) LIKE '%1%';

UPDATE public.products
SET sub_category = 'مستورد'
WHERE (id::text) LIKE '%2%' OR (id::text) LIKE '%3%';

UPDATE public.products
SET sub_category = 'خالي من السكر'
WHERE (id::text) LIKE '%4%' OR (id::text) LIKE '%5%';

UPDATE public.products
SET sub_category = 'عبوات عائلية'
WHERE sub_category IS NULL;
