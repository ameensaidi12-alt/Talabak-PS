-- إضافة أعمدة حقيقية لساعات العمل وعدد التقييمات
ALTER TABLE public.vendors 
ADD COLUMN IF NOT EXISTS closing_time TEXT DEFAULT '23:00',
ADD COLUMN IF NOT EXISTS review_count INT DEFAULT 10;

-- تحديث البيانات الحالية بقيم افتراضية لضمان عمل الواجهة فوراً
UPDATE public.vendors 
SET closing_time = '23:00', 
    review_count = 15
WHERE closing_time IS NULL OR closing_time = '';
