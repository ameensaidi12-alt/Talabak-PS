-- 1. جدول تصنيفات المنتجات (المنيوي الداخلي)
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID REFERENCES public.vendors(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. جدول المنتجات
CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
  vendor_id uuid REFERENCES public.vendors(id) ON DELETE CASCADE,
  category_id uuid REFERENCES public.categories(id) ON DELETE SET NULL,
  name text NOT NULL,
  description text NULL,
  base_price numeric(10, 2) NOT NULL,
  image_url text NULL,
  is_available boolean DEFAULT true,
  product_type text NULL,
  is_trending boolean DEFAULT false,
  created_at timestamp WITH time zone DEFAULT now()
);

-- 3. خيارات المنتج (مثلاً: الحجم، الإضافات)
CREATE TABLE IF NOT EXISTS public.product_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
  product_id uuid REFERENCES public.products(id) ON DELETE CASCADE,
  name text NOT NULL,
  is_required boolean DEFAULT false,
  is_multiple boolean DEFAULT false,
  created_at timestamp WITH time zone DEFAULT now()
);

-- 4. قيم الخيارات (مثلاً: صغير، كبير، بيبسي)
CREATE TABLE IF NOT EXISTS public.product_option_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
  option_id uuid REFERENCES public.product_options(id) ON DELETE CASCADE,
  name text NOT NULL,
  price_modifier numeric(10, 2) DEFAULT 0.00,
  created_at timestamp WITH time zone DEFAULT now()
);

-- 5. تفعيل الحماية
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_option_values ENABLE ROW LEVEL SECURITY;

-- سياسات القراءة العامة
DROP POLICY IF EXISTS "Public read pc" ON public.categories;
CREATE POLICY "Public read pc" ON public.categories FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read prod" ON public.products;
CREATE POLICY "Public read prod" ON public.products FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read opt" ON public.product_options;
CREATE POLICY "Public read opt" ON public.product_options FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read val" ON public.product_option_values;
CREATE POLICY "Public read val" ON public.product_option_values FOR SELECT USING (true);

-- 6. تحديث الـ View لجلب المنيو مع الخيارات (اختياري، يمكن الجلب مباشرة من الجداول)
DROP VIEW IF EXISTS public.vendor_menu_view CASCADE;
CREATE OR REPLACE VIEW public.vendor_menu_view 
WITH (security_invoker = true)
AS
SELECT 
    p.category_id,
    COALESCE(pc.name, 'إضافات') AS category_name,
    COALESCE(pc.sort_order, 999) AS category_order,
    p.vendor_id,
    p.id AS product_id,
    p.name AS product_name,
    p.description,
    p.base_price AS price,
    p.image_url,
    p.is_trending
FROM public.products p
LEFT JOIN public.categories pc ON p.category_id = pc.id
ORDER BY category_order ASC, p.is_trending DESC, p.name ASC;
