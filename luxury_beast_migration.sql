-- 1. Rename categories to product_categories safely
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'categories') THEN
    ALTER TABLE public.categories RENAME TO product_categories;
  END IF;
END $$;

-- 2. Add trending flag to categories
ALTER TABLE public.product_categories 
ADD COLUMN IF NOT EXISTS is_trending BOOLEAN DEFAULT false;

-- 3. Enhance products table
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS sort_order INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS is_featured BOOLEAN DEFAULT false;

-- 4. Enhance product_options table
ALTER TABLE public.product_options
ADD COLUMN IF NOT EXISTS option_type TEXT DEFAULT 'single';

-- 5. Create Performance Indexes
CREATE INDEX IF NOT EXISTS idx_products_category 
ON public.products(category_id);

CREATE INDEX IF NOT EXISTS idx_products_trending 
ON public.products(is_trending);

CREATE INDEX IF NOT EXISTS idx_categories_trending 
ON public.product_categories(is_trending);

-- 6. Update the View (reflecting table rename and new fields)
DROP VIEW IF EXISTS public.vendor_menu_view CASCADE;
CREATE OR REPLACE VIEW public.vendor_menu_view 
WITH (security_invoker = true)
AS
SELECT 
    p.category_id,
    COALESCE(pc.name, 'إضافات') AS category_name,
    COALESCE(pc.sort_order, 999) AS category_order,
    pc.is_trending AS category_is_trending,
    p.vendor_id,
    p.id AS product_id,
    p.name AS product_name,
    p.description,
    p.base_price AS price,
    p.image_url,
    p.is_trending,
    p.is_featured,
    p.sort_order AS product_sort_order
FROM public.products p
LEFT JOIN public.product_categories pc ON p.category_id = pc.id
ORDER BY category_order ASC, p.is_trending DESC, product_sort_order ASC, p.name ASC;
