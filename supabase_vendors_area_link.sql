-- ربط المتاجر بالمناطق لتسهيل التصفية
ALTER TABLE public.vendors 
ADD COLUMN IF NOT EXISTS area_id UUID REFERENCES public.delivery_areas(id);

-- تحديث بعض المتاجر بمناطق تجريبية (تأكد من تشغيل ملف المناطق أولاً)
DO $$ 
BEGIN
    UPDATE public.vendors 
    SET area_id = (SELECT id FROM public.delivery_areas WHERE name LIKE '%الطيبة%' LIMIT 1)
    WHERE address LIKE '%الطيبة%' OR address LIKE '%قلنسوة%';

    UPDATE public.vendors 
    SET area_id = (SELECT id FROM public.delivery_areas WHERE name LIKE '%القدس%' LIMIT 1)
    WHERE address LIKE '%القدس%';
END $$;
