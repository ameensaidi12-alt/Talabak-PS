-- SQL to add location support to delivery areas
-- Run this in your Supabase SQL Editor

-- 1. Add location column if not exists
ALTER TABLE public.delivery_areas ADD COLUMN IF NOT EXISTS location GEOGRAPHY(POINT);

-- 2. Update areas with sample coordinates (You can adjust these)
UPDATE public.delivery_areas SET location = 'POINT(35.2544 32.2211)' WHERE name = 'القدس';
UPDATE public.delivery_areas SET location = 'POINT(35.3000 32.7000)' WHERE name = 'الناصرة وضواحيها';
UPDATE public.delivery_areas SET location = 'POINT(35.1500 32.5000)' WHERE name = 'ام الفحم';
UPDATE public.delivery_areas SET location = 'POINT(35.1000 32.3000)' WHERE name = 'باقة الغربية';
UPDATE public.delivery_areas SET location = 'POINT(35.0000 32.8000)' WHERE name = 'حيفا';
UPDATE public.delivery_areas SET location = 'POINT(34.8700 31.3700)' WHERE name = 'رهط';
UPDATE public.delivery_areas SET location = 'POINT(35.2900 32.8600)' WHERE name = 'سخنين - عرابة - دير حنا';
UPDATE public.delivery_areas SET location = 'POINT(35.2100 32.9300)' WHERE name = 'جديدة المكر - يركا - ياسيف';
UPDATE public.delivery_areas SET location = 'POINT(35.0000 32.2300)' WHERE name = 'الطيبة - الطيرة - قلنسوة';
