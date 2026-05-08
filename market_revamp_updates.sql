-- تحديثات الماركت (Market Revamp Schema Updates)

-- 1. إضافة عمود "صورة الكاتلوج" إلى جدول الفئات
ALTER TABLE public.categories 
ADD COLUMN IF NOT EXISTS image_url TEXT;

-- 2. إضافة عمود "الفرع" (تصنيف فرعي) إلى جدول المنتجات
ALTER TABLE public.products 
ADD COLUMN IF NOT EXISTS sub_category TEXT;

-- [اختياري] تحديث الصفوف الموجودة بقيم افتراضية إذا لزم الأمر
-- UPDATE public.categories SET image_url = 'https://example.com/default_cat.png' WHERE image_url IS NULL;

-- 3. [توضيح] كيف تعبي البيانات:
-- عند إضافة منتج، حط في خانة sub_category اسم الفرع (مثلاً: "قسم الأجبان", "منظفات", إلخ)
-- عند إضافة كاتلوج، حط رابط الصورة في image_url
