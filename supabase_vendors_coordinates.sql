-- إضافة إحداثيات تجريبية للمحلات لتظهر على الخريطة
-- ملاحظة: نستخدم تنسيق POINT(long lat)

UPDATE public.vendors 
SET location = 'POINT(35.2544 32.2211)' -- نابلس/المنطقة الوسطى
WHERE name = 'بيتزا هت';

UPDATE public.vendors 
SET location = 'POINT(35.2137 31.7683)' -- القدس
WHERE name = 'كنتاكي';

UPDATE public.vendors 
SET location = 'POINT(34.8516 32.2276)' -- الطيبة
WHERE name = 'سوبر ماركت الهدى';
