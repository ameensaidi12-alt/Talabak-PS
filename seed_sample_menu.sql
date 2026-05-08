-- 1. تعريف المتجر المستهدف (شاورما الفوال)
-- ID: d1234567-e89b-42d3-a456-426614174001

-- 2. إدخال تصنيفات المنيو (Categories)
INSERT INTO public.product_categories (id, vendor_id, name, sort_order)
VALUES 
('11111111-1111-1111-1111-111111111111', 'd1234567-e89b-42d3-a456-426614174001', 'الأطباق الرئيسية 🍖', 1),
('22222222-2222-2222-2222-222222222222', 'd1234567-e89b-42d3-a456-426614174001', 'ساندويشات 🌯', 2),
('33333333-3333-3333-3333-333333333333', 'd1234567-e89b-42d3-a456-426614174001', 'مشروبات غازية 🥤', 3)
ON CONFLICT (id) DO NOTHING;

-- 3. إدخال منتجات (أحدها Trending لترى التصميم الفخم)
INSERT INTO public.products (id, vendor_id, category_id, name, description, base_price, image_url, is_trending)
VALUES 
-- منتج مميز (Trending)
('aaaaaaa1-1111-1111-1111-111111111111', 'd1234567-e89b-42d3-a456-426614174001', '11111111-1111-1111-1111-111111111111', 'سوبر شاورما الوجبة العائلية', 'وجبة تكفي 4 أشخاص مع مقبلات وبطاطس', 85.00, 'https://images.unsplash.com/photo-1544025162-d76694265947?q=80&w=1000', true),

-- ساندويشات
('aaaaaaa2-2222-2222-2222-222222222222', 'd1234567-e89b-42d3-a456-426614174001', '22222222-2222-2222-2222-222222222222', 'لارج شاورما دجاج', 'خبز صاج، ثوم، مخلل، شاورما فاخرة', 18.00, 'https://images.unsplash.com/photo-1561651823-34feb02250e4?q=80&w=1000', false),
('aaaaaaa3-2222-2222-2222-222222222222', 'd1234567-e89b-42d3-a456-426614174001', '22222222-2222-2222-2222-222222222222', 'عربي عادي', 'مقطع مع بطاطس وصوص ثوم', 22.00, 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?q=80&w=1000', false),

-- مشروبات
('aaaaaaa4-3333-3333-3333-333333333333', 'd1234567-e89b-42d3-a456-426614174001', '33333333-3333-3333-3333-333333333333', 'كوكا كولا 330 مل', 'بارد ومنعش', 3.00, 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?q=80&w=1000', false)
ON CONFLICT (id) DO NOTHING;

-- 4. إدخال خيارات (Options) لمنتج الشاورما
-- خيار الحجم (إجباري)
INSERT INTO public.product_options (id, product_id, name, is_required, is_multiple)
VALUES ('bbbbbbb1-1111-1111-1111-111111111111', 'aaaaaaa1-1111-1111-1111-111111111111', 'اختر الحجم', true, false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.product_option_values (option_id, name, price_modifier)
VALUES 
('bbbbbbb1-1111-1111-1111-111111111111', 'وسط', 0.00),
('bbbbbbb1-1111-1111-1111-111111111111', 'كبير جداً', 20.00);

-- خيار الإضافات (اختياري ومتعدد)
INSERT INTO public.product_options (id, product_id, name, is_required, is_multiple)
VALUES ('bbbbbbb2-1111-1111-1111-111111111111', 'aaaaaaa1-1111-1111-1111-111111111111', 'إضافات مفضلة', false, true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.product_option_values (option_id, name, price_modifier)
VALUES 
('bbbbbbb2-1111-1111-1111-111111111111', 'زيادة صوص ثوم', 2.00),
('bbbbbbb2-1111-1111-1111-111111111111', 'زيادة مخلل', 1.00),
('bbbbbbb2-1111-1111-1111-111111111111', 'جبنة شيدر', 5.00);
