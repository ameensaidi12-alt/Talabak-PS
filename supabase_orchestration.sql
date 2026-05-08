-- 1. Create the automatic address orchestration function
-- This function identifies the nearest delivery area and saves the user address in one step.
-- Run this in your Supabase SQL Editor.

CREATE OR REPLACE FUNCTION public.set_user_address_auto(
    p_street TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
) RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_area_id UUID;
    v_area_name TEXT;
    v_result JSONB;
BEGIN
    -- 1. Get current user ID
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated to save address';
    END IF;

    -- 2. Find the nearest delivery area using geography distance operator (<->)
    -- We assume delivery_areas has a 'location' column of type geography(point)
    SELECT id, name INTO v_area_id, v_area_name
    FROM public.delivery_areas
    WHERE location IS NOT NULL
      AND is_active = true
    ORDER BY location <-> ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    LIMIT 1;

    -- 3. Update existing addresses to remove default status for this user
    UPDATE public.user_addresses 
    SET is_default = false 
    WHERE user_id = v_user_id;

    -- 4. INSERT or UPDATE (UPSERT)
    -- This ensures only ONE row per user in the table
    INSERT INTO public.user_addresses (
        user_id,
        area_id,
        address_line_1,
        location,
        is_default,
        title
    ) VALUES (
        v_user_id,
        v_area_id,
        p_street,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        true,
        'منزل'
    )
    ON CONFLICT (user_id) 
    DO UPDATE SET
        area_id = EXCLUDED.area_id,
        address_line_1 = EXCLUDED.address_line_1,
        location = EXCLUDED.location,
        is_default = EXCLUDED.is_default,
        created_at = NOW()
    RETURNING jsonb_build_object(
        'id', id,
        'area_id', area_id,
        'area_name', v_area_name,
        'street', address_line_1
    ) INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- IMPORTANT: YOU MUST RUN THIS TO ENFORCE THE RULE AT DATABASE LEVEL
-- ALTER TABLE public.user_addresses ADD CONSTRAINT unique_user_address UNIQUE (user_id);
