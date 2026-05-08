-- 1. تأكد من وجود مناطق توصيل ببيانات صحيحة
INSERT INTO public.delivery_areas (name, location, is_active)
VALUES
('رام الله', ST_SetSRID(ST_MakePoint(35.2063, 31.9038), 4326)::geography, true),
('الخليل', ST_SetSRID(ST_MakePoint(35.0938, 31.5326), 4326)::geography, true),
('طولكرم', ST_SetSRID(ST_MakePoint(35.0278, 32.3108), 4326)::geography, true)
ON CONFLICT DO NOTHING;

-- 2. تحديث المتاجر لتربط بمنطقة "نابلس" بشكل افتراضي (للتجربة)
-- هذا يضمن ظهور المتاجر عند اختيار "نابلس"
UPDATE public.vendors
SET area_id = (SELECT id FROM public.delivery_areas WHERE name = 'نابلس' LIMIT 1)
WHERE area_id IS NULL;

-- 3. التحقق من البيانات
SELECT v.name as vendor, da.name as area 
FROM vendors v 
LEFT JOIN delivery_areas da ON v.area_id = da.id;
