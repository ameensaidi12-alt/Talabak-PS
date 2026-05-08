-- Check if vendors are linked to delivery areas
SELECT v.id, v.name, v.area_id, da.name as area_name
FROM public.vendors v
LEFT JOIN public.delivery_areas da ON v.area_id = da.id;

-- If area_id is NULL for vendors, update them to a default area (e.g., Nablus) for testing
-- UPDATE public.vendors 
-- SET area_id = (SELECT id FROM public.delivery_areas WHERE name = 'نابلس' LIMIT 1)
-- WHERE area_id IS NULL;
