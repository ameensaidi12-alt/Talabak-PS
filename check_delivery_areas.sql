-- Check delivery_areas table data
-- Run this in Supabase SQL Editor to see all your delivery areas

SELECT 
    id,
    name,
    ST_AsText(location::geometry) as location_text,
    is_active,
    created_at
FROM public.delivery_areas
ORDER BY name;

-- If you see only one row or no rows, you need to add more delivery areas
-- Example to add more areas:

/*
INSERT INTO public.delivery_areas (name, location, is_active) VALUES
('نابلس', ST_SetSRID(ST_MakePoint(35.2544, 32.2211), 4326)::geography, true),
('رام الله', ST_SetSRID(ST_MakePoint(35.2063, 31.9038), 4326)::geography, true),
('الخليل', ST_SetSRID(ST_MakePoint(35.0938, 31.5326), 4326)::geography, true),
('جنين', ST_SetSRID(ST_MakePoint(35.3007, 32.4607), 4326)::geography, true),
('طولكرم', ST_SetSRID(ST_MakePoint(35.0278, 32.3108), 4326)::geography, true),
('قلقيلية', ST_SetSRID(ST_MakePoint(34.9833, 32.1833), 4326)::geography, true),
('سلفيت', ST_SetSRID(ST_MakePoint(35.1833, 32.0833), 4326)::geography, true),
('طوباس', ST_SetSRID(ST_MakePoint(35.3667, 32.3167), 4326)::geography, true),
('بيت لحم', ST_SetSRID(ST_MakePoint(35.2033, 31.7054), 4326)::geography, true),
('أريحا', ST_SetSRID(ST_MakePoint(35.4583, 31.8611), 4326)::geography, true);
*/
