-- Add delivery capability columns to vendors table
ALTER TABLE public.vendors 
ADD COLUMN IF NOT EXISTS has_delivery BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS has_pickup BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS is_free_delivery BOOLEAN DEFAULT false;

-- Optional: Update existing vendors to have some variation for testing
-- UPDATE public.vendors SET has_pickup = true WHERE id IN (SELECT id FROM public.vendors LIMIT 3);
-- UPDATE public.vendors SET is_free_delivery = true WHERE id IN (SELECT id FROM public.vendors OFFSET 3 LIMIT 2);
