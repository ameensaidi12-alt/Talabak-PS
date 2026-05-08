-- SAMPLE SEED DATA FOR HATSTAR APP (FIXED UUIDs)

-- 2. Insert Vendors
INSERT INTO vendors (id, name, type, logo_url, delivery_fee, estimated_delivery_time, rating_avg, is_open)
VALUES 
('d1234567-e89b-42d3-a456-426614174001', 'مطعم شاورما الفوال', 'restaurant', 'https://as1.ftcdn.net/v2/jpg/02/75/39/23/1000_F_275392381_9up6qY5qS0OnVIdT97zT6ZIn7Xp9InS9.jpg', 5.00, '25-35 دقيقة', 4.8, true),
('d1234567-e89b-42d3-a456-426614174002', 'بيتزا ومعجنات الباشا', 'restaurant', 'https://img.freepik.com/free-vector/pizza-logo-design-template_151167-74.jpg', 7.00, '30-45 دقيقة', 4.5, true),
('d1234567-e89b-42d3-a456-426614174003', 'سوبر ماركت الهدى', 'supermarket', 'https://img.freepik.com/free-vector/supermarket-logo-template_23-2148466601.jpg', 10.00, '20-40 دقيقة', 4.9, true);

-- 3. Insert Categories
INSERT INTO categories (id, vendor_id, name, sort_order)
VALUES 
('c1234567-e89b-42d3-a456-426614174001', 'd1234567-e89b-42d3-a456-426614174001', 'الأكثر مبيعاً', 1),
('c1234567-e89b-42d3-a456-426614174002', 'd1234567-e89b-42d3-a456-426614174001', 'أطباق', 2),
('c1234567-e89b-42d3-a456-426614174003', 'd1234567-e89b-42d3-a456-426614174003', 'خضروات وفواكه', 1);

-- 4. Insert Products
INSERT INTO products (id, vendor_id, category_id, name, description, base_price, image_url, is_available)
VALUES 
(gen_random_uuid(), 'd1234567-e89b-42d3-a456-426614174001', 'c1234567-e89b-42d3-a456-426614174001', 'طبق شاورما عربي', 'شاورما دجاج مع ثوم وبطاطس', 25.00, 'https://images.unsplash.com/photo-1544025162-d76694265947?q=80&w=1000', true),
(gen_random_uuid(), 'd1234567-e89b-42d3-a456-426614174001', 'c1234567-e89b-42d3-a456-426614174001', 'صحن حمص باللحمة', 'حمص بالطريقة الشامية مع قطع اللحم', 15.00, 'https://images.unsplash.com/photo-1577906030559-8bac4aee47f2?q=80&w=1000', true),
(gen_random_uuid(), 'd1234567-e89b-42d3-a456-426614174003', 'c1234567-e89b-42d3-a456-426614174003', 'كيلو موز', 'موز طازج', 8.00, 'https://images.unsplash.com/photo-1571771894821-ce9b6c11b08e?q=80&w=1000', true);

-- 5. Insert Options for Products
-- Fixed the product ID to start with a valid hex character 'a' instead of 'p'
INSERT INTO products (id, vendor_id, category_id, name, description, base_price, image_url, is_available)
VALUES ('a9999999-e89b-42d3-a456-426614174001', 'd1234567-e89b-42d3-a456-426614174001', 'c1234567-e89b-42d3-a456-426614174001', 'بطاطس مقلية', 'مقرمشة وساخنة', 10.00, 'https://images.unsplash.com/photo-1630384066272-1177f686353d?q=80&w=1000', true);

INSERT INTO product_options (id, product_id, name, is_required)
VALUES ('01234567-e89b-42d3-a456-426614174001', 'a9999999-e89b-42d3-a456-426614174001', 'اختر الحجم', true);

INSERT INTO product_option_values (option_id, name, price_modifier)
VALUES 
('01234567-e89b-42d3-a456-426614174001', 'صغير', 0.00),
('01234567-e89b-42d3-a456-426614174001', 'وسط', 3.00),
('01234567-e89b-42d3-a456-426614174001', 'كبير', 5.00);
